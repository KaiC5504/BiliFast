import 'package:bilifast/device/status_bar.dart';
import 'package:bilifast/player_ui/status_bar_view.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'landscape_chrome_test.dart' show CountingStatusFeed;

const _charging = DeviceStatus(battery: 0.85, charging: true, network: StatusNetwork.wifi);

Future<void> _mount(WidgetTester tester, StatusBarFeed feed, {DateTime Function()? now}) async {
  tester.view
    ..physicalSize = const Size(956, 440)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(left: 62, right: 62, bottom: 21);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LandscapeStatusBar(feed: feed, now: now ?? DateTime.now),
            ),
          ],
        ),
      ),
    ),
  );
}

BatteryPainter _battery(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.descendant(of: find.byType(BatteryGlyph), matching: find.byType(CustomPaint)))
            .painter!
        as BatteryPainter;

void main() {
  test('the time reads HH:mm', () {
    expect(LandscapeStatusBar.timeOf(DateTime(2026, 10, 20, 9, 5)), '09:05');
    expect(LandscapeStatusBar.timeOf(DateTime(2026, 10, 20, 19, 35, 59)), '19:35');
    expect(LandscapeStatusBar.timeOf(DateTime(2026, 10, 20)), '00:00');
  });

  testWidgets('the time is the local clock, turning over with each minute', (tester) async {
    var clock = DateTime(2026, 10, 20, 9, 5, 30);
    await _mount(tester, FixedStatusBarFeed(_charging), now: () => clock);
    expect(find.text('09:05'), findsOneWidget);

    clock = DateTime(2026, 10, 20, 9, 5, 59);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text('09:05'), findsOneWidget);

    clock = DateTime(2026, 10, 20, 9, 6);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('09:06'), findsOneWidget);

    clock = DateTime(2026, 10, 20, 9, 7);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('09:07'), findsOneWidget);
  });

  testWidgets('WIFI shows only on Wi-Fi; the level stays either way', (tester) async {
    final feed = FixedStatusBarFeed(_charging);
    await _mount(tester, feed);
    expect(find.text('WIFI'), findsOneWidget);

    for (final network in [StatusNetwork.cellular, StatusNetwork.none]) {
      feed.status.value = DeviceStatus(battery: 0.85, charging: true, network: network);
      await tester.pump();
      expect(find.text('WIFI'), findsNothing, reason: network.name);
      expect(find.byKey(const ValueKey('status-wifi')), findsNothing, reason: network.name);
      expect(find.text('85%'), findsOneWidget, reason: network.name);
      expect(tester.getRect(find.byType(BatteryGlyph)).right, closeTo(883, 0.01), reason: network.name);
    }

    feed.status.value = _charging;
    await tester.pump();
    expect(find.text('WIFI'), findsOneWidget);
  });

  testWidgets('the battery fills to the level: white as on 04, green under a white bolt while charging as on 05', (
    tester,
  ) async {
    final feed = FixedStatusBarFeed(const DeviceStatus(battery: 0.75, charging: false, network: StatusNetwork.wifi));
    await _mount(tester, feed);
    expect(find.text('75%'), findsOneWidget);
    var battery = _battery(tester);
    const inside = LandscapeStatusTheme.batteryWidth - LandscapeStatusTheme.fillInset * 2;
    expect(battery.fill.width, closeTo(inside * 0.75, 0.001));
    expect(battery.fill.width, closeTo(12, 0.001), reason: "04's 75% fill is 12 pt");
    expect(battery.fill.height, LandscapeStatusTheme.batteryHeight - LandscapeStatusTheme.fillInset * 2);
    expect(battery.fillColor, BiliColors.onVideo);
    final glyph = find.descendant(of: find.byType(BatteryGlyph), matching: find.byType(CustomPaint));
    expect(
      tester.renderObject(glyph),
      paints
        ..rrect(style: PaintingStyle.stroke, color: BiliColors.onVideo)
        ..rrect(color: BiliColors.onVideo)
        ..rrect(color: BiliColors.onVideo),
    );
    expect(tester.renderObject(glyph), isNot(paints..path()));

    feed.status.value = _charging;
    await tester.pump();
    expect(find.text('85%'), findsOneWidget);
    battery = _battery(tester);
    expect(battery.charging, isTrue);
    expect(battery.fill.width, closeTo(inside * 0.85, 0.001));
    expect(battery.fillColor, LandscapeStatusTheme.charging);
    expect(
      tester.renderObject(glyph),
      paints
        ..rrect(style: PaintingStyle.stroke)
        ..rrect(color: BiliColors.onVideo)
        ..rrect(color: LandscapeStatusTheme.charging)
        ..path(color: BiliColors.onVideo),
    );

    feed.status.value = const DeviceStatus(battery: 0, charging: false, network: StatusNetwork.wifi);
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);
    expect(_battery(tester).fill.width, 0);
  });

  testWidgets('a battery iOS cannot read draws neither the level nor the glyph', (tester) async {
    const unknown = DeviceStatus(battery: null, charging: false, network: StatusNetwork.wifi);
    await _mount(tester, FixedStatusBarFeed(unknown));
    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(BatteryGlyph), findsNothing);
    expect(find.text('WIFI'), findsOneWidget);
  });

  testWidgets('watches its feed from when it shows until it is disposed, one for one, and moves to a new feed', (
    tester,
  ) async {
    final first = CountingStatusFeed(_charging);
    await _mount(tester, first);
    expect(first.calls, [true]);

    await tester.pump(const Duration(minutes: 2));
    expect(first.calls, [true], reason: 'the clock ticking watches nothing new');

    final second = CountingStatusFeed(_charging);
    await _mount(tester, second);
    expect(first.calls, [true, false]);
    expect(second.calls, [true]);

    await tester.pumpWidget(const SizedBox());
    expect(second.calls, [true, false]);
  });

  testWidgets('takes no touches', (tester) async {
    await _mount(tester, FixedStatusBarFeed(_charging));
    expect(find.byKey(const ValueKey('status-time')).hitTestable(), findsNothing);
    expect(find.byType(BatteryGlyph).hitTestable(), findsNothing);
  });
}
