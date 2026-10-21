import 'dart:async';
import 'dart:math' show max, min;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show requestFailureMessage;
import '../../space/follow_book.dart';
import '../page_api.dart';
import 'favourites_model.dart';
import 'video_actions.dart';

/// [VideoActions] for one video over [PageApi] (BiliNative `ActionsModel.swift`).
class ActionsModel extends ChangeNotifier implements VideoActions {
  ActionsModel({
    required this._api,
    required this.detail,
    VideoRelation? relation,
    UploaderCard? uploader,
    required this._isLoggedIn,
    required this._accountMid,
    required this._requestLogin,
    required this._toast,
    bool Function()? appAuthorized,
    Future<bool> Function()? requestAppAuth,
    this._follows,
    Logger? logger,
  })  : _appAuthorized = appAuthorized ?? _never,
        _requestAppAuth = requestAppAuth ?? _refused,
        _logger = logger ?? Logger.shared,
        _likeCount = detail.stat.like,
        _coinCount = detail.stat.coin,
        _favCount = detail.stat.favorite,
        _shareCount = detail.stat.share {
    if (relation != null) apply(relation);
    if (uploader != null) applyUploader(uploader);
    _follows?.addListener(_followChanged);
  }

  final VideoDetail detail;
  final PageApi _api;
  final bool Function() _isLoggedIn;
  final int? Function() _accountMid;
  final VoidCallback _requestLogin;
  final void Function(String message) _toast;

  /// Whether the app token, which 不喜欢 needs, is held; [_requestAppAuth] asks for it and says whether it came.
  final bool Function() _appAuthorized;
  final Future<bool> Function() _requestAppAuth;
  final FollowBook? _follows;
  final Logger _logger;

  static bool _never() => false;
  static Future<bool> _refused() async => false;

  bool _liked = false;
  bool _disliked = false;
  bool _favorited = false;
  bool _following = false;
  int _coins = 0;
  bool? _seasonFav;
  int _likeCount;
  int _coinCount;
  int _favCount;
  int _shareCount;
  ActionPrompt? _prompt;

  /// The change that set each field last. A late relation answer must not overwrite those, but still fills in the
  /// rest, and a field whose changes are all taken back shows what Bilibili last said again.
  final Map<_Field, _Change> _owners = {};
  VideoRelation? _relation;

  /// The relation's 关注 or the uploader card's, whichever came last, or a 关注 accepted elsewhere since.
  bool? _saidFollowing;

  /// Bumped by every 关注 accepted elsewhere; see [answerStamp].
  int _followStamp = 0;
  final Set<String> _busy = {};
  bool _disposed = false;

  @override
  bool get liked => _liked;

  @override
  bool get disliked => _disliked;

  @override
  bool get favorited => _favorited;

  @override
  bool get following => _following;

  @override
  bool get followingKnown => _saidFollowing != null || _owners.containsKey(_Field.following);

  /// Taken as a relation or card ask goes out, and handed back with its answer to [apply], [applyUploader] or
  /// [reset]: a 关注 accepted elsewhere after the ask holds over the answer's.
  int get answerStamp => _followStamp;

  @override
  int get coins => _coins;

  @override
  int get likeCount => _likeCount;

  @override
  int get coinCount => _coinCount;

  @override
  int get favCount => _favCount;

  @override
  int get shareCount => _shareCount;

  @override
  bool? get seasonFavourited => _seasonFav;

  @override
  ActionPrompt? get prompt => _prompt;

  /// A relation answer fills in what the user hasn't changed, and later what a refused change gives back. [asked] is
  /// the [answerStamp] its ask went out with; without one the answer counts as asked just now.
  void apply(VideoRelation relation, {int? asked}) {
    final before = _snapshot;
    _relation = relation;
    if (_askedSinceFollow(asked)) _saidFollowing = relation.attention;
    for (final field in _Field.values) {
      if (!_owners.containsKey(field)) _showSaid(field);
    }
    if (_snapshot.changedFrom(before).isNotEmpty) _notify();
  }

  void applyUploader(UploaderCard card, {int? asked}) {
    if (card.mid != detail.owner.mid || !_askedSinceFollow(asked)) return;
    _saidFollowing = card.following;
    if (_owners.containsKey(_Field.following) || card.following == _following) return;
    _following = card.following;
    _notify();
  }

  bool _askedSinceFollow(int? asked) => asked == null || asked == _followStamp;

