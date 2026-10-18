import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../page_api.dart';
import 'video_actions.dart';

/// Contracts stub: counts from the detail and nothing else until the models agent fills it in.
class ActionsModel extends ChangeNotifier implements VideoActions {
  ActionsModel({
    required PageApi api,
    required this.detail,
    VideoRelation? relation,
    UploaderCard? uploader,
    required bool Function() isLoggedIn,
    required int? Function() accountMid,
    required VoidCallback requestLogin,
    required void Function(String message) toast,
    this.dislikeAvailable = false,
    Logger? logger,
  })  : likeCount = detail.stat.like,
        coinCount = detail.stat.coin,
        favCount = detail.stat.favorite,
        shareCount = detail.stat.share;

  final VideoDetail detail;

  @override
  final bool dislikeAvailable;

  @override
  bool liked = false;

  @override
  bool disliked = false;

  @override
  bool favorited = false;

  @override
  bool following = false;

  @override
  int coins = 0;

  @override
  int likeCount;

  @override
  int coinCount;

  @override
  int favCount;

  @override
  int shareCount;

  @override
  bool? seasonFavourited;

  @override
  ActionPrompt? prompt;

  /// A relation answer fills in what the user hasn't changed yet.
  void apply(VideoRelation relation) {}

  void applyUploader(UploaderCard card) {}

  /// After a login: this account's state, whatever was tapped before.
  Future<void> refreshRelation() async {}

  @override
  int get maxCoins => 0;

  @override
  bool get tripleDone => false;

  @override
  bool get tripleSends => false;

  @override
  void clearPrompt() {}

  @override
  bool canGive(int multiply, double balance) => false;

  @override
  Future<void> toggleLike() async {}

  @override
  Future<void> toggleDislike() async {}

  @override
  Future<void> triple() async {}

  @override
  Future<void> coin(int multiply, {required bool alsoLike}) async {}

  @override
  Future<double> coinBalance() async => 0;

  @override
  Future<void> applyFavourites({required List<int> add, required List<int> remove, bool? inAnyFolder}) async {}

  @override
  FavouriteFolders openFolders() => throw UnimplementedError();

  @override
  void tapFollow() {}

  @override
  Future<void> toggleFollow() async {}

  @override
  Future<void> toggleSeasonFavourite() async {}

  @override
  Future<void> shared() async {}

  @override
  void ask(ActionPrompt prompt) {}
}
