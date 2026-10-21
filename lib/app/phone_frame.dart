import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../device/orientation.dart';
import '../shared/theme.dart';

/// On Windows the app runs in a window the size of KaiC's iPhone 17 Pro Max, so layouts look as they will on the
/// phone: upright 440×956, turned sideways for landscape full screen, with the phone's safe areas around the content.
abstract final class PhoneFrame {
  static const portrait = Size(440, 956);
  static const landscape = Size(956, 440);

  /// The Dynamic Island and the home indicator, in points.
  static const portraitPadding = EdgeInsets.only(top: 62, bottom: 34);
  static const landscapePadding = EdgeInsets.only(left: 62, right: 62, bottom: 21);

  static const _channel = MethodChannel('bilifast/window');

  static bool get enabled => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The status bar's brightness the page under it asks for with its [AnnotatedRegion], read where iOS reads it;
  /// null until a page has asked.
  @visibleForTesting
  static ValueListenable<Brightness?> get statusBarBrightness => _statusBarBrightness;
  static final _statusBarBrightness = ValueNotifier<Brightness?>(null);

  /// Turns the window with landscape full screen and back.
  static void follow(OrientationController orientation) {
    if (!enabled) return;
    var landscapeNow = false;
    orientation.addListener(() {
      final wanted = orientation.presentation == Presentation.landscape;
      if (wanted == landscapeNow) return;
      landscapeNow = wanted;
      final size = wanted ? landscape : portrait;
      unawaited(_channel
          .invokeMethod<void>('setClientSize', {'width': size.width, 'height': size.height})
          .catchError((Object _) {}));
    });
  }

  /// Gives the content the phone's safe areas, by the window's shape.
  static Widget wrap(BuildContext context, Widget child) {
    if (!enabled) return child;
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    final padding = landscape ? landscapePadding : portraitPadding;
    final framed = MediaQuery(data: media.copyWith(padding: padding, viewPadding: padding), child: child);
    // The phone hides its status bar in landscape full screen.
    if (landscape) return framed;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        _StyleProbe(child: framed),
        const Positioned(top: 0, left: 0, right: 0, height: 62, child: _StatusBar()),
      ],
    );
  }
}

/// Finds the page's [SystemUiOverlayStyle] at the status bar's middle after each frame, as the engine does for the
/// phone's own bar (`RenderView`), whose layer tree only a render object can search.
class _StyleProbe extends SingleChildRenderObjectWidget {
  const _StyleProbe({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderStyleProbe();
}

class _RenderStyleProbe extends RenderProxyBox {
  static _RenderStyleProbe? _attached;
  static bool _watching = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _attached = this;
    if (_watching) return;
    _watching = true;
    // Persistent callbacks can't be removed, so there is one for the app; it runs after the frame is composited.
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _attached?._find());
  }

  @override
  void detach() {
    if (identical(_attached, this)) _attached = null;
    super.detach();
  }

  void _find() {
    if (!hasSize) return;
    final at = Offset(size.width / 2, PhoneFrame.portraitPadding.top / 2);
    final brightness = layer?.find<SystemUiOverlayStyle>(at)?.statusBarBrightness;
    // As on the phone, a page that asks nothing leaves the bar as it was.
    if (brightness == null || brightness == PhoneFrame._statusBarBrightness.value) return;
    // The bar can't rebuild in the frame being finished.
    SchedulerBinding.instance.addPostFrameCallback((_) => PhoneFrame._statusBarBrightness.value = brightness);
  }
}

/// The iPhone's clock, signal, Wi-Fi and battery where 01 shows them, so the band above the content reads as the
/// phone's status bar rather than a gap. White or black as the page asks ([PhoneFrame.statusBarBrightness]); until
/// one has, a difference with white, which shows on light and black pages.
class _StatusBar extends StatefulWidget {
  const _StatusBar();

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: PhoneFrame.statusBarBrightness,
        builder: (context, brightness, _) => CustomPaint(
          painter: _StatusPainter(
            time,
            BiliFonts.family,
            switch (brightness) {
              Brightness.dark => BiliColors.onVideo,
              Brightness.light => BiliColors.videoBackground,
              null => null,
            },
          ),
        ),
      ),
    );
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter(this.time, this.family, this.ink);

  final String time;
  final String? family;

  /// Null draws a difference with white.
  final Color? ink;

  Paint _paint() => ink == null
      ? (Paint()
          ..color = BiliColors.onVideo
          ..blendMode = BlendMode.difference)
      : (Paint()..color = ink!);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = _paint();
    final clock = TextPainter(
      text: TextSpan(
        text: time,
        style: TextStyle(fontFamily: family, fontSize: 17, fontWeight: FontWeight.w600, foreground: fill),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // 01: the clock's ink runs from x 61 to 106 and y 26 to 39.
    clock.paint(canvas, Offset(83.5 - clock.width / 2, 32.5 - clock.height / 2));
    for (var bar = 0; bar < 4; bar++) {
      final height = 4.0 + bar * 2.6;
      canvas.drawRRect(
        RRect.fromLTRBR(312 + bar * 4.5, 38.5 - height, 315 + bar * 4.5, 38.5, const Radius.circular(1)),
        fill,
      );
    }
    final wifi = _paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final radius in [4.5, 8.5, 12.5]) {
      canvas.drawArc(Rect.fromCircle(center: const Offset(350.5, 39), radius: radius), -2.3, 1.6, false, wifi);
    }
    canvas.drawRRect(RRect.fromLTRBR(368, 27, 387, 38.5, const Radius.circular(3.5)), fill);
    canvas.drawRRect(RRect.fromLTRBR(388, 30.5, 389.5, 35, const Radius.circular(1)), fill);
  }

  @override
  bool shouldRepaint(_StatusPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.family != family || oldDelegate.ink != ink;
}
