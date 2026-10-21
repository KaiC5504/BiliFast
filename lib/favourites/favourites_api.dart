import 'package:bili_core/api.dart';

/// 我的收藏's calls, the website's.
abstract interface class FavouritesApi {}

class ClientFavouritesApi implements FavouritesApi {
  ClientFavouritesApi(this._client);

  // ignore: unused_field
  final BiliClient _client;
}
