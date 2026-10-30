import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/network_monitor.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../account/fake_web_cookies.dart';
import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';
const ok = '{"code":0,"message":"0"}';

final class _Network implements NetworkMonitor {
  final controller = StreamController<bool>.broadcast(sync: true);

  @override
  Stream<bool> get changes => controller.stream;
}

/// What waits is sent once the launch's account check says logged in, on coming back to the foreground and on a
/// network change, only while the account may report; a logout drops it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CannedHttp http;
  late _Network network;
  late HistoryOutbox outbox;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, ok);
    network = _Network();
    outbox = HistoryOutbox.memory(logger: Logger(session: 'test'));
  });

  Future<AppEnvironment> environment({CookieLoad stored = const StoredCookies(Canned.cookies)}) => AppEnvironment.load(
    keychain: FakeKeychain(stored),
    http: http,
    webCookies: FakeWebCookies(),
    logger: Logger(session: 'test'),
  );

  /// A report of BV1a that got no answer.
  Future<void> waiting() async {
    try {
      await outbox.send('BV1a', 1, 42, () async => throw const BiliNetworkError('SocketException'));
    } on BiliNetworkError {
      // Kept for the flush.
    }
    expect(outbox.reports, hasLength(1));
  }

  HistoryOutboxFlusher flusher(AppEnvironment environment) {
    final made = HistoryOutboxFlusher(outbox: outbox, environment: environment, network: network);
    addTearDown(made.dispose);
    return made;
  }

  List<String> beats() => [
    for (final request in http.to(heartbeatPath)) Uri.splitQueryString(utf8.decode(request.body!))['played_time']!,
  ];

  test('the launch sends what waits once the account check says logged in', () async {
    await waiting();
    final env = await environment();
    flusher(env);
    await pumpEventQueue();
    expect(beats(), isEmpty, reason: 'the account is not known yet');
    await env.refreshAccount();
    await pumpEventQueue();
    expect(env.account, isA<LoggedIn>());
    expect(beats(), ['42']);
    expect(outbox.reports, isEmpty);
  });

  test('an account already known when the app\'s services are made flushes at once', () async {
    await waiting();
    final env = await environment();
    await env.refreshAccount();
    flusher(env);
    await pumpEventQueue();
    expect(beats(), ['42']);
  });

  test('coming back to the foreground and a network change send it again after a failure', () async {
    final env = await environment();
    await env.refreshAccount();
    final made = flusher(env);
    await waiting();
    http.errors[heartbeatPath] = const SocketException('offline');
    network.controller.add(true);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), hasLength(1));
    expect(outbox.reports, hasLength(1), reason: 'still no network');

    made.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), hasLength(1), reason: 'only coming back flushes');
    made.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), hasLength(2));

    http.errors.remove(heartbeatPath);
    network.controller.add(false);
    await pumpEventQueue();
    expect(beats(), ['42', '42', '42']);
    expect(outbox.reports, isEmpty);

    network.controller.add(true);
    made.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), hasLength(3), reason: 'nothing waiting, nothing sent');
  });

  test('nothing is sent while the account may not report: logged out, a refused login, --fake-account', () async {
    await waiting();
    final out = await environment(stored: const NoStoredCookies());
    await out.refreshAccount();
    expect(out.account, isA<LoggedOut>());
    final made = flusher(out);
    made.didChangeAppLifecycleState(AppLifecycleState.resumed);
    network.controller.add(true);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), isEmpty);

    http.routes[Canned.navPath] = (200, Canned.navLoggedOut);
    final expired = await environment();
    await expired.refreshAccount();
    expect(expired.account, isA<LoginExpired>());
    flusher(expired).didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), isEmpty);

    final fake = await environment();
    fake.useFakeAccount();
    flusher(fake).didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(http.to(heartbeatPath), isEmpty);
    expect(outbox.reports, hasLength(1));
  });

  test('a report older than 5 minutes asks the account\'s history first, once', () async {
    var clock = DateTime(2026, 10, 31, 9);
    outbox = HistoryOutbox.memory(
      logger: Logger(session: 'test'),
      now: () => clock,
    );
    await waiting();
    clock = clock.add(const Duration(minutes: 6));
    http.routes['/x/web-interface/history/cursor'] = (200, '{"code":0,"message":"0","data":{"list":[]}}');
    final env = await environment();
    await env.refreshAccount();
    flusher(env);
    await pumpEventQueue();
    expect(http.paths.where((path) => path == '/x/web-interface/history/cursor' || path == heartbeatPath), [
      '/x/web-interface/history/cursor',
      heartbeatPath,
    ]);
    expect(outbox.reports, isEmpty);
  });

  test('logging out drops what waits: whoever logs in next may be another account', () async {
    final env = await environment();
    await env.refreshAccount();
    flusher(env);
    http.errors[heartbeatPath] = const SocketException('offline');
    await waiting();
    await env.logout();
    expect(env.account, isA<LoggedOut>());
    expect(outbox.reports, isEmpty);
  });

  test('the app\'s services flush the outbox they are given and stop listening when disposed', () async {
    await waiting();
    final env = await environment();
    final services = AppServices(
      environment: env,
      playback: AppPlayback(() => Completer<PlaybackController>().future, network: network),
      recents: await RecentStore.load(null, logger: Logger(session: 'test')),
      historyOutbox: outbox,
      network: network,
    );
    addTearDown(services.playback.dispose);
    expect(services.historyOutbox, same(outbox));
    await env.refreshAccount();
    await pumpEventQueue();
    expect(beats(), ['42']);

    services.dispose();
    await waiting();
    network.controller.add(true);
    await pumpEventQueue();
    expect(beats(), ['42'], reason: 'disposed, it hears no more');
  });
}
