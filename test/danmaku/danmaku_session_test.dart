import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/danmaku/mask/mask_feed.dart';
import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/foundation.dart';
import 'package:bilifast/video/page_api.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_mask_feed.dart';

/// The account's 屏蔽词 as a test sets them.
class Rules extends BlockRuleStore {
  Rules(PageApi api, this.answers) : super(api: api, isLoggedIn: () => true);

  List<BlockRule> value = const [];
  int refreshes = 0;

  /// What each refresh answers, in order; null (it worked) once they run out.
  final List<String?> answers;

  @override
  List<BlockRule> get rules => value;

  set rules(List<BlockRule> next) {
    value = next;
    notifyListeners();
  }

  @override
  Future<String?> refresh({bool force = false}) async {
    refreshes++;
    return answers.isEmpty ? null : answers.removeAt(0);
  }
}

final class Rig {
  Rig({
    this.loggedIn = true,
    this.vip = false,
    this.mid = 12345,
    List<String?>? ruleAnswers,
    ValueListenable<DanmakuMaskInfo?>? maskInfo,
    MaskFetch? maskFetch,
    MaskFeedFactory maskFeeds = createMaskFeed,
    DanmakuSettings initial = const DanmakuSettings(),
  }) : settings = DanmakuSettingsStore.memory(initial) {
    final logger = Logger(session: 'test')..add(logs);
    feed = DanmakuFeed(client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger), logger: logger);
    rules = Rules(api, [...?ruleAnswers]);
    session = DanmakuSession(
      feed: feed,
      settings: settings,
      rules: rules,
      api: api,
      target: () => target,
      position: () => position,
      isLoggedIn: () => loggedIn,
      isVip: () => vip,
      accountMid: () => mid,
      requestLogin: () => loginRequests++,
      accountChanges: account,
      maskInfo: maskInfo,
      maskFetch: maskFetch,
      maskFeeds: maskFeeds,
      logger: logger,
    );
  }

  /// The app's account notifier.
  final account = _Account();

  final http = Canned.http()
    ..dataRoutes[Canned.segmentPath] = (
      200,
      danmakuSegmentBytes([(1000, '前方高能'), (2000, '来了')]),
    );
  final api = FakePageApi();
  final DanmakuSettingsStore settings;
  final logs = MemorySink();
  late final DanmakuFeed feed;
  late final Rules rules;
  late final DanmakuSession session;
  bool loggedIn;
  bool vip;
  int mid;
  DanmakuTarget? target = (bvid: 'BV1GJ411x7h7', cid: 42);
  double position = 1.5;
  int loginRequests = 0;

  Future<void> load() async {
    feed.load(cid: 42, durationMs: 300000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
  }

  List<String> shown() {
    final timeline = feed.timeline!;
    timeline.seek(-1);
    return [
      for (var ms = 999; ms < 10000; ms += 1000)
        for (final item in timeline.advance(ms)) item.text,
    ];
  }

  void dispose() {
    session.dispose();
    feed.dispose();
    account.dispose();
  }
}

