import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

/// The account's 屏蔽词 as a test sets them.
class Rules extends BlockRuleStore {
  Rules(PageApi api) : super(api: api, isLoggedIn: () => true);

  List<BlockRule> value = const [];
  int refreshes = 0;

  @override
  List<BlockRule> get rules => value;

  set rules(List<BlockRule> next) {
    value = next;
    notifyListeners();
  }

  @override
  Future<String?> refresh({bool force = false}) async {
    refreshes++;
    return null;
  }
}

final class Rig {
  Rig({this.loggedIn = true, this.vip = false, this.mid = 12345}) {
    final logger = Logger(session: 'test')..add(logs);
    feed = DanmakuFeed(client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger), logger: logger);
    rules = Rules(api);
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
      toast: toasts.add,
      requestLogin: () => loginRequests++,
      logger: logger,
    );
  }

  final http = Canned.http()
    ..dataRoutes[Canned.segmentPath] = (
      200,
      danmakuSegmentBytes([(1000, '前方高能'), (2000, '来了')]),
    );
  final api = FakePageApi();
  final settings = DanmakuSettingsStore.memory();
  final logs = MemorySink();
  final toasts = <String>[];
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

    test('logged out asks for the login', () async {
      rig = Rig(loggedIn: false);
      expect(await rig.session.send('你好', const DanmakuStyle()), '需要登录');
      expect(rig.loginRequests, 1);
      expect(rig.api.calls, isEmpty);
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

    test('the server wanting a login asks for it', () async {
      rig = Rig();
      await rig.load();
      rig.api.failures['postDanmaku'] = const BiliError.api(code: -101, message: '账号未登录');
      expect(await rig.session.send('你好', const DanmakuStyle()), '需要登录');
      expect(rig.loginRequests, 1);
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
