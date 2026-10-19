import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/actions/actions_model.dart';
import 'package:bilifast/video/actions/favourites_model.dart';
import 'package:bilifast/video/actions/video_actions.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _season = UgcSeason(id: 5001, title: '演示合集', intro: '', sections: []);

VideoDetail _detail({int copyright = 1, UgcSeason? season}) => VideoDetail(
  bvid: 'BV1Dm4y1A7aa',
  aid: 900000001,
  title: '演示',
  cover: '',
  pubdate: 0,
  duration: 200,
  desc: '',
  descParts: const [],
  copyright: copyright,
  owner: const VideoOwner(mid: 42, name: '演示UP主', face: ''),
  stat: const VideoStat(view: 37000, danmaku: 337, reply: 213, favorite: 3907, coin: 1210, share: 148, like: 9131),
  pages: const [],
  season: season,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

VideoRelation _relation({
  bool like = false,
  bool dislike = false,
  bool favorite = false,
  bool attention = false,
  int coins = 0,
  bool seasonFav = false,
}) => VideoRelation(
  like: like,
  dislike: dislike,
  favorite: favorite,
  attention: attention,
  coins: coins,
  seasonFav: seasonFav,
);

UploaderCard _card({required int mid, required bool following}) =>
    UploaderCard(mid: mid, name: '演示UP主', face: '', fans: 475000, videos: 410, isVip: false, following: following);

/// [FakePageApi] that also notes the ids the calls went out with, and can answer 三连 its own way.
class _RecordingApi extends FakePageApi {
  final ids = <String>[];
  TripleResult? tripleAnswer;

  @override
  Future<void> like({required int aid, required String bvid, required bool on}) {
    ids.add('like aid=$aid bvid=$bvid');
    return super.like(aid: aid, bvid: bvid, on: on);
  }

  @override
  Future<void> follow({required int mid, required bool on}) {
    ids.add('follow mid=$mid');
    return super.follow(mid: mid, on: on);
  }

  @override
  Future<TripleResult> triple({required int aid, required String bvid}) async {
    final answer = tripleAnswer;
    if (answer == null) return super.triple(aid: aid, bvid: bvid);
    calls.add('triple');
    return answer;
  }
}

class _Rig {
  _Rig({
    this.loggedIn = true,
    int copyright = 1,
    UgcSeason? season,
    VideoRelation? relation,
    UploaderCard? uploader,
    int? mid = 10001,
    bool dislikeAvailable = false,
  }) {
    model = ActionsModel(
      api: api,
      detail: _detail(copyright: copyright, season: season),
      relation: relation,
      uploader: uploader,
      isLoggedIn: () => loggedIn,
      accountMid: () => mid,
      requestLogin: () => logins += 1,
      toast: toasts.add,
      dislikeAvailable: dislikeAvailable,
      logger: Logger(session: 'test')..add(logs),
    );
    model.addListener(() => notified += 1);
  }

  final api = _RecordingApi();
  final toasts = <String>[];
  final logs = MemorySink();
  bool loggedIn;
  var logins = 0;
  var notified = 0;
  late final ActionsModel model;

  List<String> get logged => [for (final event in logs.events) event.msg];

  Completer<void> hold(String method) => api.holds[method] = Completer<void>();
}

void main() {
  final rigs = <_Rig>[];

  _Rig rig({
    bool loggedIn = true,
    int copyright = 1,
    UgcSeason? season,
    VideoRelation? relation,
    UploaderCard? uploader,
    int? mid = 10001,
    bool dislikeAvailable = false,
  }) {
    final made = _Rig(
      loggedIn: loggedIn,
      copyright: copyright,
      season: season,
      relation: relation,
      uploader: uploader,
      mid: mid,
      dislikeAvailable: dislikeAvailable,
    );
    rigs.add(made);
    return made;
  }

  tearDown(() {
    for (final made in rigs) {
      made.model.dispose();
    }
    rigs.clear();
  });

  group('点赞', () {
    test('shows at once, clears 不喜欢, and goes out for this video', () async {
      final r = rig(relation: _relation(dislike: true));
      expect(r.model.disliked, isTrue);
      final gate = r.hold('like');
      final pending = r.model.toggleLike();
      expect(r.model.liked, isTrue, reason: 'the change shows while the server has not answered');
      expect(r.model.disliked, isFalse);
      expect(r.model.likeCount, 9132);
      gate.complete();
      await pending;
      expect(r.model.liked, isTrue);
      expect(r.api.calls, ['like on=true']);
      expect(r.api.ids, ['like aid=900000001 bvid=BV1Dm4y1A7aa']);

      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      expect(r.model.likeCount, 9131);
      expect(r.api.calls.last, 'like on=false');
      expect(r.toasts, isEmpty);
    });

    test('a refusal rolls back and toasts the server\'s words', () async {
      final r = rig(relation: _relation(dislike: true));
      r.api.failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      expect(r.model.disliked, isTrue);
      expect(r.model.likeCount, 9131);
      expect(r.toasts, ['已赞过']);
      expect(r.logins, 0);
      expect(r.logged, contains('like failed'));
      expect(r.logs.events.single.f.keys, isNot(contains('stack')), reason: 'a refusal is not a bug');
    });

    test('an expired login rolls back and asks for a login', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: -101, message: '账号未登录');
      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      expect(r.model.likeCount, 9131);
      expect(r.logins, 1);
      expect(r.toasts, isEmpty, reason: 'the login prompt has the words');
    });

    test('a second tap while one is out sends nothing', () async {
      final r = rig();
      final gate = r.hold('like');
      final first = r.model.toggleLike();
      await r.model.toggleLike();
      expect(r.model.liked, isTrue);
      gate.complete();
      await first;
      expect(r.api.calls, ['like on=true']);
    });

    test('a network failure says so', () async {
      final r = rig();
      r.api.failures['like'] = const SocketLikeError();
      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      expect(r.toasts, ['网络连接失败，请检查网络后重试']);
      expect(r.logins, 0);
    });

    test('a bug in the answer says 操作失败 and logs where it came from', () async {
      final r = rig();
      r.api.failures['like'] = StateError('No element');
      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      expect(r.toasts, ['操作失败']);
      final event = r.logs.events.singleWhere((event) => event.msg == 'like failed');
      expect(event.f.keys, contains('stack'));
    });
  });

  test('logged out, every action but 分享 asks for a login and sends nothing', () async {
    final r = rig(loggedIn: false, season: _season);
    await r.model.toggleLike();
    await r.model.triple();
    await r.model.coin(1, alsoLike: true);
    await r.model.applyFavourites(add: [3001], remove: []);
    await r.model.toggleFollow();
    r.model.ask(ActionPrompt.coin);
    expect(r.logins, 6);
    r.model.ask(ActionPrompt.favourites);
    r.model.tapFollow();
    await r.model.toggleSeasonFavourite();
    expect(r.logins, 9);
    expect(r.model.prompt, isNull);
    expect(r.model.liked, isFalse);
    expect(r.model.coins, 0);
    expect(r.model.following, isFalse);
    expect(r.model.seasonFavourited, isNull);
    expect(r.model.tripleSends, isFalse);
    expect(r.api.calls, isEmpty);

    // Sharing needs no account: the sheet opens, the share is just not counted.
    r.model.ask(ActionPrompt.share);
    expect(r.model.prompt, ActionPrompt.share);
    await r.model.shared();
    expect(r.model.shareCount, 148);
    expect(r.api.calls, isEmpty);
    expect(r.logins, 9);
  });

  group('三连', () {
    test('sets all three and counts only what is new', () async {
      final r = rig(relation: _relation(like: true));
      await r.model.triple();
      expect(r.api.calls, ['triple']);
      expect(r.model.liked, isTrue);
      expect(r.model.favorited, isTrue);
      expect(r.model.coins, 2);
      expect(r.model.likeCount, 9131, reason: 'already liked: only the favourite and the two coins are new');
      expect(r.model.favCount, 3908);
      expect(r.model.coinCount, 1212);
      expect(r.model.maxCoins, 0);
      expect(r.model.tripleDone, isTrue);
      expect(r.toasts, isEmpty);
    });

    test('when all three are done it only toasts', () async {
      final r = rig(relation: _relation(like: true, favorite: true, coins: 1));
      await r.model.triple();
      expect(r.toasts, ['已三连']);
      expect(r.api.calls, isEmpty);
    });

    test('settles from what the server did, not from what was shown', () async {
      final r = rig();
      r.api.tripleAnswer = const TripleResult(like: true, coin: false, favorite: false, multiply: 0);
      await r.model.triple();
      expect(r.model.liked, isTrue);
      expect(r.model.likeCount, 9132);
      expect(r.model.favorited, isFalse, reason: 'the optimistic favourite is taken back');
      expect(r.model.favCount, 3907);
      expect(r.model.coins, 0, reason: 'no coins to give');
      expect(r.model.coinCount, 1210);
    });

    test('answered without the coin it toasts 投币失败 and keeps the like and the favourite', () async {
      final r = rig();
      r.api.tripleAnswer = const TripleResult(like: true, coin: false, favorite: true, multiply: 0);
      await r.model.triple();
      expect(r.toasts, ['投币失败']);
      expect(r.model.liked, isTrue);
      expect(r.model.likeCount, 9132);
      expect(r.model.favorited, isTrue);
      expect(r.model.favCount, 3908);
      expect(r.model.coins, 0);
      expect(r.model.coinCount, 1210);
    });

    test('with no coin left to give, an answer without one toasts nothing', () async {
      final r = rig(relation: _relation(coins: 2));
      r.api.tripleAnswer = const TripleResult(like: true, coin: false, favorite: true, multiply: 0);
      await r.model.triple();
      expect(r.toasts, isEmpty);
      expect(r.model.tripleDone, isTrue);
    });

    test('never counts more coins than the video allows', () async {
      final r = rig(copyright: 2);
      r.api.tripleAnswer = const TripleResult(like: true, coin: true, favorite: true, multiply: 2);
      await r.model.triple();
      expect(r.model.coins, 1);
      expect(r.model.coinCount, 1211);
    });

    test('a refusal rolls back and keeps the 不喜欢', () async {
      final r = rig(relation: _relation(dislike: true, attention: true));
      r.api.failures['triple'] = const BiliError.api(code: -352, message: '风控校验失败');
      await r.model.triple();
      expect(r.model.liked, isFalse);
      expect(r.model.disliked, isTrue);
      expect(r.model.favorited, isFalse);
      expect(r.model.following, isTrue);
      expect(r.model.likeCount, 9131);
      expect(r.model.favCount, 3907);
      expect(r.toasts, ['请求过于频繁，请稍后再试']);
    });

    test('tripleSends only when a 三连 would go out', () async {
      expect(rig().model.tripleSends, isTrue);
      expect(rig(loggedIn: false).model.tripleSends, isFalse);
      expect(rig(relation: _relation(like: true, favorite: true, coins: 2)).model.tripleSends, isFalse);

      final r = rig();
      final gate = r.hold('triple');
      final pending = r.model.triple();
      expect(r.model.tripleSends, isFalse, reason: 'one is out already');
      gate.complete();
      await pending;
    });
  });

  group('投币', () {
    test('limits: a repost takes one, an original two, less what was given', () {
      final repost = rig(copyright: 2).model;
      expect(repost.maxCoins, 1);
      expect(repost.canGive(2, 10), isFalse);
      expect(repost.canGive(1, 10), isTrue);

      final oneGiven = rig(relation: _relation(coins: 1)).model;
      expect(oneGiven.maxCoins, 1);
      expect(oneGiven.canGive(2, 10), isFalse);

      final original = rig().model;
      expect(original.maxCoins, 2);
      expect(original.canGive(2, 2), isTrue);
      expect(original.canGive(2, 1.5), isFalse);
      expect(original.canGive(1, 1.5), isTrue);
      expect(original.canGive(1, 0.5), isFalse);
      expect(original.canGive(0, 10), isFalse);
    });

    test('adds coins, can also like, and toasts past the limit', () async {
      final r = rig();
      await r.model.coin(1, alsoLike: true);
      expect(r.model.coins, 1);
      expect(r.model.coinCount, 1211);
      expect(r.model.liked, isTrue);
      expect(r.model.likeCount, 9132);
      expect(r.api.calls, ['coin multiply=1 like=true']);
      await r.model.coin(2, alsoLike: false);
      expect(r.toasts, ['最多还能投1个硬币']);
      await r.model.coin(1, alsoLike: false);
      await r.model.coin(1, alsoLike: false);
      expect(r.toasts, ['最多还能投1个硬币', '已投满2个硬币']);
      expect(r.api.calls.where((call) => call.startsWith('coin')), hasLength(2));
    });

    test('a repost at its limit says one coin', () async {
      final r = rig(copyright: 2, relation: _relation(coins: 1));
      await r.model.coin(1, alsoLike: false);
      expect(r.toasts, ['已投满1个硬币']);
      expect(r.api.calls, isEmpty);
    });

    test('a refusal takes the coins and the like back', () async {
      final r = rig();
      r.api.failures['coin'] = const BiliError.api(code: -104, message: '硬币不足');
      await r.model.coin(2, alsoLike: true);
      expect(r.model.coins, 0);
      expect(r.model.coinCount, 1210);
      expect(r.model.liked, isFalse);
      expect(r.model.likeCount, 9131);
      expect(r.toasts, ['硬币不足']);
    });

    test('the balance comes from the api, and its failure reaches the dialog', () async {
      final r = rig();
      r.api.balance = 873;
      expect(await r.model.coinBalance(), 873);
      r.api.failures['coinBalance'] = const BiliError.http(500);
      await expectLater(r.model.coinBalance(), throwsA(isA<BiliError>()));
      expect(r.logins, 0);
    });

    test('a balance Bilibili refuses for want of a login asks for the login, and still fails the ask', () async {
      final r = rig();
      r.api.failures['coinBalance'] = const BiliError.api(code: -101, message: '账号未登录');
      await expectLater(r.model.coinBalance(), throwsA(isA<BiliError>()));
      expect(r.logins, 1);
      expect(r.toasts, isEmpty);
    });
  });

  group('关注', () {
    test('已关注 asks first; the confirm then unfollows, and 关注 follows the uploader', () async {
      final r = rig(relation: _relation(attention: true));
      r.model.tapFollow();
      expect(r.model.prompt, ActionPrompt.unfollow);
      expect(r.api.calls, isEmpty);
      r.model.clearPrompt();
      expect(r.model.prompt, isNull);
      await r.model.toggleFollow();
      expect(r.model.following, isFalse);
      await r.model.toggleFollow();
      expect(r.model.following, isTrue);
      expect(r.api.calls, ['follow on=false', 'follow on=true']);
      expect(r.api.ids, ['follow mid=42', 'follow mid=42']);
    });

    test('关注 while not following follows at once', () async {
      final r = rig();
      r.model.tapFollow();
      expect(r.model.following, isTrue);
      expect(r.model.prompt, isNull);
      expect(r.api.calls, ['follow on=true']);
    });

    test('the uploader card sets 关注 only for this video\'s uploader, and only before a tap', () async {
      final r = rig(uploader: _card(mid: 42, following: true));
      expect(r.model.following, isTrue);
      r.model.applyUploader(_card(mid: 7, following: false));
      expect(r.model.following, isTrue, reason: 'someone else\'s card');
      await r.model.toggleFollow();
      expect(r.model.following, isFalse);
      r.model.applyUploader(_card(mid: 42, following: true));
      expect(r.model.following, isFalse, reason: 'the tap stands');
    });
  });

  group('收藏', () {
    test('adding favourites; removing from every folder takes it back', () async {
      final r = rig();
      await r.model.applyFavourites(add: [11], remove: []);
      expect(r.model.favorited, isTrue);
      expect(r.model.favCount, 3908);
      await r.model.applyFavourites(add: [], remove: [11], inAnyFolder: false);
      expect(r.model.favorited, isFalse);
      expect(r.model.favCount, 3907);
      expect(r.api.calls, ['updateFavourites add=11 remove=', 'updateFavourites add= remove=11']);
    });

    test('moving between folders keeps it favourited', () async {
      final r = rig(relation: _relation(favorite: true));
      await r.model.applyFavourites(add: [12], remove: [11], inAnyFolder: true);
      expect(r.model.favorited, isTrue);
      expect(r.model.favCount, 3907);
    });

    test('no change sends nothing', () async {
      final r = rig();
      await r.model.applyFavourites(add: [], remove: []);
      expect(r.api.calls, isEmpty);
      expect(r.notified, 0);
    });

    test('openFolders hands the sheet a model that starts loading', () {
      final r = rig();
      final folders = r.model.openFolders();
      addTearDown(folders.dispose);
      expect(folders, isA<FavouritesModel>());
      expect(folders.loading, isTrue);
      expect(r.api.calls, ['favouriteFolders']);
    });
  });

  group('late relation', () {
    test('does not undo a tap', () async {
      final r = rig();
      await r.model.toggleLike();
      r.model.apply(_relation());
      expect(r.model.liked, isTrue);
    });

    test('still fills in what was not tapped', () async {
      final r = rig();
      await r.model.toggleFollow();
      r.model.apply(_relation(like: true, favorite: true, coins: 1));
      expect(r.model.following, isTrue, reason: 'the late answer undid the follow');
      expect(r.model.liked, isTrue);
      expect(r.model.favorited, isTrue);
      expect(r.model.coins, 1);
      expect(r.model.tripleDone, isTrue);
    });

    test('a refused like takes the relation that answers after it', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      r.model.apply(_relation(like: true));
      expect(r.model.liked, isTrue, reason: 'the refused tap kept the relation out');
      expect(r.model.likeCount, 9131, reason: 'the count holds this account\'s like already');

      r.api.failures.remove('like');
      await r.model.toggleLike();
      expect(r.api.calls, ['like on=true', 'like on=false']);
      expect(r.model.liked, isFalse);
      expect(r.model.likeCount, 9130);
    });

    test('a relation that lands while a refused like is out shows once the like is taken back', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      final gate = r.hold('like');
      final pending = r.model.toggleLike();
      r.model.apply(_relation(like: true, coins: 1));
      expect(r.model.liked, isTrue);
      expect(r.model.likeCount, 9132, reason: 'the tap shows until it is answered');
      expect(r.model.coins, 1);
      gate.complete();
      await pending;
      expect(r.model.liked, isTrue);
      expect(r.model.likeCount, 9131);
    });

    test('a change taken back under another action still out shows that action\'s', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: 65004, message: '取消点赞失败');
      final coinGate = r.hold('coin');
      final coin = r.model.coin(1, alsoLike: true);
      await r.model.toggleLike();
      expect(r.model.liked, isTrue, reason: 'the coin\'s like is back');
      expect(r.model.likeCount, 9132);
      r.model.apply(_relation());
      expect(r.model.liked, isTrue, reason: 'the coin still out stands on it');
      coinGate.complete();
      await coin;
      expect(r.model.liked, isTrue);
    });

    test('two refused actions on one field leave neither\'s change', () async {
      final r = rig(relation: _relation());
      r.api.failures['coin'] = const BiliError.api(code: -104, message: '硬币不足');
      r.api.failures['like'] = const BiliError.api(code: 65004, message: '取消点赞失败');
      final coinGate = r.hold('coin');
      final likeGate = r.hold('like');
      final coin = r.model.coin(1, alsoLike: true);
      final like = r.model.toggleLike();
      expect(r.model.liked, isFalse);
      coinGate.complete();
      await coin;
      expect(r.model.coins, 0);
      expect(r.model.liked, isFalse);
      likeGate.complete();
      await like;
      expect(r.model.liked, isFalse, reason: 'the unlike\'s rollback brought back the refused coin\'s like');
      expect(r.model.likeCount, 9131);
      expect(r.model.coinCount, 1210);
    });

    test('after a login, reset shows this account\'s state whatever was tapped', () async {
      final r = rig();
      await r.model.toggleLike();
      r.model.reset(_relation(favorite: true, coins: 2, attention: true));
      expect(r.model.liked, isFalse);
      expect(r.model.favorited, isTrue);
      expect(r.model.coins, 2);
      expect(r.model.following, isTrue);
      expect(r.api.calls, ['like on=true'], reason: 'the page asks for the relation; the actions only show it');
    });
  });

  group('side by side', () {
    test('a failed like leaves a follow in flight alone', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      final likeGate = r.hold('like');
      final followGate = r.hold('follow');
      final like = r.model.toggleLike();
      final follow = r.model.toggleFollow();
      expect(r.model.liked, isTrue);
      expect(r.model.following, isTrue);

      likeGate.complete();
      await like;
      expect(r.model.liked, isFalse);
      expect(r.model.likeCount, 9131);
      expect(r.model.following, isTrue, reason: 'the like\'s rollback undid the follow');
      followGate.complete();
      await follow;
      expect(r.model.following, isTrue);
      expect(r.toasts, ['已赞过']);
    });

    test('two failures each take back only their own', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      r.api.failures['follow'] = const BiliError.api(code: 22001, message: '不能关注自己');
      final likeGate = r.hold('like');
      final followGate = r.hold('follow');
      final like = r.model.toggleLike();
      final follow = r.model.toggleFollow();

      likeGate.complete();
      await like;
      followGate.complete();
      await follow;
      expect(r.model.liked, isFalse, reason: 'the follow\'s rollback brought the failed like back');
      expect(r.model.likeCount, 9131);
      expect(r.model.following, isFalse);
      expect(r.toasts, ['已赞过', '不能关注自己']);
    });

    test('a refused like does not undo the like a 三连 confirmed', () async {
      final r = rig();
      r.api.failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      final gate = r.hold('like');
      final like = r.model.toggleLike();
      await r.model.triple();
      expect(r.model.liked, isTrue);
      gate.complete();
      await like;
      expect(r.model.liked, isTrue, reason: 'the like\'s rollback undid what the 三连 did');
      expect(r.model.likeCount, 9132);
      expect(r.model.tripleDone, isTrue);
      expect(r.toasts, ['已赞过']);
    });

    test('a refused 收藏 does not undo the favourite a 三连 confirmed', () async {
      final r = rig();
      r.api.failures['updateFavourites'] = const BiliError.api(code: 11201, message: '已经收藏过了');
      final gate = r.hold('updateFavourites');
      final favourites = r.model.applyFavourites(add: [11], remove: []);
      await r.model.triple();
      gate.complete();
      await favourites;
      expect(r.model.favorited, isTrue);
      expect(r.model.favCount, 3908);
    });

    test('a failed coin takes back only what it changed', () async {
      final r = rig(relation: _relation(like: true));
      r.api.failures['coin'] = const BiliError.api(code: -104, message: '硬币不足');
      final coinGate = r.hold('coin');
      final coin = r.model.coin(1, alsoLike: true);
      await r.model.toggleLike();
      expect(r.model.liked, isFalse);
      expect(r.model.likeCount, 9130);
      coinGate.complete();
      await coin;
      expect(r.model.coins, 0);
      expect(r.model.coinCount, 1210);
      expect(r.model.liked, isFalse, reason: 'the coin found it liked already, so the unlike stands');
      expect(r.model.likeCount, 9130);
    });
  });

  group('合集 订阅', () {
    test('null without a 合集, and before the relation answers', () {
      expect(rig().model.seasonFavourited, isNull);
      expect(rig(relation: _relation(seasonFav: true)).model.seasonFavourited, isNull);
      expect(rig(season: _season).model.seasonFavourited, isNull);
      expect(rig(season: _season, relation: _relation(seasonFav: true)).model.seasonFavourited, isTrue);
    });

    test('a relation that answers fills it in', () {
      final r = rig(season: _season);
      r.model.apply(_relation(seasonFav: true));
      expect(r.model.seasonFavourited, isTrue);
      expect(r.notified, 1);
    });

    test('subscribes and unsubscribes the 合集, toasting each', () async {
      final r = rig(season: _season, relation: _relation());
      expect(r.model.seasonFavourited, isFalse);
      final gate = r.hold('favSeason');
      final pending = r.model.toggleSeasonFavourite();
      expect(r.model.seasonFavourited, isTrue, reason: 'shown at once');
      expect(r.toasts, isEmpty);
      gate.complete();
      await pending;
      expect(r.toasts, ['已收藏合集']);
      await r.model.toggleSeasonFavourite();
      expect(r.model.seasonFavourited, isFalse);
      expect(r.toasts, ['已收藏合集', '已取消收藏']);
      expect(r.api.calls, ['favSeason season=5001 on=true', 'favSeason season=5001 on=false']);
    });

    test('a refusal takes it back with the server\'s words', () async {
      final r = rig(season: _season, relation: _relation());
      r.api.failures['favSeason'] = const BiliError.api(code: 11001, message: '已经订阅过了');
      await r.model.toggleSeasonFavourite();
      expect(r.model.seasonFavourited, isFalse);
      expect(r.toasts, ['已经订阅过了']);
    });

    test('a late relation does not undo it', () async {
      final r = rig(season: _season);
      await r.model.toggleSeasonFavourite();
      r.model.apply(_relation(seasonFav: false));
      expect(r.model.seasonFavourited, isTrue);
    });

    test('logged out a tap asks for a login and sends nothing', () async {
      final r = rig(loggedIn: false, season: _season);
      await r.model.toggleSeasonFavourite();
      expect(r.logins, 1);
      expect(r.api.calls, isEmpty);
    });

    test('logged in with the relation unknown, a tap subscribes', () async {
      final r = rig(season: _season);
      expect(r.model.seasonFavourited, isNull);
      await r.model.toggleSeasonFavourite();
      expect(r.api.calls, ['favSeason season=5001 on=true']);
      expect(r.model.seasonFavourited, isTrue);
    });

    test('without a 合集 there is nothing to send', () async {
      final r = rig();
      await r.model.toggleSeasonFavourite();
      expect(r.api.calls, isEmpty);
      expect(r.toasts, isEmpty);
    });
  });

  group('不喜欢', () {
    test('is not available in this build: a tap says so and sends nothing', () async {
      final r = rig();
      expect(r.model.dislikeAvailable, isFalse);
      await r.model.toggleDislike();
      expect(r.toasts, ['此版本不支持不喜欢']);
      expect(r.model.disliked, isFalse);
      expect(r.api.calls, isEmpty);
    });

    test('says so logged out too, without asking for a login', () async {
      final r = rig(loggedIn: false);
      await r.model.toggleDislike();
      expect(r.toasts, ['此版本不支持不喜欢']);
      expect(r.logins, 0);
    });

    test('with the TV keys: logged out asks for a login, logged in still says it can\'t', () async {
      final out = rig(loggedIn: false, dislikeAvailable: true);
      await out.model.toggleDislike();
      expect(out.logins, 1);
      expect(out.toasts, isEmpty);

      final r = rig(dislikeAvailable: true);
      await r.model.toggleDislike();
      expect(r.toasts, ['此版本不支持不喜欢']);
      expect(r.logins, 0);
      expect(r.api.calls, isEmpty);
    });
  });

  group('分享', () {
    test('a completed share counts once logged in', () async {
      final r = rig();
      await r.model.shared();
      expect(r.model.shareCount, 149);
      expect(r.api.calls, ['countShare']);
    });

    test('a failed count is taken back quietly and logged', () async {
      final r = rig();
      r.api.failures['countShare'] = const BiliError.http(500);
      final gate = r.hold('countShare');
      final pending = r.model.shared();
      expect(r.model.shareCount, 149);
      gate.complete();
      await pending;
      expect(r.model.shareCount, 148);
      expect(r.toasts, isEmpty);
      expect(r.logged, contains('share count failed'));
    });
  });

  group('prompts', () {
    test('投币 and 收藏 put their prompt up for the page, which clears it', () {
      final r = rig();
      r.model.ask(ActionPrompt.coin);
      expect(r.model.prompt, ActionPrompt.coin);
      expect(r.notified, 1);
      r.model.clearPrompt();
      expect(r.model.prompt, isNull);
      expect(r.notified, 2);
      r.model.clearPrompt();
      expect(r.notified, 2, reason: 'nothing was up');
      r.model.ask(ActionPrompt.favourites);
      expect(r.model.prompt, ActionPrompt.favourites);
    });
  });

  group('failure words', () {
    test('Bilibili\'s own refusals show word for word; codes the app knows keep its words; a bug is 操作失败', () {
      expect(ActionsModel.failureMessage(const BiliError.api(code: 65006, message: '已赞过')), '已赞过');
      expect(ActionsModel.failureMessage(const BiliError.api(code: -101, message: '账号未登录')), '需要登录');
      expect(ActionsModel.failureMessage(const BiliError.api(code: -352, message: '风控校验失败')), '请求过于频繁，请稍后再试');
      expect(ActionsModel.failureMessage(const BiliError.api(code: -412, message: '请求被拦截')), '请求过于频繁，请稍后再试');
      expect(ActionsModel.failureMessage(const BiliError.api(code: -404, message: '啥都木有')), '视频不存在或已被删除');
      expect(ActionsModel.failureMessage(const BiliError.api(code: 10003, message: '')), 'B 站返回错误 10003：');
      expect(ActionsModel.failureMessage(const BiliError.http(412)), 'B 站暂时拒绝了请求（风控），稍后再试');
      expect(ActionsModel.failureMessage(const SocketLikeError()), '网络连接失败，请检查网络后重试');
      expect(ActionsModel.failureMessage(TimeoutException('slow')), '网络连接失败，请检查网络后重试');
      expect(ActionsModel.failureMessage(StateError('No element')), '操作失败');
      expect(ActionsModel.failureMessage(const FormatException('Unexpected end of input')), '操作失败');
    });
  });

  group('notifications', () {
    test('every visible change notifies: the change, then its settling', () async {
      final r = rig();
      await r.model.toggleLike();
      expect(r.notified, 2);
      r.api.failures['follow'] = const BiliError.http(500);
      await r.model.toggleFollow();
      expect(r.notified, 4, reason: 'shown, then taken back');
      expect(r.model.following, isFalse);
    });

    test('a relation that changes nothing does not notify', () {
      final r = rig();
      r.model.apply(_relation());
      expect(r.notified, 0);
    });

    test('an answer after dispose changes nothing it shows, toasts nothing and asks for no login', () async {
      final api = _RecordingApi();
      final toasts = <String>[];
      var logins = 0;
      final model = ActionsModel(
        api: api,
        detail: _detail(),
        isLoggedIn: () => true,
        accountMid: () => 1,
        requestLogin: () => logins += 1,
        toast: toasts.add,
        logger: Logger(session: 'test'),
      );
      api.failures['like'] = const BiliError.api(code: -101, message: '账号未登录');
      final gate = api.holds['like'] = Completer<void>();
      final pending = model.toggleLike();
      model.dispose();
      gate.complete();
      await pending;
      expect(toasts, isEmpty);
      expect(logins, 0);
    });
  });
}

/// What the transports throw when the connection fails: not a [BiliError].
class SocketLikeError implements Exception {
  const SocketLikeError();

  @override
  String toString() => 'ClientException: Connection refused';
}
