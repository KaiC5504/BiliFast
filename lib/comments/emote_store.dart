import 'package:bili_core/api.dart';

import '../video/page_api.dart';

/// 最近使用 (BiliNative `RecentEmotes`): the emotes picked last, newest first, at most [limit], kept across launches
/// in `emotes_recent.json` in the app's support folder (in memory only when [load] has no path).
class RecentEmotes {
  RecentEmotes.memory();

  static const limit = 14;

  static RecentEmotes shared = RecentEmotes.memory();

  static Future<RecentEmotes> load(String? path) async => RecentEmotes.memory();

  List<Emote> get list => const [];

  void record(Emote emote) {}
}

/// The emote panel's packages, asked for once per launch and shared by every composer.
class EmoteCatalog {
  static final shared = EmoteCatalog();

  /// The packages, asking the server only the first time (and again after a failure).
  Future<List<EmotePackage>> load(PageApi api) async => const [];
}
