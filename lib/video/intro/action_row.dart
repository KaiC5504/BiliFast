import 'dart:async';

import 'package:bili_core/logic.dart' show CountFormat;
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../shared/action_glyphs.dart';
import '../../shared/theme.dart';
import '../actions/video_actions.dart';
import 'triple_ring.dart';

/// 点赞 不喜欢 投币 收藏 分享 under the title (03). Holding 点赞 fills rings around 点赞, 投币 and 收藏 and does 三连.
/// The row owns the gap above its icons and ends at the bottom of its counts.
class ActionRow extends StatefulWidget {
  const ActionRow({super.key, required this.actions});

  final VideoActions actions;

  @override
  State<ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<ActionRow> with TickerProviderStateMixin {
  late final _ring = AnimationController(vsync: this, duration: TripleTiming.fill)..addStatusListener(_ringStatus);
  late final _burst = AnimationController(vsync: this, duration: TripleTiming.burst);
  Timer? _hold;

  /// The press got as far as the rings: letting go then is an aborted 三连, not a tap on 点赞.
  bool _ringStarted = false;
  bool _tripled = false;

  VideoActions get _actions => widget.actions;

  @override
  void dispose() {
    _hold?.cancel();
    _ring.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _likeDown() {
    _hold?.cancel();
    _ringStarted = false;
    _tripled = false;
    _hold = Timer(TripleTiming.delay, () {
      if (!mounted) return;
      _ringStarted = true;
      _ring.forward(from: 0);
    });
  }

  void _likeUp() {
    _hold?.cancel();
    if (_tripled) return;
    if (_ringStarted) {
      _ring.animateBack(0, duration: TripleTiming.release);
    } else {
      unawaited(_actions.toggleLike());
    }
  }

  void _likeCancel() {
    _hold?.cancel();
    if (_ringStarted && !_tripled) _ring.animateBack(0, duration: TripleTiming.release);
  }

  void _ringStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _ringStarted && !_tripled) _triple();
  }

  void _triple() {
    _tripled = true;
    _ring.value = 0;
    // Logged out a login prompt follows, and when all three are done the model only says 已三连: no burst for those.
    if (_actions.tripleSends) {
      if (!MediaQuery.disableAnimationsOf(context)) _burst.forward(from: 0);
      unawaited(HapticFeedback.mediumImpact());
    }
    unawaited(_actions.triple());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _actions,
      builder: (context, _) {
        final actions = _actions;
        Widget ring(Widget cell) => _Ringed(progress: _ring, burst: _burst, child: cell);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ActionCell(
                  key: const ValueKey('action-like'),
                  glyph: ActionGlyph.like,
                  label: '点赞',
                  activeLabel: '取消点赞',
                  count: actions.likeCount,
                  active: actions.liked,
                  onTap: () => unawaited(actions.toggleLike()),
                  onLongPress: () => unawaited(actions.triple()),
                  onDown: _likeDown,
                  onUp: _likeUp,
                  onCancel: _likeCancel,
                  decorate: ring,
                ),
              ),
              Expanded(
                child: _ActionCell(
                  key: const ValueKey('action-dislike'),
                  glyph: ActionGlyph.dislike,
                  label: '不喜欢',
                  active: actions.disliked,
                  dimmed: !actions.dislikeAvailable,
                  onTap: () => unawaited(actions.toggleDislike()),
                ),
              ),
              Expanded(
                child: _ActionCell(
                  key: const ValueKey('action-coin'),
                  glyph: ActionGlyph.coin,
                  label: '投币',
                  activeLabel: '已投币',
                  count: actions.coinCount,
                  active: actions.coins > 0,
                  onTap: () => actions.ask(ActionPrompt.coin),
                  decorate: ring,
                ),
              ),
              Expanded(
                child: _ActionCell(
                  key: const ValueKey('action-favourite'),
                  glyph: ActionGlyph.favourite,
                  label: '收藏',
                  activeLabel: '已收藏',
                  count: actions.favCount,
                  active: actions.favorited,
                  onTap: () => actions.ask(ActionPrompt.favourites),
                  decorate: ring,
                ),
              ),
              Expanded(
                child: _ActionCell(
                  key: const ValueKey('action-share'),
                  glyph: ActionGlyph.share,
                  label: '分享',
                  count: actions.shareCount,
                  active: false,
                  onTap: () => actions.ask(ActionPrompt.share),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The 三连 ring centred on a cell's icon.
class _Ringed extends StatelessWidget {
  const _Ringed({required this.progress, required this.burst, required this.child});

  final Animation<double> progress;
  final Animation<double> burst;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const offset = (ActionTheme.iconSize - ActionTheme.ring) / 2;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        child,
        Positioned(
          top: ActionTheme.topGap + offset,
          child: TripleRing(progress: progress, burst: burst),
        ),
      ],
    );
  }
}

/// One column: the icon, pink and popping when it turns on, over its count, or its name while the count is 0.
class _ActionCell extends StatefulWidget {
  const _ActionCell({
    super.key,
    required this.glyph,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
    this.activeLabel,
    this.dimmed = false,
    this.onLongPress,
    this.onDown,
    this.onUp,
    this.onCancel,
    this.decorate,
  });

