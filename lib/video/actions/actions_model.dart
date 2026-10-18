import 'dart:async';
import 'dart:math' show max, min;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

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
    this.dislikeAvailable = false,
    Logger? logger,
  })  : _logger = logger ?? Logger.shared,
        _likeCount = detail.stat.like,
        _coinCount = detail.stat.coin,
        _favCount = detail.stat.favorite,
        _shareCount = detail.stat.share {
    if (relation != null) apply(relation);
    if (uploader != null) applyUploader(uploader);
  }

  final VideoDetail detail;
  final PageApi _api;
  final bool Function() _isLoggedIn;
  final int? Function() _accountMid;
  final VoidCallback _requestLogin;
  final void Function(String message) _toast;
  final Logger _logger;

  @override
  final bool dislikeAvailable;

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

  /// What the user has changed: a late relation answer must not overwrite those, but still fills in the rest.
  final Set<_Field> _touched = {};
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

  /// A relation answer fills in what the user hasn't changed yet.
  void apply(VideoRelation relation) {
    final before = _snapshot;
    if (!_touched.contains(_Field.liked)) _liked = relation.like;
    if (!_touched.contains(_Field.disliked)) _disliked = relation.dislike;
    if (!_touched.contains(_Field.favorited)) _favorited = relation.favorite;
    if (!_touched.contains(_Field.following)) _following = relation.attention;
    if (!_touched.contains(_Field.coins)) _coins = relation.coins;
    if (detail.season != null && !_touched.contains(_Field.seasonFav)) _seasonFav = relation.seasonFav;
    if (_snapshot.changedFrom(before).isNotEmpty) _notify();
  }

  void applyUploader(UploaderCard card) {
    if (_touched.contains(_Field.following) || card.mid != detail.owner.mid || card.following == _following) return;
    _following = card.following;
    _notify();
  }

  /// After a login: this account's state, whatever was tapped before.
  Future<void> refreshRelation() async {
    if (!_isLoggedIn()) return;
    try {
      final relation = await _api.relation(aid: detail.aid, bvid: detail.bvid);
      if (_disposed) return;
      _liked = relation.like;
      _disliked = relation.dislike;
      _favorited = relation.favorite;
      _following = relation.attention;
      _coins = relation.coins;
      if (detail.season != null) _seasonFav = relation.seasonFav;
      _notify();
    } catch (error) {
      _logger.warn(LogCategory.api, 'relation failed', {'error': '$error'});
    }
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
    return _perform('like', () => _setLiked(on), () => _api.like(aid: detail.aid, bvid: detail.bvid, on: on));
  }

  /// Bilibili takes 不喜欢 only through the app API, signed with the TV app's keys and the TV login's token.
  @override
  Future<void> toggleDislike() async {
    if (dislikeAvailable && !_isLoggedIn()) {
      _login();
      return;
    }
    _say('此版本不支持不喜欢');
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
    final before = _snapshot;
    final expected = maxCoins;
    await _perform('triple', () {
      _setLiked(true);
      _setFavorited(true);
    }, () async {
      final result = await _api.triple(aid: detail.aid, bvid: detail.bvid);
      _settleTriple(result, before, expected);
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
    }, () => _api.coin(aid: detail.aid, bvid: detail.bvid, multiply: multiply, alsoLike: alsoLike));
  }

  @override
  Future<double> coinBalance() => _api.coinBalance();

  /// Without [inAnyFolder], adding means favourited and removing means not.
  @override
  Future<void> applyFavourites({required List<int> add, required List<int> remove, bool? inAnyFolder}) async {
    if (add.isEmpty && remove.isEmpty) return;
    final after = inAnyFolder ?? add.isNotEmpty;
    await _perform(
      'favourites',
      () => _setFavorited(after),
      () => _api.updateFavourites(aid: detail.aid, add: add, remove: remove),
    );
  }

  @override
  FavouriteFolders openFolders() =>
      FavouritesModel(api: _api, aid: detail.aid, mid: _accountMid, actions: this, logger: _logger);

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
    return _perform('follow', () => _following = on, () => _api.follow(mid: detail.owner.mid, on: on));
  }

  @override
  Future<void> toggleSeasonFavourite() async {
    final season = detail.season;
    if (season == null) return;
    final on = !(_seasonFav ?? false);
    await _perform(
      'season',
      () => _seasonFav = on,
      () => _api.favSeason(seasonId: season.id, on: on),
      done: () => _say(on ? '已收藏合集' : '已取消收藏'),
    );
  }

  /// Sharing needs no account, so logged out it is simply not counted.
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

  /// Bilibili words its refusals for the user (硬币不足, 已经点赞过了), so those show as sent; codes the app knows
  /// better keep [BiliError.userMessage].
  static String failureMessage(Object error) => switch (error) {
        BiliAPIError(:final code, :final message) when message.isNotEmpty && !_ownWords.contains(code) => message,
        final BiliError failure => failure.userMessage,
        _ => '网络连接失败，请检查网络后重试',
      };

  static const _ownWords = {-101, -352, -412, -404};

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

  /// Takes back one action: only the fields it changed, and only those still showing its change. Actions run side
  /// by side (点赞 and 关注 sit next to each other), and one failing must not undo another.
  void _undo(_Snapshot before, _Snapshot after) {
    T back<T>(T now, T was, T changed) => was != changed && now == changed ? was : now;
    _liked = back(_liked, before.liked, after.liked);
    _disliked = back(_disliked, before.disliked, after.disliked);
    _favorited = back(_favorited, before.favorited, after.favorited);
    _following = back(_following, before.following, after.following);
    _coins = back(_coins, before.coins, after.coins);
    _seasonFav = back(_seasonFav, before.seasonFav, after.seasonFav);
    _likeCount = back(_likeCount, before.likeCount, after.likeCount);
    _coinCount = back(_coinCount, before.coinCount, after.coinCount);
    _favCount = back(_favCount, before.favCount, after.favCount);
  }

  /// Like clears dislike, as on the server.
  void _setLiked(bool on) {
    if (on == _liked) return;
    _liked = on;
    _likeCount = max(0, _likeCount + (on ? 1 : -1));
    if (on) _disliked = false;
  }

  void _setFavorited(bool on) {
    if (on == _favorited) return;
    _favorited = on;
    _favCount = max(0, _favCount + (on ? 1 : -1));
  }

  /// The server says what 三连 actually did: the optimistic like and favourite are corrected to it and the coins it
  /// spent are added.
  void _settleTriple(TripleResult result, _Snapshot before, int expected) {
    _liked = before.liked || result.like;
    _likeCount = before.likeCount + (_liked && !before.liked ? 1 : 0);
    _disliked = _liked ? false : before.disliked;
    _favorited = before.favorited || result.favorite;
    _favCount = before.favCount + (_favorited && !before.favorited ? 1 : 0);
    final spent = result.coin ? min(result.multiply, expected) : 0;
    _coins = before.coins + spent;
    _coinCount = before.coinCount + spent;
  }

  /// One action: shown at once, sent, and taken back with the server's words if it fails. A second tap while it is
  /// out does nothing.
  Future<void> _perform(String name, void Function() change, Future<void> Function() call, {VoidCallback? done}) async {
    if (!_isLoggedIn()) {
      _login();
      return;
    }
    if (!_busy.add(name)) return;
    final before = _snapshot;
    change();
    final after = _snapshot;
    _touched.addAll(after.changedFrom(before));
    _notify();
    try {
      await call();
      done?.call();
    } catch (error) {
      _undo(before, after);
      _logger.warn(LogCategory.api, '$name failed', {'error': '$error'});
      _say(failureMessage(error));
      if (error is BiliError && error.needsLogin) _login();
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

  Set<_Field> changedFrom(_Snapshot other) => {
        if (liked != other.liked) _Field.liked,
        if (disliked != other.disliked) _Field.disliked,
        if (favorited != other.favorited) _Field.favorited,
        if (following != other.following) _Field.following,
        if (coins != other.coins) _Field.coins,
        if (seasonFav != other.seasonFav) _Field.seasonFav,
      };
}