  /// A 关注 accepted elsewhere (the uploader sheet, a space) wins over an earlier tap here and over a relation or card
  /// answer asked before it; a tap here still in flight keeps its own answer.
  void _followChanged() {
    final change = _follows?.last;
    if (change == null || change.mid != detail.owner.mid) return;
    _followStamp += 1;
    _saidFollowing = change.following;
    if (_busy.contains('follow')) return;
    _owners.remove(_Field.following);
    if (_following == change.following) return;
    _following = change.following;
    _notify();
  }

  /// After a login: this account's state, whatever was tapped before.
  void reset(VideoRelation relation, {int? asked}) {
    _owners.clear();
    apply(relation, asked: asked);
  }

  int get _coinLimit => detail.copyright == 2 ? 1 : 2;

  @override
  int get maxCoins => max(0, _coinLimit - _coins);

  @override
  bool get tripleDone => _liked && _coins > 0 && _favorited;

  @override
  bool get tripleSends => _isLoggedIn() && !tripleDone && !_busy.contains('triple');

  @override
  void clearPrompt() {
    if (_prompt == null) return;
    _prompt = null;
    _notify();
  }

  @override
  bool canGive(int multiply, double balance) => multiply >= 1 && multiply <= maxCoins && balance >= multiply;

  @override
  Future<void> toggleLike() {
    final on = !_liked;
    return _perform('like', () => _setLiked(on), (_) => _api.like(aid: detail.aid, bvid: detail.bvid, on: on));
  }

  /// The official API's call, so without the app token it asks for one first and goes on only once it has it. A token
  /// Bilibili turns down is asked for again, and the tap isn't replayed.
  @override
  Future<void> toggleDislike() async {
    if (!_isLoggedIn()) {
      _login();
      return;
    }
    if (!_appAuthorized()) {
      if (!await _requestAppAuth() || _disposed) return;
    }
    final on = !_disliked;
    await _perform(
      'dislike',
      () => _setDisliked(on),
      (_) => _api.dislike(aid: detail.aid, on: on),
      done: () => _say(on ? '感谢反馈' : '取消不喜欢'),
      official: true,
    );
  }

  @override
  Future<void> triple() async {
    if (!_isLoggedIn()) {
      _login();
      return;
    }
    if (tripleDone) {
      _say('已三连');
      return;
    }
    final expected = maxCoins;
    await _perform('triple', () {
      _setLiked(true);
      _setFavorited(true);
    }, (action) async {
      final result = await _api.triple(aid: detail.aid, bvid: detail.bvid);
      _settleTriple(action, result, expected);
      if (expected > 0 && !result.coin) _say('投币失败');
    });
  }

  @override
  Future<void> coin(int multiply, {required bool alsoLike}) async {
    if (!_isLoggedIn()) {
      _login();
      return;
    }
    final allowed = maxCoins;
    if (multiply < 1 || multiply > allowed) {
      _say(allowed == 0 ? '已投满$_coinLimit个硬币' : '最多还能投$allowed个硬币');
      return;
    }
    await _perform('coin', () {
      _coins += multiply;
      _coinCount += multiply;
      if (alsoLike) _setLiked(true);
    }, (_) => _api.coin(aid: detail.aid, bvid: detail.bvid, multiply: multiply, alsoLike: alsoLike));
  }

  @override
  Future<double> coinBalance() async {
    try {
      return await _api.coinBalance();
    } on BiliError catch (error) {
      if (error.needsLogin) _login();
      rethrow;
    }
  }

  /// Without [inAnyFolder], adding means favourited and removing means not.
  @override
  Future<void> applyFavourites({required List<int> add, required List<int> remove, bool? inAnyFolder}) async {
    if (add.isEmpty && remove.isEmpty) return;
    final after = inAnyFolder ?? add.isNotEmpty;
    await _perform(
      'favourites',
      () => _setFavorited(after),
      (_) => _api.updateFavourites(aid: detail.aid, add: add, remove: remove),
    );
  }

  @override
  FavouriteFolders openFolders() => FavouritesModel(
        api: _api,
        aid: detail.aid,
        mid: _accountMid,
        actions: this,
        requestLogin: _login,
        logger: _logger,
      );

  @override
  void tapFollow() {
    if (!_isLoggedIn()) {
      _login();
      return;
    }
    if (_following) {
      _setPrompt(ActionPrompt.unfollow);
    } else {
      unawaited(toggleFollow());
    }
  }

  @override
  Future<void> toggleFollow() {
    final on = !_following;
    return _perform(
      'follow',
      () => _following = on,
      (_) => _api.follow(mid: detail.owner.mid, on: on),
      done: () => _follows?.changed(detail.owner.mid, following: on),
    );
  }

