import 'favourites_api.dart';

/// Answers from memory, for tests and `--fake-account`.
class FakeFavouritesApi implements FavouritesApi {
  FakeFavouritesApi();

  factory FakeFavouritesApi.demo() => FakeFavouritesApi();
}
