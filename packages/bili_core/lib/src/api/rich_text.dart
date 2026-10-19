import 'package:characters/characters.dart';

sealed class RichRun {
  const RichRun();

  const factory RichRun.text(String text) = TextRun;
  const factory RichRun.emote({required String token, required String url, required int size}) = EmoteRun;
  const factory RichRun.mention({required String name, required int mid}) = MentionRun;
  const factory RichRun.link({required String title, required String url, bool note}) = LinkRun;
  const factory RichRun.video({required String id}) = VideoRun;
  const factory RichRun.timestamp({required String label, required int seconds}) = TimestampRun;
}

final class TextRun extends RichRun {
  const TextRun(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TextRun && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'text($text)';
}

final class EmoteRun extends RichRun {
  const EmoteRun({required this.token, required this.url, required this.size});

  final String token;
  final String url;
  final int size;

  @override
  bool operator ==(Object other) => other is EmoteRun && other.token == token && other.url == url && other.size == size;

  @override
  int get hashCode => Object.hash(token, url, size);

  @override
  String toString() => 'emote($token, $url, $size)';
}

final class MentionRun extends RichRun {
  const MentionRun({required this.name, required this.mid});

  final String name;
  final int mid;

  @override
  bool operator ==(Object other) => other is MentionRun && other.name == name && other.mid == mid;

  @override
  int get hashCode => Object.hash(name, mid);

  @override
  String toString() => 'mention($name, $mid)';
}

final class LinkRun extends RichRun {
  const LinkRun({required this.title, required this.url, this.note = false});

  final String title;
  final String url;

  /// A 笔记 (a note on the video) the comment links to, shown as a "[笔记]" lead.
  final bool note;

  @override
  bool operator ==(Object other) => other is LinkRun && other.title == title && other.url == url && other.note == note;

  @override
  int get hashCode => Object.hash(title, url, note);

  @override
  String toString() => note ? 'note($title, $url)' : 'link($title, $url)';
}

final class VideoRun extends RichRun {
  const VideoRun({required this.id});

  final String id;

  @override
  bool operator ==(Object other) => other is VideoRun && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'video($id)';
}

final class TimestampRun extends RichRun {
  const TimestampRun({required this.label, required this.seconds});

  final String label;
  final int seconds;

  @override
  bool operator ==(Object other) => other is TimestampRun && other.label == label && other.seconds == seconds;

  @override
  int get hashCode => Object.hash(label, seconds);

  @override
  String toString() => 'timestamp($label, $seconds)';
}

final class EmoteRef {
  const EmoteRef({required this.url, required this.size});

  final String url;
  final int size;

  @override
  bool operator ==(Object other) => other is EmoteRef && other.url == url && other.size == size;

  @override
  int get hashCode => Object.hash(url, size);
}

final class LinkRef {
  const LinkRef({required this.title, required this.url, this.note = false});

  final String title;
  final String url;
  final bool note;

  @override
  bool operator ==(Object other) => other is LinkRef && other.title == title && other.url == url && other.note == note;

  @override
  int get hashCode => Object.hash(title, url, note);
}

typedef _Match = ({int length, RichRun run});
typedef _Matcher = _Match? Function(List<String> characters, int index);

/// A piece of the message: still plain characters, or an already recognised run.
typedef _Piece = ({List<String>? pending, RichRun? done});

/// Turns a comment's plain text plus the lookup tables the server sends with it into styled runs.
/// Everything works on grapheme clusters, so an emoji or a combining mark is never cut in half.
abstract final class RichText {
  /// Each kind is searched in the text the earlier kinds left over, so an emote key wins over a mention,
  /// a mention over a link, and a link key over a bare BV number inside it. A 笔记 link moves to the front, where the
  /// official app puts its "[笔记]" lead.
  static List<RichRun> runs(
    String message, {
    required Map<String, EmoteRef> emotes,
    required Map<String, int> mentions,
    required Map<String, LinkRef> links,
  }) {
    var pieces = <_Piece>[(pending: graphemes(message), done: null)];
    pieces = _split(
      pieces,
      _literals([
        for (final MapEntry(:key, :value) in emotes.entries)
          (token: key, run: RichRun.emote(token: key, url: value.url, size: value.size)),
      ], once: false),
    );
    pieces = _split(
      pieces,
      _literals([
        for (final MapEntry(:key, :value) in mentions.entries)
          (token: '@$key', run: RichRun.mention(name: key, mid: value)),
      ], once: false),
    );
    // The server marks these `match_once`: only the first occurrence of a link word is a link.
    pieces = _split(
      pieces,
      _literals([
        for (final MapEntry(:key, :value) in links.entries)
          (token: key, run: RichRun.link(title: value.title, url: value.url, note: value.note)),
      ], once: true),
    );
    pieces = _split(pieces, _videoID);
    pieces = _split(pieces, _timestamp);
    final merged = _merged(pieces);
    bool isNote(RichRun run) => run is LinkRun && run.note;
    if (!merged.any(isNote)) return merged;
    return [...merged.where(isNote), ..._merged([for (final run in merged.where((run) => !isNote(run))) _piece(run)])];
  }

  static _Piece _piece(RichRun run) =>
      run is TextRun ? (pending: graphemes(run.text), done: null) : (pending: null, done: run);

  /// Extended grapheme clusters (UAX #29), as Swift splits a String into Characters.
  static List<String> graphemes(String text) => text.characters.toList();

