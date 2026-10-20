import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/device/turn_style.dart';
import 'package:bilifast/devtools/turn_cycle.dart';
import 'package:bilifast/devtools/turn_cycle_badge.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/main.dart' show BiliFastApp;
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../device/fake_orientation_host.dart' show FakeOrientationHost;
import '../playback/fakes.dart';
import '../support/fake_player.dart';

/// 开发者 → 轮换测试: two round trips per style, through TurnStyle.cycle, then back to the style chosen before it.
void main() {
  final styles = TurnStyle.cycle;

  /// Chosen in 方式, 截图 and 起转 before the cycle starts.
  const chosen = TurnStyle(picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture);

  late MemorySink logs;
  late Logger logger;
  late PlayerPrefs prefs;
  late OrientationController orientation;
  late TurnCycle cycle;

  setUp(() {
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    prefs = PlayerPrefs.memory(logger: logger);
    orientation = OrientationController(logger: logger);
    cycle = TurnCycle(orientation: orientation, prefs: prefs, logger: logger);
  });

  tearDown(() {
    cycle.dispose();
    orientation.dispose();
  });

  List<LogEvent> cycleLines() => logs.events.where((event) => event.msg.startsWith('turn cycle')).toList();

  /// Out to landscape and back, each held long enough to count.
  void roundTrip(FakeAsync async, {Presentation back = Presentation.inline}) {
    orientation.enterLandscape();
    async.elapse(TurnCycle.settle);
    back == Presentation.vertical ? orientation.enterVertical() : orientation.exitToInline();
    async.elapse(TurnCycle.settle);
  }

  test('it walks 7 styles: 系统 first, then every 截图 and 起转 of 请求前关', () {
    expect(styles, hasLength(7));
    expect(styles.first, TurnStyle.system);
    final drawn = styles.skip(1);
    expect(drawn.map((style) => style.method), everyElement(TurnMethod.quietRequest));
    expect({for (final style in drawn) (style.picture, style.spinStart)}, {
      for (final picture in TurnPicture.values)
        for (final start in TurnSpinStart.values) (picture, start),
    });
    expect(styles[1], const TurnStyle(), reason: 'the shipped style right after the reference');
  });

  test('off at launch: turning counts nothing and nothing is applied', () {
    fakeAsync((async) {
      expect(cycle.on, isFalse);
      roundTrip(async);
      roundTrip(async);
      expect(cycle.position, 1);
      expect(cycle.roundTrips, 0);
      expect(prefs.turnStyle, const TurnStyle());
      expect(orientation.turnStyle, TurnStyle.system, reason: 'untouched; launch applies the saved style');
      expect(cycleLines(), isEmpty);
    });
  });

  test('switching on starts at 1, saves and applies it, and logs it', () {
    fakeAsync((async) {
      prefs.turnStyle = chosen;
      cycle.start();
      expect(cycle.on, isTrue);
      expect(cycle.position, 1);
      expect(cycle.style, styles.first);
      expect(prefs.turnStyle, styles.first);
      expect(orientation.turnStyle, styles.first);
      final line = cycleLines().single;
      expect(line.msg, 'turn cycle');
      expect(line.cat, LogCategory.ui);
      expect(line.f['index'], const LogInt(1));
      expect(line.f['of'], LogInt(styles.length));
      expect(line.f['label'], LogString(styles.first.label));
      expect(line.f['wUs'], isA<LogInt>());
      expect((line.f['wUs']! as LogInt).value, closeTo(DateTime.now().microsecondsSinceEpoch, 60e6));
    });
  });

  test('every 2 round trips it moves on: one counts once back upright, the second applies the next style', () {
    fakeAsync((async) {
      var notified = 0;
      cycle
        ..addListener(() => notified += 1)
        ..start();
      roundTrip(async);
      expect(cycle.roundTrips, 1);
      expect(cycle.position, 1);
      expect(orientation.turnStyle, styles[0]);
      roundTrip(async);
      expect(cycle.position, 2);
      expect(cycle.roundTrips, 0);
      expect(cycle.style, styles[1]);
      expect(prefs.turnStyle, cycle.style);
      expect(orientation.turnStyle, cycle.style);
      expect(cycleLines().map((line) => line.f['index']), const [LogInt(1), LogInt(2)]);
      expect(cycleLines().last.f['label'], LogString(styles[1].label));
      expect(notified, 3, reason: 'on, the first round trip, the move');
    });
  });

  test('the style changes only once upright has settled, never as the return starts or in landscape', () {
    fakeAsync((async) {
      cycle.start();
      roundTrip(async);
      orientation.enterLandscape();
      async.elapse(TurnCycle.settle * 3);
      expect(orientation.turnStyle, styles[0], reason: 'landscape never applies');
      orientation.exitToInline();
      async.elapse(TurnCycle.settle - const Duration(milliseconds: 1));
      expect(orientation.turnStyle, styles[0], reason: 'the return is still turning');
      expect(cycle.roundTrips, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(cycle.position, 2);
      expect(orientation.turnStyle, styles[1]);
    });
  });

  test('on the phone the next style reaches the host after the return\'s own request, not before it', () {
    expect(styles[0].method.drawn, isFalse, reason: 'the cycle starts at the reference, iOS\'s own turn');
    expect(styles[1].method.drawn, isTrue);
    fakeAsync((async) {
      final host = FakeOrientationHost();
      final phone = OrientationController(host: host, logger: logger);
      final phoneCycle = TurnCycle(orientation: phone, prefs: prefs, logger: logger);
      addTearDown(phoneCycle.dispose);
      addTearDown(phone.dispose);
      phone.begin(Object(), videoIsVertical: false);
      phoneCycle.start();
      async.flushMicrotasks();
      expect(host.sent, isEmpty, reason: '系统 with a page: nothing to take over');
      for (var trip = 0; trip < 2; trip++) {
        phone.enterLandscape();
        async.elapse(TurnCycle.settle);
        phone.exitToInline();
        async.flushMicrotasks();
        expect(host.sent.last, 'portrait', reason: 'the return is asked for under the first style');
        async.elapse(TurnCycle.settle);
      }
      expect(host.sent, ['landscape', 'portrait', 'landscape', 'portrait', 'takeover on']);
      expect(host.pictures.single, styles[1].picture);
    });
  });

  test('a turn held for less than the settle time is not counted: a refused rotation or a quick flip back', () {
    fakeAsync((async) {
      cycle.start();
      orientation.enterLandscape();
      async.elapse(const Duration(milliseconds: 300));
      orientation.exitToInline();
      async.elapse(TurnCycle.settle * 2);
      expect(cycle.roundTrips, 0, reason: 'landscape never settled');

      orientation.enterLandscape();
      async.elapse(TurnCycle.settle);
      orientation.exitToInline();
      async.elapse(const Duration(milliseconds: 500));
      orientation.enterLandscape();
      async.elapse(TurnCycle.settle);
      expect(cycle.roundTrips, 0, reason: 'upright never settled: still the same trip out');
      orientation.exitToInline();
      async.elapse(TurnCycle.settle);
      expect(cycle.roundTrips, 1);
    });
  });

  test('竖屏 is upright: landscape → 竖屏 → landscape is one round trip and the start of the next, never two', () {
    fakeAsync((async) {
      cycle.start();
      orientation.enterLandscape();
      async.elapse(TurnCycle.settle);
      orientation.enterVertical();
      async.elapse(TurnCycle.settle);
      expect(cycle.roundTrips, 1);
      orientation.enterLandscape();
      async.elapse(TurnCycle.settle);
      expect(cycle.roundTrips, 1, reason: 'out again: nothing counts until it is back upright');
      orientation.exitToInline();
      async.elapse(TurnCycle.settle);
      expect(cycle.position, 2, reason: 'the second round trip');

      orientation.enterVertical();
      async.elapse(TurnCycle.settle);
      orientation.exitToInline();
      async.elapse(TurnCycle.settle);
      expect(cycle.roundTrips, 0, reason: '竖屏 and back without landscape turns nothing');

      roundTrip(async, back: Presentation.vertical);
      orientation.exitToInline();
      async.elapse(TurnCycle.settle);
      expect(cycle.roundTrips, 1, reason: '竖屏 then inline is still one return');
    });
  });

  test('it goes through TurnStyle.cycle in order, then logs done, switches off and puts back the style chosen before',
      () {
    fakeAsync((async) {
      var notified = 0;
      prefs.turnStyle = chosen;
      cycle.start();
      final applied = <TurnStyle>[cycle.style];
      cycle.addListener(() {
        notified += 1;
        if (cycle.on && cycle.roundTrips == 0) applied.add(cycle.style);
      });
      for (var trip = 0; trip < styles.length * 2; trip++) {
        expect(cycle.on, isTrue, reason: 'round trip ${trip + 1}');
        roundTrip(async);
      }
      expect(applied, styles);
      expect(cycleLines().where((line) => line.msg == 'turn cycle').map((line) => line.f['label']),
          [for (final style in styles) LogString(style.label)]);
      expect(cycleLines().where((line) => line.msg == 'turn cycle').map((line) => line.f['index']),
          [for (var i = 1; i <= styles.length; i++) LogInt(i)]);
      final done = cycleLines().last;
      expect(done.msg, 'turn cycle done');
      expect(done.f['of'], LogInt(styles.length));
      expect(done.f['label'], LogString(chosen.label));
      expect(done.f['wUs'], isA<LogInt>());
      expect(cycle.on, isFalse);
      expect(prefs.turnStyle, chosen);
      expect(orientation.turnStyle, chosen);
      expect(notified, styles.length * 2);

      roundTrip(async);
      roundTrip(async);
      expect(prefs.turnStyle, chosen, reason: 'off: turning moves nothing');
      expect(cycleLines().last.msg, 'turn cycle done');
    });
  });

  test('重置 goes back to 1 and starts its count again, even with a return still settling', () {
    fakeAsync((async) {
      cycle.start();
      for (var trip = 0; trip < 5; trip++) {
        roundTrip(async);
      }
      expect(cycle.position, 3);
      expect(cycle.roundTrips, 1);
      orientation.enterLandscape();
      async.elapse(TurnCycle.settle);
      orientation.exitToInline();
      cycle.start();
      async.elapse(TurnCycle.settle);
      expect(cycle.position, 1);
      expect(cycle.roundTrips, 0, reason: 'the trip under the old style isn\'t counted for the first');
      expect(orientation.turnStyle, styles[0]);
      expect(prefs.turnStyle, styles[0]);
      expect(cycleLines().last.f['index'], const LogInt(1));
      roundTrip(async);
      roundTrip(async);
      expect(cycle.position, 2);
    });
  });

  test('重置 keeps the style chosen before the cycle, not the one it was on', () {
    fakeAsync((async) {
      prefs.turnStyle = chosen;
      cycle.start();
      for (var trip = 0; trip < 4; trip++) {
        roundTrip(async);
      }
      cycle.start();
      expect(prefs.turnStyle, styles[0]);
      cycle.stop();
      expect(prefs.turnStyle, chosen);
      expect(orientation.turnStyle, chosen);
    });
  });

  test('started again later, it puts back what was chosen then', () {
    fakeAsync((async) {
      prefs.turnStyle = chosen;
      cycle
        ..start()
        ..stop();
      const later = TurnStyle(picture: TurnPicture.none);
      prefs.turnStyle = later;
      cycle.start();
      roundTrip(async);
      roundTrip(async);
      cycle.stop();
      expect(prefs.turnStyle, later);
      expect(orientation.turnStyle, later);
      expect(cycleLines().last.f['label'], LogString(later.label));
    });
  });

  test('switching off puts back the style chosen before, stops counting and logs it', () {
    fakeAsync((async) {
      prefs.turnStyle = chosen;
      cycle.start();
      roundTrip(async);
      roundTrip(async);
      roundTrip(async);
      orientation.enterLandscape();
      async.elapse(TurnCycle.settle);
      orientation.exitToInline();
      cycle.stop();
      async.elapse(TurnCycle.settle);
      expect(cycle.on, isFalse);
      expect(cycle.position, 2);
      expect(prefs.turnStyle, chosen);
      expect(orientation.turnStyle, chosen);
      final off = cycleLines().last;
      expect(off.msg, 'turn cycle off');
      expect(off.f['index'], const LogInt(2));
      expect(off.f['of'], LogInt(styles.length));
      expect(off.f['label'], LogString(chosen.label));
      expect(off.f['wUs'], isA<LogInt>());
      expect(async.pendingTimers, isEmpty);
    });
  });

  group('the badge', () {
    late TurnCycle appCycle;
    late OrientationController appOrientation;

    Future<void> show(WidgetTester tester, {Size size = const Size(440, 956), EdgeInsets? safe}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final padding = safe ?? const EdgeInsets.only(top: 62, bottom: 34);
      tester.view.padding = FakeViewPadding(
          left: padding.left, top: padding.top, right: padding.right, bottom: padding.bottom);
      tester.view.viewPadding = tester.view.padding;
      addTearDown(tester.view.reset);
      final environment = await AppEnvironment.load(
          keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: Canned.http(), logger: logger);
      final playback = AppPlayback(() async => PlaybackController(
            client: environment.client,
            engine: FakeEngine(),
            player: FakePlayer(),
            clock: ManualClock().clock,
            startTimer: FakeTimers().start,
            logger: logger,
          ));
      addTearDown(playback.dispose);
      appOrientation = OrientationController(logger: logger);
      addTearDown(appOrientation.dispose);
      appCycle = TurnCycle(orientation: appOrientation, prefs: prefs, logger: logger);
      addTearDown(appCycle.dispose);
      await tester.pumpWidget(BiliFastApp(
        services: AppServices(
          environment: environment,
          playback: playback,
          recents: await RecentStore.load(null, logger: logger),
          device: PlayerDevice(orientation: appOrientation, controls: appOrientation.controls),
          turnCycle: appCycle,
        ),
      ));
      await tester.pump();
    }

    final badge = find.byKey(const ValueKey('turn-cycle-badge'));

    /// What the badge says at [position] in the cycle, on round trip [trip].
    String says(int position, int trip) =>
        '轮换 $position/${styles.length} · ${styles[position - 1].label} · $trip/${TurnCycle.roundTripsPerStyle}';

    /// Every semantics node on screen, as its label and place.
    List<String> nodes() => [
          for (final node in find.semantics.byPredicate((_) => true).evaluate())
            '${node.label}|${node.rect}|${node.transform}',
        ]..sort();

    testWidgets('shows only while 轮换测试 runs, over the whole app, top centre just below the status bar, and lets '
        'taps through', (tester) async {
      await show(tester);
      expect(badge, findsNothing);

      appCycle.start();
      await tester.pump();
      expect(find.text(says(1, 1)), findsOneWidget);
      final rect = tester.getRect(badge);
      expect(rect.top, 62 + BiliMetrics.rowGap / 2, reason: 'just below the status bar');
      expect(rect.center.dx, 440 / 2);
      expect(rect.left, greaterThan(SettingsTheme.backLeft + SettingsTheme.backTarget),
          reason: 'clear of a bar\'s back chevron');
      expect(rect.height, lessThan(SettingsTheme.barHeight / 2), reason: 'one small line');
      expect(find.ancestor(of: badge, matching: find.byType(Navigator)), findsNothing, reason: 'above every route');
      final hits = tester.hitTestOnBinding(tester.getCenter(badge)).path.map((entry) => entry.target);
      expect(hits, isNot(contains(tester.renderObject(badge))));
      expect(hits, contains(tester.renderObject(find.byType(Navigator))), reason: 'the page under it gets the tap');
      final text = tester.widget<Text>(find.text(says(1, 1)));
      final style = DefaultTextStyle.of(tester.element(find.text(says(1, 1)))).style;
      expect(text.style, isNull);
      expect(style.color, BiliColors.onVideo);
      expect(style.fontFamily, BiliFonts.family);
      expect(style.fontSize, BiliMetrics.smallText);
      expect(style.decoration, isNot(TextDecoration.underline), reason: 'not the no-Material error style');
      final box = tester.widget<DecoratedBox>(badge).decoration as BoxDecoration;
      expect(box.color, BiliColors.statsFill);

      appCycle.stop();
      await tester.pump();
      expect(badge, findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('accessibility reads it as its own small node, and the app\'s nodes stay as they were', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      await tester.pump(const Duration(seconds: 1));
      final before = nodes();
      expect(before.where((node) => node.contains('轮换')), isEmpty);

      appCycle.start();
      await tester.pump();
      final node = tester.getSemantics(badge);
      expect(node.label, says(1, 1));
      expect(node.rect.size, tester.getSize(badge));
      expect(node.hasChildren, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      final after = nodes();
      expect(after.where((node) => node.contains('轮换')), hasLength(1), reason: 'in no other node\'s label');
      expect(after.where((node) => !node.contains('轮换')).toList(), before);

      appCycle.stop();
      await tester.pump();
      expect(nodes(), before);
      semantics.dispose();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('it follows the count and the style', (tester) async {
      await show(tester);
      appCycle.start();
      await tester.pump();
      appOrientation.enterLandscape();
      await tester.pump(TurnCycle.settle);
      appOrientation.exitToInline();
      await tester.pump(TurnCycle.settle);
      expect(find.text(says(1, 2)), findsOneWidget);
      appOrientation.enterLandscape();
      await tester.pump(TurnCycle.settle);
      appOrientation.exitToInline();
      await tester.pump(TurnCycle.settle);
      expect(find.text(says(2, 1)), findsOneWidget);
      expect(TurnCycleBadge.text(appCycle), says(2, 1));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('in landscape it sits at the top centre, clear of the Dynamic Island', (tester) async {
      await show(tester, size: const Size(956, 440), safe: const EdgeInsets.only(left: 62, right: 62, bottom: 21));
      appCycle.start();
      await tester.pump();
      final rect = tester.getRect(badge);
      expect(rect.top, BiliMetrics.rowGap / 2);
      expect(rect.center.dx, 956 / 2);
      expect(rect.left, greaterThan(62));
      expect(rect.right, lessThan(956 - 62));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
