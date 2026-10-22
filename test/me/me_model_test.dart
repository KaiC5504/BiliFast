import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/home/feed_model.dart' show requestFailureMessage;
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The account half [MeModel] follows: the test sets the account and counts the logins.
class _Environment extends ChangeNotifier implements AppEnvironment {
  _Environment(this._account);

  Account _account;

  @override
  Account get account => _account;

  set account(Account value) {
    _account = value;
    notifyListeners();
  }

  @override
  final ValueNotifier<int> logins = ValueNotifier(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A transport error whose words end with the request's URL, as package:http's do.
class _TransportError implements Exception {
  @override
  String toString() => 'ClientException: Connection reset, uri=https://api.bilibili.com/x/web-interface/nav';
}

void main() {
  const loggedIn = LoggedIn(name: '测试账号', vip: true);
  const renamed = NavInfo(isLogin: true, mid: 1, uname: '改了名字', level: 5);
  const demoCounts = MeCounts(dynamics: 0, following: 13, followers: 0);

  late FakeMeApi api;
  late _Environment environment;
  late DateTime clock;
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    api = FakeMeApi.demo();
    clock = DateTime(2026, 10, 22, 12);
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
  });

  MeModel make({Account account = loggedIn}) {
    environment = _Environment(account);
    final model = MeModel(api: api, environment: environment, now: () => clock, logger: logger);
    addTearDown(model.dispose);
    return model;
  }

  Future<void> idle() => pumpEventQueue();

  MeShown shownView(MeModel model) {
    expect(model.view, isA<MeShown>());
    return model.view as MeShown;
  }

  test('logged in, it waits for the tab, then asks nav and stat side by side and shows the account', () async {
    final model = make();
    expect(model.view, isA<MeLoading>());
    await idle();
    expect(api.calls, isEmpty, reason: 'nothing is asked before the tab shows');

    final nav = api.holds['nav'] = Completer<void>();
    final stat = api.holds['stat'] = Completer<void>();
    model.shown();
    await idle();
    expect(api.calls, unorderedEquals(['nav', 'stat']), reason: 'both are out before either answers');
    expect(model.view, isA<MeLoading>());

    nav.complete();
    stat.complete();
    await idle();
    final view = shownView(model);
    expect(view.profile, MeProfile.fromNav(api.navInfo));
    expect(view.counts, demoCounts);
  });

  test('the demo is --fake-account\'s 测试账号: a level 5 年度大会员 with 879 硬币 and 2.3 B币', () async {
    final model = make();
    model.shown();
    await idle();
    final profile = shownView(model).profile;
    expect(profile.mid, 1);
    expect(profile.name, '测试账号');
    expect(profile.level, 5);
    expect(profile.coins, 879);
    expect(profile.bcoin, 2.3);
    expect(profile.vip, isTrue);
    expect(profile.vipLabel, '年度大会员');
    expect(profile.vipBadge, isTrue);
    expect(profile.face, startsWith('https://'));
    expect(profile.pendant, startsWith('https://'));
  });

  for (final account in const [LoggedOut(), LoginExpired()]) {
    test('${account.runtimeType}, it shows 点击登录 and calls nothing', () async {
      final model = make(account: account);
      expect(model.view, isA<MeLoggedOut>());
      model.shown();
      expect(await model.refresh(), isNull);
      await idle();
      expect(api.calls, isEmpty);
      expect(model.view, isA<MeLoggedOut>());
    });
  }

  test('before the launch\'s check answers a showing loads, and the check settling asks nothing more', () async {
    final model = make(account: const AccountUnknown());
    expect(model.view, isA<MeLoading>());
    model.shown();
    await idle();
    expect(api.calls.length, 2);
    environment.account = loggedIn;
    await idle();
    expect(api.calls.length, 2);
    expect(model.view, isA<MeShown>());
  });

