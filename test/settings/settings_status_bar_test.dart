import 'dart:async';

import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/main.dart' show DefaultStatusBar;
import 'package:bilifast/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dressed 我的 asking for white icons.
const _lightPage = AnnotatedRegion<SystemUiOverlayStyle>(
  value: SystemUiOverlayStyle.light,
  child: ColoredBox(color: Color(0xFF161513)),
);

void main() {
  /// Pushes [page] over [_lightPage] and stops the slide once its left edge has passed the status bar's middle,
  /// where the engine looks for the style; the page under it is still drawn.
  Future<Brightness?> midPush(WidgetTester tester, Widget page) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => DefaultStatusBar(child: child!),
        home: _lightPage,
      ),
    );
    await tester.pump();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    unawaited(navigator.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => page)));
    // The route's first frame lays it out offstage, where it slides from.
    await tester.pump();
    double left() => tester.getTopLeft(find.byWidget(page)).dx;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (left() < 210) break;
    }
    expect(left(), inExclusiveRange(150, 220));
    expect(find.byWidget(_lightPage), findsOneWidget, reason: 'still drawn under it');
    final icons = SystemChrome.latestStyle?.statusBarIconBrightness;
    await tester.pumpAndSettle();
    return icons;
  }

  testWidgets("设置 pushed over a dressed 我的 turns the icons dark as it covers the bar's middle, not at the end", (
    tester,
  ) async {
    expect(await midPush(tester, const SettingsScaffold(title: '设置', children: [])), Brightness.dark);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('a page naming no style would leave them white over it until the slide ends', (tester) async {
    expect(await midPush(tester, const ColoredBox(color: Color(0xFFFFFFFF))), Brightness.light);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark, reason: 'the default, once under it');
  });
}
