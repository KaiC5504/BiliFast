import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/follow_book.dart';
import 'package:bilifast/space/space_follow.dart';
import 'package:bilifast/video/actions/actions_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_details_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

const _owner = 42;

VideoDetail _detail() => const VideoDetail(
  bvid: 'BV1Dm4y1A7aa',
  aid: 900000001,
  title: '演示',
  cover: '',
  pubdate: 0,
  duration: 200,
  desc: '',
  descParts: [],
  copyright: 1,
  owner: VideoOwner(mid: _owner, name: '演示UP主', face: ''),
  stat: VideoStat(view: 1, danmaku: 1, reply: 1, favorite: 1, coin: 1, share: 1, like: 1),
  pages: [],
  season: null,
  staff: [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

const _card = UploaderCard(mid: _owner, name: '演示UP主', face: '', fans: 1, videos: 1, isVip: false, following: false);
const _followed = UploaderCard(mid: _owner, name: '演示UP主', face: '', fans: 1, videos: 1, isVip: false, following: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logs = MemorySink();
  final logger = Logger(session: 'test')..add(logs);

  group('SpaceFollow', () {
    late FakePageApi api;
    late FollowBook book;
    late List<String> toasts;
    late int logins;
    late bool loggedIn;

    SpaceFollow follow({bool? following}) {
      final model = SpaceFollow(
        mid: _owner,
        api: api,
        book: book,
        isLoggedIn: () => loggedIn,
        requestLogin: () => logins += 1,
        toast: toasts.add,
        following: following,
        logger: logger,
      );
      addTearDown(model.dispose);
      return model;
    }

    setUp(() {
      api = FakePageApi(uploader: _card);
      book = FollowBook();
      toasts = [];
      logins = 0;
      loggedIn = true;
    });

    test('logged in it asks the web card; logged out it is false without a call', () async {
      api.uploader = const UploaderCard(mid: 1, name: '', face: '', fans: 0, videos: 0, isVip: false, following: true);
      final model = follow();
      expect(model.following, isNull);
      await model.load();
      expect(model.following, isTrue);

      loggedIn = false;
      api.calls.clear();
      final out = follow();
      await out.load();
      expect(out.following, isFalse);
      expect(api.calls, isEmpty);
    });

    test('a tap follows at once, tells every page, and toasts 关注成功; again it unfollows', () async {
      final model = follow(following: false);
      final heard = <({int mid, bool following})?>[];
      book.addListener(() => heard.add(book.last));
      final tap = model.toggle();
      expect(model.following, isTrue);
      expect(model.busy, isTrue);
      await tap;
      expect(heard, [(mid: _owner, following: true)]);
      expect(toasts, ['关注成功']);
      await model.toggle();
      expect(model.following, isFalse);
      expect(toasts.last, '取消关注成功');
    });

    test('a refusal gives the old state back and says why', () async {
      api.failures['follow'] = const BiliError.api(code: 22009, message: '关注已达上限');
      final model = follow(following: false);
      await model.toggle();
      expect(model.following, isFalse);
      expect(toasts, ['关注已达上限']);
      expect(book.last, isNull);
    });

    test('logged out a tap asks for the login and changes nothing', () async {
      loggedIn = false;
      final model = follow(following: false);
      await model.toggle();
      expect(logins, 1);
      expect(model.following, isFalse);
      expect(api.calls, isEmpty);
    });

    test('a change made elsewhere shows here', () {
      final model = follow(following: false);
      book.changed(_owner, following: true);
      expect(model.following, isTrue);
      book.changed(7, following: false);
      expect(model.following, isTrue);
    });

    test('a card answer asked before a follow and landing after it leaves the follow standing', () async {
      final model = follow(following: false);
      final held = api.holds['uploaderCard'] = Completer<void>();
      final asked = model.load();
      api.holds.clear();
      await model.toggle();
      expect(model.following, isTrue);
      held.complete();
      await asked;
      expect(model.following, isTrue, reason: 'the card was asked before the follow');

      await model.toggle();
      expect(api.calls.where((call) => call.startsWith('follow')), ['follow on=true', 'follow on=false']);
    });

    test('a card answer asked before a change elsewhere leaves that change standing', () async {
      final model = follow(following: false);
      final held = api.holds['uploaderCard'] = Completer<void>();
      final asked = model.load();
      book.changed(_owner, following: true);
      held.complete();
      await asked;
      expect(model.following, isTrue);

      api.holds.clear();
      api.uploader = _card;
      await model.load();
      expect(model.following, isFalse, reason: 'one asked after it is Bilibili\'s word');
    });

    test('after a failed check a tap asks the card first, and an uploader already followed shows so', () async {
      api.failures['uploaderCard'] = const BiliError.http(500);
      final model = follow();
      await model.load();
      expect(model.following, isNull);
      api.failures.clear();
      api.uploader = _followed;
      await model.toggle();
      expect(model.following, isTrue);
      expect(api.calls, ['uploaderCard mid=$_owner', 'uploaderCard mid=$_owner'], reason: 'no follow sent');
      expect(toasts, isEmpty);
    });

    test('after a failed check a tap whose check fails again says so and sends nothing; the next follows', () async {
      const failure = BiliError.http(500);
      api.failures['uploaderCard'] = failure;
      final model = follow();
      await model.load();
      final tap = model.toggle();
      expect(model.busy, isTrue);
      await tap;
      expect(model.following, isNull);
      expect(toasts, [ActionsModel.failureMessage(failure)]);
      expect(api.calls.where((call) => call.startsWith('follow')), isEmpty);
      expect(logs.events.last.f['error'], const LogString('http 500'));

      api.failures.clear();
      await model.toggle();
      expect(api.calls.last, 'follow on=true');
      expect(model.following, isTrue);
      expect(toasts.last, '关注成功');
    });

    test('取消关注 while the follow is still out is sent once it returns, one call at a time', () async {
      final model = follow(following: false);
      final held = api.holds['follow'] = Completer<void>();
      final tap = model.toggle();
      final again = model.toggle();
      expect(model.following, isFalse, reason: 'the latest tap shows at once');
      expect(api.calls, ['follow on=true']);
      api.holds.clear();
      held.complete();
      await tap;
      await again;
      expect(api.calls, ['follow on=true', 'follow on=false']);
      expect(model.following, isFalse);
      expect(model.busy, isFalse);
      expect(book.last, (mid: _owner, following: false));
      expect(toasts, ['取消关注成功']);
    });

    test('taps that end where the call out is going send nothing more', () async {
      final model = follow(following: false);
      final held = api.holds['follow'] = Completer<void>();
      final tap = model.toggle();
      unawaited(model.toggle());
      unawaited(model.toggle());
      expect(model.following, isTrue);
      held.complete();
      await tap;
      expect(api.calls, ['follow on=true']);
      expect(model.following, isTrue);
      expect(toasts, ['关注成功']);
    });

    test('a refused follow-up gives back what Bilibili took', () async {
      final model = follow(following: false);
      final first = api.holds['follow'] = Completer<void>();
      final tap = model.toggle();
      unawaited(model.toggle());
      final second = api.holds['follow'] = Completer<void>();
      first.complete();
      await pumpEventQueue();
      expect(api.calls, ['follow on=true', 'follow on=false']);
      expect(model.following, isFalse);
      api.failures['follow'] = const BiliError.api(code: 22009, message: '关注已达上限');
      second.complete();
      await tap;
      expect(model.following, isTrue);
      expect(book.last, (mid: _owner, following: true));
      expect(toasts, ['关注已达上限']);
    });
  });

  group('the video page follows a change made in the sheet or a space', () {
    test('its 关注 takes the book\'s word for its uploader, and its own accepted tap reaches the book', () async {
      final book = FollowBook();
      final api = FakePageApi();
      final model = ActionsModel(
        api: api,
        detail: _detail(),
        isLoggedIn: () => true,
        accountMid: () => 1,
        requestLogin: () {},
        toast: (_) {},
        follows: book,
        logger: logger,
      );
      addTearDown(model.dispose);

      book.changed(7, following: true);
      expect(model.following, isFalse);
      book.changed(_owner, following: true);
      expect(model.following, isTrue);
      model.apply(const VideoRelation(like: false, dislike: false, favorite: false, attention: false, coins: 0));
      expect(model.following, isFalse, reason: 'a later relation answer is still Bilibili\'s word');

      await model.toggleFollow();
      expect(book.last, (mid: _owner, following: true));
    });

    test('a relation or card answer asked before the sheet\'s 关注 and landing after it leaves that standing', () async {
      final book = FollowBook();
      final api = FakePageApi(uploader: _card);
      final card = api.holds['uploaderCard'] = Completer<void>();
      final relation = api.holds['relation'] = Completer<void>();
      final session = FakePlayerSession();
      final details = VideoPageDetailsModel(
        session: session,
        api: api,
        isLoggedIn: () => true,
        accountMid: () => 1,
        requestLogin: () {},
        toast: (_) {},
        follows: book,
        logger: logger,
      );
      addTearDown(() {
        details.dispose();
        session.dispose();
      });
      final detail = _detail();
      session
        ..detail = detail
        ..video = VideoView(bvid: detail.bvid, aid: detail.aid, pages: detail.pages)
        ..changed();
      final actions = details.actions!;
      expect(api.calls, ['uploaderCard mid=$_owner', 'relation']);

      book.changed(_owner, following: true);
      expect(actions.following, isTrue);
      relation.complete();
      card.complete();
      await pumpEventQueue();
      expect(actions.following, isTrue, reason: 'both were asked before the sheet\'s follow');
    });
  });

  test('the fake pages its videos, most played sorting by plays', () async {
    final api = FakeSpaceApi.demo(now: DateTime(2026, 10, 21));
    final first = await api.videos(1, order: SpaceOrder.latest);
    expect(first.items, hasLength(20));
    expect(first.hasMore, isTrue);
    final last = await api.videos(1, order: SpaceOrder.latest, next: '40');
    expect(last.items, hasLength(5));
    expect(last.hasMore, isFalse);
    final played = await api.videos(1, order: SpaceOrder.mostPlayed);
    expect(played.items.first.play, greaterThanOrEqualTo(played.items[1].play));
    unawaited(api.profile(3));
  });
}
