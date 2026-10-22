import 'dart:async';

import 'package:bilifast/app/phone_frame.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/main.dart' show DefaultStatusBar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _navigator = GlobalKey<NavigatorState>();

/// A dressed page asking for white icons, as 我的 over a dark skin does.
const _lightPage = AnnotatedRegion<SystemUiOverlayStyle>(
  value: SystemUiOverlayStyle.light,
  child: ColoredBox(color: Color(0xFF161513)),
);

/// A white page that names no style.
Widget _plainPage(BuildContext context) => const ColoredBox(color: Color(0xFFFFFFFF));

Future<void> _show(WidgetTester tester, {required TransitionBuilder builder}) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(navigatorKey: _navigator, builder: builder, home: _lightPage));
  await tester.pump();
}

Future<void> _push(WidgetTester tester, WidgetBuilder page) async {
  unawaited(_navigator.currentState!.push(SwipeBackPageRoute<void>(builder: page)));
  await tester.pumpAndSettle();
  await tester.pump();
}

Future<void> _pop(WidgetTester tester) async {
  _navigator.currentState!.pop();
  await tester.pumpAndSettle();
  await tester.pump();
}

Brightness? _icons() => SystemChrome.latestStyle?.statusBarIconBrightness;

void main() {
  testWidgets('without the default a page naming no style keeps the light one under it: white on white', (
    tester,
  ) async {
    await _show(tester, builder: (context, child) => child!);
    expect(_icons(), Brightness.light);
    await _push(tester, _plainPage);
    expect(_icons(), Brightness.light);
  });

  testWidgets("with it that page gets dark icons, a page's own style still wins, and back is light again", (
    tester,
  ) async {
    await _show(tester, builder: (context, child) => DefaultStatusBar(child: child!));
    expect(_icons(), Brightness.light);
    await _push(tester, _plainPage);
    expect(_icons(), Brightness.dark);
    await _push(tester, (context) => _lightPage);
    expect(_icons(), Brightness.light);
    await _pop(tester);
    expect(_icons(), Brightness.dark);
    await _pop(tester);
    expect(_icons(), Brightness.light);
  });

  testWidgets("on Windows the drawn status bar follows the same style", (tester) async {
    await _show(tester, builder: (context, child) => PhoneFrame.wrap(context, DefaultStatusBar(child: child!)));
    await tester.pump();
    expect(PhoneFrame.statusBarBrightness.value, Brightness.dark, reason: 'white icons');
    await _push(tester, _plainPage);
    expect(PhoneFrame.statusBarBrightness.value, Brightness.light, reason: 'black icons');
    await _pop(tester);
    expect(PhoneFrame.statusBarBrightness.value, Brightness.dark);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
