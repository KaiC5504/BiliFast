import 'dart:async';

import 'package:bili_core/api.dart';

import 'page_api.dart';

/// A [PageApi] that answers from memory: the tests' fake, and the actions' backend in `--fake-account` runs on the
/// PC, so every button can be pressed there without a call reaching Bilibili or KaiC's account.
class FakePageApi implements PageApi {
  FakePageApi({
    this.relationValue = const VideoRelation(like: false, dislike: false, favorite: false, attention: false, coins: 0),
    this.uploader,
    this.tagsValue = const [],
    this.online = '1',
    this.balance = 10,
    List<FavFolder>? folders,
    this.delay = Duration.zero,
  }) : _folders = [...?folders];

  /// What the PC run shows: an uploader with fans, two folders (one private), coins to give, topic and BGM chips.
  factory FakePageApi.demo() => FakePageApi(
        uploader: const UploaderCard(
          mid: 1,
          name: '测试UP主',
          face: '',
          fans: 475000,
          videos: 410,
          isVip: true,
          following: false,
          official: OfficialKind.person,
        ),
        tagsValue: const [
          VideoTag(id: 1, name: '《グランドエスケープ》', kind: VideoTagKind.bgm),
          VideoTag(id: 2, name: '动漫二创激励计划', kind: VideoTagKind.topic),
          VideoTag(id: 3, name: '必剪创作', kind: VideoTagKind.normal),
        ],
        online: '53',
        balance: 873,
        folders: const [
          FavFolder(id: 11, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
          FavFolder(id: 12, title: '二乃', count: 8, isPrivate: true, contains: false, isDefault: false),
        ],
        delay: const Duration(milliseconds: 300),
      );

  VideoRelation relationValue;
  UploaderCard? uploader;
  List<VideoTag> tagsValue;
  String online;
  double balance;
  final List<FavFolder> _folders;

  /// How long each answer takes, so optimistic changes and spinners show.
  Duration delay;

  /// Every call, as its method name with the arguments that matter (`like on=true`, `coin multiply=2 like=true`).
  final List<String> calls = [];

  /// A method named here (`like`, `coinBalance`, ...) throws this instead of answering.
  final Map<String, Object> failures = {};

  /// A method named here waits for its completer before it answers (or throws), so a test can look at what shows
  /// while the server hasn't answered. The call is in [calls] already.
  final Map<String, Completer<void>> holds = {};

  /// False: folder lists leave out the folders [createFolder] made, as a list fetched before them would.
  bool listsNewFolders = true;

  var _nextFolderId = 100;

  List<FavFolder> get folders => List.unmodifiable(_folders);

  Future<T> _answer<T>(String name, String call, T Function() value) async {
    calls.add(call);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  @override
  Future<VideoRelation> relation({required int aid, required String bvid}) =>
      _answer('relation', 'relation', () => relationValue);

  @override
  Future<UploaderCard> uploaderCard({required int mid}) => _answer('uploaderCard', 'uploaderCard mid=$mid', () {
        final card = uploader;
        if (card == null) throw const BiliError.api(code: -404, message: '啥都木有');
        return card;
      });

  @override
  Future<List<VideoTag>> tags({required String bvid, required int cid}) =>
      _answer('tags', 'tags cid=$cid', () => tagsValue);

  @override
  Future<String> onlineCount({required int aid, required String bvid, required int cid}) =>
      _answer('onlineCount', 'onlineCount cid=$cid', () => online);

  @override
  Future<void> like({required int aid, required String bvid, required bool on}) => _answer('like', 'like on=$on', () {
        relationValue = _relation(like: on, dislike: on ? false : relationValue.dislike);
      });

  @override
  Future<TripleResult> triple({required int aid, required String bvid}) => _answer('triple', 'triple', () {
        final multiply = 2 - relationValue.coins;
        relationValue = _relation(like: true, favorite: true, coins: relationValue.coins + multiply);
        return TripleResult(like: true, coin: multiply > 0, favorite: true, multiply: multiply);
      });

  @override
  Future<void> coin({required int aid, required String bvid, required int multiply, required bool alsoLike}) =>
      _answer('coin', 'coin multiply=$multiply like=$alsoLike', () {
        if (balance < multiply) throw const BiliError.api(code: -104, message: '硬币不足');
        balance -= multiply;
        relationValue = _relation(coins: relationValue.coins + multiply, like: alsoLike || relationValue.like);
      });

  @override
  Future<double> coinBalance() => _answer('coinBalance', 'coinBalance', () => balance);

  @override
  Future<List<FavFolder>> favouriteFolders({required int mid, required int aid}) =>
      _answer('favouriteFolders', 'favouriteFolders', () => folders);

  @override
  Future<void> updateFavourites({required int aid, required List<int> add, required List<int> remove}) =>
      _answer('updateFavourites', 'updateFavourites add=${add.join(',')} remove=${remove.join(',')}', () {
        for (var i = 0; i < _folders.length; i++) {
          final folder = _folders[i];
          final added = add.contains(folder.id) && !folder.contains;
          final removed = remove.contains(folder.id) && folder.contains;
          if (!added && !removed) continue;
          _folders[i] = FavFolder(
            id: folder.id,
            title: folder.title,
            count: folder.count + (added ? 1 : -1),
            isPrivate: folder.isPrivate,
            contains: added,
            isDefault: folder.isDefault,
          );
        }
        relationValue = _relation(favorite: _folders.any((folder) => folder.contains));
      });

  @override
  Future<FavFolder> createFolder({required String title, required bool isPrivate}) =>
      _answer('createFolder', 'createFolder title=$title private=$isPrivate', () {
        final folder = FavFolder(
          id: _nextFolderId++,
          title: title,
          count: 0,
          isPrivate: isPrivate,
          contains: false,
          isDefault: false,
        );
        if (listsNewFolders) _folders.add(folder);
        return folder;
      });

  @override
  Future<void> countShare({required int aid}) => _answer('countShare', 'countShare', () {});

  @override
  Future<void> follow({required int mid, required bool on}) => _answer('follow', 'follow on=$on', () {
        relationValue = _relation(attention: on);
      });

  @override
  Future<void> favSeason({required int seasonId, required bool on}) =>
      _answer('favSeason', 'favSeason season=$seasonId on=$on', () {
        relationValue = _relation(seasonFav: on);
      });

  @override
  Future<void> addToWatchLater({required int aid}) => _answer('addToWatchLater', 'addToWatchLater aid=$aid', () {});

  VideoRelation _relation({bool? like, bool? dislike, bool? favorite, bool? attention, int? coins, bool? seasonFav}) =>
      VideoRelation(
        like: like ?? relationValue.like,
        dislike: dislike ?? relationValue.dislike,
        favorite: favorite ?? relationValue.favorite,
        attention: attention ?? relationValue.attention,
        coins: coins ?? relationValue.coins,
        seasonFav: seasonFav ?? relationValue.seasonFav,
      );
}
