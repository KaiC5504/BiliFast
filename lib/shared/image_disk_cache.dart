import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Downloads a picture's bytes; throws `NetworkImageLoadException` for a status other than 200.
typedef ImageFetch = Future<Uint8List> Function(Uri url, Map<String, String>? headers);

/// Every network picture kept on the phone, so a picture asked for again (iOS emptied the memory cache, a page came
/// back, the app relaunched) comes from storage instead of the network. Files are named by a hash of the address, in
/// the caches folder iOS may empty when storage runs short; past [capBytes] the oldest go first.
class ImageDiskCache {
  ImageDiskCache({required this.folder, this.capBytes = defaultCapBytes, this._fetch});

  static const defaultCapBytes = 500 * 1024 * 1024;

  /// The app's, set at launch; null in tests, where pictures come straight from the network as before.
  static ImageDiskCache? shared;

  final String folder;
  final int capBytes;
  final ImageFetch? _fetch;

  /// Asks in flight by address, so a second ask for one shares the first's download.
  final _loads = <String, _Load>{};

  /// What the folder holds, known once [start] has totalled it.
  int? _bytes;
  int? _files;

  Future<void>? _trimming;

  /// Bumped by [clear], so a download that started before it is not stored after it.
  int _generation = 0;

  /// Temporary files carry this run's tag, so [start] tells a crashed run's half-written ones from this run's.
  final String _run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  int _serial = 0;

  bool _warnedStore = false;
  _MemoryPressure? _observer;