  /// Not knowing (the relation hasn't answered or couldn't be asked) counts as not subscribed.
  @override
  Future<void> toggleSeasonFavourite() async {
    final season = detail.season;
    if (season == null) return;
    final on = !(_seasonFav ?? false);
    await _perform(
      'season',
      () => _seasonFav = on,
      (_) => _api.favSeason(seasonId: season.id, on: on),
      done: () => _say(on ? '已收藏合集' : '已取消收藏'),
    );
  }

  /// Sharing needs no account but the counter does, so logged out a share isn't counted.
  @override
  Future<void> shared() async {
    if (!_isLoggedIn()) return;
    _shareCount += 1;
    _notify();
    try {
      await _api.countShare(aid: detail.aid);
    } catch (error) {
      // The share itself went out; a toast about the counter would only confuse.
      _shareCount -= 1;
      _notify();
      _logger.warn(LogCategory.api, 'share count failed', {'error': '$error'});
    }
  }

  @override
  void ask(ActionPrompt prompt) {
    if (prompt != ActionPrompt.share && !_isLoggedIn()) {
      _login();
      return;
    }
    _setPrompt(prompt);
  }

  void _setPrompt(ActionPrompt prompt) {
    _prompt = prompt;
    _notify();
  }

  /// Bilibili words its refusals for the user (硬币不足, 已经点赞过了), so their message shows word for word; codes the
  /// app knows better keep [BiliError.userMessage]. Anything else is a lost connection or a bug (操作失败).
  static String failureMessage(Object error) => switch (error) {
        BiliAPIError(:final code, :final message) when message.isNotEmpty && !_ownWords.contains(code) => message,
        _ => requestFailureMessage(error, fallback: '操作失败'),
      };

  static const _ownWords = {-101, -352, -412, -404};

  /// No token, or one Bilibili turned down (the client's codes for that; it has reported the token to be dropped).
  static bool _tokenRefused(Object error) => switch (error) {
        BiliNoAppTokenError() => true,
        BiliAPIError(code: -101 || -2) => true,
        _ => false,
      };

  _Snapshot get _snapshot => _Snapshot(
        liked: _liked,
        disliked: _disliked,
        favorited: _favorited,
        following: _following,
        coins: _coins,
        seasonFav: _seasonFav,
        likeCount: _likeCount,
        coinCount: _coinCount,
        favCount: _favCount,
      );

  /// Runs [change] for [action], which then holds every field the change moved, and the [confirmed] ones as well.
  void _record(_Action action, void Function() change, {Set<_Field> confirmed = const {}}) {
    final before = _snapshot;
    change();
    for (final field in {..._snapshot.changedFrom(before), ...confirmed}) {
      final under = _owners[field];
      if (under != null && identical(under, action.changes[field])) continue;
      _owners[field] = action.changes[field] = _Change(before, under);
    }
  }

  /// Takes back [action]'s change to each of [fields]. A field another action has set since keeps that value, and
  /// skips this change if that one is taken back too; a field no change holds any more shows what Bilibili last said.
  /// Actions run side by side (点赞 and 关注 sit next to each other, a 三连 can land while a 点赞 is out), and one
  /// failing must not undo another.
  void _undo(_Action action, Iterable<_Field> fields) {
    for (final field in fields) {
      final change = action.changes[field];
      if (change == null || change.undone) continue;
      change.undone = true;
      if (!identical(_owners[field], change)) continue;
      var back = change;
      while (back.under?.undone ?? false) {
        back = back.under!;
      }
      _restore(field, back.before);
      if (back.under case final standing?) {
        _owners[field] = standing;
      } else {
        _owners.remove(field);
        _showSaid(field);
      }
    }
  }

  void _restore(_Field field, _Snapshot from) {
    switch (field) {
      case _Field.liked:
        _liked = from.liked;
        _likeCount = from.likeCount;
      case _Field.disliked:
        _disliked = from.disliked;
      case _Field.favorited:
        _favorited = from.favorited;
        _favCount = from.favCount;
      case _Field.following:
        _following = from.following;
      case _Field.coins:
        _coins = from.coins;
        _coinCount = from.coinCount;
      case _Field.seasonFav:
        _seasonFav = from.seasonFav;
    }
  }

  /// What Bilibili last said about [field], for a field no change holds. The counts stay: they include this account's
  /// part already.
  void _showSaid(_Field field) {
    if (field == _Field.following) {
      if (_saidFollowing case final following?) _following = following;
      return;
    }
    final relation = _relation;
    if (relation == null) return;
    switch (field) {
      case _Field.liked:
        _liked = relation.like;
      case _Field.disliked:
        _disliked = relation.dislike;
      case _Field.favorited:
        _favorited = relation.favorite;
      case _Field.coins:
        _coins = relation.coins;
      case _Field.seasonFav:
        if (detail.season != null) _seasonFav = relation.seasonFav;
      case _Field.following:
        break;
    }
  }

