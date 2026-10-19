import 'dart:async';

import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../account/fake_web_cookies.dart';
import '../playback/fakes.dart';
import 'fake_keychain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a login fetches the 屏蔽词 again and a logout drops them; the launch\'s check leaves them to the page', () async {
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const NoStoredCookies()),
      http: Canned.http(),
      webCookies: FakeWebCookies(),
      logger: Logger(session: 'test'),
    );
    final api = FakePageApi()..blockRules = [const BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: 'spoiler')];
    final services = AppServices(
      environment: environment,
      playback: AppPlayback(() => Completer<PlaybackController>().future),
      recents: await RecentStore.load(null, logger: Logger(session: 'test')),
      pageApi: api,
    );
    addTearDown(services.playback.dispose);
    int fetches() => api.calls.where((call) => call == 'danmakuBlockRules').length;

    environment.useFakeAccount();
    await pumpEventQueue();
    expect(fetches(), 0);

    await environment.logout();
    await pumpEventQueue();
    expect(services.blockRules.rules, isEmpty);
    expect(fetches(), 0);

    environment.useFakeAccount();
    await pumpEventQueue();
    expect(fetches(), 1);
    expect(services.blockRules.rules.single.filter, 'spoiler');
  });
}
