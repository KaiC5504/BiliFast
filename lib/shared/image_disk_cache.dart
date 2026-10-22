import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_core/devlog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Downloads a picture's bytes; throws `NetworkImageLoadException` for a status other than 200.
typedef ImageFetch = Future<Uint8List> Function(Uri url, Map<String, String>? headers);

/// The pictures shown through `StoredNetworkImage`, kept on the phone, so a picture asked for again (iOS emptied the
/// memory cache, a page came back, the app relaunched) comes from storage instead of the network. Files are named by a
/// hash of the address, in the caches folder iOS may empty when storage runs short; past [capBytes] the least recently
/// read go first.
class ImageDiskCache {
  ImageDiskCache({required this.folder, this.capBytes = defaultCapBytes, this._fetch});

  static const defaultCapBytes = 500 * 1024 * 1024;

  /// How long a download, request and body together, may take.
  static const downloadTimeout = Duration(seconds: 30);

  /// The app's, set at launch; null in tests and when launch couldn't get the caches folder, and pictures then come
  /// straight from the network.
  static ImageDiskCache? shared;

  final String folder;
  final int capBytes;
  final ImageFetch? _fetch;

  /// Asks in flight by address, so a second ask for one shares the first's download.
  final _loads = <String, _Load>{};

  /// What the folder holds, known once a trim has totalled it.
  int? _bytes;
  int? _files;

  /// Whether [start] has ended, whether or not it could total the folder.
  bool _started = false;

  Future<void>? _trimming;

  /// After a trim failed, stores to let by before the next is tried; doubled for each failure in a row.
  int _trimBackoff = 0;
  int _trimSkips = 0;
  bool _warnedTrim = false;

  /// Bumped by [clear], so a download that started before it is not stored after it.
  int _generation = 0;

  /// Temporary files carry this run's tag, so [start] tells a crashed run's half-written ones from this run's.
  final String _run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  int _serial = 0;

  /// Pictures shown but not stored this run, and the reasons already warned of.
  int _notStored = 0;
  final _storeReasons = <String>{};

  _MemoryPressure? _observer;

  /// Makes the folder, deletes the temporary files earlier runs left and totals what is stored; past the cap, trims to
  /// 80% of it, so the next stores don't trim again at once. Watches for memory pressure and logs `image cache`. Never
  /// throws.
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
      Logger.shared.info(LogCategory.ui, 'image cache', _summary(trim));
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'image cache not read', {'error': _describe(error)});
    } finally {
      _started = true;
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
    if (total == null) {
      // [start] couldn't total the folder, or a clear couldn't list it: a trim counts it afresh.
      if (_started) _trimInBackground();
      return;
    }
    _bytes = total + bytes.length;
    _files = (_files ?? 0) + 1;
    if (total + bytes.length > capBytes) _trimInBackground();
  }

  /// Each reason once a run: a full disk or a folder iOS refuses fails every picture alike.
  void _storeFailed(Object error) {
    _notStored += 1;
    final reason = _describe(error);
    if (!_storeReasons.add(reason)) return;
    Logger.shared.warn(LogCategory.ui, 'image not stored', {'error': reason});
  }

  void _trimInBackground() {
    if (_trimming != null) return;
    if (_trimSkips > 0) {
      _trimSkips -= 1;
      return;
    }
    _trimming = _trim(leftovers: false)
        .then((trim) {
          _trimBackoff = 0;
          Logger.shared.info(LogCategory.ui, trim.trimmed > 0 ? 'image cache trimmed' : 'image cache', _summary(trim));
        })
        .catchError((Object error) {
          // A folder that can't be listed fails every trim alike.
          _trimBackoff = _trimBackoff == 0 ? 16 : math.min(_trimBackoff * 2, 1024);
          _trimSkips = _trimBackoff;
          if (_warnedTrim) return;
          _warnedTrim = true;
          Logger.shared.warn(LogCategory.ui, 'image cache not trimmed', {'error': _describe(error)});
        })
        .whenComplete(() => _trimming = null);
  }

  /// Totals the folder and, past the cap, deletes the least recently read pictures until well under it. With
  /// [leftovers], also deletes the temporary files a run that died mid-write left behind.
  Future<({int files, int bytes, int trimmed})> _trim({required bool leftovers}) async {
    final pictures = <(File, int, DateTime)>[];
    var total = 0;
    await for (final file in _listed()) {
      if (file.path.endsWith('.tmp')) {
        if (leftovers && !file.path.contains('.$_run-')) await _delete(file);
        continue;
      }
      try {
        final stat = await file.stat();
        pictures.add((file, stat.size, stat.modified));
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

  Map<String, Object> _summary(({int files, int bytes, int trimmed}) trim) => {
    'files': trim.files,
    'mb': _megabytes(trim.bytes),
    'trimmed': trim.trimmed,
    if (_notStored > 0) 'notStored': _notStored,
  };

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

  /// What the folder takes in bytes, temporary files included.
  Future<int> sizeBytes() async {
    var total = 0;
    try {
      await for (final file in _listed()) {
        try {
          total += await file.length();
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException catch (error) {
      Logger.shared.warn(LogCategory.ui, 'image cache size not read', {'error': _describe(error)});
    }
    return total;
  }

  /// Deletes every stored picture. A download under way is not stored once it lands.
  Future<void> clear() async {
    _generation += 1;
    var deleted = 0;
    var failed = 0;
    try {
      await for (final file in _listed()) {
        if (await _delete(file)) {
          deleted += 1;
        } else {
          failed += 1;
        }
      }
    } on FileSystemException catch (error) {
      _bytes = null;
      _files = null;
      Logger.shared.warn(LogCategory.ui, 'image cache not cleared', {'error': _describe(error), 'files': deleted});
      return;
    }
    if (_bytes != null) {
      _bytes = 0;
      _files = 0;
    }
    Logger.shared.info(LogCategory.ui, 'image cache cleared', {'files': deleted, if (failed > 0) 'failed': failed});
  }

  /// The folder's files, none while there is no folder; any other failure to list it throws.
  Stream<File> _listed() async* {
    try {
      await for (final entity in listFolder()) {
        if (entity is File) yield entity;
      }
    } on PathNotFoundException {
      // Not made yet, or iOS emptied the caches folder under the running app.
    }
  }

  /// The folder's entries; a test stands in a listing that fails.
  @visibleForTesting
  Stream<FileSystemEntity> listFolder() => Directory(folder).list(followLinks: false);

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

  /// The app's download, as [NetworkImage] makes it; a [TimeoutException] once [timeout] has passed.
  static Future<Uint8List> download(Uri url, Map<String, String>? headers, {Duration timeout = downloadTimeout}) {
    HttpClientRequest? request;
    Future<Uint8List> fetch() async {
      final asking = request = await _client.getUrl(url);
      headers?.forEach(asking.headers.add);
      final response = await asking.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<List<int>>(<int>[]);
        throw NetworkImageLoadException(statusCode: response.statusCode, uri: url);
      }
      return consolidateHttpClientResponseBytes(response);
    }

    return fetch().timeout(
      timeout,
      onTimeout: () {
        // Without this a stalled server would keep the connection.
        request?.abort();
        throw TimeoutException('picture download', timeout);
      },
    );
  }

  // The same client setup as NetworkImage's, with a connection timeout.
  static final HttpClient _sharedClient = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 15);

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
