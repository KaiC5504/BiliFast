import 'package:bili_core/api.dart' show FavFolder, UploaderCard, VideoCard, VideoTag;
import 'package:bilifast/video/actions/video_actions.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/player_session.dart' show ActionResult;
import 'package:flutter/foundation.dart';

/// [VideoActions] with settable state that records every call, for widget tests of whatever shows or taps actions.
class FakeVideoActions extends ChangeNotifier implements VideoActions {
  FakeVideoActions({
    this.liked = false,
    this.disliked = false,
    this.favorited = false,
    this.following = false,
    this.followingKnown = true,
    this.coins = 0,
    this.likeCount = 9131,
    this.coinCount = 1210,
    this.favCount = 3907,
    this.shareCount = 148,
    this.maxCoins = 2,
    this.dislikeAvailable = false,
    this.seasonFavourited,
    this.balance = 873,
  });

  final calls = <String>[];

  @override
  bool liked;

  @override
  bool disliked;

  @override
  bool favorited;

  @override
  bool following;

  @override
  bool followingKnown;

  @override
  int coins;

  @override
  int likeCount;

  @override
  int coinCount;

  @override
  int favCount;

  @override
  int shareCount;

  @override
  int maxCoins;

  @override
  bool dislikeAvailable;

  @override
  bool? seasonFavourited;

  @override
  ActionPrompt? prompt;

  double balance;

  /// Set to make [coinBalance] throw.
  Object? balanceFailure;

  FakeFavouriteFolders folders = FakeFavouriteFolders();

  void changed() => notifyListeners();

  @override
  bool get tripleDone => liked && coins > 0 && favorited;

  @override
  bool get tripleSends => !tripleDone;

  @override
  void clearPrompt() {
    calls.add('clearPrompt');
    prompt = null;
    notifyListeners();
  }

  @override
  bool canGive(int multiply, double balance) => multiply >= 1 && multiply <= maxCoins && balance >= multiply;

  @override
  Future<void> toggleLike() async => calls.add('toggleLike');

  @override
  Future<void> toggleDislike() async => calls.add('toggleDislike');

  @override
  Future<void> triple() async => calls.add('triple');

  @override
  Future<void> coin(int multiply, {required bool alsoLike}) async => calls.add('coin $multiply alsoLike=$alsoLike');

  @override
  Future<double> coinBalance() async {
    calls.add('coinBalance');
    if (balanceFailure case final failure?) throw failure;
    return balance;
  }

  @override
  Future<void> applyFavourites({required List<int> add, required List<int> remove, bool? inAnyFolder}) async =>
      calls.add('applyFavourites add=${add.join(',')} remove=${remove.join(',')} inAny=$inAnyFolder');

  @override
  FavouriteFolders openFolders() {
    calls.add('openFolders');
    return folders;
  }

  @override
  void tapFollow() => calls.add('tapFollow');

  @override
  Future<void> toggleFollow() async => calls.add('toggleFollow');

  @override
  Future<void> toggleSeasonFavourite() async => calls.add('toggleSeasonFavourite');

  @override
  Future<void> shared() async => calls.add('shared');

  @override
  void ask(ActionPrompt prompt) {
    calls.add('ask ${prompt.name}');
    this.prompt = prompt;
    notifyListeners();
  }
}

/// [FavouriteFolders] over a settable list, recording calls.
class FakeFavouriteFolders extends ChangeNotifier implements FavouriteFolders {
  FakeFavouriteFolders({
    List<FavFolder>? folders,
    Set<int>? ticked,
    this.loading = false,
    this.error,
  })  : folders = folders ??
            const [
              FavFolder(id: 11, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
              FavFolder(id: 12, title: '二乃', count: 8, isPrivate: true, contains: false, isDefault: false),
            ],
        ticked = ticked ?? {};

  final calls = <String>[];

  @override
  List<FavFolder> folders;

  final Set<int> ticked;

  @override
  bool loading;

  @override
  String? error;

  String? createFailure;
  bool disposed = false;

  @override
  bool isTicked(int folderId) => ticked.contains(folderId);

  @override
  void toggle(int folderId) {
    calls.add('toggle $folderId');
    if (!ticked.remove(folderId)) ticked.add(folderId);
    notifyListeners();
  }

  @override
  Future<String?> create(String title, {required bool isPrivate}) async {
    calls.add('create $title private=$isPrivate');
    if (createFailure case final failure?) return failure;
    final id = 100 + folders.length;
    folders = [
      ...folders,
      FavFolder(id: id, title: title, count: 0, isPrivate: isPrivate, contains: false, isDefault: false),
    ];
    ticked.add(id);
    notifyListeners();
    return null;
  }

  @override
  Future<void> commit() async => calls.add('commit');

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// [PageDetails] with settable parts.
class FakePageDetails extends ChangeNotifier implements PageDetails {
  FakePageDetails({this.actions, this.uploader, this.tags = const [], String? online}) : online = ValueNotifier(online);

  @override
  VideoActions? actions;

  @override
  UploaderCard? uploader;

  @override
  List<VideoTag> tags;

  @override
  final ValueNotifier<String?> online;

  bool? activeSet;
  final watchLaterCalls = <String>[];

  void changed() => notifyListeners();

  @override
  Future<ActionResult> watchLater(VideoCard card) async {
    watchLaterCalls.add(card.bvid);
    return const ActionResult('已添加至稍后再看', ok: true);
  }

  @override
  set active(bool value) => activeSet = value;

  @override
  void dispose() {
    online.dispose();
    super.dispose();
  }
}
