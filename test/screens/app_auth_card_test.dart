import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/app_auth.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/screens/player_test_page.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

Widget stageStandIn(BuildContext context, PlaybackController controller,
        {required bool showStats, required bool danmakuEnabled}) =>
    const SizedBox(key: ValueKey('stage'));

/// Counts what 开发者 asks of the token.
class StubAppAuth extends ChangeNotifier implements AppAuth {
  StubAppAuth({this.expiresAt});

  @override
  DateTime? expiresAt;

  int requests = 0;
  int reauthorizations = 0;

  @override
  bool get authorized => expiresAt != null;

  @override
  Future<void> start() async {}

  @override
  Future<bool> request(BuildContext context) async {
    requests += 1;
    expiresAt = DateTime.now().add(const Duration(days: 180, hours: 12));
    notifyListeners();
    return true;
  }

  @override
  Future<bool> reauthorize(BuildContext context) async {
    reauthorizations += 1;
    return true;
  }
}

/// 开发者's 官方接口 row (the token's state and 授权 / 重新授权) and 推荐's 官方 / 网页 choice.
void main() {
  late PlayerPrefs prefs;

  setUp(() => prefs = PlayerPrefs.memory());

  Future<void> show(WidgetTester tester, {AppAuth? appAuth}) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await tester.pumpWidget(MaterialApp(
      home: PlayerTestPage(
        environment: environment,
        stageBuilder: stageStandIn,
        prefs: prefs,
        appAuth: appAuth,
        startPlayback: () async => PlaybackController(
          client: environment.client,
          engine: FakeEngine(),
          player: FakePlayer(),
          clock: ManualClock().clock,
          startTimer: FakeTimers().start,
          logger: logger,
        ),
      ),
    ));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('official-feed')));
    await tester.pump();
  }

  final state = find.byKey(const ValueKey('app-auth-state'));
  final button = find.byKey(const ValueKey('app-auth-button'));

  testWidgets('without the token it reads 未授权, and 授权 asks for it', (tester) async {
    final auth = StubAppAuth();
    await show(tester, appAuth: auth);
    expect(find.text('官方接口'), findsOneWidget);
    expect(tester.widget<Text>(state).data, '未授权');
    expect(find.descendant(of: button, matching: find.text('授权')), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(auth.requests, 1);
    expect(auth.reauthorizations, 0);
    expect(tester.widget<Text>(state).data, '已授权 · 剩 180 天');
    expect(find.descendant(of: button, matching: find.text('重新授权')), findsOneWidget);
  });

  testWidgets('with the token it reads the days left, and 重新授权 asks again', (tester) async {
    final auth = StubAppAuth(expiresAt: DateTime.now().add(const Duration(days: 42, hours: 12)));
    await show(tester, appAuth: auth);
    expect(tester.widget<Text>(state).data, '已授权 · 剩 42 天');

    // As ghosthand presses it on the PC.
    final semantics = tester.ensureSemantics();
    tester.semantics.tap(find.semantics.byLabel('重新授权'));
    await tester.pump();
    expect(auth.reauthorizations, 1);
    expect(auth.requests, 0);
    semantics.dispose();
  });

  testWidgets('推荐 switches between 官方 and 网页 and keeps the choice', (tester) async {
    await show(tester, appAuth: StubAppAuth());
    final choice = find.byKey(const ValueKey('official-feed'));
    Set<bool> selected() => tester.widget<SegmentedButton<bool>>(choice).selected;
    expect(find.text('推荐'), findsOneWidget);
    expect(selected(), {true});

    await tester.tap(find.descendant(of: choice, matching: find.text('网页')));
    await tester.pump();
    expect(selected(), {false});
    expect(prefs.officialFeed, isFalse);

    await tester.tap(find.descendant(of: choice, matching: find.text('官方')));
    await tester.pump();
    expect(selected(), {true});
    expect(prefs.officialFeed, isTrue);
  });

  testWidgets('without a token service the 官方接口 row is left out, 推荐 stays', (tester) async {
    prefs.officialFeed = false;
    await show(tester);
    expect(find.text('官方接口'), findsNothing);
    expect(button, findsNothing);
    expect(tester.widget<SegmentedButton<bool>>(find.byKey(const ValueKey('official-feed'))).selected, {false});
  });
}
