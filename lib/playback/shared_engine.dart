import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';

/// The one engine isolate and local server every page's controller plays through, as the Swift app's AVPlayers
/// shared one engine. Each controller holds an [EngineLease] on it. Once the isolate is gone, the next [lease] starts
/// one replacement, which every controller's own recovery (a lease asked for again) then moves onto. 设置's CDN 节点
/// is kept here, so a replacement starts on it too.
final class SharedEngine {
  SharedEngine(this._start, {Logger? logger}) : _logger = logger ?? Logger.shared;

  final Future<PlaybackEngine> Function() _start;
  final Logger _logger;
  PlaybackEngine? _engine;
  Future<PlaybackEngine>? _starting;
  NodeMode? _nodeMode;
  ({PlaybackEngine engine, Future<bool> answer})? _probe;
  bool _lost = false;
  bool _disposed = false;

  /// The engine running now; null before the first start finished and once it is gone.
  PlaybackEngine? get running => _engine;

  /// The running engine, started first when there is none. Callers while a start is out share it.
  Future<PlaybackEngine> current() {
    if (_disposed) return Future.error(const RipperError(RipperErrorKind.closed));
    final engine = _engine;
    if (engine != null) return Future.value(engine);
    return _starting ??= _startOne();
  }

  Future<PlaybackEngine> _startOne() async {
    try {
      final engine = await _start();
      if (_disposed) {
        unawaited(engine.dispose().catchError((Object _) {}));
        throw const RipperError(RipperErrorKind.closed);
      }
      _engine = engine;
      if (_nodeMode case final mode?) engine.setNodeMode(mode);
      // An engine's fatal reports end when it does, a crashed isolate's included.
      engine.fatals.listen(null, onDone: () => _gone(engine), onError: (Object _) {});
      if (_lost) {
        _lost = false;
        _logger.info(LogCategory.engine, 'shared engine replaced');
      }
      return engine;
    } finally {
      _starting = null;
    }
  }

  /// One controller's hold on the running engine, started first when none runs.
  Future<EngineLease> lease() async => EngineLease._(this, await current());

  void _gone(PlaybackEngine engine) {
    if (!identical(_engine, engine)) return;
    _engine = null;
    _lost = !_disposed;
    if (_lost) _logger.error(LogCategory.engine, 'shared engine closed, the next page starts a new one');
    unawaited(engine.dispose().catchError((Object _) {}));
  }

  /// 设置's CDN 节点, for the engine running now and any that replaces it.
  void setNodeMode(NodeMode mode) {
    _nodeMode = mode;
    _engine?.setNodeMode(mode);
  }

  /// A memory warning: every playback on the engine trims its prefetch, once however many pages are open.
  void dropCache() => _engine?.dropCache();

  /// The phone's network path changed: the engine's node health starts over, once for every page.
  Future<void> networkChanged({required bool interfaceChanged}) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.networkChanged(interfaceChanged: interfaceChanged);
    } catch (error) {
      _logger.warn(LogCategory.engine, 'network change not taken', {'error': '$error'});
    }
  }

  /// One probe of the local server at a time: the pages that ask while one is out (every page at once, on coming
  /// back to the foreground) share its answer.
  Future<bool> _ensureServing(PlaybackEngine engine) {
    final probe = _probe;
    if (probe != null && identical(probe.engine, engine)) return probe.answer;
    final answer = engine.ensureServing();
    final asked = (engine: engine, answer: answer);
    _probe = asked;
    void done() {
      if (identical(_probe, asked)) _probe = null;
    }

    unawaited(answer.then<void>((_) => done(), onError: (Object _) => done()));
    return answer;
  }

  Future<void> dispose() async {
    _disposed = true;
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}

/// One controller's hold on the [SharedEngine]: every call goes to the engine it was given. [dispose] releases the
/// sources this lease prepared and leaves the engine running for the other pages. A call that finds the engine gone
/// tells the shared engine, so the next lease starts a new one.
final class EngineLease implements PlaybackEngine {
  EngineLease._(this._shared, this.engine);