  /// Trims to the cap, oldest first, and logs `image cache`. Never throws.
  Future<void> start() async {
    if (_observer == null) {
      try {
        final observer = _MemoryPressure(this);
        WidgetsBinding.instance.addObserver(observer);
        _observer = observer;
      } catch (error) {
        Logger.shared.warn(LogCategory.ui, 'image cache not watching memory', {'error': _describe(error)});
      }
    }
    try {
      await Directory(folder).create(recursive: true);
      final trim = await _trim(leftovers: true);
      Logger.shared.info(LogCategory.ui, 'image cache', {
        'files': trim.files,
        'mb': _megabytes(trim.bytes),
        'trimmed': trim.trimmed,
      });
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'image cache not read', {'error': _describe(error)});
    }
  }

  @visibleForTesting
  void dispose() {
    final observer = _observer;
    if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    _observer = null;
  }

  /// The picture at [url] from storage, or downloaded (with [headers]) and stored.
  Future<Uint8List> bytes(String url, {Map<String, String>? headers}) {
    final running = _loads[url];
    if (running != null) return running.bytes.future;
    final load = _Load();
    _loads[url] = load;
    load.done = _load(url, headers, load.bytes).whenComplete(() {
      if (identical(_loads[url], load)) _loads.remove(url);
    });
    return load.bytes.future;
  }

  Future<void> _load(String url, Map<String, String>? headers, Completer<Uint8List> result) async {
    try {
      final file = fileOf(url);
      final stored = await _read(file);
      if (stored != null) {
        result.complete(stored);
        // Trimming goes by modification time, so a picture still being looked at is kept over one long unseen.
        file.setLastModified(DateTime.now()).ignore();
        return;
      }
      final generation = _generation;
      final fetched = await (_fetch ?? download)(Uri.base.resolve(url), headers);
      result.complete(fetched);
      if (fetched.isEmpty || generation != _generation) return;
      await _store(file, fetched, generation);
    } catch (error, stack) {
      if (!result.isCompleted) {
        result.completeError(error, stack);
      } else {
        _storeFailed(error);
      }
    }
  }

  static Future<Uint8List?> _read(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } on FileSystemException {
      return null;
    }
  }

  /// Written under a temporary name and renamed into place, so a picture is never read half written.
  Future<void> _store(File file, Uint8List bytes, int generation) async {
    final temporary = File('${file.path}.$_run-${_serial++}.tmp');
    try {
      try {
        await temporary.writeAsBytes(bytes);
      } on PathNotFoundException {
        // iOS emptied the caches folder under the running app, or [start] hasn't made it yet.
        await Directory(folder).create(recursive: true);
        await temporary.writeAsBytes(bytes);
      }
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      temporary.delete().ignore();
      // A clear meanwhile deleted the temporary file; that is no failure.
      if (generation != _generation) return;
      _storeFailed(error);
      return;
    }
    if (generation != _generation) {
      file.delete().ignore();
      return;
    }
    final total = _bytes;
    if (total == null) return;
    _bytes = total + bytes.length;
    _files = (_files ?? 0) + 1;
    if (total + bytes.length > capBytes) _trimInBackground();
  }

  /// Once a run: a full disk or a folder iOS refuses fails every picture alike.
  void _storeFailed(Object error) {
    if (_warnedStore) return;
    _warnedStore = true;
    Logger.shared.warn(LogCategory.ui, 'image not stored', {'error': _describe(error)});
  }

  void _trimInBackground() {
    if (_trimming != null) return;
    _trimming = _trim(leftovers: false)
        .then((trim) {
          Logger.shared.info(LogCategory.ui, 'image cache trimmed', {
            'files': trim.files,
            'mb': _megabytes(trim.bytes),
            'trimmed': trim.trimmed,
          });
        })
        .catchError((Object error) {
          Logger.shared.warn(LogCategory.ui, 'image cache not trimmed', {'error': _describe(error)});
        })
        .whenComplete(() => _trimming = null);
  }

  /// Totals the folder and, past the cap, deletes the oldest-modified pictures until well under it. With
  /// [leftovers], also deletes the temporary files a run that died mid-write left behind.
  Future<({int files, int bytes, int trimmed})> _trim({required bool leftovers}) async {
    final pictures = <(File, int, DateTime)>[];
    var total = 0;
    await for (final entity in Directory(folder).list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.tmp')) {
        if (leftovers && !entity.path.contains('.$_run-')) await _delete(entity);
        continue;
      }
      try {
        final stat = await entity.stat();
        pictures.add((entity, stat.size, stat.modified));
        total += stat.size;
      } on FileSystemException {
        continue;
      }
    }
    var trimmed = 0;
    if (total > capBytes) {
      pictures.sort((a, b) => a.$3.compareTo(b.$3));
      final target = capBytes * 0.8;
      for (final (file, size, _) in pictures) {
        if (total <= target) break;
        if (await _delete(file)) {
          total -= size;
          trimmed += 1;
        }
      }
    }
    _bytes = total;
    _files = pictures.length - trimmed;
    return (files: pictures.length - trimmed, bytes: total, trimmed: trimmed);
  }

  /// Deletes the stored copy of [url], as one that would not decode; the next ask downloads it again.
  Future<void> forget(String url) async {
    await _loads[url]?.done;
    final file = fileOf(url);
    try {
      final size = await file.length();
      await file.delete();
      if (_bytes case final total?) {
        _bytes = total - size;
        _files = (_files ?? 1) - 1;
      }
    } on FileSystemException {
      // Not stored, or already gone.
    }
  }

  /// What the stored pictures take, in bytes.
  Future<int> sizeBytes() async {
    var total = 0;
    try {
      await for (final entity in Directory(folder).list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      // No folder yet.
    }
    return total;
  }

  /// Deletes every stored picture.
  Future<void> clear() async {
    _generation += 1;
    var deleted = 0;
    var failed = 0;
    try {
      await for (final entity in Directory(folder).list(followLinks: false)) {
        if (entity is! File) continue;
        if (await _delete(entity)) {
          deleted += 1;
        } else {
          failed += 1;
        }
      }
    } on FileSystemException {
      // No folder yet.
    }
    if (_bytes != null) {
      _bytes = 0;
      _files = 0;
    }
    Logger.shared.info(LogCategory.ui, 'image cache cleared', {'files': deleted, if (failed > 0) 'failed': failed});
  }

  /// Every load and trim under way, finished.
  @visibleForTesting
  Future<void> settle() async {
    while (_loads.isNotEmpty || _trimming != null) {
      await Future.wait([for (final load in _loads.values) load.done, ?_trimming]);
    }
  }

  @visibleForTesting
  File fileOf(String url) => File('$folder${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}');

  void _memoryPressure() {
    Logger.shared.info(LogCategory.ui, 'images cleared', {
      'live': PaintingBinding.instance.imageCache.liveImageCount,
      'files': ?_files,
    });
  }

  static Future<bool> _delete(File file) async {
    try {
      await file.delete();
      return true;
    } on FileSystemException {
      // Windows can't delete a file another reader still holds.
      return false;
    }
  }

  static double _megabytes(int bytes) => (bytes / (1024 * 1024) * 10).round() / 10;

  /// The OS's reason, never the path or the address.
  static String _describe(Object error) => switch (error) {
    FileSystemException(:final osError?) => osError.message,
    FileSystemException(:final message) => message,
    _ => '${error.runtimeType}',
  };

  /// The app's download, as [NetworkImage] makes it.
  static Future<Uint8List> download(Uri url, Map<String, String>? headers) async {
    final request = await _client.getUrl(url);
    headers?.forEach(request.headers.add);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<List<int>>(<int>[]);
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: url);
    }
    return consolidateHttpClientResponseBytes(response);
  }

  // Content-Length stays trustworthy only uncompressed; consolidateHttpClientResponseBytes inflates.
  static final HttpClient _sharedClient = HttpClient()..autoUncompress = false;

  static HttpClient get _client {
    HttpClient? client;
    assert(() {
      client = debugNetworkImageHttpClientProvider?.call();
      return true;
    }());
    return client ?? _sharedClient;
  }
}

final class _Load {
  final bytes = Completer<Uint8List>();
  late final Future<void> done;
}

class _MemoryPressure with WidgetsBindingObserver {
  _MemoryPressure(this._cache);

  final ImageDiskCache _cache;

  /// The painting binding has emptied the memory cache by now; what it still holds live stays on screen.
  @override
  void didHaveMemoryPressure() => _cache._memoryPressure();
}
