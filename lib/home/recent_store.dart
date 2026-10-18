import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

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

/// 最近打开: the last [limit] parts opened from links, newest first, kept in a JSON file in the support folder
/// (Swift kept them in UserDefaults).
class RecentStore extends ChangeNotifier {
  RecentStore._(this._path, this._items, this._logger);

  static const limit = 30;

  /// A missing or unreadable file starts empty; [path] null keeps the list in memory only.
  static Future<RecentStore> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    var items = <RecentVideo>[];
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString()) as List<Object?>;
          items = [for (final item in json) RecentVideo.fromJson(item! as Map<String, Object?>)];
        }
      } catch (error) {
        log.warn(LogCategory.app, 'recents unreadable, starting empty', {'error': '$error'});
      }
    }
    return RecentStore._(path, items, log);
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
    final path = _path;
    if (path == null) return;
    final text = jsonEncode([for (final item in _items) item.toJson()]);
    // One write after another, so an older list never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'recents not saved', {'error': '$error'});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}