  test('showing again reloads quietly, at most once per 30 s, and an unchanged answer redraws nothing', () async {
    final model = make();
    model.shown();
    await idle();
    expect(api.calls.length, 2);

    clock = clock.add(const Duration(seconds: 29));
    model.shown();
    await idle();
    expect(api.calls.length, 2, reason: 'within the gap');

    clock = clock.add(const Duration(seconds: 1));
    var notified = 0;
    model.addListener(() => notified++);
    final hold = api.holds['nav'] = Completer<void>();
    model.shown();
    await idle();
    expect(api.calls.length, 4);
    expect(model.view, isA<MeShown>(), reason: 'the page stays while it reloads');
    expect(notified, 0);
    hold.complete();
    await idle();
    expect(notified, 0, reason: 'the same account and counts');

    clock = clock.add(const Duration(seconds: 30));
    api.navInfo = renamed;
    model.shown();
    await idle();
    expect(api.calls.length, 6);
    expect(notified, 1);
    expect(shownView(model).profile.name, '改了名字');
  });

  test('a pull counts toward the gap', () async {
    final model = make();
    await model.refresh();
    clock = clock.add(const Duration(seconds: 10));
    model.shown();
    await idle();
    expect(api.calls.length, 2);
  });

  test('a showing or a pull while a load is out joins it', () async {
    final model = make();
    final hold = api.holds['nav'] = Completer<void>();
    model.shown();
    final pulled = model.refresh();
    model.shown();
    final pulledAgain = model.refresh();
    await idle();
    expect(api.calls, unorderedEquals(['nav', 'stat']));

    var done = false;
    unawaited(pulled.then((_) => done = true));
    await idle();
    expect(done, isFalse, reason: 'the pull completes only when the answer is in');

    hold.complete();
    expect(await pulled, isNull);
    expect(await pulledAgain, isNull);
    expect(model.view, isA<MeShown>());

    await model.refresh();
    expect(api.calls.length, 4, reason: 'the next pull asks again');
  });

  for (final account in const [LoggedOut(), LoginExpired()]) {
    test('turning ${account.runtimeType} shows 点击登录 at once and drops the answer still out', () async {
      final model = make();
      model.shown();
      await idle();
      expect(model.view, isA<MeShown>());

      final hold = api.holds['nav'] = Completer<void>();
      final pulled = model.refresh();
      await idle();
      environment.account = account;
      expect(model.view, isA<MeLoggedOut>(), reason: 'the old profile goes at once');

      hold.complete();
      expect(await pulled, isNull);
      await idle();
      expect(model.view, isA<MeLoggedOut>());

      model.shown();
      expect(await model.refresh(), isNull);
      expect(api.calls.length, 4, reason: 'logged out, nothing more is asked');
    });
  }

  test('a login loads at once, without waiting for the tab', () async {
    final model = make(account: const LoggedOut());
    environment.account = const AccountUnknown();
    expect(model.view, isA<MeLoggedOut>(), reason: 'didLogin passes through unknown');

    environment.account = loggedIn;
    expect(model.view, isA<MeLoading>());
    await idle();
    expect(api.calls, unorderedEquals(['nav', 'stat']));
    expect(shownView(model).profile.name, '测试账号');

    environment.logins.value += 1;
    model.shown();
    await idle();
    expect(api.calls.length, 2, reason: 'the login count after it and a showing within the gap ask nothing more');
  });

  test('a login over an account that read logged in loads afresh, as it may be another account', () async {
    final model = make();
    model.shown();
    await idle();

    api.navInfo = const NavInfo(isLogin: true, mid: 2, uname: '另一个账号');
    environment.account = const AccountUnknown();
    environment.account = const LoggedIn(name: '另一个账号', vip: false);
    expect(shownView(model).profile.name, '测试账号');

    environment.logins.value += 1;
    expect(model.view, isA<MeLoading>(), reason: 'the old account isn\'t shown as the new one');
    await idle();
    expect(api.calls.length, 4);
    expect(shownView(model).profile.name, '另一个账号');
  });

  test('the first load failing shows the reason; a showing past the gap tries again', () async {
    const error = BiliError.network('SocketException');
    api.failures['nav'] = error;
    final model = make();
    model.shown();
    await idle();
    expect(model.view, MeFailed(requestFailureMessage(error)));
    expect((model.view as MeFailed).message, '网络连接失败，请检查网络后重试');

    api.failures.clear();
    model.shown();
    await idle();
    expect(api.calls.length, 2, reason: 'within the gap');

    clock = clock.add(const Duration(seconds: 30));
    final hold = api.holds['nav'] = Completer<void>();
    model.shown();
    expect(model.view, isA<MeLoading>());
    hold.complete();
    await idle();
    expect(model.view, isA<MeShown>());
  });

