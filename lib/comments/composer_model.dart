import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';

import 'comments_model.dart';
import 'emote_store.dart';

/// A picture picked for a comment, uploaded only when the comment is posted.
@immutable
class PickedPicture {
  const PickedPicture({required this.bytes, required this.name});

  final Uint8List bytes;

  /// The file name with its extension, which the upload needs.
  final String name;
}

/// One opening of the composer (14, BiliNative `ComposerModel`): the text for one reply target, kept as a draft
/// while it is unsent, the emote panel switch, @ mentions, pictures and 转到动态, and posting.
class ComposerModel extends ChangeNotifier {
  ComposerModel({required this.comments, required this.target, RecentEmotes? recent, EmoteCatalog? catalog})
    : _recentEmotes = recent ?? RecentEmotes.shared,
      _catalog = catalog ?? EmoteCatalog.shared;

  static const maxPictures = 9;

  final CommentsModel comments;
  final ReplyTarget target;
  // ignore: unused_field
  final RecentEmotes _recentEmotes;
  // ignore: unused_field
  final EmoteCatalog _catalog;

  String _text = '';
  bool _syncToDynamic = false;
  bool _showingEmotes = false;

  String get text => _text;

  /// Saves the draft as it goes.
  set text(String value) {
    _text = value;
    notifyListeners();
  }

  bool get syncToDynamic => _syncToDynamic;
  set syncToDynamic(bool value) {
    _syncToDynamic = value;
    notifyListeners();
  }

  bool get showingEmotes => _showingEmotes;
  set showingEmotes(bool value) {
    _showingEmotes = value;
    notifyListeners();
  }

  bool get posting => false;

  bool get canPost => false;

  /// 发条评论's prompt, or "回复 name :" for a reply.
  String get placeholder => '';

  /// 最近使用, read once when the composer opens so the row stays put while emotes are tapped.
  List<Emote> get recent => const [];

  /// Records [emote] in 最近使用; the composer puts its token into the text at the cursor.
  void usedEmote(Emote emote) {}

  Future<List<EmotePackage>> emotePackages() async => const [];

  /// The @names in the text so far, with their mids; only names still in the text are sent.
  Map<String, int> get mentions => const {};

  /// Records [who]; the composer puts "@name " into the text at the cursor.
  void mentioned(MentionCandidate who) {}

  Future<List<MentionCandidate>> searchMentions(String query) async => const [];

  List<PickedPicture> get pictures => const [];

  void addPictures(List<PickedPicture> picked) {}

  void removePicture(int index) {}

  /// True once the comment is posted and shown; on failure the text stays and the reason is toasted.
  Future<bool> post() async => false;
}
