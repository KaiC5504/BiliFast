import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../device/orientation.dart';
import '../shared/theme.dart';
import 'danmaku_session.dart';
import 'send/danmaku_send_bar.dart';
import 'send/danmaku_style_panel.dart';

/// The send bar riding on the keyboard, with the style panel in the keyboard's place after A (22, 23, 36-39), as a
/// layer in the page's Stack. On the small player the page under the player dims (39) and a tap there closes; in
/// landscape and 竖屏 a tap anywhere above the bar does. Lets touches through while the bar is down.
class DanmakuOverlays extends StatefulWidget {
  const DanmakuOverlays({
    super.key,
    required this.session,
    required this.presentation,
    required this.playerBottom,
    required this.toast,
  });

  final DanmakuSession session;
  final Presentation presentation;

  /// Where the small player ends on the page; the dim starts there.
  final double playerBottom;
  final ValueChanged<String> toast;

  /// Forgets the keyboard heights the style panel takes; for tests.
  @visibleForTesting
  static void debugForgetKeyboard() => _DanmakuOverlaysState._keyboard.clear();

  @override
  State<DanmakuOverlays> createState() => _DanmakuOverlaysState();
}

class _DanmakuOverlaysState extends State<DanmakuOverlays> {
  /// The keyboard's height the last time it was up, landscape's and portrait's apart, which the style panel takes so
  /// the bar stays put.
  static final Map<bool, double> _keyboard = {};

  final _focus = FocusNode(debugLabel: 'danmaku-send');
  bool _styleShown = false;
  double _lastInset = 0;
  Timer? _keyboardWait;

  @override
  void initState() {
    super.initState();
    widget.session.sendOpen.addListener(_openChanged);
    widget.session.sender.addListener(_changed);
    _focus.addListener(_focusChanged);
    if (widget.session.sendOpen.value) _focusSoon();
  }

  @override
  void didUpdateWidget(DanmakuOverlays oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.sendOpen.removeListener(_openChanged);
      oldWidget.session.sender.removeListener(_changed);
      widget.session.sendOpen.addListener(_openChanged);
      widget.session.sender.addListener(_changed);
      _openChanged();
    }
  }

  @override
  void dispose() {
    widget.session.sendOpen.removeListener(_openChanged);
    widget.session.sender.removeListener(_changed);
    _keyboardWait?.cancel();
    _focus.dispose();
    super.dispose();
  }

  bool get _landscape => widget.presentation == Presentation.landscape;

  void _changed() {
    if (mounted) setState(() {});
  }

  void _openChanged() {
    if (!mounted) return;
    if (widget.session.sendOpen.value) {
      setState(() => _styleShown = false);
      _focusSoon();
    } else {
      _keyboardWait?.cancel();
      _focus.unfocus();
      setState(() => _styleShown = false);
    }
  }

  /// The field is built in the next frame; it takes focus then, which brings the keyboard.
  void _focusSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.session.sendOpen.value && !_styleShown) _focus.requestFocus();
  });

  void _focusChanged() {
    if (_focus.hasFocus && _styleShown) _waitForKeyboard();
  }

  /// The panel stays until the keyboard has risen over it (see [_trackKeyboard]), or gives way after a while: a
  /// hardware keyboard shows no software one.
  void _waitForKeyboard() {
    _keyboardWait?.cancel();
    _keyboardWait = Timer(DanmakuSendTheme.keyboardWait, _leaveStyle);
  }

  void _leaveStyle() {
    if (!mounted || !_focus.hasFocus || !_styleShown) return;
    _keyboardWait?.cancel();
    setState(() => _styleShown = false);
  }

  void _trackKeyboard(double inset, double panel) {
    if (inset > 0 && _focus.hasFocus) {
      // Kept while it rises or rests; a keyboard on its way down has no height worth keeping.
      if (!_styleShown && inset >= _lastInset) _keyboard[_landscape] = inset;
      if (_styleShown && inset >= panel - 0.5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _leaveStyle());
      }
    }
    _lastInset = inset;
  }

  double get _panelHeight =>
      _keyboard[_landscape] ??
      (_landscape ? DanmakuSendTheme.landscapePanelHeight : DanmakuSendTheme.portraitPanelHeight);

  void _toggleStyle() {
    widget.session.sender.sawStyleHint();
    if (_styleShown) {
      _focus.requestFocus();
      return;
    }
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 0) _keyboard[_landscape] = inset;
    setState(() => _styleShown = true);
    _focus.unfocus();
  }

  Future<void> _send() async {
    final session = widget.session;
    final sender = session.sender;
    if (!sender.canSend || session.closed) return;
    final message = await sender.send();
    if (!mounted) return;
    if (message != null) {
      widget.toast(message);
    } else if (identical(widget.session, session)) {
      session.closeSend();
    }
  }

  void _close() => widget.session.closeSend();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (!session.sendOpen.value) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    final panel = _panelHeight;
    _trackKeyboard(inset, panel);
    final dark = _landscape;
    final inline = widget.presentation == Presentation.inline;
    final below = _styleShown
        ? SizedBox(
            height: panel,
            child: DanmakuStylePanel(
              model: session.sender,
              dark: dark,
              offerBottom: _landscape,
              isVip: session.isVip,
              onVipOnly: () => widget.toast('开通大会员后可使用'),
            ),
          )
        : SizedBox(
            key: const ValueKey('danmaku-send-keyboard'),
            height: math.max(inset, media.viewPadding.bottom),
            child: ColoredBox(color: dark ? DanmakuSendTheme.darkArea : DanmakuSendTheme.lightBar),
          );
    return BlockSemantics(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: inline ? widget.playerBottom : 0,
            bottom: 0,
            child: Semantics(
              button: true,
              label: '关闭',
              onTap: _close,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('danmaku-send-dim'),
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: inline ? const ColoredBox(color: DanmakuSendTheme.dim) : const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DanmakuSendBar(
                  model: session.sender,
                  presentation: widget.presentation,
                  focusNode: _focus,
                  styleShown: _styleShown,
                  closed: session.closed,
                  onStyle: _toggleStyle,
                  onSend: () => unawaited(_send()),
                ),
                below,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
