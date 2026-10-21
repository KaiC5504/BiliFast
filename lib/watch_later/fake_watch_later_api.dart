import 'watch_later_api.dart';

/// Answers from memory, for tests and `--fake-account`.
class FakeWatchLaterApi implements WatchLaterApi {
  FakeWatchLaterApi();

  factory FakeWatchLaterApi.demo() => FakeWatchLaterApi();
}
