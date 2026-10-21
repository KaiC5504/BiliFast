import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

/// 搜索历史, kept on the phone only, newest first, and whether 搜索发现 is hidden (52's 👁), in a JSON file in the
/// support folder: `{"words": [...], "discoveryHidden": bool}`.
class SearchHistoryStore extends ChangeNotifier {
  SearchHistoryStore.memory({Logger? logger}) : this._(null, [], false, logger ?? Logger.shared);

  SearchHistoryStore._(this._path, this._words, this._discoveryHidden, this._logger);

  /// [path] null keeps it in memory only. An unreadable file is set aside as `.bad` and the history starts empty;
  /// words that aren't text are dropped.
  static Future<SearchHistoryStore> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return SearchHistoryStore._(null, [], false, log);
    final file = File(path);
    if (!await file.exists()) return SearchHistoryStore._(path, [], false, log);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      final words = json['words'] ?? const <Object?>[];
      if (words is! List) throw const FormatException('words not a list');
      final hidden = json['discoveryHidden'];
      return SearchHistoryStore._(path, _tidy(words.whereType<String>()), hidden is bool && hidden, log);
    } catch (error) {
      log.warn(LogCategory.app, 'search history unreadable, starting empty', {
        'file': _name(file),
        'error': _reason(error),
      });
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'search history not set aside', {'file': _name(file), 'error': _reason(error)});
    }
    return SearchHistoryStore._(path, [], false, log);
  }

  static const limit = 20;

  final String? _path;
  final List<String> _words;
  bool _discoveryHidden;
  final Logger _logger;
  Future<void> _writing = Future.value();

  List<String> get words => List.unmodifiable(_words);

  bool get discoveryHidden => _discoveryHidden;

  /// To the front, once; trimmed, and nothing for a blank word.
  void add(String word) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;
    if (_words.isNotEmpty && _words.first == trimmed) return;
    _words
      ..remove(trimmed)
      ..insert(0, trimmed);
    if (_words.length > limit) _words.removeRange(limit, _words.length);
    _changed();
  }

  /// Drops one word.
  void remove(String word) {
    if (_words.remove(word.trim())) _changed();
  }

  void clear() {
    if (_words.isEmpty) return;
    _words.clear();
    _changed();
  }

  void setDiscoveryHidden(bool hidden) {
    if (hidden == _discoveryHidden) return;
    _discoveryHidden = hidden;
    _changed();
  }

  Map<String, Object?> _toJson() => {'words': _words, 'discoveryHidden': _discoveryHidden};

  /// Trimmed, without blanks or repeats (the first, newest, kept), and no more than [limit].
  static List<String> _tidy(Iterable<String> words) {
    final seen = <String>{};
    return [
      for (final word in words.map((word) => word.trim()))
        if (word.isNotEmpty && seen.add(word)) word,
    ].take(limit).toList();
  }

  void _changed() {
    notifyListeners();
    final path = _path;
    if (path == null) return;
    final text = jsonEncode(_toJson());
    // One write after another, so an older history never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    final file = File(path);
    try {
      await file.parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'search history not saved', {'file': _name(file), 'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;

  static String _name(File file) => file.uri.pathSegments.last;

  /// The error without the text that failed, which is what the user searched: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}
