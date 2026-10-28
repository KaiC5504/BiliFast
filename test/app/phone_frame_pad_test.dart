import 'package:bilifast/app/phone_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => PhoneFrame.wrap(context, child!),
    home: const ColoredBox(color: Color(0xFF000000)),
  ));
}

EdgeInsets _padding(WidgetTester tester) =>
    MediaQuery.paddingOf(tester.element(find.byType(ColoredBox).last));

Finder _bar<T>() => find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is T);

void main() {
  group('with --pad', () {
    setUp(() => PhoneFrame.debugPad = true);
    tearDown(() => PhoneFrame.debugPad = false);

    testWidgets("the iPad's 24 pt status bar, sideways, full screen included", (tester) async {
      await _show(tester, PhoneFrame.padLandscape);
      expect(_padding(tester), PhoneFrame.padPadding);
      expect(_bar<PadStatusPainter>(), findsOneWidget);
      expect(tester.getSize(_bar<PadStatusPainter>()), Size(PhoneFrame.padLandscape.width, 24));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('and upright', (tester) async {
      await _show(tester, PhoneFrame.padPortrait);
      expect(_padding(tester), PhoneFrame.padPadding);
      expect(tester.getSize(_bar<PadStatusPainter>()), Size(PhoneFrame.padPortrait.width, 24));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  testWidgets("the iPhone's frame is as it was: its bar upright, none in landscape", (tester) async {
    await _show(tester, PhoneFrame.portrait);
    expect(_padding(tester), PhoneFrame.portraitPadding);
    expect(_bar<PadStatusPainter>(), findsNothing);
    expect(tester.getSize(find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter != null).last),
        const Size(440, 62));

    await _show(tester, PhoneFrame.landscape);
    expect(_padding(tester), PhoneFrame.landscapePadding);
    expect(find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter != null), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  test("the iPad's time and date as ipad/01 writes them", () {
    expect(padStatusTime(DateTime(2026, 10, 29, 0, 12)), '12:12 AM');
    expect(padStatusTime(DateTime(2026, 10, 29, 13, 5)), '1:05 PM');
    expect(padStatusTime(DateTime(2026, 10, 29, 12)), '12:00 PM');
    expect(padStatusDate(DateTime(2026, 10, 29)), 'Thu 29 Oct');
    expect(padStatusDate(DateTime(2026, 3, 1)), 'Sun 1 Mar');
  });
}
