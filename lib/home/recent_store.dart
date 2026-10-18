import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A part opened from a pasted link, as 最近打开 lists it (port of PlayerRoute in RecentStore.swift).
@immutable
final class RecentVideo {
  const RecentVideo({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.part,
    required this.page,
    required this.pageCount,
  });

  factory RecentVideo.fromJson(Map<String, Object?> json) => RecentVideo(
    bvid: json['bvid']! as String,
    cid: json['cid']! as int,
    title: json['title']! as String,
    part: json['part'] as String? ?? '',
    page: json['page'] as int? ?? 1,
    pageCount: json['pageCount'] as int? ?? 1,
  );

  final String bvid;
  final int cid;
  final String title;
  final String part;
  final int page;
  final int pageCount;

  String get id => '$bvid#$cid';

  Map<String, Object?> toJson() => {
    'bvid': bvid,
    'cid': cid,
    'title': title,
    'part': part,
    'page': page,
    'pageCount': pageCount,
  };

  @override
  bool operator ==(Object other) => other is RecentVideo && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// The Swift app's 最近打开 as the UTF-8 text of its JSON; null when it saved none.
typedef SwiftRecentsReader = Future<String?> Function();

/// UserDefaults `home.recents` of the Swift app this build replaced on the phone (LegacyDefaults.swift): the JSON
/// of `[PlayerRoute]`, whose fields are [RecentVideo]'s.
Future<String?> readSwiftRecents() => const MethodChannel('bilifast/legacy_defaults').invokeMethod<String>('recents');

/// 最近打开: the last [limit] parts opened from links, newest first, kept in a JSON file in the support folder
/// (Swift kept them in UserDefaults).
class RecentStore extends ChangeNotifier {
  RecentStore._(this._path, this._items, this._logger);

  static const limit = 30;

  /// [path] null keeps the list in memory only. With no file yet, the list starts from the Swift app's on iOS and
  /// is saved, so that happens once; [readSwift] stands in for the channel in tests. An unreadable file is set
  /// aside as `.bad` and the list starts empty; entries that don't decode are dropped one by one.
  static Future<RecentStore> load(String? path, {Logger? logger, SwiftRecentsReader? readSwift}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return RecentStore._(null, [], log);
    final file = File(path);
    if (await file.exists()) {
      final items = await _readFile(file, log);
      final store = RecentStore._(path, items ?? [], log);
      // Saved empty, so a file set aside never lets the Swift list back in on the next launch.
      if (items == null) store._save();
      return store;
    }
    final store = RecentStore._(path, [], log);
    final reader = readSwift ?? (Platform.isIOS ? readSwiftRecents : null);
    if (reader != null) await store._importSwift(reader);
    return store;
  }

  /// Null when the file can't be read at all; it is then renamed to `.bad`.
  static Future<List<RecentVideo>?> _readFile(File file, Logger log) async {
    final fields = <String, Object>{'file': _name(file)};
    try {
      fields['bytes'] = await file.length();
      final (items, skipped) = _decode(await file.readAsString());
      if (skipped > 0) {
        log.warn(LogCategory.app, 'recents entries skipped', {...fields, 'skipped': skipped, 'kept': items.length});
      }
      return items;
    } catch (error) {
      log.warn(LogCategory.app, 'recents unreadable, starting empty', {...fields, 'error': _reason(error)});
    }
    try {
      await file.rename('${file.path}.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'recents not set aside', {...fields, 'error': _reason(error)});
    }
    return null;
  }

  /// Throws when [text] is not a JSON list; skips and counts the entries that aren't a [RecentVideo].
  static (List<RecentVideo>, int) _decode(String text) {
    final json = jsonDecode(text);
    if (json is! List) throw const FormatException('not a list');
    final items = <RecentVideo>[];
    var skipped = 0;
    for (final entry in json) {
      if (entry is Map<String, Object?>) {
        try {
          items.add(RecentVideo.fromJson(entry));
          continue;
        } on TypeError {
          // A field missing or of the wrong type.
        }
      }
      skipped++;
    }
    return (items, skipped);
  }

  static String _name(File file) => file.uri.pathSegments.last;

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    PlatformException(:final code) => 'PlatformException($code)',
    _ => '${error.runtimeType}',
  };

  Future<void> _importSwift(SwiftRecentsReader read) async {
    final String? text;
    try {
      text = await read();
    } catch (error) {
      // Nothing saved, so the next launch tries again.
      _logger.warn(LogCategory.app, 'Swift recents not read', {'error': _reason(error)});
      return;
    }
    if (text != null) {
      try {
        final (items, skipped) = _decode(text);
        _items = items.take(limit).toList();
        _logger.info(LogCategory.app, 'recents carried over from the Swift app', {
          'kept': _items.length,
          'skipped': skipped,
        });
      } catch (error) {
        _logger.warn(LogCategory.app, 'Swift recents unreadable', {
          'bytes': utf8.encode(text).length,
          'error': _reason(error),
        });
      }
    }
    _save();
  }

  final String? _path;
  List<RecentVideo> _items;
  final Logger _logger;
  Future<void> _writing = Future.value();

  List<RecentVideo> get items => List.unmodifiable(_items);

  void add(RecentVideo video) {
    _items = [video, ..._items.where((item) => item.id != video.id)].take(limit).toList();
    _changed();
  }

  void clear() {
    _items = [];
    _changed();
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  void _save() {
    final path = _path;
    if (path == null) return;
    final text = jsonEncode([for (final item in _items) item.toJson()]);
    // One write after another, so an older list never lands last.
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
      _logger.warn(LogCategory.app, 'recents not saved', {'file': _name(file), 'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}
