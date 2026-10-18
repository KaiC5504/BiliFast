import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../device/orientation.dart';

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
    final padding = media.size.width > media.size.height ? landscapePadding : portraitPadding;
    return MediaQuery(data: media.copyWith(padding: padding, viewPadding: padding), child: child);
  }
}