void main() {
  late Rig rig;

  tearDown(() => rig.dispose());

  group('the filter', () {
    test('a 弹幕设置 change filters the loaded danmaku again', () async {
      rig = Rig();
      await rig.load();
      expect(rig.shown(), ['前方高能', '来了']);

      rig.settings.update(rig.settings.value.copyWith(filter: const DanmakuFilterOptions(blockScroll: true)));
      await rig.feed.settle();
      expect(rig.feed.timeline, isNotNull);
      expect(rig.shown(), isEmpty);

      rig.settings.reset();
      await rig.feed.settle();
      expect(rig.shown(), ['前方高能', '来了']);
    });

    test('a 屏蔽词 change filters the loaded danmaku again', () async {
      rig = Rig();
      await rig.load();
      rig.rules.rules = const [BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '高能')];
      await rig.feed.settle();
      expect(rig.shown(), ['来了']);
    });

    test('what is set when the page opens applies to the first segment', () async {
      rig = Rig();
      rig.settings.update(rig.settings.value.copyWith(filter: const DanmakuFilterOptions(blockScroll: true)));
      rig.rules.rules = const [BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '来')];
      expect(rig.feed.options.blockScroll, isTrue);
      rig.settings.reset();
      await rig.load();
      expect(rig.shown(), ['前方高能']);
    });

    test('after dispose the stores no longer reach the feed', () async {
      rig = Rig();
      final settings = rig.settings;
      rig.session.dispose();
      settings.update(settings.value.copyWith(filter: const DanmakuFilterOptions(blockColored: true)));
      expect(rig.feed.options.blockColored, isFalse);
      rig.feed.dispose();
      rig = Rig();
    });
  });

  test('the rules are asked for once when logged in, never logged out', () {
    rig = Rig();
    expect(rig.rules.refreshes, 1);
    rig.dispose();
    rig = Rig(loggedIn: false);
    expect(rig.rules.refreshes, 0);
  });

  test('a page opened before the account was known asks for the rules once it is', () {
    rig = Rig(loggedIn: false);
    expect(rig.rules.refreshes, 0);
    rig.loggedIn = true;
    rig.account.changed();
    expect(rig.rules.refreshes, 1);
    rig.account.changed();
    expect(rig.rules.refreshes, 1, reason: 'only on becoming logged in');
  });

  test('a login from the page asks for the rules again, though the account looked logged in', () {
    rig = Rig(mid: 0);
    expect(rig.rules.refreshes, 1);
    rig.mid = 777;
    rig.session.refreshAccount();
    expect(rig.rules.refreshes, 2);
    rig.loggedIn = false;
    rig.session.refreshAccount();
    expect(rig.rules.refreshes, 2, reason: 'a gate that answered without a login asks nothing');
  });

  group('a failed rules refresh', () {
    test('is tried once more after 15 s', () {
      fakeAsync((async) {
        rig = Rig(ruleAnswers: [BlockRuleStore.syncFailed, BlockRuleStore.syncFailed]);
        async.elapse(const Duration(seconds: 14));
        expect(rig.rules.refreshes, 1);
        async.elapse(const Duration(seconds: 1));
        expect(rig.rules.refreshes, 2);
        async.elapse(const Duration(minutes: 5));
        expect(rig.rules.refreshes, 2, reason: 'once, not in a loop');
      });
    });

    test('is not tried again after a success, a logout or dispose', () {
      fakeAsync((async) {
        rig = Rig();
        async.elapse(const Duration(minutes: 1));
        expect(rig.rules.refreshes, 1);
        rig.dispose();

        rig = Rig(ruleAnswers: [BlockRuleStore.syncFailed]);
        async.flushMicrotasks();
        rig.loggedIn = false;
        async.elapse(const Duration(minutes: 1));
        expect(rig.rules.refreshes, 1);
        rig.dispose();

        rig = Rig(ruleAnswers: [BlockRuleStore.syncFailed]);
        async.flushMicrotasks();
        rig.dispose();
        async.elapse(const Duration(minutes: 1));
        expect(rig.rules.refreshes, 1);
        expect(async.pendingTimers, isEmpty);
        rig = Rig();
      });
    });
  });

  test('the session tells its listeners when the uploader closed danmaku', () async {
    rig = Rig();
    rig.http.dataRoutes[Canned.segmentPath] = (200, danmakuSegmentBytes(const [], closed: true));
    var heard = 0;
    rig.session.addListener(() => heard++);
    await rig.load();
    expect(rig.session.closed, isTrue);
    expect(heard, 1);
    rig.feed.load(cid: 43, durationMs: 300000);
    expect(rig.session.closed, isFalse);
    expect(heard, 2);
  });

  group('send', () {
    test('goes out at the playhead and shows at once in its box', () async {
      rig = Rig();
      await rig.load();
      rig.feed.update(positionMs: 1600, playing: true);
      final result = await rig.session.send('  你好  ', const DanmakuStyle(size: DanmakuSize.small, position: DanmakuPosition.top, color: 0xD42D25));
      expect(result, isNull);

      final draft = rig.api.postedDanmaku.single;
      expect(
        (draft.cid, draft.bvid, draft.text, draft.mode, draft.fontSize, draft.color, draft.gradient, draft.progressMs),
        (42, 'BV1GJ411x7h7', '你好', 5, 18, 0xD42D25, false, 1500),
      );
      rig.position = 2.5;
      final own = rig.session.recent().singleWhere((elem) => elem.content == '你好');
      expect((own.id, own.midHash, own.mode, own.progressMs), (9000, MidHash.of(12345), 5, 1600));
      expect(rig.shown(), contains('你好'));
    });

    test('the gradient goes out in white for a VIP', () async {
      rig = Rig(vip: true);
      await rig.load();
      expect(await rig.session.send('渐变', const DanmakuStyle(color: 0xD42D25, gradient: true)), isNull);
      final draft = rig.api.postedDanmaku.single;
      expect((draft.color, draft.gradient), (0xFFFFFF, true));
    });

    test('logged out asks the page for the login once, sends nothing and keeps the draft', () async {
      rig = Rig(loggedIn: false);
      rig.session.sender.text = '你好';
      expect(await rig.session.sender.send(), '');
      expect(rig.loginRequests, 1);
      expect(rig.api.calls, isEmpty);
      expect(rig.session.sender.text, '你好');
    });

    test('blank sends nothing and says nothing', () async {
      rig = Rig();
      expect(await rig.session.send('  \n ', const DanmakuStyle()), isNull);
      expect(rig.api.calls, isEmpty);
    });

    test('closed by the uploader', () async {
      rig = Rig();
      rig.http.dataRoutes[Canned.segmentPath] = (200, danmakuSegmentBytes(const [], closed: true));
      await rig.load();
      expect(await rig.session.send('你好', const DanmakuStyle()), 'UP主已关闭弹幕');
      expect(rig.api.calls, isEmpty);
    });

    test('the gradient without VIP', () async {
      rig = Rig();
      expect(await rig.session.send('你好', const DanmakuStyle(gradient: true)), '开通大会员后可使用');
      expect(rig.api.calls, isEmpty);
    });

    test('no video yet', () async {
      rig = Rig()..target = null;
      expect(await rig.session.send('你好', const DanmakuStyle()), '视频还没有加载好');
      expect(rig.api.calls, isEmpty);
    });

    test('the server wanting a login asks the page for the login instead of a message, the draft kept', () async {
      rig = Rig();
      await rig.load();
      rig.api.failures['postDanmaku'] = const BiliError.api(code: -101, message: '账号未登录');
      rig.session.sender.text = '你好';
      expect(await rig.session.sender.send(), '');
      expect(rig.loginRequests, 1);
      expect(rig.session.sender.text, '你好');
      expect(rig.shown(), isNot(contains('你好')));
    });

    test('Bilibili\'s own refusal shows as it is worded', () async {
      rig = Rig();
      await rig.load();
      rig.api.failures['postDanmaku'] = const BiliError.api(code: 36703, message: '弹幕发送频率过快');
      expect(await rig.session.send('你好', const DanmakuStyle()), '弹幕发送频率过快');
      expect(rig.shown(), isNot(contains('你好')));
      expect([for (final event in rig.logs.events) event.msg], contains('danmaku post failed'));
    });

    test('one whose post lands after the page moved to another part is not shown there', () async {
      rig = Rig();
      await rig.load();
      final hold = rig.api.holds['postDanmaku'] = Completer<void>();
      final sent = rig.session.send('你好', const DanmakuStyle());
      rig.feed.load(cid: 43, durationMs: 300000);
      rig.feed.update(positionMs: 1000, playing: true);
      await rig.feed.settle();
      hold.complete();
      expect(await sent, isNull);
      expect(rig.api.postedDanmaku.single.cid, 42);
      expect(rig.shown(), ['前方高能', '来了']);
    });

    test('anything else is the network message', () async {
      rig = Rig();
      await rig.load();
      rig.api.failures['postDanmaku'] = const BiliError.http(500);
      expect(await rig.session.send('你好', const DanmakuStyle()), '发送失败，请检查网络后重试');
      rig.api.failures['postDanmaku'] = const BiliError.api(code: -400, message: '');
      expect(await rig.session.send('你好', const DanmakuStyle()), '发送失败，请检查网络后重试');
      rig.api.failures['postDanmaku'] = StateError('socket closed');
      expect(await rig.session.send('你好', const DanmakuStyle()), '发送失败，请检查网络后重试');
      expect(rig.loginRequests, 0);
    });
  });

  group('人像防挡', () {
    final maskInfo = ValueNotifier<DanmakuMaskInfo?>(null);
    late FakeMaskFeeds feeds;
    Future<Uint8List> fetch(Uri url, {required int start, int? end}) async => Uint8List(0);
    DanmakuMaskInfo info(int cid, {int time = 1, String url = 'https://upos.example/mask.webmask'}) =>
        DanmakuMaskInfo(cid: cid, plat: 0, fps: 30, time: time, url: Uri.parse(url));

    setUp(() {
      maskInfo.value = null;
      feeds = FakeMaskFeeds();
    });

    Rig shielded({MaskFetch? maskFetch}) =>
        rig = Rig(maskInfo: maskInfo, maskFetch: maskFetch ?? fetch, maskFeeds: feeds.call);

    void turn(bool on) => rig.settings.update(rig.settings.value.copyWith(peopleShield: on));

    test("a part with a mask gets a feed for it, over the page's fetch", () {
      maskInfo.value = info(42);
      shielded();
      expect(rig.session.mask.value, same(feeds.made.single));
      expect(feeds.made.single.info, same(maskInfo.value));
      expect(feeds.made.single.fetch, same(fetch));
    });

    test("a new part's mask replaces the feed, the old one let go before it is disposed", () {
      shielded();
      expect(rig.session.mask.value, isNull, reason: 'not known yet');
      maskInfo.value = info(42);
      final first = feeds.made.single;
      final seen = <(MaskFeed?, bool)>[];
      rig.session.mask.addListener(() => seen.add((rig.session.mask.value, first.disposed)));
      maskInfo.value = info(43);
      expect(feeds.made, hasLength(2));
      expect(seen.single, (feeds.made.last, false));
      expect(first.disposed, isTrue);
      expect(feeds.made.last.disposed, isFalse);

      maskInfo.value = null;
      expect(rig.session.mask.value, isNull, reason: 'a part without one');
      expect(feeds.made.last.disposed, isTrue);
    });

    test('the same mask read again keeps its feed', () {
      maskInfo.value = info(42);
      shielded();
      maskInfo.value = info(42);
      expect(feeds.made, hasLength(1));
      expect(feeds.made.single.disposed, isFalse);

      maskInfo.value = info(42, time: 2);
      expect(feeds.made, hasLength(2), reason: 'a new version is a new file');
    });

    test('switched off, the feed goes and no other comes; on again, one comes for the part playing', () {
      maskInfo.value = info(42);
      shielded();
      final first = feeds.made.single;
      turn(false);
      expect(rig.session.mask.value, isNull);
      expect(first.disposed, isTrue);
      maskInfo.value = info(43);
      expect(feeds.made, hasLength(1));

      turn(true);
      expect(rig.session.mask.value, same(feeds.made.last));
      expect(feeds.made.last.info?.cid, 43);
      rig.settings.update(rig.settings.value.copyWith(opacity: 0.5));
      expect(feeds.made, hasLength(2), reason: 'other settings leave it be');
    });

    test('a page saved with it off makes no feed', () {
      maskInfo.value = info(42);
      rig = Rig(
        maskInfo: maskInfo,
        maskFetch: fetch,
        maskFeeds: feeds.call,
        initial: const DanmakuSettings(peopleShield: false),
      );
      maskInfo.value = info(43);
      expect(rig.session.mask.value, isNull);
      expect(feeds.made, isEmpty);
    });

    test('an offline page, with no fetch, never makes one', () {
      maskInfo.value = info(42);
      rig = Rig(maskInfo: maskInfo, maskFeeds: feeds.call);
      expect(rig.session.mask.value, isNull);
      expect(feeds.made, isEmpty);
    });

    test('dispose lets go of the feed and disposes it', () {
      maskInfo.value = info(42);
      shielded();
      final feed = feeds.made.single;
      rig.dispose();
      expect(feed.disposed, isTrue);
      maskInfo.value = info(43);
      expect(feeds.made, hasLength(1), reason: 'no longer listening');
      rig = Rig();
    });
  });

  test('recent and hide reach the feed at the playhead', () async {
    rig = Rig();
    await rig.load();
    rig.position = 1.5;
    expect([for (final elem in rig.session.recent()) elem.content], ['前方高能']);
    rig.position = 3;
    final recent = rig.session.recent();
    expect([for (final elem in recent) elem.content], ['前方高能', '来了']);

    rig.session.hide(recent.first);
    expect([for (final elem in rig.session.recent()) elem.content], ['来了']);
    expect(rig.shown(), ['来了']);
  });
}

final class _Account extends ChangeNotifier {
  void changed() => notifyListeners();
}
