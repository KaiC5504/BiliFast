import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/devlog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme.dart';
import '../../shared/toast.dart';
import 'video_actions.dart';

/// Opens a link outside the app; false when nothing could.
typedef OpenLink = Future<bool> Function(Uri link);

Future<bool> _openExternally(Uri link) => launchUrl(link);

/// 投币 (15): the one- and two-coin crates, 22娘, the balance and 同时点赞内容, over the whole page (BiliNative
/// `CoinDialog.swift`). Arrows, a sideways swipe or a tap on the other crate picks; a swipe up or a tap on 22娘 (or
/// on the picked crate) throws, and the coin goes out once the dialog has gone.
class CoinDialog extends StatefulWidget {
  const CoinDialog({super.key, required this.actions, required this.onClose, this.openLink = _openExternally});

  final VideoActions actions;
  final VoidCallback onClose;

  /// Tests pass their own so nothing reaches the platform.
  final OpenLink openLink;

  /// 如何获取硬币？, as BiliNative opens it.
  static final helpLink = Uri.parse('https://www.bilibili.com/blackboard/help.html');

  /// 同时点赞内容, on by default; kept for the session only until the player prefs carry it.
  static bool alsoLike = true;

  @override
  State<CoinDialog> createState() => _CoinDialogState();
}

abstract final class _Art {
  static const _dir = 'assets/images/paycoins';
  static const box = '$_dir/ic_pay_coins_box.png';
  static const coinOne = '$_dir/ic_coins_one.png';
  static const coinTwo = '$_dir/ic_coins_two.png';
  static const mario = '$_dir/ic_22_mario.png';
  static const gunSister = '$_dir/ic_22_gun_sister.png';
  static const notEnough = '$_dir/ic_22_not_enough_pay.png';
  static const thunder = ['$_dir/ic_thunder_1.png', '$_dir/ic_thunder_2.png', '$_dir/ic_thunder_3.png'];

  static String arrow({required bool left, required bool enabled}) =>
      '$_dir/ic_${left ? 'left' : 'right'}${enabled ? '' : '_disable'}.png';
}