  /// Like clears dislike and dislike clears like, as on the server.
  void _setLiked(bool on) {
    if (on == _liked) return;
    _liked = on;
    _likeCount = max(0, _likeCount + (on ? 1 : -1));
    if (on) _disliked = false;
  }

  void _setDisliked(bool on) {
    _disliked = on;
    if (on) _setLiked(false);
  }

  void _setFavorited(bool on) {
    if (on == _favorited) return;
    _favorited = on;
    _favCount = max(0, _favCount + (on ? 1 : -1));
  }

  /// The server says what 三连 actually did: what it didn't do is taken back as a failure would be, and what it did,
  /// with the coins it spent, is its own from then on, so a refused 点赞 or 收藏 still out can't undo it.
  void _settleTriple(_Action action, TripleResult result, int expected) {
    _undo(action, [
      if (!result.like) ...[_Field.liked, _Field.disliked],
      if (!result.favorite) _Field.favorited,
    ]);
    final spent = result.coin ? min(result.multiply, expected) : 0;
    _record(action, () {
      if (result.like) _setLiked(true);
      if (result.favorite) _setFavorited(true);
      final coins = min(_coinLimit, _coins + spent);
      _coinCount += coins - _coins;
      _coins = coins;
    }, confirmed: {
      if (result.like) ...{_Field.liked, _Field.disliked},
      if (result.favorite) _Field.favorited,
      if (spent > 0) _Field.coins,
    });
  }

  /// One action: shown at once, sent, and taken back with the server's words if it fails. A second tap while it is
  /// out does nothing. An [official] call's -101 is about the app token, not the web login.
  Future<void> _perform(String name, void Function() change, Future<void> Function(_Action action) call,
      {VoidCallback? done, bool official = false}) async {
    if (!_isLoggedIn()) {
      _login();
      return;
    }
    if (!_busy.add(name)) return;
    final action = _Action();
    _record(action, change);
    _notify();
    try {
      await call(action);
      done?.call();
    } catch (error, stack) {
      _undo(action, _Field.values);
      _logger.warn(LogCategory.api, '$name failed', {
        'error': '$error',
        // A refusal is Bilibili's; anything else may be a bug in reading its answer.
        if (error is! BiliError) 'stack': '$stack',
      });
      // An expired login gets the login prompt's words alone, and a refused app token the token's confirm.
      if (official && _tokenRefused(error)) {
        if (!_disposed) unawaited(_requestAppAuth());
      } else if (error is BiliError && error.needsLogin) {
        _login();
      } else {
        _say(failureMessage(error));
      }
    } finally {
      _busy.remove(name);
      _notify();
    }
  }

  /// A page that has moved on to another video, or left, shows nothing for this one.
  void _say(String message) {
    if (!_disposed) _toast(message);
  }

  void _login() {
    if (!_disposed) _requestLogin();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _follows?.removeListener(_followChanged);
    super.dispose();
  }
}

enum _Field { liked, disliked, favorited, following, coins, seasonFav }

final class _Snapshot {
  const _Snapshot({
    required this.liked,
    required this.disliked,
    required this.favorited,
    required this.following,
    required this.coins,
    required this.seasonFav,
    required this.likeCount,
    required this.coinCount,
    required this.favCount,
  });

  final bool liked;
  final bool disliked;
  final bool favorited;
  final bool following;
  final int coins;
  final bool? seasonFav;
  final int likeCount;
  final int coinCount;
  final int favCount;

  /// A count belongs to its field: 点赞's to liked, 投币's to coins, 收藏's to favorited.
  Set<_Field> changedFrom(_Snapshot other) => {
        if (liked != other.liked || likeCount != other.likeCount) _Field.liked,
        if (disliked != other.disliked) _Field.disliked,
        if (favorited != other.favorited || favCount != other.favCount) _Field.favorited,
        if (following != other.following) _Field.following,
        if (coins != other.coins || coinCount != other.coinCount) _Field.coins,
        if (seasonFav != other.seasonFav) _Field.seasonFav,
      };
}

/// One action's change to one field. [under] is the change it replaced, which shows again if this one is taken back.
final class _Change {
  _Change(this.before, this.under);

  /// Everything as it was just before; only this change's field is read back from it.
  final _Snapshot before;
  final _Change? under;
  bool undone = false;
}

/// One tap's changes, field by field.
final class _Action {
  final Map<_Field, _Change> changes = {};
}
