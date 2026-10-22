import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';

import '../../devtools/crash_log.dart';
import 'svga_decoder.dart';
import 'svga_movie.dart';
import 'svga_painter.dart';

/// Decodes `.svga` files once and keeps the last few by path and modified time, so a view built again (a bar icon
/// selected, a page shown again) draws at once. The file is read and decoded on another isolate, its pictures by the
/// engine.
final class SvgaLoader {
  /// [read] stands in for the file's read and decode in tests.
  SvgaLoader({this.capacity = 16, Future<SvgaMovie> Function(String path)? read}) : _read = read ?? _decodeFile;

  static final shared = SvgaLoader();

  final int capacity;
  final Future<SvgaMovie> Function(String path) _read;
  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final Set<String> _logged = {};

  /// The decoded movie: at once when it is cached, else once decoded. Null when the file can't be read, logged once.
  FutureOr<SvgaComposition?> load(File file) {
    // A stat, not a read: the decode itself stays off this isolate.
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file) {
      _logOnce(file.path, file, 'missing');
      return null;
    }
    final key = '${file.path}|${stat.modified.microsecondsSinceEpoch}|${stat.size}';
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached.done ? cached.value : cached.future;
    }
    final entry = _Entry();
    entry.future = _decode(file, key).then((value) {
      entry
        ..value = value
        ..done = true;
      return value;
    });
    _entries[key] = entry;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return entry.future;
  }

  Future<SvgaComposition?> _decode(File file, String cacheKey) async {
    final images = <String, ui.Image>{};
    Future<void> picture(String key, Uint8List bytes) async {
      try {
        images[key] = await _picture(bytes);
      } on Exception catch (error) {
        _logPictureOnce(cacheKey, file, key, error);
      }
    }

    try {
      final movie = await _read(file.path);
      await Future.wait([for (final MapEntry(:key, :value) in movie.images.entries) picture(key, value)]);
      // A movie of pictures that draws none would show an empty box instead of its fallback.
      if (movie.images.isNotEmpty && images.isEmpty) {
        _logOnce(cacheKey, file, 'no picture decodes');
        return null;
      }
      return SvgaComposition(movie, images);
    } on Exception catch (error) {
      _logOnce(cacheKey, file, error is FormatException ? error.message : error.runtimeType.toString());
      return null;
    } on Error catch (error, stack) {
      for (final image in images.values) {
        image.dispose();
      }
      CrashLog.report(error, stack, source: 'svga decode', fields: {'file': _name(file)});
      return null;
    }
  }

  /// Static, so the closure sent to the isolate holds nothing but the path.
  static Future<SvgaMovie> _decodeFile(String path) =>
      Isolate.run(() => SvgaDecoder.decode(File(path).readAsBytesSync()));

  static Future<ui.Image> _picture(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  void _logOnce(String key, File file, String error) {
    if (!_logged.add(key)) return;
    Logger.shared.warn(LogCategory.ui, 'svga unreadable', {'file': _name(file), 'error': error});
  }

  /// The key is the movie's own name for the picture, not a path.
  void _logPictureOnce(String cacheKey, File file, String key, Exception error) {
    if (!_logged.add('$cacheKey|$key')) return;
    Logger.shared.warn(LogCategory.ui, 'svga picture unreadable', {
      'file': _name(file),
      'sprite': key.length <= 60 ? key : '${key.substring(0, 60)}…',
      'error': error.runtimeType.toString(),
    });
  }

  static String _name(File file) => file.uri.pathSegments.last;
}

final class _Entry {
  late final Future<SvgaComposition?> future;
  SvgaComposition? value;
  bool done = false;
}
