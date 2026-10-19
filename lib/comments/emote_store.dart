import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';

import '../video/page_api.dart';

/// 最近使用 (BiliNative `RecentEmotes`): the emotes picked last, newest first, at most [limit], kept across launches
/// in `emotes_recent.json` in the app's support folder (in memory only when [load] has no path).
class RecentEmotes {
  RecentEmotes.memory({Logger? logger}) : this._(null, [], logger ?? Logger.shared);

  RecentEmotes._(this._path, this._list, this._logger);

  static const limit = 14;

  static RecentEmotes shared = RecentEmotes.memory();

  /// A file that can't be read is set aside as `.bad` and the list starts empty; entries that don't decode are
  /// dropped one by one.
  static Future<RecentEmotes> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return RecentEmotes._(null, [], log);
    final file = File(path);
    if (!await file.exists()) return RecentEmotes._(path, [], log);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! List) throw const FormatException('not a list');
      final emotes = <Emote>[];
      for (final entry in json) {
        if (entry case {'token': final String token, 'url': final String url, 'large': final bool large}
            when token.isNotEmpty) {
          emotes.add(Emote(token: token, url: url, large: large));
        }
      }
      if (emotes.length < json.length) {
        log.warn(LogCategory.app, 'recent emotes skipped', {'skipped': json.length - emotes.length});
      }
      return RecentEmotes._(path, emotes.take(limit).toList(), log);
    } catch (error) {
      log.warn(LogCategory.app, 'recent emotes unreadable, starting empty', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'recent emotes not set aside', {'error': _reason(error)});
    }
    return RecentEmotes._(path, [], log);
  }

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };

  final String? _path;
  List<Emote> _list;
  final Logger _logger;
  Future<void> _writing = Future.value();

  List<Emote> get list => List.unmodifiable(_list);

  void record(Emote emote) {
    _list = [emote, ..._list.where((recent) => recent.token != emote.token)].take(limit).toList();
    _save();
  }

  void _save() {
    final path = _path;
    if (path == null) return;
    final text = jsonEncode([
      for (final emote in _list) {'token': emote.token, 'url': emote.url, 'large': emote.large},
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
      _logger.warn(LogCategory.app, 'recent emotes not saved', {'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}

/// The emote panel's packages, shared by every composer: kept once they arrive, asked for again after a failure or an
/// empty answer.
class EmoteCatalog {
  EmoteCatalog({Logger? logger}) : _logger = logger ?? Logger.shared;

  static final shared = EmoteCatalog();

  final Logger _logger;
  PageApi? _api;
  Future<List<EmotePackage>>? _packages;

  /// The packages, asking the server only the first time (and again after a failure or an empty answer, as Swift
  /// did). Every composer waiting meanwhile shares the one call. A failure reaches the caller.
  Future<List<EmotePackage>> load(PageApi api) {
    // Tests each bring their own fake; the app has one api for its whole life.
    if (!identical(api, _api)) {
      _api = api;
      _packages = null;
    }
    if (_packages case final packages?) return packages;
    final asked = _ask(api);
    _packages = asked;
    void forget() {
      if (identical(_packages, asked)) _packages = null;
    }

    unawaited(
      asked.then((packages) {
        if (packages.isEmpty) forget();
      }, onError: (Object _) => forget()),
    );
    return asked;
  }

  Future<List<EmotePackage>> _ask(PageApi api) async {
    try {
      return await api.emotePackages();
    } catch (error) {
      _logger.warn(LogCategory.api, 'emote packages failed', {'error': '$error'});
      rethrow;
    }
  }
}
