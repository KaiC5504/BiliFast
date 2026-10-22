import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';

import 'svga_decoder.dart';
import 'svga_movie.dart';
import 'svga_painter.dart';

/// Decodes `.svga` files once and keeps the last few by path and modified time, so a view built again (a bar icon
/// selected, a page shown again) draws at once. The file is read and decoded on another isolate, its pictures by the
/// engine.
final class SvgaLoader {
  SvgaLoader({this.capacity = 16});

  static final shared = SvgaLoader();

  final int capacity;
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
    try {
      final movie = await _decodeFile(file.path);
      final images = <String, ui.Image>{};
      await Future.wait([
        for (final MapEntry(:key, :value) in movie.images.entries)
          _picture(value).then((image) {
            if (image != null) images[key] = image;
          }),
      ]);
      return SvgaComposition(movie, images);
    } catch (error) {
      _logOnce(cacheKey, file, error is FormatException ? error.message : error.runtimeType.toString());
      return null;
    }
  }

  /// Static, so the closure sent to the isolate holds nothing but the path.
  static Future<SvgaMovie> _decodeFile(String path) =>
      Isolate.run(() => SvgaDecoder.decode(File(path).readAsBytesSync()));

  static Future<ui.Image?> _picture(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _logOnce(String key, File file, String error) {
    if (!_logged.add(key)) return;
    Logger.shared.warn(LogCategory.ui, 'svga unreadable', {'file': file.uri.pathSegments.last, 'error': error});
  }
}

final class _Entry {
  late final Future<SvgaComposition?> future;
  SvgaComposition? value;
  bool done = false;
}