class _CoinDialogState extends State<CoinDialog> with TickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final _mascotIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final _mascotRise = CurvedAnimation(parent: _mascotIn, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  late final _throw = AnimationController(vsync: this, duration: _throwTime);

  late int _selection = _offered.last;
  double? _balance;
  bool _throwing = false;
  bool _closing = false;
  Offset _drag = Offset.zero;

  VideoActions get _actions => widget.actions;

  /// A repost, or an original with one coin given, offers only the one-coin crate.
  List<int> get _offered => _actions.maxCoins >= 2 ? const [1, 2] : const [1];

  bool _affordable(int multiply) {
    final balance = _balance;
    return balance == null ? multiply >= 1 && multiply <= _actions.maxCoins : _actions.canGive(multiply, balance);
  }

  @override
  void initState() {
    super.initState();
    _entrance.forward();
    _mascotIn.forward();
    unawaited(_askBalance());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && !_closing) _mascotIn.value = 1;
    _throw.duration = still ? Duration.zero : _throwTime;
  }

  static const _throwTime = Duration(milliseconds: 500);

  @override
  void dispose() {
    _entrance.dispose();
    _mascotRise.dispose();
    _mascotIn.dispose();
    _pulse.dispose();
    _throw.dispose();
    super.dispose();
  }

  /// The balance decides which crates are open, so a failed ask is tried again while the dialog stays up.
  Future<void> _askBalance() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: attempt));
      if (!mounted || _closing) return;
      try {
        final balance = await _actions.coinBalance();
        if (!mounted) return;
        setState(() {
          _balance = balance;
          if (!_affordable(_selection) && _affordable(1)) _selection = 1;
        });
        return;
      } catch (error) {
        Logger.shared.warn(LogCategory.api, 'coin balance failed', {
          'attempt': attempt,
          'error': '${error.runtimeType}',
        });
      }
    }
  }

  void _choose(int multiply) {
    if (_throwing || _closing || multiply == _selection || !_offered.contains(multiply)) return;
    setState(() => _selection = multiply);
    if (!MediaQuery.disableAnimationsOf(context)) _pulse.forward(from: 0);
    unawaited(HapticFeedback.selectionClick());
  }

  void _tapCrate(int multiply) => multiply == _selection ? _send() : _choose(multiply);

  void _dragEnd() {
    final drag = _drag;
    _drag = Offset.zero;
    if (drag.dx.abs() > drag.dy.abs() && drag.dx.abs() > 40) {
      _choose(drag.dx < 0 ? _selection + 1 : _selection - 1);
    } else if (drag.dy < -50 && drag.dy.abs() > drag.dx.abs()) {
      _send();
    }
  }

  Future<void> _send() async {
    if (_throwing || _closing) return;
    if (!_affordable(_selection)) {
      showToast(context, '硬币不足');
      return;
    }
    final multiply = _selection;
    final alsoLike = CoinDialog.alsoLike;
    setState(() => _throwing = true);
    unawaited(HapticFeedback.mediumImpact());
    await _throw.forward();
    if (!mounted) return;
    unawaited(_actions.coin(multiply, alsoLike: alsoLike));
    await _close();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    unawaited(_mascotIn.reverse());
    await _entrance.reverse();
    if (mounted) widget.onClose();
  }

  Future<void> _help() async {
    var opened = false;
    try {
      opened = await widget.openLink(CoinDialog.helpLink);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'coin help link failed', {'error': '${error.runtimeType}'});
    }
    if (!opened && mounted) showToast(context, '每日登录可获得1硬币');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final landscape = size.width > size.height;
    final shown = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: FadeTransition(
            opacity: shown,
            child: const ColoredBox(color: ActionTheme.coinDim),
          ),
        ),
        if (landscape) _landscape(size, padding, shown) else ..._portrait(size, padding, shown),
      ],
    );
  }

  static const _stageHeight =
      ActionTheme.selectedCrate +
      ActionTheme.mascotGap +
      ActionTheme.mascotHeight +
      ActionTheme.hintGap +
      ActionTheme.hintLine * 2;

  List<Widget> _portrait(Size size, EdgeInsets padding, Animation<double> shown) {
    final top = size.height * ActionTheme.cratesCentre - ActionTheme.selectedCrate / 2;
    final bottom = padding.bottom + ActionTheme.bottomLift - ActionTheme.bottomRow / 2;
    return [
      Positioned(left: 0, right: 0, top: top, height: _stageHeight, child: _stage(size.width, shown)),
      Positioned(
        left: 0,
        right: 0,
        bottom: bottom,
        height: ActionTheme.bottomRow,
        child: FadeTransition(opacity: shown, child: _bottomRow()),
      ),
    ];
  }

  Widget _landscape(Size size, EdgeInsets padding, Animation<double> shown) {
    const gap = ActionTheme.bottomLift - ActionTheme.bottomRow / 2;
    const natural = _stageHeight + gap + ActionTheme.bottomRow;
    final available = size.height - padding.top - padding.bottom - ActionTheme.hintGap * 2;
    final scale = math.min(1.0, available / natural);
    return Center(
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: ActionTheme.landscapeColumn,
          height: natural,
          child: Column(
            children: [
              _stage(ActionTheme.landscapeColumn, shown),
              const SizedBox(height: gap),
              SizedBox(
                height: ActionTheme.bottomRow,
                child: FadeTransition(opacity: shown, child: _bottomRow()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The crates, 22娘 and the two lines under her; swiping anywhere on it picks or throws.
  Widget _stage(double width, Animation<double> shown) {
    final balance = _balance;
    final short = balance != null && !_affordable(_selection);
    final text = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: ActionTheme.hintFont,
      height: ActionTheme.hintLine / ActionTheme.hintFont,
      color: ActionTheme.coinText,
      decoration: TextDecoration.none,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _drag = Offset.zero,
      onPanUpdate: (details) => _drag += details.delta,
      onPanEnd: (_) => _dragEnd(),
      onPanCancel: () => _drag = Offset.zero,
      child: SizedBox(
        width: width,
        height: _stageHeight,
        child: Column(
          children: [
            _crates(width, shown),
            const SizedBox(height: ActionTheme.mascotGap),
            _mascot(),
            const SizedBox(height: ActionTheme.hintGap),
            FadeTransition(
              opacity: shown,
              child: Column(
                children: [
                  Text(short ? '硬币不足' : '上滑或点击22娘投硬币', style: text.copyWith(color: ActionTheme.coinHint)),
                  Text('硬币余额：${balance == null ? '--' : balance.toStringAsFixed(1)}', style: text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _crates(double width, Animation<double> shown) {
    final still = MediaQuery.disableAnimationsOf(context);
    final slide = still ? Duration.zero : const Duration(milliseconds: 320);
    final offered = _offered;
    final rise = CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack);
    return SizedBox(
      width: width,
      height: ActionTheme.selectedCrate,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final multiply in offered)
            AnimatedPositioned(
              key: ValueKey(multiply),
              duration: slide,
              curve: Curves.easeOutCubic,
              left: width / 2 + (multiply - _selection) * ActionTheme.crateSpacing - _side(multiply) / 2,
              top: (ActionTheme.selectedCrate - _side(multiply)) / 2,
              width: _side(multiply),
              height: _side(multiply),
              child: FadeTransition(
                opacity: shown,
                child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(rise), child: _crate(multiply)),
              ),
            ),
          if (offered.length > 1 && !_throwing) ...[
            _arrow(left: true, enabled: _selection == 2, shown: shown),
            _arrow(left: false, enabled: _selection == 1, shown: shown),
          ],
        ],
      ),
    );
  }

  double _side(int multiply) => multiply == _selection ? ActionTheme.selectedCrate : ActionTheme.crate;

  Widget _crate(int multiply) {
    final selected = multiply == _selection;
    final affordable = _affordable(multiply);
    final hop = CurvedAnimation(parent: _throw, curve: const Interval(0, 0.2));
    final flight = CurvedAnimation(
      parent: _throw,
      curve: const Interval(0.15, 0.85, curve: Curves.easeIn),
    );
    final fade = CurvedAnimation(parent: _throw, curve: const Interval(0.55, 0.85));
    return Semantics(
      button: true,
      label: '$multiply 硬币',
      selected: selected,
      onTap: () => _tapCrate(multiply),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapCrate(multiply),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            final tint = affordable ? null : ActionTheme.coinUnaffordable;
            return AnimatedBuilder(
              animation: _throw,
              builder: (context, _) {
                final thrown = selected && _throwing;
                final lift = thrown ? -math.sin(math.pi * hop.value) * side * 0.12 : 0.0;
                final frame = thrown && multiply == 2 ? _thunderFrame(_throw.value) : null;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, lift),
                      child: Image.asset(
                        _Art.box,
                        width: side,
                        height: side,
                        color: tint,
                        colorBlendMode: BlendMode.srcATop,
                        gaplessPlayback: true,
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, side * ActionTheme.coinArtDrop + (thrown ? -flight.value * side * 3.2 : lift)),
                      child: Opacity(
                        opacity: thrown ? 1 - fade.value : 1,
                        child: Image.asset(
                          multiply == 1 ? _Art.coinOne : _Art.coinTwo,
                          height: side * ActionTheme.coinArt,
                          color: tint,
                          colorBlendMode: BlendMode.srcATop,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    if (frame != null)
                      IgnorePointer(
                        child: OverflowBox(
                          maxWidth: side * ActionTheme.thunderWidth,
                          maxHeight: double.infinity,
                          child: Transform.translate(
                            // The first frame's glowing square sits below the art's centre; it goes on the crate.
                            offset: Offset(0, frame == 0 ? -side * ActionTheme.thunderFirstDrop : 0),
                            child: Image.asset(_Art.thunder[frame], width: side * ActionTheme.thunderWidth),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// The lightning plays over the two-coin crate as its coin leaves, as the official app's does.
  static int? _thunderFrame(double t) {
    if (t < 0.2 || t >= 0.74) return null;
    return ((t - 0.2) / 0.18).floor().clamp(0, 2);
  }

  Widget _arrow({required bool left, required bool enabled, required Animation<double> shown}) {
    const top = (ActionTheme.selectedCrate - ActionTheme.arrowHeight) / 2;
    const inset = ActionTheme.arrowCentreInset - ActionTheme.arrowWidth / 2;
    final target = left ? 1 : 2;
    final image = Image.asset(
      _Art.arrow(left: left, enabled: enabled),
      width: ActionTheme.arrowWidth,
      height: ActionTheme.arrowHeight,
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );
    // The touch area reaches past the small arrow; the art stays where 15 draws it.
    const reach = BiliMetrics.gutter;
    return Positioned(
      left: left ? inset - reach : null,
      right: left ? null : inset - reach,
      top: top - reach,
      child: FadeTransition(
        opacity: shown,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: '选择$target硬币',
          onTap: enabled ? () => _choose(target) : null,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _choose(target) : null,
            child: Padding(padding: const EdgeInsets.all(reach), child: image),
          ),
        ),
      ),
    );
  }

  Widget _mascot() {
    final affordable = _affordable(_selection);
    final art = !affordable ? _Art.notEnough : (_selection == 1 ? _Art.mario : _Art.gunSister);
    final pulse = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    final hop = CurvedAnimation(parent: _throw, curve: const Interval(0, 0.2));
    return Semantics(
      button: true,
      label: '投币',
      onTap: _send,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _send,
        child: AnimatedBuilder(
          animation: Listenable.merge([_mascotRise, _throw]),
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              (1 - _mascotRise.value) * ActionTheme.mascotHeight * 3 -
                  math.sin(math.pi * hop.value) * ActionTheme.mascotHeight * 0.12,
            ),
            child: child,
          ),
          child: ScaleTransition(
            scale: pulse,
            // A fixed box, so she takes taps and holds her place before her art has decoded.
            child: SizedBox(
              width: ActionTheme.mascotHeight * ActionTheme.mascotAspect,
              height: ActionTheme.mascotHeight,
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
                child: Image.asset(art, key: ValueKey(art), height: ActionTheme.mascotHeight, gaplessPlayback: true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomRow() {
    final style = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: ActionTheme.bottomFont,
      color: ActionTheme.coinText,
      decoration: TextDecoration.none,
    );
    final alsoLike = CoinDialog.alsoLike;
    void toggle() => setState(() => CoinDialog.alsoLike = !CoinDialog.alsoLike);
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Semantics(
            label: '同时点赞内容',
            toggled: alsoLike,
            onTap: toggle,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.only(left: ActionTheme.bottomInset, right: BiliMetrics.gutter),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: ActionTheme.checkbox,
                      child: CustomPaint(painter: _CheckboxPainter(alsoLike)),
                    ),
                    const SizedBox(width: ActionTheme.checkboxGap),
                    Text('同时点赞内容', style: style),
                  ],
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Semantics(
            button: true,
            label: '关闭',
            onTap: _close,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: SizedBox.square(
                dimension: ActionTheme.bottomRow,
                child: Center(
                  child: SizedBox.square(
                    dimension: ActionTheme.close,
                    child: CustomPaint(painter: _ClosePainter()),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Semantics(
            button: true,
            label: '如何获取硬币？',
            onTap: _help,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _help,
              child: Padding(
                padding: const EdgeInsets.only(left: BiliMetrics.gutter, right: ActionTheme.bottomEndInset),
                child: Center(child: Text('如何获取硬币？', style: style)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 15's square tick box: a white rounded outline, ticked when on.
class _CheckboxPainter extends CustomPainter {
  _CheckboxPainter(this.on);

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ActionTheme.coinText
      ..style = PaintingStyle.stroke
      ..strokeWidth = ActionTheme.checkboxLine
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final box = (Offset.zero & size).deflate(ActionTheme.checkboxLine / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(ActionTheme.checkboxRadius)), line);
    if (!on) return;
    final w = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.17, w * 0.53)
        ..lineTo(w * 0.4, w * 0.74)
        ..lineTo(w * 0.83, w * 0.33),
      line..strokeWidth = ActionTheme.checkboxTick,
    );
  }

  @override
  bool shouldRepaint(_CheckboxPainter old) => old.on != on;
}

/// 15's ✕: a thin half-white ring round a small cross.
class _ClosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final paint = Paint()
      ..color = ActionTheme.coinClose
      ..style = PaintingStyle.stroke
      ..strokeWidth = ActionTheme.closeRing;
    canvas.drawCircle(centre, (size.shortestSide - ActionTheme.closeRing) / 2, paint);
    paint
      ..strokeWidth = ActionTheme.closeCross
      ..strokeCap = StrokeCap.round;
    const half = ActionTheme.closeCrossHalf;
    canvas
      ..drawLine(centre + const Offset(-half, -half), centre + const Offset(half, half), paint)
      ..drawLine(centre + const Offset(half, -half), centre + const Offset(-half, half), paint);
  }

  @override
  bool shouldRepaint(_ClosePainter old) => false;
}