  final ActionGlyph glyph;
  final String label;

  /// What VoiceOver reads while [active], as landscape says it; the name under the icon stays [label].
  final String? activeLabel;
  final int? count;
  final bool active;
  final bool dimmed;

  /// What a tap does; also the accessibility press.
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 点赞 takes the raw press instead of [onTap], so a hold can become 三连: [onDown] as the finger lands, then
  /// [onUp] or [onCancel].
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final VoidCallback? onCancel;
  final Widget Function(Widget cell)? decorate;

  @override
  State<_ActionCell> createState() => _ActionCellState();
}

class _ActionCellState extends State<_ActionCell> with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: ActionTheme.popScale).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: ActionTheme.popScale, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 65,
    ),
  ]).animate(_pop);
  bool _pressed = false;

  /// From the finger landing until it lifts, slides off or is taken by a scroll.
  bool _holding = false;

  @override
  void didUpdateWidget(_ActionCell old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !MediaQuery.disableAnimationsOf(context)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  void _landed() {
    _holding = true;
    widget.onDown?.call();
  }

  void _ended({required bool cancelled}) {
    _press(false);
    if (!_holding) return;
    _holding = false;
    (cancelled ? widget.onCancel : widget.onUp)?.call();
  }

  String get _text {
    final count = widget.count;
    return count == null || count <= 0 ? widget.label : CountFormat.short(count);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final fade = still ? Duration.zero : const Duration(milliseconds: 180);
    final raw = widget.onDown != null;
    final cell = TweenAnimationBuilder<double>(
      tween: Tween(end: widget.active ? 1 : 0),
      duration: fade,
      builder: (context, on, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: ActionTheme.topGap),
          ScaleTransition(
            scale: _scale,
            child: ActionIcon(
              widget.glyph,
              solid: true,
              size: ActionTheme.iconSize,
              color: Color.lerp(ActionTheme.icon, BiliColors.pink, on)!,
            ),
          ),
          const SizedBox(height: ActionTheme.countGap),
          SizedBox(
            height: ActionTheme.countLine,
            child: Center(
              child: Text(
                _text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontFamily: BiliFonts.family,
                  fontSize: ActionTheme.countFont,
                  height: 1,
                  color: Color.lerp(ActionTheme.count, BiliColors.pink, on),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final body = AnimatedScale(
      scale: _pressed && !still ? BiliMetrics.chromePressedScale : 1,
      duration: const Duration(milliseconds: 120),
      child: Opacity(opacity: widget.dimmed ? ActionTheme.unavailableOpacity : 1, child: cell),
    );
    return Semantics(
      button: true,
      label: widget.active ? widget.activeLabel ?? widget.label : widget.label,
      value: widget.count == null ? null : CountFormat.short(widget.count!),
      selected: widget.active,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      customSemanticsActions: widget.onLongPress == null
          ? null
          : {const CustomSemanticsAction(label: '一键三连'): widget.onLongPress!},
      excludeSemantics: true,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _PressRecognizer: GestureRecognizerFactoryWithHandlers<_PressRecognizer>(
            () => _PressRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onPress = _landed
              ..onLost = (() => _ended(cancelled: true))
              ..onTapDown = ((_) => _press(true))
              ..onTapUp = ((_) => _ended(cancelled: false))
              ..onTapCancel = (() => _ended(cancelled: true))
              ..onTap = raw ? null : widget.onTap,
          ),
        },
        child: widget.decorate?.call(body) ?? body,
      ),
    );
  }
}

/// A tap that also says when its finger lands and when the finger is taken before any tap down. In the page's scroll
/// view and pager onTapDown waits [kPressTimeout] to see the finger isn't scrolling, which would start the 三连 hold
/// late, and a scroll that wins before then sends no cancel.
class _PressRecognizer extends TapGestureRecognizer {
  _PressRecognizer({super.debugOwner});

  VoidCallback? onPress;
  VoidCallback? onLost;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final fresh = state == GestureRecognizerState.ready;
    super.addAllowedPointer(event);
    if (fresh) onPress?.call();
  }

  @override
  void rejectGesture(int pointer) {
    final primary = pointer == primaryPointer;
    super.rejectGesture(pointer);
    if (primary) onLost?.call();
  }
}
