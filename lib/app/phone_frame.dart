import 'dart:async';

import 'package:flutter/foundation.dart';
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
      children: [framed, const Positioned(top: 0, left: 0, right: 0, height: 62, child: _StatusBar())],
    );
  }
}

/// The iPhone's clock, signal, Wi-Fi and battery where 01 shows them, so the band above the content reads as the
/// phone's status bar rather than a gap. Drawn as a difference with white, so it shows on light and black pages.
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
    return IgnorePointer(child: CustomPaint(painter: _StatusPainter(time)));
  }
}

class _StatusPainter extends CustomPainter {
  _StatusPainter(this.time);

  final String time;

  static final _ink = Paint()
    ..color = BiliColors.onVideo
    ..blendMode = BlendMode.difference;

  @override
  void paint(Canvas canvas, Size size) {
    final clock = TextPainter(
      text: TextSpan(
        text: time,
        style: TextStyle(fontFamily: BiliFonts.family, fontSize: 17, fontWeight: FontWeight.w600, foreground: _ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // 01: the clock's ink runs from x 61 to 106 and y 26 to 39.
    clock.paint(canvas, Offset(83.5 - clock.width / 2, 32.5 - clock.height / 2));
    for (var bar = 0; bar < 4; bar++) {
      final height = 4.0 + bar * 2.6;
      canvas.drawRRect(
        RRect.fromLTRBR(312 + bar * 4.5, 38.5 - height, 315 + bar * 4.5, 38.5, const Radius.circular(1)),
        _ink,
      );
    }
    final wifi = Paint()
      ..color = BiliColors.onVideo
      ..blendMode = BlendMode.difference
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final radius in [4.5, 8.5, 12.5]) {
      canvas.drawArc(Rect.fromCircle(center: const Offset(350.5, 39), radius: radius), -2.3, 1.6, false, wifi);
    }
    canvas.drawRRect(RRect.fromLTRBR(368, 27, 387, 38.5, const Radius.circular(3.5)), _ink);
    canvas.drawRRect(RRect.fromLTRBR(388, 30.5, 389.5, 35, const Radius.circular(1)), _ink);
  }

  @override
  bool shouldRepaint(_StatusPainter oldDelegate) => oldDelegate.time != time;
}
