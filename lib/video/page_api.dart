import 'package:bili_core/api.dart';

/// The calls the page body makes besides playback: its side loads and the actions. The app asks Bilibili
/// ([ClientPageApi]); tests and `--fake-account` runs on the PC answer from memory (`FakePageApi`).
abstract interface class PageApi {
  Future<VideoRelation> relation({required int aid, required String bvid});

  Future<UploaderCard> uploaderCard({required int mid});

  Future<List<VideoTag>> tags({required String bvid, required int cid});

  /// N人正在看's N as the server words it ("53", "1000+").
  Future<String> onlineCount({required int aid, required String bvid, required int cid});

  Future<void> like({required int aid, required String bvid, required bool on});

  Future<TripleResult> triple({required int aid, required String bvid});

  Future<void> coin({required int aid, required String bvid, required int multiply, required bool alsoLike});

  Future<double> coinBalance();

  Future<List<FavFolder>> favouriteFolders({required int mid, required int aid});

  Future<void> updateFavourites({required int aid, required List<int> add, required List<int> remove});

  Future<FavFolder> createFolder({required String title, required bool isPrivate});

  Future<void> countShare({required int aid});

  Future<void> follow({required int mid, required bool on});

  Future<void> favSeason({required int seasonId, required bool on});

  Future<void> addToWatchLater({required int aid});
}

class ClientPageApi implements PageApi {
  ClientPageApi(this._client);

  final BiliClient _client;

  @override
  Future<VideoRelation> relation({required int aid, required String bvid}) => _client.relation(aid: aid, bvid: bvid);

  @override
  Future<UploaderCard> uploaderCard({required int mid}) => _client.uploaderCard(mid: mid);

  @override
  Future<List<VideoTag>> tags({required String bvid, required int cid}) => _client.tags(bvid: bvid, cid: cid);

  @override
  Future<String> onlineCount({required int aid, required String bvid, required int cid}) =>
      _client.onlineCount(aid: aid, bvid: bvid, cid: cid);

  @override
  Future<void> like({required int aid, required String bvid, required bool on}) =>
      _client.like(aid: aid, bvid: bvid, on: on);

  @override
  Future<TripleResult> triple({required int aid, required String bvid}) => _client.triple(aid: aid, bvid: bvid);

  @override
  Future<void> coin({required int aid, required String bvid, required int multiply, required bool alsoLike}) =>
      _client.coin(aid: aid, bvid: bvid, multiply: multiply, alsoLike: alsoLike);

  @override
  Future<double> coinBalance() => _client.coinBalance();

  @override
  Future<List<FavFolder>> favouriteFolders({required int mid, required int aid}) =>
      _client.favouriteFolders(mid: mid, aid: aid);

  @override
  Future<void> updateFavourites({required int aid, required List<int> add, required List<int> remove}) =>
      _client.updateFavourites(aid: aid, add: add, remove: remove);

  @override
  Future<FavFolder> createFolder({required String title, required bool isPrivate}) =>
      _client.createFolder(title: title, isPrivate: isPrivate);

  @override
  Future<void> countShare({required int aid}) => _client.countShare(aid: aid);

  @override
  Future<void> follow({required int mid, required bool on}) => _client.follow(mid: mid, on: on);

  @override
  Future<void> favSeason({required int seasonId, required bool on}) => _client.favSeason(seasonId: seasonId, on: on);

  @override
  Future<void> addToWatchLater({required int aid}) => _client.addToWatchLater(aid: aid);
}