  static List<_Piece> _split(List<_Piece> pieces, _Matcher match) {
    final output = <_Piece>[];
    for (final piece in pieces) {
      final characters = piece.pending;
      if (characters == null) {
        output.add(piece);
        continue;
      }
      var start = 0;
      var index = 0;
      while (index < characters.length) {
        final found = match(characters, index);
        if (found != null) {
          if (start < index) output.add((pending: characters.sublist(start, index), done: null));
          output.add((pending: null, done: found.run));
          index += found.length;
          start = index;
        } else {
          index += 1;
        }
      }
      if (start < characters.length) output.add((pending: characters.sublist(start), done: null));
    }
    return output;
  }

  static List<RichRun> _merged(List<_Piece> pieces) {
    final runs = <RichRun>[];
    final buffer = StringBuffer();
    for (final piece in pieces) {
      final done = piece.done;
      if (done == null) {
        buffer.writeAll(piece.pending!);
      } else {
        if (buffer.isNotEmpty) runs.add(RichRun.text(buffer.toString()));
        buffer.clear();
        runs.add(done);
      }
    }
    if (buffer.isNotEmpty) runs.add(RichRun.text(buffer.toString()));
    return runs;
  }

  /// Longest token first, so "@小明明" is not read as "@小明" followed by "明".
  static _Matcher _literals(List<({String token, RichRun run})> entries, {required bool once}) {
    final tokens =
        [
          for (final entry in entries)
            if (entry.token.isNotEmpty) (text: entry.token, characters: graphemes(entry.token), run: entry.run),
        ]..sort((lhs, rhs) {
          if (lhs.characters.length != rhs.characters.length) {
            return rhs.characters.length.compareTo(lhs.characters.length);
          }
          return lhs.text.compareTo(rhs.text);
        });
    final used = <int>{};
    return (characters, index) {
      for (var position = 0; position < tokens.length; position++) {
        if (once && used.contains(position)) continue;
        final token = tokens[position];
        if (_matches(characters, index, token.characters)) {
          used.add(position);
          return (length: token.characters.length, run: token.run);
        }
      }
      return null;
    };
  }

  static bool _matches(List<String> characters, int index, List<String> token) {
    if (index + token.length > characters.length) return false;
    for (var offset = 0; offset < token.length; offset++) {
      if (characters[index + offset] != token[offset]) return false;
    }
    return true;
  }

  /// `BV` plus ten letters or digits, or `av` plus digits.
  static _Match? _videoID(List<String> characters, int index) {
    if (_matches(characters, index, const ['B', 'V'])) {
      final end = index + 12;
      if (end > characters.length || !characters.sublist(index + 2, end).every(_isASCIIAlphanumeric)) return null;
      return (length: 12, run: RichRun.video(id: characters.sublist(index, end).join()));
    }
    // "lav12" is a word, not a video.
    if (_matches(characters, index, const ['a', 'v']) && (index == 0 || !_isASCIIAlphanumeric(characters[index - 1]))) {
      final end = _endOfDigits(characters, index + 2);
      if (end <= index + 2) return null;
      return (length: end - index, run: RichRun.video(id: characters.sublist(index, end).join()));
    }
    return null;
  }

  /// `m:ss` or `h:mm:ss` with either colon. A digit on either side means the number is something else,
  /// such as the "1920:1080" in a resolution, so it is left as text.
  static _Match? _timestamp(List<String> characters, int index) {
    if (index > 0 && _isASCIIDigit(characters[index - 1])) return null;
    final leadEnd = _endOfDigits(characters, index);
    final leadLength = leadEnd - index;
    if (leadLength < 1 || leadLength > 2 || !_isColon(characters, leadEnd) || !_twoDigits(characters, leadEnd + 1)) {
      return null;
    }
    var end = leadEnd + 3;
    final fields = [_number(characters, index, leadEnd), _number(characters, leadEnd + 1, end)];
    if (_isColon(characters, end) && _twoDigits(characters, end + 1) && !_isDigit(characters, end + 3)) {
      fields.add(_number(characters, end + 1, end + 3));
      end += 3;
    }
    if (_isDigit(characters, end) || !fields.skip(1).every((field) => field < 60)) return null;
    final seconds = fields.fold(0, (total, field) => total * 60 + field);
    return (
      length: end - index,
      run: RichRun.timestamp(label: characters.sublist(index, end).join(), seconds: seconds),
    );
  }

  static int _number(List<String> characters, int from, int to) =>
      int.tryParse(characters.sublist(from, to).join()) ?? 0;

  static int _endOfDigits(List<String> characters, int index) {
    var end = index;
    while (_isDigit(characters, end)) {
      end += 1;
    }
    return end;
  }

  static bool _twoDigits(List<String> characters, int index) =>
      _isDigit(characters, index) && _isDigit(characters, index + 1);

  static bool _isDigit(List<String> characters, int index) =>
      index < characters.length && _isASCIIDigit(characters[index]);

  static bool _isColon(List<String> characters, int index) =>
      index < characters.length && (characters[index] == ':' || characters[index] == '：');

  static bool _isASCIIDigit(String character) {
    if (character.length != 1) return false;
    final unit = character.codeUnitAt(0);
    return unit >= 48 && unit <= 57;
  }

  static bool _isASCIIAlphanumeric(String character) {
    if (character.length != 1) return false;
    final unit = character.codeUnitAt(0);
    return (unit >= 48 && unit <= 57) || (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }
}