  test('a pull on the failed page has no toast: the page shows the reason', () async {
    api.failures['nav'] = const BiliError.http(503);
    final model = make();
    expect(await model.refresh(), isNull);
    expect(model.view, const MeFailed('网络请求失败（HTTP 503）'));
    expect(await model.refresh(), isNull);
    expect(model.view, isA<MeFailed>());

    api.failures.clear();
    expect(await model.refresh(), isNull);
    expect(model.view, isA<MeShown>());
  });

  test('with the page shown, a failed nav keeps it and the pull returns the reason to toast', () async {
    final model = make();
    expect(await model.refresh(), isNull);
    final shown = model.view;

    api.failures['nav'] = const BiliError.api(code: -352, message: '');
    expect(await model.refresh(), '请求过于频繁，请稍后再试');
    expect(model.view, same(shown));

    clock = clock.add(const Duration(seconds: 30));
    model.shown();
    await idle();
    expect(model.view, same(shown), reason: 'a quiet reload failing keeps the page too');

    api.failures.clear();
    expect(await model.refresh(), isNull);
  });

  test('a stat failure still shows the profile and keeps the counts it had', () async {
    api.failures['stat'] = const BiliError.network('TimeoutException');
    final model = make();
    expect(await model.refresh(), isNull);
    var view = shownView(model);
    expect(view.profile.name, '测试账号');
    expect(view.counts, isNull, reason: 'none yet');

    api.failures.clear();
    await model.refresh();
    expect(shownView(model).counts, demoCounts);

    api.failures['stat'] = const BiliError.http(500);
    api.navInfo = renamed;
    expect(await model.refresh(), isNull);
    view = shownView(model);
    expect(view.profile.name, '改了名字');
    expect(view.counts, demoCounts);
  });

  test('nav answering not logged in shows 点击登录 and leaves the environment be', () async {
    final model = make();
    model.shown();
    await idle();
    expect(model.view, isA<MeShown>());

    api.navInfo = const NavInfo(isLogin: false);
    expect(await model.refresh(), isNull);
    expect(model.view, isA<MeLoggedOut>());
    expect(environment.account, loggedIn);

    api.navInfo = const NavInfo(isLogin: true, mid: 1, uname: '测试账号');
    api.failures['nav'] = const BiliError.api(code: -101, message: '账号未登录');
    final fresh = make();
    expect(await fresh.refresh(), isNull);
    expect(fresh.view, isA<MeLoggedOut>(), reason: 'a -101 is the same answer');
  });

  test('a failure logs the error\'s kind, never a transport\'s words with the URL', () async {
    api.failures['nav'] = _TransportError();
    api.failures['stat'] = _TransportError();
    final model = make();
    model.shown();
    await idle();
    expect(model.view, const MeFailed('网络连接失败，请检查网络后重试'));

    final warnings = [
      for (final event in sink.events)
        if (event.level == LogLevel.warn) event,
    ];
    expect(warnings.map((event) => event.msg), unorderedEquals(['me nav failed', 'me stat failed']));
    for (final event in warnings) {
      expect(event.f['error']?.toJson(), '_TransportError');
    }
    expect(sink.events.map((event) => '${event.toJson()}').join(), isNot(contains('bilibili.com')));

    api.failures['nav'] = const BiliError.api(code: -500, message: '服务器错误');
    await model.refresh();
    expect(sink.events.last.f['error']?.toJson(), 'BiliError.api(-500, 服务器错误)');
  });

  test('dispose stops following the account', () async {
    environment = _Environment(const LoggedOut());
    MeModel(api: api, environment: environment, now: () => clock, logger: logger).dispose();
    environment.account = loggedIn;
    environment.logins.value += 1;
    await idle();
    expect(api.calls, isEmpty);
  });
}
