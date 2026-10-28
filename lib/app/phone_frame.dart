import 'dart:async';

import 'package:bili_core/devlog.dart';
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

  /// KaiC's iPad Pro 11" (3rd generation) with `--pad`: 834×1194 upright, 1194×834 sideways, the status bar and the
  /// home indicator the same in both. The window opens sideways: upright is taller than the PC's screen.
  static const padPortrait = Size(834, 1194);
  static const padLandscape = Size(1194, 834);
  static const padPadding = EdgeInsets.only(top: 24, bottom: 20);

  /// Set by [usePad] before the first frame.
  static bool get pad => _pad;
  static bool _pad = false;

  @visibleForTesting
  static set debugPad(bool value) => _pad = value;

  static const _channel = MethodChannel('bilifast/window');

  static bool get enabled => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The status bar's brightness the page under it asks for with its [AnnotatedRegion], read where iOS reads it;
  /// null until a page has asked.
  @visibleForTesting
  static ValueListenable<Brightness?> get statusBarBrightness => _statusBarBrightness;
  static final _statusBarBrightness = ValueNotifier<Brightness?>(null);

  /// Makes the window KaiC's iPad, sideways.
  static void usePad() {
    if (!enabled) return;
    _pad = true;
    unawaited(_resize(padLandscape));
  }

  /// Turns the window with landscape full screen and back. The iPad doesn't turn for full screen.
  static void follow(OrientationController orientation) {
    if (!enabled || _pad) return;
    var landscapeNow = false;
    orientation.addListener(() {
      final wanted = orientation.presentation == Presentation.landscape;
      if (wanted == landscapeNow) return;
      landscapeNow = wanted;
      unawaited(_resize(wanted ? landscape : portrait));
    });
  }

  static Future<void> _resize(Size size) async {
    try {
      await _channel.invokeMethod<void>('setClientSize', {'width': size.width, 'height': size.height});
    } on Object catch (error) {
      Logger.shared.warn(LogCategory.ui, 'window resize failed', {'error': '${error.runtimeType}'});
    }
  }

  /// Gives the content the phone's safe areas, by the window's shape.
  static Widget wrap(BuildContext context, Widget child) {
    if (!enabled) return child;
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    final padding = _pad ? padPadding : (landscape ? landscapePadding : portraitPadding);
    final framed = MediaQuery(data: media.copyWith(padding: padding, viewPadding: padding), child: child);
    // The phone hides its status bar in landscape full screen; the iPad keeps it (08).
    if (landscape && !_pad) return framed;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        _StyleProbe(child: framed),
        Positioned(top: 0, left: 0, right: 0, height: padding.top, child: const _StatusBar()),
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
    final bar = PhoneFrame.pad ? PhoneFrame.padPadding : PhoneFrame.portraitPadding;
    final at = Offset(size.width / 2, bar.top / 2);
    final brightness = layer?.find<SystemUiOverlayStyle>(at)?.statusBarBrightness;
    // As on the phone, a page that asks nothing leaves the bar as it was.
    if (brightness == null || brightness == PhoneFrame._statusBarBrightness.value) return;
    // The bar can't rebuild in the frame being finished.
    SchedulerBinding.instance.addPostFrameCallback((_) => PhoneFrame._statusBarBrightness.value = brightness);
  }
}

/// The iPhone's clock, signal, Wi-Fi and battery where 01 shows them, so the band above the content reads as the
/// phone's status bar rather than a gap; with `--pad` the iPad's time, date, Wi-Fi and battery (ipad/01, 08). White or
/// black as the page asks ([PhoneFrame.statusBarBrightness]); until one has, a difference with white, which shows on
/// light and black pages.
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
        builder: (context, brightness, _) {
          final ink = switch (brightness) {
            Brightness.dark => BiliColors.onVideo,
            Brightness.light => BiliColors.videoBackground,
            null => null,
          };
          return CustomPaint(
            painter: PhoneFrame.pad
                ? PadStatusPainter(padStatusTime(now), padStatusDate(now), BiliFonts.family, ink)
                : _StatusPainter(time, BiliFonts.family, ink),
          );
        },
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

/// The iPad's clock as ipad/01 writes it: twelve hours, then AM or PM.
@visibleForTesting
String padStatusTime(DateTime now) {
  final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
  return '$hour:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}';
}

/// The date beside it, as KaiC's iPad writes it (Thu 29 Oct).
@visibleForTesting
String padStatusDate(DateTime now) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
}

/// The iPad's 24 pt status bar, measured off ipad/01 and 08 (pt = px / 2): the time's ink from x 17, AM 3.5 pt and
/// the date 12.5 pt after it, Wi-Fi from 103 pt before the right edge, 100% ending 48 pt before it, the battery's
/// outline from 42.5 to 18; text on the 20.5 pt baseline. The same upright and sideways (02).
@visibleForTesting
class PadStatusPainter extends CustomPainter {
  PadStatusPainter(this.time, this.date, this.family, this.ink);

  final String time;
  final String date;
  final String? family;

  /// Null draws a difference with white.
  final Color? ink;

  static const _baseline = 20.5;
  static const _meridiemGap = 2.5;
  static const _dateGap = 11.5;

  Paint _paint({double alpha = 1}) {
    final paint = Paint()..color = (ink ?? BiliColors.onVideo).withValues(alpha: alpha);
    if (ink == null) paint.blendMode = BlendMode.difference;
    return paint;
  }

  TextPainter _text(String text, Paint fill) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w500, foreground: fill),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  void _onBaseline(Canvas canvas, TextPainter text, double left) =>
      text.paint(canvas, Offset(left, _baseline - text.computeDistanceToActualBaseline(TextBaseline.alphabetic)));

  @override
  void paint(Canvas canvas, Size size) {
    final fill = _paint();
    // AM and PM sit closer than a space would put them.
    final split = time.lastIndexOf(' ');
    final clock = _text(split < 0 ? time : time.substring(0, split), fill);
    _onBaseline(canvas, clock, 16.5);
    var end = 16.5 + clock.width;
    if (split >= 0) {
      final meridiem = _text(time.substring(split + 1), fill);
      _onBaseline(canvas, meridiem, end + _meridiemGap);
      end += _meridiemGap + meridiem.width;
    }
    _onBaseline(canvas, _text(date, fill), end + _dateGap);

    final right = size.width;
    final percent = _text('100%', fill);
    _onBaseline(canvas, percent, right - 48 - percent.width);

    final wifi = Offset(right - 96.25, 20);
    canvas.drawCircle(wifi.translate(0, -1.2), 1.4, fill);
    final arc = _paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;
    for (final radius in [4.9, 8.0]) {
      canvas.drawArc(Rect.fromCircle(center: wifi, radius: radius), -2.32, 1.64, false, arc);
    }

    canvas.drawRRect(
      RRect.fromLTRBR(right - 42, 10, right - 18.5, 21.5, const Radius.circular(3.5)),
      _paint(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(RRect.fromLTRBR(right - 40.5, 11.5, right - 20, 20, const Radius.circular(2.5)), fill);
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(right - 16.5, 13.5, right - 15.25, 17.5,
          topRight: const Radius.circular(1), bottomRight: const Radius.circular(1)),
      _paint(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(PadStatusPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.date != date || oldDelegate.family != family || oldDelegate.ink != ink;
}
