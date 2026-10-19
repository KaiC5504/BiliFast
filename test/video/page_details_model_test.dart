import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/actions/actions_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_details_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

const _bvA = 'BV1Dm4y1A7aa';
const _bvB = 'BV1EF411e9oF';

VideoDetail _detail(String bvid, {int aid = 900000001, int owner = 42, List<int> cids = const [11, 12]}) => VideoDetail(
  bvid: bvid,
  aid: aid,
  title: '演示',
  cover: '',
  pubdate: 0,
  duration: 200,
  desc: '',
  descParts: const [],
  copyright: 1,
  owner: VideoOwner(mid: owner, name: '演示UP主', face: ''),
  stat: const VideoStat(view: 37000, danmaku: 337, reply: 213, favorite: 3907, coin: 1210, share: 148, like: 9131),
  pages: [
    for (final (index, cid) in cids.indexed) VideoPage(cid: cid, page: index + 1, part: 'P${index + 1}', duration: 100),
  ],
  season: null,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

UploaderCard _card(int mid, {bool following = false, int fans = 475000}) =>
    UploaderCard(mid: mid, name: '演示UP主', face: '', fans: fans, videos: 410, isVip: true, following: following);

const _tagsA = [VideoTag(id: 1, name: '《グランドエスケープ》', kind: VideoTagKind.bgm)];
const _tagsB = [VideoTag(id: 2, name: '动漫二创激励计划', kind: VideoTagKind.topic)];

VideoCard _related(String bvid, {int aid = 77}) => VideoCard(
  aid: aid,
  bvid: bvid,
  cid: 5,
  title: '相关视频',
  cover: '',
  duration: 60,
  ownerMid: 7,
  ownerName: 'UP',
  views: 1,
  danmaku: 0,
  likes: 0,
);

/// [FakePageApi] whose side loads answer when the test says: each call to a method in [held] waits on its own
/// completer, in the order the calls were made.
class _HeldApi extends FakePageApi {
  _HeldApi(this.held);

  final Set<String> held;
  final waiting = <String, List<Completer<void>>>{};

  Future<void> _wait(String name) async {
    if (!held.contains(name)) return;
    final gate = Completer<void>();
    (waiting[name] ??= []).add(gate);
    await gate.future;
  }

  void open(String name, int index) => waiting[name]![index].complete();

  @override
  Future<UploaderCard> uploaderCard({required int mid}) async {
    final answer = super.uploaderCard(mid: mid)..ignore();
    await _wait('uploaderCard');
    return answer;
  }

  @override
  Future<VideoRelation> relation({required int aid, required String bvid}) async {
    final answer = super.relation(aid: aid, bvid: bvid)..ignore();
    await _wait('relation');
    return answer;
  }

  @override
  Future<List<VideoTag>> tags({required String bvid, required int cid}) async {
    final answer = super.tags(bvid: bvid, cid: cid)..ignore();
    await _wait('tags');
    return answer;
  }

  @override
  Future<String> onlineCount({required int aid, required String bvid, required int cid}) async {
    final answer = super.onlineCount(aid: aid, bvid: bvid, cid: cid)..ignore();
    await _wait('onlineCount');
    return answer;
  }
}

class _Rig {
  _Rig({
    FakePageApi? api,
    this.loggedIn = true,
    Listenable? accountChanges,
    Listenable? pageLogins,
    PeriodicTimerSpy? periodic,
  }) : api = api ?? FakePageApi(uploader: _card(42), tagsValue: _tagsA, online: '53') {
    model = VideoPageDetailsModel(
      session: session,
      api: this.api,
      isLoggedIn: () => loggedIn,
      accountMid: () => loggedIn ? 10001 : null,
      requestLogin: () => logins += 1,
      toast: toasts.add,
      periodic: periodic?.start,
      logger: Logger(session: 'test')..add(logs),
      accountChanges: accountChanges,
      logins: pageLogins,
    );
    model.addListener(() => notified += 1);
  }

  final session = FakePlayerSession();
  final FakePageApi api;
  final toasts = <String>[];
  final logs = MemorySink();
  bool loggedIn;
  var logins = 0;
  var notified = 0;
  late final VideoPageDetailsModel model;

  ActionsModel? get actions => model.actions as ActionsModel?;

  List<String> get logged => [for (final event in logs.events) event.msg];

  List<String> callsTo(String method) => [
    for (final call in api.calls)
      if (call.split(' ').first == method) call,
  ];

  /// The session's signed view arrives; the part follows with [cid].
  void show(VideoDetail detail, {int? cid}) {
    session.detail = detail;
    session.video = VideoView(bvid: detail.bvid, aid: detail.aid, pages: detail.pages);
    session.part = cid == null ? null : detail.pages.firstWhere((page) => page.cid == cid);
    session.changed();
  }

  /// Another part of the same video, as the controller opens it: the detail is gone for a moment.
  void switchPart(VideoDetail detail, int cid) {
    session.detail = null;
    session.video = null;
    session.part = null;
    session.changed();
    show(detail, cid: cid);
  }

  void dispose() {
    model.dispose();
    session.dispose();
  }
}

class PeriodicTimerSpy {
  final periods = <Duration>[];

  Timer start(Duration period, void Function() tick) {
    periods.add(period);
    return Timer.periodic(period, (_) => tick());
  }
}

const _toBackground = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
const _toForeground = [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void lifecycle(List<AppLifecycleState> states) {
    for (final state in states) {
      // ignore: invalid_use_of_protected_member
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  tearDown(() {
    if (binding.lifecycleState case final state? when state != AppLifecycleState.resumed) lifecycle(_toForeground);
  });

  void onFakeClock(void Function(FakeAsync async, _Rig Function({FakePageApi? api, bool loggedIn}) rig) body) {
    fakeAsync((async) {
      final rigs = <_Rig>[];
      _Rig rig({FakePageApi? api, bool loggedIn = true}) {
        final made = _Rig(api: api, loggedIn: loggedIn);
        rigs.add(made);
        return made;
      }

      body(async, rig);
      for (final made in rigs) {
        made.dispose();
      }
      async.flushMicrotasks();
    });
  }

  test('nothing loads before the video is known', () {
    onFakeClock((async, rig) {
      final r = rig();
      async.elapse(const Duration(minutes: 1));
      expect(r.model.actions, isNull);
      expect(r.model.uploader, isNull);
      expect(r.model.tags, isEmpty);
      expect(r.model.online.value, isNull);
      expect(r.api.calls, isEmpty);
    });
  });

  test('a video\'s detail brings its actions, the uploader\'s card and the relation, each applied as it lands', () {
    onFakeClock((async, rig) {
      final r = rig();
      r.api.relationValue = const VideoRelation(
        like: true,
        dislike: false,
        favorite: false,
        attention: true,
        coins: 1,
      );
      r.show(_detail(_bvA));
      expect(r.actions?.detail.bvid, _bvA);
      expect(r.notified, 1);
      async.flushMicrotasks();
      expect(r.api.calls, containsAll(['uploaderCard mid=42', 'relation']));
      expect(r.model.uploader?.fans, 475000);
      expect(r.actions?.liked, isTrue);
      expect(r.actions?.coins, 1);
      expect(r.actions?.following, isTrue);
      expect(r.callsTo('tags'), isEmpty, reason: 'no part yet');
      expect(r.callsTo('onlineCount'), isEmpty);
    });
  });

  test('logged out, the uploader and the tags load but the relation is not asked', () {
    onFakeClock((async, rig) {
      final r = rig(loggedIn: false);
      r.api.uploader = _card(42, following: true);
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      expect(r.model.uploader, isNotNull);
      expect(r.actions?.following, isTrue, reason: 'the card says so');
      expect(r.model.tags, _tagsA);
      expect(r.callsTo('relation'), isEmpty);
    });
  });

  test('the part brings its tags and N人正在看 at once, then every 30 s', () {
    onFakeClock((async, rig) {
      final r = rig();
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      expect(r.callsTo('tags'), ['tags cid=11']);
      expect(r.model.tags, _tagsA);
      expect(r.callsTo('onlineCount'), ['onlineCount cid=11']);
      expect(r.model.online.value, '53');

      r.api.online = '1000+';
      async.elapse(const Duration(seconds: 29));
      expect(r.callsTo('onlineCount'), hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(r.callsTo('onlineCount'), hasLength(2));
      expect(r.model.online.value, '1000+');
      async.elapse(const Duration(seconds: 60));
      expect(r.callsTo('onlineCount'), hasLength(4));
    });
  });

  test('the poll runs on the injected timer, every 30 s', () {
    fakeAsync((async) {
      final spy = PeriodicTimerSpy();
      final r = _Rig(periodic: spy);
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      expect(spy.periods, [VideoPageDetailsModel.onlineInterval]);
      expect(VideoPageDetailsModel.onlineInterval, const Duration(seconds: 30));
      r.dispose();
    });
  });

  test('inactive stops the poll; active again asks at once and polls on', () {
    onFakeClock((async, rig) {
      final r = rig();
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      r.model.active = false;
      async.elapse(const Duration(minutes: 5));
      expect(r.callsTo('onlineCount'), hasLength(1));

      r.model.active = true;
      async.flushMicrotasks();
      expect(r.callsTo('onlineCount'), hasLength(2));
      async.elapse(const Duration(seconds: 30));
      expect(r.callsTo('onlineCount'), hasLength(3));
      r.model.active = true;
      async.flushMicrotasks();
      expect(r.callsTo('onlineCount'), hasLength(3), reason: 'already active');
    });
  });

  group('in the background', () {
    test('N人正在看 stops; back in the foreground it asks at once and polls on', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        expect(r.callsTo('onlineCount'), hasLength(1));
        lifecycle(_toBackground);
        async.elapse(const Duration(minutes: 5));
        expect(r.callsTo('onlineCount'), hasLength(1), reason: 'polled in the background or in PiP');

        lifecycle(_toForeground);
        async.flushMicrotasks();
        expect(r.callsTo('onlineCount'), hasLength(2));
        async.elapse(const Duration(seconds: 30));
        expect(r.callsTo('onlineCount'), hasLength(3));
      });
    });

    test('a moment inactive (Control Centre, a call banner) keeps polling', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        lifecycle([AppLifecycleState.inactive]);
        async.elapse(const Duration(seconds: 30));
        expect(r.callsTo('onlineCount'), hasLength(2));
        lifecycle([AppLifecycleState.resumed]);
        async.flushMicrotasks();
        expect(r.callsTo('onlineCount'), hasLength(2), reason: 'it never stopped');
      });
    });

    test('a covered page stays quiet when the app comes back', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        r.model.active = false;
        lifecycle(_toBackground);
        lifecycle(_toForeground);
        async.elapse(const Duration(minutes: 1));
        expect(r.callsTo('onlineCount'), hasLength(1));
      });
    });

    test('a page made in the background waits for the foreground', () {
      onFakeClock((async, rig) {
        lifecycle(_toBackground);
        final r = rig();
        r.show(_detail(_bvA), cid: 11);
        async.elapse(const Duration(minutes: 1));
        expect(r.callsTo('onlineCount'), isEmpty);
        lifecycle(_toForeground);
        async.flushMicrotasks();
        expect(r.callsTo('onlineCount'), hasLength(1));
      });
    });
  });

  group('a relation that failed', () {
    test('is asked again once the page shows again, and not once it answered', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.api.failures['relation'] = const BiliError.http(500);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        r.api.failures.remove('relation');
        r.api.relationValue = const VideoRelation(like: true, dislike: false, favorite: false, attention: false, coins: 2);
        async.elapse(const Duration(minutes: 1));
        expect(r.callsTo('relation'), hasLength(1), reason: 'no retries on a timer');

        r.model.active = false;
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(2));
        expect(r.actions?.liked, isTrue);
        expect(r.actions?.maxCoins, 0, reason: 'the coins given are known now');
        r.model.active = false;
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(2), reason: 'it answered');
      });
    });

    test('is asked again when the app comes back, once each time', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.api.failures['relation'] = const BiliError.http(500);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        lifecycle(_toBackground);
        lifecycle(_toForeground);
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(2));
        async.elapse(const Duration(minutes: 1));
        expect(r.callsTo('relation'), hasLength(2));
        lifecycle(_toBackground);
        lifecycle(_toForeground);
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(3));
      });
    });

    test('asked again keeps what was tapped since', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.api.failures['relation'] = const BiliError.http(500);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        unawaited(r.actions!.toggleLike());
        async.flushMicrotasks();
        r.api.failures.remove('relation');
        r.api.relationValue = const VideoRelation(like: false, dislike: false, favorite: false, attention: false, coins: 1);
        r.model.active = false;
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.actions?.liked, isTrue);
        expect(r.actions?.coins, 1);
      });
    });

    test('for an earlier video is not asked again', () {
      onFakeClock((async, rig) {
        final r = rig();
        r.api.failures['relation'] = const BiliError.http(500);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        r.api.failures.remove('relation');
        r.show(_detail(_bvB, cids: [21]), cid: 21);
        async.flushMicrotasks();
        r.model.active = false;
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(2), reason: 'the new video asked its own');
      });
    });
  });

  test('while inactive the session is not followed; active again catches up', () {
    onFakeClock((async, rig) {
      final r = rig();
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      final first = r.model.actions;
      r.model.active = false;
      // A newer page's video on the shared player.
      r.show(_detail(_bvB, owner: 43, cids: [21]), cid: 21);
      async.flushMicrotasks();
      expect(r.model.actions, same(first));
      expect(r.callsTo('uploaderCard'), ['uploaderCard mid=42']);

      r.show(_detail(_bvA), cid: 11);
      r.model.active = true;
      async.flushMicrotasks();
      expect(r.model.actions, same(first), reason: 'its own video is back on the player');
      expect(r.callsTo('tags'), ['tags cid=11']);
    });
  });

  test('another part keeps the actions and the uploader, and brings its own tags and count', () {
    onFakeClock((async, rig) {
      final r = rig();
      final detail = _detail(_bvA);
      r.show(detail, cid: 11);
      async.flushMicrotasks();
      final actions = r.model.actions;
      r.api.tagsValue = _tagsB;
      r.api.online = '7';
      r.switchPart(detail, 12);
      expect(r.model.tags, _tagsA, reason: 'kept until the part\'s own arrive');
      async.flushMicrotasks();
      expect(r.model.actions, same(actions));
      expect(r.model.uploader, isNotNull);
      expect(r.callsTo('uploaderCard'), hasLength(1));
      expect(r.callsTo('relation'), hasLength(1));
      expect(r.callsTo('tags'), ['tags cid=11', 'tags cid=12']);
      expect(r.model.tags, _tagsB);
      expect(r.callsTo('onlineCount').last, 'onlineCount cid=12');
      expect(r.model.online.value, '7');
      async.elapse(const Duration(seconds: 30));
      expect(r.callsTo('onlineCount'), ['onlineCount cid=11', 'onlineCount cid=12', 'onlineCount cid=12']);
    });
  });

  test('the same part again asks nothing', () {
    onFakeClock((async, rig) {
      final r = rig();
      final detail = _detail(_bvA);
      r.show(detail, cid: 11);
      async.flushMicrotasks();
      final calls = r.api.calls.length;
      r.switchPart(detail, 11);
      r.session.changed();
      async.flushMicrotasks();
      expect(r.api.calls, hasLength(calls));
    });
  });

  test('a new video swaps in new actions, disposes the old, and starts its side loads afresh', () {
    onFakeClock((async, rig) {
      final r = rig();
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      final old = r.model.actions!;
      r.api.uploader = _card(43, fans: 12);
      r.api.tagsValue = _tagsB;
      r.api.online = '9';
      r.session.detail = null;
      r.session.changed();
      expect(r.model.actions, same(old), reason: 'the old video shows until the new one is known');

      r.show(_detail(_bvB, aid: 2, owner: 43, cids: [21]), cid: 21);
      expect(r.actions?.detail.bvid, _bvB);
      expect(() => old.addListener(() {}), throwsFlutterError, reason: 'the old actions were disposed');
      expect(r.model.uploader, isNull);
      expect(r.model.tags, isEmpty);
      expect(r.model.online.value, isNull);
      async.flushMicrotasks();
      expect(r.model.uploader?.mid, 43);
      expect(r.model.tags, _tagsB);
      expect(r.model.online.value, '9');
      expect(r.callsTo('uploaderCard'), ['uploaderCard mid=42', 'uploaderCard mid=43']);
      expect(r.callsTo('relation'), hasLength(2));
    });
  });

  test('a part of a newer video waits for that video\'s detail', () {
    onFakeClock((async, rig) {
      final r = rig();
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      final b = _detail(_bvB, cids: [21]);
      r.session.video = VideoView(bvid: _bvB, pages: b.pages);
      r.session.part = b.pages.first;
      r.session.changed();
      async.flushMicrotasks();
      expect(r.callsTo('tags'), ['tags cid=11'], reason: 'the part is not the known video\'s');
    });
  });

  group('late answers', () {
    test('for an earlier video are dropped', () {
      onFakeClock((async, rig) {
        final api = _HeldApi({'uploaderCard', 'relation'})..uploader = _card(42, fans: 1);
        api.relationValue = const VideoRelation(like: true, dislike: false, favorite: true, attention: true, coins: 2);
        final r = rig(api: api);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        r.show(_detail(_bvB, owner: 42, cids: [21]), cid: 21);
        async.flushMicrotasks();
        api.open('uploaderCard', 0);
        api.open('relation', 0);
        async.flushMicrotasks();
        expect(r.model.uploader, isNull, reason: 'the card was asked for the earlier video');
        expect(r.actions?.liked, isFalse);
        expect(r.actions?.following, isFalse);

        api.open('uploaderCard', 1);
        api.open('relation', 1);
        async.flushMicrotasks();
        expect(r.model.uploader?.fans, 1);
        expect(r.actions?.liked, isTrue);
      });
    });

    test('for an earlier part are dropped', () {
      onFakeClock((async, rig) {
        final api = _HeldApi({'tags', 'onlineCount'})
          ..tagsValue = _tagsA
          ..online = '53';
        final r = rig(api: api);
        final detail = _detail(_bvA);
        r.show(detail, cid: 11);
        async.flushMicrotasks();
        api.tagsValue = _tagsB;
        api.online = '7';
        r.switchPart(detail, 12);
        async.flushMicrotasks();
        api.open('tags', 0);
        api.open('onlineCount', 0);
        async.flushMicrotasks();
        expect(r.model.tags, isEmpty);
        expect(r.model.online.value, isNull);

        api.open('tags', 1);
        api.open('onlineCount', 1);
        async.flushMicrotasks();
        expect(r.model.tags, _tagsB);
        expect(r.model.online.value, '7');
      });
    });

    test('a slow count gets no second ask piled on', () {
      onFakeClock((async, rig) {
        final api = _HeldApi({'onlineCount'});
        final r = rig(api: api);
        r.show(_detail(_bvA), cid: 11);
        async.elapse(const Duration(seconds: 65));
        expect(r.callsTo('onlineCount'), hasLength(1));
        api.open('onlineCount', 0);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(r.callsTo('onlineCount'), hasLength(2));
      });
    });
  });

  test('side-load failures are logged, keep the last value and toast nothing', () {
    onFakeClock((async, rig) {
      final r = rig();
      final detail = _detail(_bvA);
      r.show(detail, cid: 11);
      async.flushMicrotasks();
      r.api.failures['tags'] = const BiliError.http(500);
      r.api.failures['onlineCount'] = const BiliError.http(500);
      r.switchPart(detail, 12);
      async.flushMicrotasks();
      expect(r.model.tags, _tagsA);
      expect(r.model.online.value, '53');
      expect(r.logged, containsAll(['tags failed', 'online count failed']));

      r.api.failures['uploaderCard'] = const BiliError.api(code: -404, message: '啥都木有');
      r.api.failures['relation'] = const BiliError.http(500);
      r.show(_detail(_bvB, cids: [21]), cid: 21);
      async.flushMicrotasks();
      expect(r.model.uploader, isNull);
      expect(r.logged, containsAll(['uploader card failed', 'relation failed']));
      expect(r.toasts, isEmpty);
      expect(r.logins, 0);
    });
  });

  group('稍后再看', () {
    test('logged out asks for a login and sends nothing', () async {
      final r = _Rig(loggedIn: false);
      addTearDown(r.dispose);
      final result = await r.model.watchLater(_related('BV1xx411c7mD'));
      expect(result.message, isEmpty, reason: 'the login request says so itself');
      expect(result.ok, isFalse);
      expect(r.logins, 1);
      expect(r.api.calls, isEmpty);
    });

    test('adds the card\'s video', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      final result = await r.model.watchLater(_related('BV1xx411c7mD', aid: 170001));
      expect(result.message, '已添加至稍后再看');
      expect(result.ok, isTrue);
      expect(r.api.calls, ['addToWatchLater aid=170001']);
    });

    test('a refusal answers with its words', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.api.failures['addToWatchLater'] = const BiliError.api(code: 90001, message: '稍后再看列表已满');
      final result = await r.model.watchLater(_related('BV1xx411c7mD'));
      expect(result.message, 'B 站返回错误 90001：稍后再看列表已满');
      expect(result.ok, isFalse);
      expect(r.logged, contains('watch later failed'));
      expect(r.logins, 0);
    });

    test('an expired login asks for a login', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.api.failures['addToWatchLater'] = const BiliError.api(code: -101, message: '账号未登录');
      final result = await r.model.watchLater(_related('BV1xx411c7mD'));
      expect(result.message, isEmpty, reason: 'the login prompt has the words');
      expect(r.logins, 1);
    });
  });

  group('a login', () {
    test('asks for this account\'s relation again', () {
      fakeAsync((async) {
        final account = ValueNotifier(0);
        final r = _Rig(loggedIn: false, accountChanges: account);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        expect(r.callsTo('relation'), isEmpty);

        r.api.relationValue = const VideoRelation(
          like: true,
          dislike: false,
          favorite: false,
          attention: true,
          coins: 0,
        );
        r.loggedIn = true;
        account.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        expect(r.actions?.liked, isTrue);
        account.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1), reason: 'still the same login');
        r.dispose();
        account.dispose();
      });
    });

    test('while covered asks once the page shows again', () {
      fakeAsync((async) {
        final account = ValueNotifier(0);
        final r = _Rig(loggedIn: false, accountChanges: account);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        r.model.active = false;
        r.loggedIn = true;
        account.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), isEmpty);
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        r.dispose();
        account.dispose();
      });
    });

    test('made from the page asks again though the account looked logged in all along, over what was tapped', () {
      fakeAsync((async) {
        final logins = ValueNotifier(0);
        final r = _Rig(pageLogins: logins);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        r.api.failures['like'] = const BiliError.api(code: -101, message: '账号未登录');
        unawaited(r.actions!.toggleLike());
        async.flushMicrotasks();
        expect(r.logins, 1);

        r.api.relationValue = const VideoRelation(
          like: true,
          dislike: false,
          favorite: false,
          attention: true,
          coins: 0,
        );
        logins.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(2));
        expect(r.actions?.liked, isTrue);
        expect(r.actions?.following, isTrue);
        expect(r.callsTo('like'), hasLength(1), reason: 'nothing tapped is sent again');
        r.dispose();
        logins.dispose();
      });
    });

    test('heard both as the account changing and from the page asks once while the first ask is out', () {
      fakeAsync((async) {
        final account = ValueNotifier(0);
        final logins = ValueNotifier(0);
        final api = _HeldApi({'relation'});
        final r = _Rig(api: api, loggedIn: false, accountChanges: account, pageLogins: logins);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        r.loggedIn = true;
        account.value += 1;
        async.flushMicrotasks();
        logins.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        api.open('relation', 0);
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        r.dispose();
        account.dispose();
        logins.dispose();
      });
    });

    test('made from the page while covered asks once the page shows again; a gate answered logged out asks nothing',
        () {
      fakeAsync((async) {
        final logins = ValueNotifier(0);
        final r = _Rig(loggedIn: false, pageLogins: logins);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        logins.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), isEmpty);

        r.model.active = false;
        r.loggedIn = true;
        logins.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), isEmpty);
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        r.dispose();
        logins.dispose();
      });
    });

    test('whose relation failed asks again once the page shows again', () {
      fakeAsync((async) {
        final account = ValueNotifier(0);
        final r = _Rig(loggedIn: false, accountChanges: account);
        r.show(_detail(_bvA), cid: 11);
        async.flushMicrotasks();
        r.api.failures['relation'] = const BiliError.http(500);
        r.loggedIn = true;
        account.value += 1;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(1));
        expect(r.logged, contains('relation failed'));
        expect(r.toasts, isEmpty);

        r.api.failures.remove('relation');
        r.api.relationValue = const VideoRelation(like: true, dislike: false, favorite: true, attention: false, coins: 0);
        r.model.active = false;
        r.model.active = true;
        async.flushMicrotasks();
        expect(r.callsTo('relation'), hasLength(2));
        expect(r.actions?.liked, isTrue);
        expect(r.actions?.favorited, isTrue);
        r.dispose();
        account.dispose();
      });
    });
  });

  test('dispose stops the poll and every listener, and disposes the actions and the count', () {
    fakeAsync((async) {
      final account = ValueNotifier(0);
      final r = _Rig(accountChanges: account);
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      final actions = r.model.actions!;
      final online = r.model.online as ValueNotifier<String?>;
      final calls = r.api.calls.length;
      r.model.dispose();
      r.show(_detail(_bvB, cids: [21]), cid: 21);
      account.value += 1;
      lifecycle(_toBackground);
      lifecycle(_toForeground);
      async.elapse(const Duration(minutes: 2));
      expect(r.api.calls, hasLength(calls));
      expect(() => actions.addListener(() {}), throwsFlutterError);
      expect(() => online.addListener(() {}), throwsFlutterError);
      r.model.dispose();
      r.session.dispose();
      account.dispose();
    });
  });

  test('an answer after dispose changes nothing', () {
    onFakeClock((async, rig) {
      final api = _HeldApi({'uploaderCard', 'tags', 'onlineCount'});
      final r = rig(api: api);
      r.show(_detail(_bvA), cid: 11);
      async.flushMicrotasks();
      r.model.dispose();
      api.open('uploaderCard', 0);
      api.open('tags', 0);
      api.open('onlineCount', 0);
      async.flushMicrotasks();
      expect(r.model.uploader, isNull);
      expect(r.model.tags, isEmpty);
    });
  });
}
