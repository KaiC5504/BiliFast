import 'package:bili_core/api.dart';

/// 稍后再看's calls, the website's.
abstract interface class WatchLaterApi {}

class ClientWatchLaterApi implements WatchLaterApi {
  ClientWatchLaterApi(this._client);

  // ignore: unused_field
  final BiliClient _client;
}
