import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_badge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The account half [FollowBadge] follows: the test sets the account and its mid, and counts the logins.
class _Environment extends ChangeNotifier implements AppEnvironment {
  _Environment(this._account, this._mid);

  Account _account;
  int? _mid;

  @override
  Account get account => _account;

  @override
  int? get mid => _mid;

  void set(Account account, {int? mid}) {
    _account = account;
    _mid = account is LoggedIn ? mid ?? _mid : null;
    notifyListeners();
  }

  @override
  final _Logins logins = _Logins();

  /// As didLogin goes: through unknown to logged in, then the login counted.
  void logIn({int mid = 1}) {
    set(const AccountUnknown());
    set(loggedIn, mid: mid);
    logins.value++;
  }

  bool get listened => hasListeners;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Logins extends ValueNotifier<int> {
  _Logins() : super(0);

  bool get listened => hasListeners;
}

const loggedIn = LoggedIn(name: '测试账号', vip: false);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDynamicApi api;
  late _Environment environment;
  late FollowBaselines baselines;
  late DateTime clock;
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    api = FakeDynamicApi(newPosts: 3);
    clock = DateTime(2026, 11, 17, 12);
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
    baselines = FollowBaselines.memory(logger: logger);
  });

  Future<FollowBadge> make({Account account = loggedIn, int? mid = 1, Map<int, String> kept = const {1: 'b1'}}) async {
    for (final MapEntry(:key, :value) in kept.entries) {
      await baselines.set(key, value);
    }
    environment = _Environment(account, account is LoggedIn ? mid : null);
    final badge = FollowBadge(
      api: api,
      environment: environment,
      baselines: baselines,
      now: () => clock,
      logger: logger,
    );
    addTearDown(badge.dispose);
    return badge;
  }

  Future<void> idle() => pumpEventQueue();

  String logged() => sink.events.map((event) => '${event.toJson()}').join();

  /// Only what the lines carry, so a value checked for can't turn up in a timestamp.
  String fields() => [for (final event in sink.events) ...event.f.values.map((value) => '${value.toJson()}')].join(' ');

  List<int> answered() => [
    for (final event in sink.events)
      if (event.msg == 'follow badge') (event.f['count']! as LogInt).value,
  ];

  void backToApp() {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  group('asking', () {
    test('start asks once from the account\'s baseline and shows the answer; start again asks nothing', () async {
      final badge = await make();
      expect(api.calls, isEmpty, reason: 'nothing before start');
      var notified = 0;
      badge.addListener(() => notified++);
      badge.start();
      await idle();
      expect(api.calls, ['updateCount b1']);
      expect(badge.count, 3);
      expect(notified, 1);

      badge.start();
      await idle();
      expect(api.calls, ['updateCount b1']);
    });

    test('a return to the app asks again at most once per gap', () async {
      final badge = await make();
      badge.start();
      await idle();
      clock = clock.add(const Duration(seconds: 30));
      backToApp();
      await idle();
      expect(api.calls, hasLength(1), reason: 'within the minute');

      clock = clock.add(const Duration(seconds: 31));
      api.newPosts = 5;
      backToApp();
      await idle();
      expect(api.calls, hasLength(2));
      expect(badge.count, 5);
      backToApp();
      await idle();
      expect(api.calls, hasLength(2));
    });

    test('refresh keeps the gap unless forced', () async {
      final badge = await make();
      badge.start();
      await idle();
      await badge.refresh();
      expect(api.calls, hasLength(1));
      await badge.refresh(force: true);
      expect(api.calls, hasLength(2));
    });

    test('a login asks once', () async {
      final badge = await make(account: const LoggedOut());
      badge.start();
      await idle();
      expect(api.calls, isEmpty);
      environment.logIn();
      await idle();
      expect(api.calls, ['updateCount b1']);
      expect(badge.count, 3);
    });

    test('at launch the account is unknown: the count waits for it to read logged in', () async {
      final badge = await make(account: const AccountUnknown());
      badge.start();
      await idle();
      expect(api.calls, isEmpty);
      environment.set(loggedIn, mid: 1);
      await idle();
      expect(api.calls, ['updateCount b1']);
      environment.set(loggedIn, mid: 1);
      await idle();
      expect(api.calls, ['updateCount b1'], reason: 'the same account checked again asks nothing');
      expect(badge.count, 3);
    });

    test('logged out, the count is 0 and nothing is asked, by start, a return or a forced refresh', () async {
      final badge = await make(account: const LoggedOut());
      badge.start();
      clock = clock.add(const Duration(minutes: 5));
      backToApp();
      await badge.refresh(force: true);
      await idle();
      expect(api.calls, isEmpty);
      expect(badge.count, 0);
    });

    test('with no baseline for the account, the count is 0 and nothing is asked until 全部 has shown one', () async {
      final badge = await make(kept: const {2: 'other'});
      badge.start();
      clock = clock.add(const Duration(minutes: 5));
      backToApp();
      await badge.refresh(force: true);
      await idle();
      expect(api.calls, isEmpty);
      expect(badge.count, 0);

      badge.seen('b9');
      await badge.refresh(force: true);
      expect(api.calls, ['updateCount b9']);
      expect(badge.count, 3);
    });

    test('a call out answers for the next caller', () async {
      final badge = await make();
      final hold = api.holds['updateCount'] = Completer<void>();
      badge.start();
      final forced = badge.refresh(force: true);
      final again = badge.refresh(force: true);
      await idle();
      expect(api.calls, hasLength(1));
      hold.complete();
      await Future.wait([forced, again]);
      expect(api.calls, hasLength(1));
      expect(badge.count, 3);
    });

    test('one info line per answered count, and none for an ask skipped', () async {
      final badge = await make();
      badge.start();
      await idle();
      expect(answered(), [3]);
      backToApp();
      await badge.refresh();
      await idle();
      expect(answered(), [3], reason: 'within the gap');
      api.newPosts = 4;
      await badge.refresh(force: true);
      expect(answered(), [3, 4]);
    });
  });

  group('failures', () {
    test('-101 clears the count and says so', () async {
      final badge = await make();
      badge.start();
      await idle();
      expect(badge.count, 3);
      var notified = 0;
      badge.addListener(() => notified++);
      api.failures['updateCount'] = const BiliAPIError(code: -101, message: '账号未登录');
      await badge.refresh(force: true);
      expect(badge.count, 0);
      expect(notified, 1);
    });

    test('any other failure keeps the count, logged by its code or kind only', () async {
      final badge = await make();
      badge.start();
      await idle();
      api.failures['updateCount'] = const BiliAPIError(code: -352, message: '演示：风控的原话');
      await badge.refresh(force: true);
      expect(badge.count, 3);
      expect(logged(), contains('follow badge failed'));
      expect(logged(), contains('api -352'));
      expect(logged(), isNot(contains('风控的原话')));

      api.failures['updateCount'] = const SocketException(
        'https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all/update?update_baseline=b1',
      );
      await badge.refresh(force: true);
      expect(badge.count, 3);
      expect(logged(), contains('SocketException'));
      expect(logged(), isNot(contains('polymer')));
      expect(logged(), isNot(contains('update_baseline')));
      expect(answered(), [3], reason: 'a failure is no answer');
    });
  });

  group('seen and clear', () {
    test('seen keeps the baseline for the account, the count goes to 0 and listeners hear it', () async {
      final badge = await make();
      badge.start();
      await idle();
      var notified = 0;
      badge.addListener(() => notified++);
      badge.seen('b2');
      expect(badge.count, 0);
      expect(notified, 1);
      expect(baselines.of(1), 'b2');

      await badge.refresh(force: true);
      expect(api.calls.last, 'updateCount b2');
    });

    test('an empty baseline is ignored', () async {
      final badge = await make();
      badge.start();
      await idle();
      var notified = 0;
      badge.addListener(() => notified++);
      badge.seen('');
      expect(badge.count, 3);
      expect(notified, 0);
      expect(baselines.of(1), 'b1');
    });

    test('an answer asked from the baseline before seen is dropped', () async {
      final badge = await make();
      final hold = api.holds['updateCount'] = Completer<void>();
      badge.start();
      await idle();
      badge.seen('b2');
      hold.complete();
      await idle();
      expect(badge.count, 0);
      expect(answered(), isEmpty);
    });

    test('clear takes the count to 0 at once, says so only on a change, and the baseline stays', () async {
      final badge = await make();
      badge.start();
      await idle();
      var notified = 0;
      badge.addListener(() => notified++);
      badge.clear();
      expect(badge.count, 0);
      expect(notified, 1);
      badge.clear();
      expect(notified, 1);
      expect(baselines.of(1), 'b1');
    });

    test('an answer still out when cleared doesn\'t bring the count back', () async {
      final badge = await make();
      badge.start();
      await idle();
      final hold = api.holds['updateCount'] = Completer<void>();
      final out = badge.refresh(force: true);
      badge.clear();
      hold.complete();
      await out;
      expect(badge.count, 0);
    });

    test('seen while logged out keeps nothing', () async {
      final badge = await make(account: const LoggedOut(), kept: const {});
      badge.seen('b2');
      expect(baselines.of(1), isNull);
      expect(badge.count, 0);
    });

    test('a baseline that can\'t be saved holds for this run', () async {
      final folder = Directory.systemTemp.createTempSync('follow_badge');
      addTearDown(() => folder.deleteSync(recursive: true));
      final blocker = File('${folder.path}${Platform.pathSeparator}blocker')..writeAsStringSync('');
      baselines = await FollowBaselines.load(
        '${blocker.path}${Platform.pathSeparator}follow_badge.json',
        logger: logger,
      );
      final badge = await make(kept: const {});
      badge.seen('b2');
      await baselines.settle();
      expect(logged(), contains('follow baselines not saved'));
      expect(baselines.of(1), 'b2');
      await badge.refresh(force: true);
      expect(api.calls, ['updateCount b2']);
    });
  });

  group('the account', () {
    test('a logout clears the count, says so, and drops an answer still out', () async {
      final badge = await make();
      badge.start();
      await idle();
      final hold = api.holds['updateCount'] = Completer<void>();
      unawaited(badge.refresh(force: true));
      var notified = 0;
      badge.addListener(() => notified++);

      environment.set(const LoggedOut());
      expect(badge.count, 0);
      expect(notified, greaterThan(0));

      hold.complete();
      await idle();
      expect(badge.count, 0, reason: 'the old account\'s answer is dropped');
      expect(answered(), [3]);
    });

    test('an expired login clears it too', () async {
      final badge = await make();
      badge.start();
      await idle();
      var notified = 0;
      badge.addListener(() => notified++);
      environment.set(const LoginExpired());
      expect(badge.count, 0);
      expect(notified, greaterThan(0));
    });

    test('logging in again after a logout asks once', () async {
      final badge = await make();
      badge.start();
      await idle();
      environment.set(const LoggedOut());
      api.calls.clear();
      environment.logIn();
      await idle();
      expect(api.calls, ['updateCount b1']);
      expect(badge.count, 3);
    });

    test('each account counts from its own baseline; a login over another asks again from the new one', () async {
      final badge = await make(kept: const {1: 'a1', 2: 'a2'});
      badge.start();
      await idle();
      expect(api.calls, ['updateCount a1']);

      final hold = api.holds['updateCount'] = Completer<void>();
      final out = badge.refresh(force: true);
      await idle();
      api.holds.remove('updateCount');
      api.newPosts = 7;
      environment.logIn(mid: 2);
      await idle();
      expect(api.calls, ['updateCount a1', 'updateCount a1', 'updateCount a2'], reason: 'once, not once per change');
      expect(badge.count, 7);
      hold.complete();
      await out;
      expect(badge.count, 7, reason: 'the first account\'s answer is dropped');

      badge.seen('a2-next');
      expect(baselines.of(2), 'a2-next');
      expect(baselines.of(1), 'a1');
    });

    test('while the next account\'s login is counted, the one before\'s count doesn\'t show for it', () async {
      final badge = await make(kept: const {1: 'a1', 2: 'a2'});
      badge.start();
      await idle();
      expect(badge.count, 3);
      environment.set(const AccountUnknown());
      expect(badge.count, 0);
      environment.set(loggedIn, mid: 2);
      expect(badge.count, 0);
    });

    test('the count hides while the account is unknown', () async {
      final badge = await make();
      badge.start();
      await idle();
      environment.set(const AccountUnknown());
      expect(badge.count, 0);
      environment.set(loggedIn, mid: 1);
      expect(badge.count, 3);
    });
  });

  test('once disposed, returns to the app, logins and refreshes ask nothing, and nothing listens', () async {
    await baselines.set(1, 'b1');
    environment = _Environment(loggedIn, 1);
    final badge = FollowBadge(
      api: api,
      environment: environment,
      baselines: baselines,
      now: () => clock,
      logger: logger,
    );
    badge.start();
    await idle();
    badge.dispose();
    expect(environment.listened, isFalse);
    expect(environment.logins.listened, isFalse);
    api.calls.clear();
    clock = clock.add(const Duration(minutes: 5));
    backToApp();
    environment.logIn();
    await badge.refresh(force: true);
    await idle();
    expect(api.calls, isEmpty);
  });

  group('the store', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('follow_baselines');
      path = '${folder.path}${Platform.pathSeparator}follow_badge.json';
    });

    tearDown(() => folder.deleteSync(recursive: true));

    test('starts empty with no file and in memory; nothing is written until a baseline is kept', () async {
      expect(FollowBaselines.memory().of(1), isNull);
      expect((await FollowBaselines.load(path, logger: logger)).of(1), isNull);
      expect((await FollowBaselines.load(null, logger: logger)).of(1), isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('each account\'s baseline is kept and read back on the next launch', () async {
      final store = await FollowBaselines.load(path, logger: logger);
      await store.set(1, 'b1');
      await store.set(2, 'b2');
      expect(jsonDecode(File(path).readAsStringSync()), {'1': 'b1', '2': 'b2'});
      expect(File('$path.tmp').existsSync(), isFalse, reason: 'written beside it, then renamed over it');
      final next = await FollowBaselines.load(path, logger: logger);
      expect(next.of(1), 'b1');
      expect(next.of(2), 'b2');
      expect(next.of(3), isNull);
    });

    test('the same baseline again writes nothing', () async {
      final store = await FollowBaselines.load(path, logger: logger);
      await store.set(1, 'b1');
      File(path).deleteSync();
      await store.set(1, 'b1');
      expect(File(path).existsSync(), isFalse);
    });

    test('writes go one after another, so the newest lands last', () async {
      final store = await FollowBaselines.load(path, logger: logger);
      await Future.wait([for (var i = 0; i < 20; i++) store.set(1, 'b$i')]);
      expect(jsonDecode(File(path).readAsStringSync()), {'1': 'b19'});
      expect(logged(), isNot(contains('not saved')));
    });

    test(
      'a write that fails reaches the caller, logged without its path; the baseline holds and the next write goes on',
      () async {
        final blocker = File('${folder.path}${Platform.pathSeparator}blocker')..writeAsStringSync('');
        final blocked = '${blocker.path}${Platform.pathSeparator}follow_badge.json';
        final store = await FollowBaselines.load(blocked, logger: logger);
        await expectLater(store.set(1, 'b1'), throwsA(isA<FileSystemException>()));
        expect(store.of(1), 'b1', reason: 'for this run');
        expect(logged(), contains('follow baselines not saved'));
        expect(logged(), isNot(contains('blocker')));
        await store.settle();

        blocker.deleteSync();
        await store.set(1, 'b2');
        expect(jsonDecode(File(blocked).readAsStringSync()), {'1': 'b2'});
      },
    );

    test('an unreadable file is set aside as .bad and starts empty, its text never logged', () async {
      File(path).writeAsStringSync('{"1": "secret-baselin');
      final store = await FollowBaselines.load(path, logger: logger);
      expect(store.of(1), isNull);
      expect(File('$path.bad').existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
      expect(logged(), contains('follow baselines unreadable'));
      expect(logged(), isNot(contains('secret-baselin')));
    });

    test('a file that isn\'t an object is unreadable too', () async {
      File(path).writeAsStringSync('["b1"]');
      final store = await FollowBaselines.load(path, logger: logger);
      expect(store.of(1), isNull);
      expect(File('$path.bad').existsSync(), isTrue);
    });

    test('an entry of the wrong type is skipped, logged by its key, the others kept', () async {
      File(path).writeAsStringSync('{"1": "b1", "2": 7654321, "3": "", "x": "stray-value"}');
      final store = await FollowBaselines.load(path, logger: logger);
      expect(store.of(1), 'b1');
      expect(store.of(2), isNull);
      expect(store.of(3), isNull);
      final ignored = [
        for (final event in sink.events)
          if (event.msg == 'follow baseline ignored') (event.f['key']! as LogString).value,
      ];
      expect(ignored, [Redactor.mid(2), Redactor.mid(3), 'not a uid']);
      expect(fields(), isNot(contains('7654321')));
      expect(fields(), isNot(contains('stray-value')));
      expect(File('$path.bad').existsSync(), isFalse);
    });

    test('in memory it keeps baselines and writes nothing', () async {
      final store = FollowBaselines.memory();
      await store.set(1, 'b1');
      expect(store.of(1), 'b1');
      expect(folder.listSync(), isEmpty);
    });
  });

  test('the demo answers 3 new posts; a plain fake 0', () async {
    expect(await FakeDynamicApi.demo().updateCount('9001'), 3);
    expect(await FakeDynamicApi().updateCount('9001'), 0);
  });
}
