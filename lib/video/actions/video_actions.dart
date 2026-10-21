import 'package:bili_core/api.dart' show FavFolder;
import 'package:flutter/foundation.dart';

/// What a tap asks the page to put up; [ActionOverlays] takes it and clears it at once.
enum ActionPrompt { coin, favourites, unfollow, share }

/// 点赞, 不喜欢, 三连, 投币, 收藏, 分享 and 关注 for the video on the page (BiliNative `ActionsModel.swift`), shared by
/// the action row, the full-screen chrome and the end screens. Every change shows at once and is taken back, field by
/// field, if the server refuses it. Logged out, every action but 分享 asks for a login and sends nothing; 不喜欢 says
/// it isn't supported first (see [dislikeAvailable]).
abstract interface class VideoActions implements Listenable {
  bool get liked;

  bool get disliked;

  bool get favorited;

  bool get following;

  /// False while [following] is only the default: the relation and the uploader's card haven't said, and 关注 hasn't
  /// been changed here or elsewhere.
  bool get followingKnown;

  /// Coins this account has given the video.
  int get coins;

  int get likeCount;

  int get coinCount;

  int get favCount;

  int get shareCount;

  /// Coins still allowed: a repost takes one, an original two, less what was given.
  int get maxCoins;

  bool get tripleDone;

  /// Whether a 三连 now goes to the server, so the row bursts only for one that does.
  bool get tripleSends;

  /// Always false until the TV login is ported: 不喜欢 is grey and a tap says 此版本不支持不喜欢.
  bool get dislikeAvailable;

  /// The 合集 holding the video is in this account's 订阅; null without a 合集, before the relation answers, or when
  /// it couldn't be asked.
  bool? get seasonFavourited;

  ActionPrompt? get prompt;

  void clearPrompt();

  bool canGive(int multiply, double balance);

  Future<void> toggleLike();

  Future<void> toggleDislike();

  Future<void> triple();

  Future<void> coin(int multiply, {required bool alsoLike});

  /// The account's coins for the coin dialog; throws when Bilibili couldn't be asked.
  Future<double> coinBalance();

  /// [inAnyFolder]: whether the video stays in some folder afterwards, which only the favourites sheet knows.
  Future<void> applyFavourites({required List<int> add, required List<int> remove, bool? inAnyFolder});

  /// The account's folders for the favourites sheet, starting to load. The caller disposes it ([ActionOverlays], once
  /// the sheet has gone).
  FavouriteFolders openFolders();

  /// 关注 follows at once; 已关注 puts up [ActionPrompt.unfollow] first.
  void tapFollow();

  Future<void> toggleFollow();

  Future<void> toggleSeasonFavourite();

  /// Counts a share the share sheet completed.
  Future<void> shared();

  /// 投币, 收藏 and 分享: puts the prompt up, or asks for a login (分享 needs none).
  void ask(ActionPrompt prompt);
}

/// The favourites sheet's folders and ticks (BiliNative `FavouriteSheet.swift`'s model). [commit] sends only the
/// difference from what the folders held when they loaded.
abstract interface class FavouriteFolders implements Listenable {
  bool get loading;

  /// Why the folders couldn't load; null otherwise.
  String? get error;

  List<FavFolder> get folders;

  bool isTicked(int folderId);

  void toggle(int folderId);

  /// 新建收藏夹: the new folder joins the list ticked. Completes with the failure's toast text, empty when it asked
  /// for the login instead, or null.
  Future<String?> create(String title, {required bool isPrivate});

  /// 完成: sends the difference through the actions, which roll back by themselves if it fails.
  Future<void> commit();

  Future<void> reload();

  void dispose();
}
