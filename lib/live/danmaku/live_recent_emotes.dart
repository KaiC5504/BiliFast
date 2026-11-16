import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../playback/playback_setup.dart' show supportFilePath;

/// The 直播 emotes used last, newest first, for the band over the keyboard (226, 223): kept across launches in
/// `live_emotes_recent.json` in the support folder, apart from the comments' `emotes_recent.json` (another kind of
/// emote, named by `emoticon_unique`).
class LiveRecentEmotes {
  LiveRecentEmotes.memory({Logger? logger}) : this._(null, [], logger ?? Logger.shared);

  LiveRecentEmotes._(this._path, this._list, this._logger);

  static const fileName = 'live_emotes_recent.json';
  static const limit = 20;

  static Future<LiveRecentEmotes>? _shared;
  static LiveRecentEmotes? _loaded;

  /// The phone's list once read, so an input opened later draws its band at once.
  static LiveRecentEmotes? get loaded => _loaded;

  /// The phone's list, read the first time it is asked for.
  static Future<LiveRecentEmotes> shared() =>
      _shared ??= load(supportFilePath(fileName)).then((store) => _loaded = store);

  /// Puts [store] in the phone's list's place (tests, or a launch that loads it itself).
  @visibleForTesting
  static void use(LiveRecentEmotes store) {
    _loaded = store;
    _shared = Future.value(store);
  }

  /// A file that can't be read is set aside as `.bad` and the list starts empty; entries that don't decode are dropped.
  static Future<LiveRecentEmotes> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return LiveRecentEmotes._(null, [], log);
    final file = File(path);
    try {
      if (!await file.exists()) return LiveRecentEmotes._(path, [], log);
      final json = jsonDecode(await file.readAsString());
      if (json is! List) throw const FormatException('not a list');
      final emotes = <LiveEmote>[];
      for (final entry in json) {
        if (entry case {'text': final String text, 'url': final String url, 'unique': final String unique}
            when text.isNotEmpty) {
          emotes.add(
            LiveEmote(
              text: text,
              url: url,
              unique: unique,
              width: switch (entry['width']) {
                final int width => width,
                _ => 0,
              },
              height: switch (entry['height']) {
                final int height => height,
                _ => 0,
              },
            ),
          );
        }
      }
      return LiveRecentEmotes._(path, emotes.take(limit).toList(), log);
    } catch (error) {
      log.warn(LogCategory.app, 'live recent emotes unreadable, starting empty', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'live recent emotes not set aside', {'error': _reason(error)});
    }
    return LiveRecentEmotes._(path, [], log);
  }

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };

  final String? _path;
  List<LiveEmote> _list;
  final Logger _logger;
  Future<void> _writing = Future.value();

  List<LiveEmote> get list => List.unmodifiable(_list);

  void record(LiveEmote emote) {
    _list = [emote, ..._list.where((recent) => !sameEmote(recent, emote))].take(limit).toList();
    _save();
  }

  /// One emote whether named by its `emoticon_unique` or, for an inline one without it, by the text it replaces.
  static bool sameEmote(LiveEmote a, LiveEmote b) =>
      a.unique.isNotEmpty || b.unique.isNotEmpty ? a.unique == b.unique : a.text == b.text;

  void _save() {
    final path = _path;
    if (path == null) return;
    final text = jsonEncode([
      for (final emote in _list)
        {'text': emote.text, 'url': emote.url, 'unique': emote.unique, 'width': emote.width, 'height': emote.height},
    ]);
    // One write after another, so an older list never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'live recent emotes not saved', {'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}