  final SharedEngine _shared;

  /// The engine running when the lease was taken.
  final PlaybackEngine engine;
  final _tokens = <String>{};
  bool _released = false;

  /// Sources prepared through this lease and not yet released.
  Set<String> get tokens => Set.unmodifiable(_tokens);

  Future<T> _call<T>(Future<T> Function() call) async {
    if (_released) throw const RipperError(RipperErrorKind.closed);
    try {
      return await call();
    } on RipperError catch (error) {
      if (error.kind == RipperErrorKind.closed) _shared._gone(engine);
      rethrow;
    }
  }

  @override
  Future<PreparedSource> prepare(PlaybackRequest request) async {
    final source = await _call(() => engine.prepare(request));
    // Let go while it was preparing: nothing will release this source through the lease now, so it goes at once.
    if (_released) {
      unawaited(engine.release(source.token).catchError((Object _) {}));
    } else {
      _tokens.add(source.token);
    }
    return source;
  }

  @override
  Future<PreparedSource> prepareLocal(LocalPlaybackRequest request) async {
    final source = await _call(() => engine.prepareLocal(request));
    if (_released) {
      unawaited(engine.release(source.token).catchError((Object _) {}));
    } else {
      _tokens.add(source.token);
    }
    return source;
  }

  @override
  Future<void> startDownload(DownloadRequest request) => _call(() => engine.startDownload(request));

  @override
  Future<DownloadGaps> stopDownload(String id) => _call(() => engine.stopDownload(id));

  @override
  Future<void> replaceDownloadUrls(
    String id,
    TrackKind track, {
    required String primary,
    required List<String> backups,
  }) => _call(() => engine.replaceDownloadUrls(id, track, primary: primary, backups: backups));

  @override
  Stream<DownloadEvent> get downloads => engine.downloads;

  @override
  Future<void> release(String token) {
    if (_released) return Future.value();
    _tokens.remove(token);
    return _call(() => engine.release(token));
  }

  @override
  Future<void> replaceUrls(String token, TrackKind track, {required String primary, required List<String> backups}) =>
      _call(() => engine.replaceUrls(token, track, primary: primary, backups: backups));

  @override
  Future<void> networkChanged({required bool interfaceChanged}) =>
      _call(() => engine.networkChanged(interfaceChanged: interfaceChanged));

  @override
  void updatePlayhead(String token, {required double seconds, required double rate}) {
    if (!_released) engine.updatePlayhead(token, seconds: seconds, rate: rate);
  }

  @override
  void reportBuffer(String token, {required double aheadSeconds, required bool playing}) {
    if (!_released) engine.reportBuffer(token, aheadSeconds: aheadSeconds, playing: playing);
  }

  @override
  void reportStall(String token) {
    if (!_released) engine.reportStall(token);
  }

  /// Nothing: a memory warning drops the shared engine's cache once ([SharedEngine.dropCache], from AppPlayback),
  /// not once per page.
  @override
  void dropCache() {}

  @override
  void dropPrefetch(String token) {
    if (!_released) engine.dropPrefetch(token);
  }

  @override
  void hint(String token, double? seconds) {
    if (!_released) engine.hint(token, seconds);
  }

  @override
  void preconnect(List<String> urls) {
    if (!_released) engine.preconnect(urls);
  }

  /// The CDN 节点 is the app's, not a page's.
  @override
  void setNodeMode(NodeMode mode) => _shared.setNodeMode(mode);

  @override
  Stream<FatalReport> get fatals => engine.fatals;

  @override
  Stream<EngineSnapshot> get stats => engine.stats;

  @override
  Future<bool> ensureServing() => _call(() => _shared._ensureServing(engine));

  @override
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    final tokens = List.of(_tokens);
    _tokens.clear();
    for (final token in tokens) {
      try {
        await engine.release(token);
      } catch (error) {
        // A gone engine took them with it.
        if (error is RipperError && error.kind == RipperErrorKind.closed) continue;
        _shared._logger.warn(LogCategory.engine, 'release failed', {'error': '$error'});
      }
    }
  }
}
