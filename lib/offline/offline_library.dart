import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/logic.dart' show QualityNames, QualityRules;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show NetworkImageLoadException;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../playback/codec_memory.dart';
import '../playback/playback_controller.dart';
import '../shared/image_disk_cache.dart';
import '../shared/remote_image.dart' show coverImageUrl, suffixedImageUrl;
import '../video/player_prefs.dart';
import 'disk/background_plan.dart';
import 'disk/offline_entry.dart';
import 'disk/offline_files.dart';
import 'offline_host.dart';
import 'offline_models.dart';

/// 离线缓存: every part cached on the phone, the queue that fills them, and the space they take. Listeners hear every
/// change, progress included (about once a second while a part downloads).
abstract class OfflineLibrary extends ChangeNotifier {
  /// Newest added first.
  List<OfflineItem> get items;

  OfflineItem? item(int cid);

  /// What every part's files take on the phone.
  int get usedBytes;

  /// What the phone has left; null when unknown (the sheet then writes 剩余 -).
  int? get freeBytes;

  /// 同时缓存数量: how many parts download at once, 1 to 3 (147).
  int get concurrency;
  void setConcurrency(int count);

  /// Something was added or finished since 离线缓存 was last opened: 查看缓存's red dot (141).
  bool get unseen;
  void markSeen();

  /// Reads what is on the phone and resumes unfinished parts. Called once at launch.
  Future<void> start();

  /// Queues [parts] at the highest quality the account gets ([quality] null) or the best at or below [quality].
  /// Parts already in the library are left as they are.
  Future<void> enqueue(List<OfflineRequest> parts, {int? quality});

  void pause(int cid);
  void resume(int cid);

  /// 全部暂停 and 全部开始 (146, 148).
  void pauseAll();
  void startAll();

  /// Stops and removes the parts, files and all.
  Future<void> delete(Iterable<int> cids);

  /// Where playback of [cid] stopped, for the cover's progress (145).
  void savePosition(int cid, double seconds);

  /// The files of a finished part; null while it isn't finished or its files are gone.
  Future<OfflinePlayback?> playback(int cid);

  /// Asks the phone for its free space again.
  Future<void> refreshFreeSpace();
}

/// The library as the app runs it: files in the support folder's `offline` ([OfflineFiles]), downloads through the
/// engine while the app is open and through iOS's background transfers once it isn't.
///
/// A part's signed addresses live only in memory. Waiting parts start oldest first, up to [concurrency] at a time;
/// each asks playurl for the best streams the account gets, saves its cover, face and danmaku, then hands its two
/// tracks to the engine, which keeps what it has across stops and launches.
class DiskOfflineLibrary extends OfflineLibrary with WidgetsBindingObserver {
  DiskOfflineLibrary({
    required this.folder,
    required this.client,
    required this.engine,
    required this.host,
    this.codecMemory,
    Logger? logger,
    Future<Uint8List> Function(Uri url)? pictures,
    VideoCodec Function()? preferredCodec,
    DateTime Function()? now,
    this.danmakuGap = const Duration(milliseconds: 500),
    this.retryGaps = const [Duration(seconds: 2), Duration(seconds: 6)],
  }) : logger = logger ?? Logger.shared,
       files = OfflineFiles(folder),
       _pictures = pictures ?? _download,
       _preferredCodec = preferredCodec ?? _playerCodec,
       _now = now ?? DateTime.now {
    host.onGraceEnding = _graceEnding;
    host.onRangeFinished = _rangeFinished;
  }

  /// Absolute, looked up this launch; everything kept inside it is named relative to it.
  final String folder;
  final BiliClient Function() client;

  /// A lease on the app's shared engine; the library keeps it and asks again once the engine is gone.
  final Future<PlaybackEngine> Function() engine;
  final OfflineHost host;
  final CodecMemory? codecMemory;
  final Logger logger;
  final OfflineFiles files;

  /// Between two danmaku segment calls, so a long video's segments don't arrive at the account as a burst.
  final Duration danmakuGap;

  /// The waits before asking playurl again after a network failure; risk control is never asked again.
  final List<Duration> retryGaps;

  final Future<Uint8List> Function(Uri url) _pictures;
  final VideoCodec Function() _preferredCodec;
  final DateTime Function() _now;

  static const maxConcurrency = 3;

  /// 8K: playurl answers every stream the account gets up to it.
  static const askQuality = 127;

  /// Signed addresses are refreshed this long before their deadline.
  static const urlMargin = Duration(minutes: 10);

  /// Background transfers may wait a while for iOS, so they go out only with addresses good for this long.
  static const handOffMargin = Duration(minutes: 30);
  static const progressInterval = Duration(seconds: 1);
  static const progressSaveInterval = Duration(seconds: 30);
  static const positionSaveDelay = Duration(seconds: 2);

  /// Seconds of danmaku in one `seg.so` answer.
  static const danmakuSegmentSeconds = 360;

  /// Fresh addresses or a track started over this many times in a row without progress fail the part.
  static const maxStrikes = 2;
  static const _maxEngineLosses = 3;

  /// Business codes that say the video is gone or hidden from the account.
  static const _unavailableCodes = {-404, -403, 62002, 62004, 62012};

  final _parts = <int, _Part>{};

  /// Parts being deleted, until their folders are gone; an enqueue of the same cid waits for it.
  final _deleting = <int, Future<void>>{};
  List<OfflineItem>? _sorted;
  int _concurrency = 1;
  bool _unseen = false;
  int? _free;
  bool _started = false;
  bool _disposed = false;

  /// Reading the folder at launch; changes wait for it.
  Future<void>? _loading;
  DateTime? _lastAdded;

  /// A network, disk or risk-control failure: waiting parts wait for a tap, 全部开始, the next return or launch.
  bool _held = false;

  bool _backgrounded = false;

  /// The host's background time is open ([OfflineHost.beginGrace]) …
  bool _graceOpen = false;

  /// … and the engine may download in it, until iOS says it ends.
  bool _graceRunning = false;
  bool _handedOff = false;
  Future<void> _lifecycle = Future.value();

  PlaybackEngine? _engine;
  Future<PlaybackEngine>? _leasing;
  StreamSubscription<DownloadEvent>? _events;
  int _engineLosses = 0;

  Future<void> _libraryWrites = Future.value();
  final _tasks = <Future<void>>{};
  DateTime? _notifiedAt;
  Timer? _notifyTimer;

  @override
  List<OfflineItem> get items =>
      _sorted ??= List.unmodifiable(<OfflineItem>[for (final part in _parts.values) part.item]..sort(_newestFirst));

  static int _newestFirst(OfflineItem a, OfflineItem b) => b.addedAt.compareTo(a.addedAt);

  @override
  OfflineItem? item(int cid) => _parts[cid]?.item;

  @override
  int get usedBytes => _parts.values.fold(0, (sum, part) => sum + part.item.bytes + part.extraBytes);

  @override
  int? get freeBytes => _free;

  @override
  int get concurrency => _concurrency;

  @override
  bool get unseen => _unseen;

  bool get _mayDownload => !_backgrounded || _graceRunning;

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      await Directory(folder).create(recursive: true);
    } catch (error) {
      logger.error(LogCategory.app, 'offline folder failed', {'error': _reason(error)});
      return;
    }
    try {
      await host.excludeFromBackup(folder);
    } catch (error) {
      logger.warn(LogCategory.app, 'offline backup exclusion failed', {'error': _reason(error)});
    }
    final loading = _loadLibrary().then((_) => _loadParts());
    _loading = loading;
    await loading;
    _sorted = null;
    _notifyNow();
    _track(refreshFreeSpace());
    // A launch iOS made in the background leaves the background session's transfers going until the app is opened.
    if (host.backgroundTransfers && await _launchedInBackground()) {
      _backgrounded = true;
      logger.info(LogCategory.app, 'offline launched in background');
      return;
    }
    await _queue(() => _comeBack(launch: true));
  }

  /// [start] runs before runApp, when Flutter may have no lifecycle state yet: iOS itself is asked then. A null state
  /// taken as the foreground would cancel the transfers iOS launched the app for.
  Future<bool> _launchedInBackground() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) return state != AppLifecycleState.resumed;
    final bool background;
    try {
      background = await host.inBackground();
    } catch (error) {
      logger.warn(LogCategory.app, 'offline app state unknown', {'error': _reason(error)});
      return false;
    }
    // Opened while iOS was asked: the resume went by unheard.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return false;
    return background;
  }

  Future<void> _loadLibrary() async {
    try {
      final json = jsonDecode(await File(files.library).readAsString());
      if (json is Map) {
        final concurrency = json['concurrency'];
        if (concurrency is int) _concurrency = concurrency.clamp(1, maxConcurrency);
        _unseen = json['unseen'] == true;
      }
    } on PathNotFoundException {
      // First launch.
    } catch (error) {
      logger.warn(LogCategory.app, 'offline library unreadable', {'error': _reason(error)});
    }
  }

  Future<void> _loadParts() async {
    final folders = <Directory>[];
    try {
      await for (final entity in Directory(folder).list(followLinks: false)) {
        if (entity is Directory) folders.add(entity);
      }
    } catch (error) {
      logger.error(LogCategory.app, 'offline folder unreadable', {'error': _reason(error)});
      return;
    }
    var unreadable = 0;
    for (final directory in folders) {
      final name = directory.uri.pathSegments.where((segment) => segment.isNotEmpty).lastOrNull ?? '';
      if (name.contains(OfflineFiles.deletedSuffix)) {
        unawaited(_remove(directory));
        continue;
      }
      final cid = int.tryParse(name);
      if (cid == null) continue;
      if (await File(files.deleting(cid)).exists()) {
        await _removeAtLaunch(cid, 'deleted');
        continue;
      }
      OfflineEntry? entry;
      var gone = false;
      try {
        entry = OfflineEntry.fromJson(jsonDecode(await File(files.entry(cid)).readAsString()), files);
        gone = entry == null || entry.cid != cid;
      } on PathNotFoundException {
        gone = true;
      } on FormatException {
        gone = true;
      } catch (error) {
        logger.warn(LogCategory.app, 'offline entry unreadable', {'cid': cid, 'error': _reason(error)});
      }
      if (gone) {
        // Nothing can show or resume it, so its files would only take the phone's space.
        await _removeAtLaunch(cid, 'unreadable');
        unreadable += 1;
        continue;
      }
      if (entry == null) {
        unreadable += 1;
        continue;
      }
      var item = entry.item;
      if (item.state == OfflineState.downloading) item = item.copyWith(state: OfflineState.waiting);
      if (!item.isDone) {
        final video = await trackBytes(files.video(cid));
        final audio = await trackBytes(files.audio(cid));
        final known = video.total > 0 && audio.total > 0;
        item = item.copyWith(bytes: video.bytes + audio.bytes, totalBytes: known ? video.total + audio.total : null);
      }
      final extra = await folderBytes(files.part(cid), skip: {OfflineFiles.videoName, OfflineFiles.audioName});
      _parts[cid] = _Part(entry.copyWith(item: item), extraBytes: extra);
      final last = _lastAdded;
      if (last == null || item.addedAt.isAfter(last)) _lastAdded = item.addedAt;
    }
    final counts = {for (final state in OfflineState.values) state.name: 0};
    for (final part in _parts.values) {
      counts.update(part.item.state.name, (count) => count + 1);
    }
    logger.info(LogCategory.app, 'offline library', {
      'parts': _parts.length,
      ...counts,
      'unreadable': unreadable,
      'concurrency': _concurrency,
    });
  }

  Future<void> _removeAtLaunch(int cid, String reason) async {
    final bytes = await folderBytes(files.part(cid));
    logger.warn(LogCategory.app, 'offline folder removed', {'cid': cid, 'reason': reason, 'bytes': bytes});
    await _remove(Directory(files.part(cid)));
  }

  @override
  Future<void> enqueue(List<OfflineRequest> parts, {int? quality}) async {
    await _loading;
    // A part being deleted lets go of its folder first, so the new one isn't removed with it.
    for (;;) {
      final deleting = [
        for (final request in parts) ?_deleting[request.cid],
      ];
      if (deleting.isEmpty) break;
      await Future.wait(deleting);
    }
    if (_disposed) return;
    final added = <_Part>[];
    for (final request in parts) {
      if (_parts.containsKey(request.cid)) continue;
      // At least a millisecond apart, so parts added together keep their order in the queue and the list.
      final now = _now();
      final last = _lastAdded;
      final addedAt = last != null && !now.isAfter(last) ? last.add(const Duration(milliseconds: 1)) : now;
      _lastAdded = addedAt;
      final item = OfflineItem(request: request, state: OfflineState.waiting, addedAt: addedAt);
      final part = _Part(OfflineEntry(item: item, ceiling: quality));
      _parts[request.cid] = part;
      added.add(part);
    }
    if (added.isEmpty) return;
    _sorted = null;
    _unseen = true;
    _held = false;
    await Future.wait([for (final part in added) _save(part)]);
    unawaited(_saveLibrary());
    logger.info(LogCategory.app, 'offline enqueued', {
      'parts': added.length,
      'ceiling': quality ?? 0,
      'cids': added.map((part) => part.cid).join(','),
    });
    _notifyNow();
    _track(_savePicturesOf(added));
    _pump();
  }

  Future<void> _savePicturesOf(List<_Part> parts) async {
    for (final part in parts) {
      if (!identical(_parts[part.cid], part)) continue;
      await _savePictures(part);
    }
  }

  @override
  void pause(int cid) {
    final part = _parts[cid];
    if (part == null || part.item.isDone || part.item.state == OfflineState.paused) return;
    _halt(part);
    _setItem(part, part.item.copyWith(state: OfflineState.paused, bps: 0, clearFailure: true));
    logger.info(LogCategory.app, 'offline paused', {'cid': cid});
    _pump();
  }

  @override
  void resume(int cid) {
    final part = _parts[cid];
    if (part == null) return;
    final state = part.item.state;
    if (state != OfflineState.paused && state != OfflineState.failed) return;
    // 视频已失效 offers no retry; asking playurl again would only hear the same.
    if (part.item.failure == OfflineFailure.unavailable) return;
    _held = false;
    part.strikes = 0;
    _setItem(part, part.item.copyWith(state: OfflineState.waiting, bps: 0, clearFailure: true));
    logger.info(LogCategory.app, 'offline resumed', {'cid': cid});
    _pump();
  }

  @override
  void pauseAll() {
    var paused = 0;
    for (final part in _parts.values) {
      final state = part.item.state;
      if (state != OfflineState.waiting && state != OfflineState.downloading) continue;
      _halt(part);
      _setItem(part, part.item.copyWith(state: OfflineState.paused, bps: 0, clearFailure: true), notify: false);
      paused += 1;
    }
    if (paused == 0) return;
    logger.info(LogCategory.app, 'offline paused all', {'parts': paused});
    _notifyNow();
  }

  @override
  void startAll() {
    var started = 0;
    for (final part in _parts.values) {
      final state = part.item.state;
      if (state != OfflineState.paused && state != OfflineState.failed) continue;
      part.strikes = 0;
      _setItem(part, part.item.copyWith(state: OfflineState.waiting, bps: 0, clearFailure: true), notify: false);
      started += 1;
    }
    _held = false;
    if (started > 0) logger.info(LogCategory.app, 'offline started all', {'parts': started});
    _notifyNow();
    _pump();
  }

  @override
  void setConcurrency(int count) {
    final clamped = count.clamp(1, maxConcurrency);
    if (clamped == _concurrency) return;
    _concurrency = clamped;
    unawaited(_saveLibrary());
    logger.info(LogCategory.app, 'offline concurrency', {'count': clamped});
    _notifyNow();
    _pump();
  }

  @override
  void markSeen() {
    if (!_unseen) return;
    _unseen = false;
    unawaited(_saveLibrary());
    _notifyNow();
  }

  @override
  Future<void> delete(Iterable<int> cids) async {
    await _loading;
    final removed = <_Part>[];
    final done = Completer<void>();
    for (final cid in cids.toSet()) {
      final part = _parts.remove(cid);
      if (part == null) continue;
      _halt(part);
      part.positionSave?.cancel();
      removed.add(part);
      _deleting[cid] = done.future;
    }
    if (removed.isEmpty) return;
    _sorted = null;
    _notifyNow();
    try {
      for (final part in removed) {
        await _deleteFiles(part);
      }
    } finally {
      for (final part in removed) {
        if (identical(_deleting[part.cid], done.future)) _deleting.remove(part.cid);
      }
      done.complete();
    }
    logger.info(LogCategory.app, 'offline deleted', {'parts': removed.length});
    unawaited(refreshFreeSpace());
    _pump();
  }

  Future<void> _deleteFiles(_Part part) async {
    // A run on its way stops at its next step; whatever it set going is stopped and written before the files go.
    await part.run;
    await part.renewal;
    await part.stopping;
    await part.writes;
    final directory = Directory(files.part(part.cid));
    if (!await directory.exists()) return;
    // The mark lets the next launch finish a removal that fails or is cut short here.
    var marked = false;
    try {
      await File(files.deleting(part.cid)).writeAsBytes(const [], flush: true);
      marked = true;
    } catch (error) {
      logger.warn(LogCategory.app, 'offline delete mark failed', {'cid': part.cid, 'error': _reason(error)});
    }
    try {
      // Renamed first, so a removal cut short leaves nothing that reads as a part at launch.
      final stamp = _now().millisecondsSinceEpoch;
      final doomed = await directory.rename('${directory.path}${OfflineFiles.deletedSuffix}-$stamp');
      await _remove(doomed);
    } catch (error) {
      logger.warn(LogCategory.app, 'offline delete failed', {
        'cid': part.cid,
        'error': _reason(error),
        'atLaunch': marked,
      });
      // Unmarked, it would come back at the next launch as if never deleted; it stays in the list instead.
      if (!marked && !_parts.containsKey(part.cid) && !_disposed) {
        final state = part.item.isDone ? OfflineState.done : OfflineState.paused;
        part.entry = part.entry.copyWith(item: part.item.copyWith(state: state, bps: 0));
        _parts[part.cid] = part;
        _sorted = null;
        unawaited(_save(part));
        _notifyNow();
      }
    }
  }

  Future<void> _remove(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } catch (error) {
      logger.warn(LogCategory.app, 'offline folder not removed', {'error': _reason(error)});
    }
  }

  @override
  void savePosition(int cid, double seconds) {
    final part = _parts[cid];
    if (part == null || part.item.position == seconds) return;
    _setItem(part, part.item.copyWith(position: seconds), save: false);
    part.positionSave?.cancel();
    part.positionSave = Timer(positionSaveDelay, () {
      part.positionSave = null;
      unawaited(_save(part));
    });
  }

  void _flushPositions() {
    for (final part in _parts.values) {
      if (part.positionSave == null) continue;
      part.positionSave!.cancel();
      part.positionSave = null;
      unawaited(_save(part));
    }
  }

  @override
  Future<OfflinePlayback?> playback(int cid) async {
    final part = _parts[cid];
    final video = part?.entry.video;
    final audio = part?.entry.audio;
    if (part == null || !part.item.isDone || video == null || audio == null) return null;
    final videoPath = files.video(cid);
    final audioPath = files.audio(cid);
    if (!await File(videoPath).exists() || !await File(audioPath).exists()) {
      logger.warn(LogCategory.app, 'offline files missing', {'cid': cid});
      return null;
    }
    final saved = part.entry.danmakuSaved;
    return OfflinePlayback(
      item: part.item,
      files: LocalPlaybackRequest(video: video, audio: audio, videoPath: videoPath, audioPath: audioPath),
      danmakuFolder: saved > 0 ? files.danmakuFolder(cid) : null,
      danmakuSegments: saved,
    );
  }

  @override
  Future<void> refreshFreeSpace() async {
    try {
      final free = await host.freeBytes();
      if (free == _free || _disposed) return;
      _free = free;
      _notifyNow();
    } catch (error) {
      logger.warn(LogCategory.app, 'offline free space failed', {'error': _reason(error)});
    }
  }

  void _pump() {
    if (!_started || _disposed || _held || !_mayDownload) return;
    var active = _parts.values.where((part) => part.item.state == OfflineState.downloading).length;
    if (active >= _concurrency) return;
    final waiting = _parts.values.where((part) => part.item.state == OfflineState.waiting).toList()
      ..sort((a, b) => a.item.addedAt.compareTo(b.item.addedAt));
    for (final part in waiting) {
      if (active >= _concurrency) break;
      active += 1;
      _setItem(part, part.item.copyWith(state: OfflineState.downloading, bps: 0, clearFailure: true));
      _launch(part);
    }
  }

  void _launch(_Part part) {
    if (part.preparing == part.epoch || part.running) return;
    final run = _run(part);
    part.run = run;
    _track(run);
  }

  /// Takes a downloading part to the engine: its pictures, its streams (asked again when the addresses are close to
  /// their deadline), its danmaku, then the download. Stops quietly once the part is paused, deleted or failed.
  Future<void> _run(_Part part) async {
    final epoch = part.epoch;
    bool live() => _isLive(part, epoch);
    part.preparing = epoch;
    try {
      await _savePictures(part);
      if (!live()) return;
      var choice = part.choice;
      if (choice == null || _nearDeadline(choice, urlMargin)) {
        final streams = await _askStreams(part, epoch);
        if (streams == null || !live()) return;
        await _useStreams(part, streams);
        choice = streams.choice;
        if (!live()) return;
      }
      await part.stopping;
      // Left the foreground meanwhile: the return starts it.
      if (!live() || !_mayDownload) return;
      final engine = await _engineLease();
      if (!live()) return;
      await _startEngine(part, epoch, engine, choice);
      if (!live()) return;
      part.running = true;
      _scheduleRefresh(part);
      logger.info(LogCategory.app, 'offline download started', {
        'cid': part.cid,
        'quality': choice.video.id,
        'codecs': choice.video.codecs,
        'audio': choice.audio.id,
        'resumed': part.item.bytes > 0,
      });
      _saveDanmakuAlongside(part);
    } catch (error) {
      _runFailed(part, epoch, error);
    } finally {
      if (part.preparing == epoch) part.preparing = null;
    }
  }

  /// Starts the engine's download for the run of [epoch]. Should the run be over by the time the engine answers, the
  /// download is stopped, unless a newer run asked for it meanwhile: the engine took that ask as already running.
  Future<void> _startEngine(_Part part, int epoch, PlaybackEngine engine, TrackChoice choice) async {
    part.engineEpoch = epoch;
    part.progressBase = null;
    await engine.startDownload(_request(part, choice));
    if (_isLive(part, epoch) || part.engineEpoch != epoch) return;
    part.stopping = _stopQuietly(engine, part.cid);
  }

  bool _isLive(_Part part, int epoch) =>
      !_disposed &&
      identical(_parts[part.cid], part) &&
      part.epoch == epoch &&
      part.item.state == OfflineState.downloading;

  void _runFailed(_Part part, int epoch, Object error) {
    if (error is RipperError && error.kind == RipperErrorKind.closed) {
      _dropEngine(_engine);
      _relaunchLater([part]);
      return;
    }
    _fail(part, epoch, _failureOf(error), error);
  }

  void _halt(_Part part) {
    part.epoch += 1;
    part.refresh?.cancel();
    part.refresh = null;
    part.bytesBeforeHandOff = null;
    final engine = _engine;
    if (part.running && engine != null) part.stopping = _stopQuietly(engine, part.cid);
    part.running = false;
  }

  Future<void> _stopQuietly(PlaybackEngine engine, int cid) async {
    try {
      await engine.stopDownload('$cid');
    } catch (error) {
      logger.warn(LogCategory.app, 'offline stop failed', {'cid': cid, 'error': _reason(error)});
    }
  }

  void _fail(_Part part, int epoch, OfflineFailure failure, Object error) {
    if (!identical(_parts[part.cid], part) || part.epoch != epoch || part.item.state != OfflineState.downloading) {
      return;
    }
    _halt(part);
    _setItem(part, part.item.copyWith(state: OfflineState.failed, failure: failure, bps: 0));
    logger.warn(LogCategory.app, 'offline failed', {'cid': part.cid, 'failure': failure.name, 'error': _reason(error)});
    if (failure == OfflineFailure.network || failure == OfflineFailure.disk) _held = true;
    _pump();
    _maybeEndGrace();
  }

  static OfflineFailure _failureOf(Object error) => switch (error) {
    BiliAPIError(:final code) when _unavailableCodes.contains(code) => OfflineFailure.unavailable,
    BiliNotDashError() => OfflineFailure.unavailable,
    BiliNetworkError() || BiliHTTPError() || TimeoutException() || SocketException() => OfflineFailure.network,
    BiliAPIError(code: -352 || -412) => OfflineFailure.network,
    FileSystemException(:final osError?) when _isDiskFull(osError) => OfflineFailure.disk,
    _ => OfflineFailure.unknown,
  };

  /// ENOSPC on iOS, ERROR_DISK_FULL and ERROR_HANDLE_DISK_FULL on Windows.
  static bool _isDiskFull(OSError error) => const {28, 112, 39}.contains(error.errorCode);

  static bool _retryable(Object error) => switch (error) {
    BiliNetworkError() || TimeoutException() || SocketException() => true,
    BiliHTTPError(:final status) => status >= 500,
    _ => false,
  };

  /// playurl, then the streams to download: the ones already begun when the answer still has them (same quality and
  /// codecs), otherwise the best the phone plays. Null once the part has failed for it.
  Future<_Streams?> _askStreams(_Part part, int epoch) async {
    final request = part.item.request;
    final PlayURLInfo info;
    try {
      info = await _playUrl(part, epoch);
    } catch (error) {
      if (_failureOf(error) != OfflineFailure.unavailable) rethrow;
      _fail(part, epoch, OfflineFailure.unavailable, error);
      return null;
    }
    if (!identical(_parts[part.cid], part)) return null;
    final dash = info.dash;
    if (dash == null) {
      _fail(part, epoch, OfflineFailure.unavailable, BiliError.notDash);
      return null;
    }
    final kept = _keptStreams(part.entry, dash, refused: (codecMemory ?? CodecMemory(logger: logger)).failedKinds);
    final choice = kept ?? _pick(dash, part.entry.ceiling);
    if (choice == null) {
      logger.warn(LogCategory.app, 'offline no track', {'cid': part.cid, ...PlaybackController.playURLSummary(info)});
      _fail(part, epoch, OfflineFailure.unknown, const PlaybackError(PlaybackErrorKind.noTrack));
      return null;
    }
    final changed = {
      if (part.entry.video == null || !_sameStream(part.entry.video!, choice.video)) TrackKind.video,
      if (part.entry.audio == null || !_sameStream(part.entry.audio!, choice.audio)) TrackKind.audio,
    };
    final name = info.qualityOptions.where((option) => option.id == choice.video.id).firstOrNull?.name;
    if (changed.isNotEmpty) {
      logger.info(LogCategory.app, 'offline streams', {
        'cid': part.cid,
        'quality': choice.video.id,
        'codecs': choice.video.codecs,
        'kbps': choice.video.bandwidth ~/ 1000,
        'audio': choice.audio.id,
        'ceiling': part.entry.ceiling ?? 0,
        'changed': changed.map((kind) => kind.name).join(','),
        'offered': info.acceptQuality.join(','),
      });
    }
    return (
      choice: choice,
      changed: changed,
      qualityName: name ?? QualityNames.full(qn: choice.video.id, serverText: null),
      duration: math.max(request.duration, dash.duration),
    );
  }

  Future<PlayURLInfo> _playUrl(_Part part, int epoch) async {
    final request = part.item.request;
    for (var attempt = 0; ; attempt++) {
      try {
        final bili = client();
        await bili.ensureRiskCookies();
        return await bili.playURL(bvid: request.bvid, cid: request.cid, quality: part.entry.ceiling ?? askQuality);
      } catch (error) {
        if (attempt >= retryGaps.length || !_retryable(error) || !identical(_parts[part.cid], part)) rethrow;
        logger.warn(LogCategory.app, 'offline playurl failed, retrying', {
          'cid': part.cid,
          'attempt': attempt,
          'error': _reason(error),
        });
        await Future<void>.delayed(retryGaps[attempt]);
        if (part.epoch != epoch) rethrow;
      }
    }
  }

  /// The streams the part began with, when the fresh answer still offers them and the phone still plays the codec.
  static TrackChoice? _keptStreams(OfflineEntry entry, Dash dash, {required Set<String> refused}) {
    final video = entry.video;
    final audio = entry.audio;
    if (video == null || audio == null) return null;
    // As PlaybackController.choose: once a codec is refused, unknown ones are too.
    final kind = TrackSelector.codecKind(video);
    if (refused.contains(kind) || (refused.isNotEmpty && kind == 'other')) return null;
    final freshVideo = dash.video.where((stream) => _sameStream(stream, video)).firstOrNull;
    final freshAudio = dash.audio.where((stream) => _sameStream(stream, audio)).firstOrNull;
    return freshVideo == null || freshAudio == null ? null : TrackChoice(video: freshVideo, audio: freshAudio);
  }

  static bool _sameStream(DashStream a, DashStream b) => a.id == b.id && a.codecs == b.codecs && a.codecid == b.codecid;

  /// The highest quality offered at or below [ceiling] (8K, 杜比视界, HDR and 4K first), in the first codec of the
  /// player's order this phone hasn't refused, with the best AAC.
  TrackChoice? _pick(Dash dash, int? ceiling) {
    final memory = codecMemory ?? CodecMemory(logger: logger);
    final order = memory.order(preferred: _preferredCodec());
    final quality = ceiling ?? askQuality;
    return PlaybackController.choose(dash, quality: quality, codecOrder: order, excluded: memory.failedKinds) ??
        TrackSelector.choose(dash, quality: quality, codecOrder: order);
  }

  /// Keeps [streams] as the part's: a track whose stream changed starts over from nothing.
  Future<void> _useStreams(_Part part, _Streams streams, {Set<TrackKind> restart = const {}}) async {
    final choice = streams.choice;
    part.choice = choice;
    part.duration = streams.duration;
    final dropped = {...streams.changed, ...restart};
    if (dropped.isEmpty) return;
    await part.stopping;
    for (final kind in dropped) {
      for (final path in files.trackFiles(part.cid, kind)) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (error) {
          logger.warn(LogCategory.app, 'offline track not cleared', {'cid': part.cid, 'error': _reason(error)});
        }
      }
    }
    final entry = part.entry;
    final video = dropped.contains(TrackKind.video);
    final audio = dropped.contains(TrackKind.audio);
    part.entry = entry.copyWith(
      item: entry.item.copyWith(
        quality: choice.video.id,
        qualityName: video ? streams.qualityName : null,
        vipOnly: QualityRules.needsVip(choice.video.id),
        bytes: 0,
        totalBytes: 0,
      ),
      video: video ? choice.video.withoutAddresses() : null,
      audio: audio ? choice.audio.withoutAddresses() : null,
      videoTotal: video ? 0 : null,
      audioTotal: audio ? 0 : null,
    );
    _sorted = null;
    await _save(part);
    _notifyNow();
  }

  bool _nearDeadline(TrackChoice choice, Duration margin) {
    final deadline = PlaybackController.urlDeadline(choice.video);
    if (deadline == null) return false;
    return deadline - _now().millisecondsSinceEpoch / 1000 < margin.inSeconds;
  }

  void _scheduleRefresh(_Part part) {
    part.refresh?.cancel();
    part.refresh = null;
    final choice = part.choice;
    final deadline = choice == null ? null : PlaybackController.urlDeadline(choice.video);
    if (deadline == null) return;
    final seconds = deadline - _now().millisecondsSinceEpoch / 1000 - urlMargin.inSeconds;
    final wait = Duration(milliseconds: (math.max(60, seconds) * 1000).round());
    final epoch = part.epoch;
    part.refresh = Timer(wait, () {
      part.refresh = null;
      if (part.epoch == epoch && part.running) _startRenew(part, epoch);
    });
  }

  void _startRenew(_Part part, int epoch, {bool expired = false, Set<TrackKind> restart = const {}}) {
    final renewal = _renew(part, epoch, expired: expired, restart: restart);
    part.renewal = renewal;
    _track(renewal);
  }

  static bool _isRiskControl(Object error) => error is BiliAPIError && (error.code == -352 || error.code == -412);

  /// Fresh addresses for a part: swapped into its running download when the streams are the same, else the changed
  /// tracks start over. After [DownloadFailure.expired] the download is started again too ([expired]), and
  /// [restart] names a track that starts over whatever the answer ([DownloadFailure.sizeChanged]).
  Future<void> _renew(_Part part, int epoch, {bool expired = false, Set<TrackKind> restart = const {}}) async {
    bool live() => _isLive(part, epoch);
    if (!live()) return;
    // The return starts it again: meanwhile a restart could meet transfers still writing into its files.
    if (_handedOff || (_backgrounded && !_graceRunning)) return;
    if (_held) {
      // Held for a refusal or a failure: nothing asks Bilibili until a tap, 全部开始 or the return.
      if (expired) _fail(part, epoch, OfflineFailure.network, StateError('held'));
      return;
    }
    final _Streams? streams;
    try {
      streams = await _askStreams(part, epoch);
    } catch (error) {
      if (_isRiskControl(error)) {
        logger.warn(LogCategory.app, 'offline url refresh refused', {'cid': part.cid, 'error': _reason(error)});
        _held = true;
        if (expired) _runFailed(part, epoch, error);
        return;
      }
      if (!expired && live()) {
        // The running download's addresses still work until the deadline; the engine says when they don't.
        logger.warn(LogCategory.app, 'offline url refresh failed', {'cid': part.cid, 'error': _reason(error)});
        part.refresh = Timer(const Duration(minutes: 1), () {
          part.refresh = null;
          if (part.epoch == epoch && part.running) _startRenew(part, epoch);
        });
        return;
      }
      _runFailed(part, epoch, error);
      return;
    }
    if (streams == null || !live()) return;
    try {
      final engine = await _engineLease();
      final id = '${part.cid}';
      final choice = streams.choice;
      if (streams.changed.isEmpty && restart.isEmpty) {
        part.choice = choice;
        part.duration = streams.duration;
        // A refused download has already ended, and its start below carries these addresses: replacing them first would
        // only park them in the engine for whatever start of this id comes next.
        if (!expired) {
          await engine.replaceDownloadUrls(
            id,
            TrackKind.video,
            primary: choice.video.baseURL,
            backups: choice.video.backupURLs,
          );
          await engine.replaceDownloadUrls(
            id,
            TrackKind.audio,
            primary: choice.audio.baseURL,
            backups: choice.audio.backupURLs,
          );
        }
        logger.info(LogCategory.app, 'offline urls refreshed', {'cid': part.cid, 'expired': expired});
        if (!live()) return;
        if (expired) {
          // A download stopped by the refusal starts again; one the engine kept waiting is left as it is.
          await _startEngine(part, epoch, engine, choice);
          if (!live()) return;
        }
      } else {
        await engine.stopDownload(id);
        part.running = false;
        if (!live()) return;
        await _useStreams(part, streams, restart: restart);
        if (!live()) return;
        await _startEngine(part, epoch, engine, choice);
        if (!live()) return;
        logger.info(LogCategory.app, 'offline restarted', {
          'cid': part.cid,
          'tracks': {...streams.changed, ...restart}.map((kind) => kind.name).join(','),
        });
      }
      part.running = true;
      _scheduleRefresh(part);
    } catch (error) {
      _runFailed(part, epoch, error);
    }
  }

  DownloadRequest _request(_Part part, TrackChoice choice) {
    final cid = part.cid;
    return DownloadRequest(
      id: '$cid',
      video: DownloadTrack(
        primary: choice.video.baseURL,
        backups: choice.video.backupURLs,
        path: files.video(cid),
        totalSize: part.entry.videoTotal,
      ),
      audio: DownloadTrack(
        primary: choice.audio.baseURL,
        backups: choice.audio.backupURLs,
        path: files.audio(cid),
        totalSize: part.entry.audioTotal,
      ),
      mediaHeaders: BiliClient.mediaHeaders,
    );
  }

  /// The cover and the uploader's face, each once; a run and the enqueue's pass share one fetch.
  Future<void> _savePictures(_Part part) =>
      part.pictures ??= _fetchPictures(part).whenComplete(() => part.pictures = null);

  Future<void> _fetchPictures(_Part part) async {
    final cid = part.cid;
    final request = part.item.request;
    if (part.item.coverFile == null && request.cover.isNotEmpty) {
      final url = coverImageUrl(request.cover, width: 720, height: 405);
      if (await _savePicture(part, url, files.cover(cid), 'cover')) {
        _setItem(part, part.item.copyWith(coverFile: files.cover(cid)));
      }
    }
    if (part.item.faceFile == null && request.ownerFace.isNotEmpty) {
      final url = suffixedImageUrl(request.ownerFace, '@120w_120h_1c_90q.jpg');
      if (await _savePicture(part, url, files.face(cid), 'face')) {
        _setItem(part, part.item.copyWith(faceFile: files.face(cid)));
      }
    }
  }

  Future<bool> _savePicture(_Part part, String url, String path, String kind) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https')) return false;
    try {
      final bytes = await _pictures(uri);
      if (!identical(_parts[part.cid], part)) return false;
      final written = await _writeFile(part, path, bytes);
      if (written) part.extraBytes += bytes.length;
      return written;
    } catch (error) {
      logger.warn(LogCategory.app, 'offline picture failed', {'cid': part.cid, 'kind': kind, 'error': _reason(error)});
      return false;
    }
  }

  /// A long video's danmaku is dozens of paced calls (67 for 6.5 hours, ~50 s), so it is saved while the media
  /// downloads rather than before; one save per part at a time.
  void _saveDanmakuAlongside(_Part part) {
    if (part.danmaku != null || part.entry.danmakuComplete) return;
    final save = _saveDanmaku(part, () => identical(_parts[part.cid], part)).whenComplete(() => part.danmaku = null);
    part.danmaku = save;
    _track(save);
  }

  /// Every 6-minute segment not yet saved, one call at a time; a failed call leaves the rest for the next run.
  Future<void> _saveDanmaku(_Part part, bool Function() live) async {
    final cid = part.cid;
    final entry = part.entry;
    final duration = math.max(part.duration, entry.item.request.duration);
    final segments = entry.danmakuSegments > 0
        ? entry.danmakuSegments
        : math.max(1, (duration / danmakuSegmentSeconds).ceil());
    var saved = entry.danmakuSaved;
    if (saved >= segments) return;
    final from = saved;
    var first = true;
    while (saved < segments && live()) {
      if (!first) await Future<void>.delayed(danmakuGap);
      first = false;
      if (!live()) break;
      final index = saved + 1;
      try {
        final bytes = await client().danmakuSegmentData(cid: cid, index: index);
        if (!identical(_parts[cid], part)) return;
        if (!await _writeFile(part, files.danmaku(cid, index), bytes)) break;
        part.extraBytes += bytes.length;
        saved = index;
      } catch (error) {
        logger.warn(LogCategory.app, 'offline danmaku failed', {'cid': cid, 'index': index, 'error': _reason(error)});
        break;
      }
    }
    if (!identical(_parts[cid], part)) return;
    part.entry = part.entry.copyWith(danmakuSegments: segments, danmakuSaved: saved);
    await _save(part);
    logger.info(LogCategory.app, 'offline danmaku', {'cid': cid, 'segments': segments, 'saved': saved - from});
  }

  Future<PlaybackEngine> _engineLease() {
    final current = _engine;
    if (current != null) return Future.value(current);
    return _leasing ??= _lease();
  }

  Future<PlaybackEngine> _lease() async {
    try {
      final leased = await engine();
      _engine = leased;
      _events = leased.downloads.listen(
        _onEvent,
        onDone: () => _engineGone(leased),
        onError: (Object error) {
          logger.warn(LogCategory.app, 'offline events failed', {'error': _reason(error)});
        },
      );
      return leased;
    } finally {
      _leasing = null;
    }
  }

  void _dropEngine(PlaybackEngine? gone) {
    if (gone == null || !identical(_engine, gone)) return;
    _engine = null;
    unawaited(_events?.cancel());
    _events = null;
  }

  /// The engine's isolate ended: its downloads went with it, and start again on the next one.
  void _engineGone(PlaybackEngine gone) {
    if (!identical(_engine, gone)) return;
    _dropEngine(gone);
    final lost = [
      for (final part in _parts.values)
        if (part.running) part,
    ];
    for (final part in lost) {
      part.running = false;
      part.refresh?.cancel();
      part.refresh = null;
    }
    if (lost.isEmpty || _disposed) return;
    logger.warn(LogCategory.app, 'offline engine gone', {'parts': lost.length});
    _relaunchLater(lost);
  }

  void _relaunchLater(List<_Part> parts) {
    _engineLosses += 1;
    if (_engineLosses > _maxEngineLosses) {
      for (final part in parts) {
        _fail(part, part.epoch, OfflineFailure.unknown, const RipperError(RipperErrorKind.closed));
      }
      return;
    }
    final epochs = {for (final part in parts) part: part.epoch};
    Timer(retryGaps.firstOrNull ?? Duration.zero, () {
      for (final MapEntry(key: part, value: epoch) in epochs.entries) {
        if (_isLive(part, epoch) && _mayDownload) _launch(part);
      }
    });
  }

  void _onEvent(DownloadEvent event) {
    final cid = int.tryParse(event.id);
    final part = cid == null ? null : _parts[cid];
    if (part == null || part.item.state != OfflineState.downloading) return;
    switch (event) {
      case DownloadProgress():
        _progress(part, event);
      case DownloadFinished():
        _finished(part, event);
      case DownloadFailed():
        _downloadFailed(part, event);
    }
  }

  void _progress(_Part part, DownloadProgress event) {
    // The engine reports once as it starts, before any byte: only bytes beyond that one are progress.
    final base = part.progressBase;
    if (base == null) {
      part.progressBase = event.bytes;
    } else if (event.bytes > base) {
      part.strikes = 0;
      _engineLosses = 0;
    }
    final known = event.videoTotal > 0 && event.audioTotal > 0;
    part.entry = part.entry.copyWith(
      item: part.item.copyWith(bytes: event.bytes, totalBytes: known ? event.total : null, bps: event.bps),
      videoTotal: event.videoTotal > 0 ? event.videoTotal : null,
      audioTotal: event.audioTotal > 0 ? event.audioTotal : null,
    );
    _sorted = null;
    final saved = part.savedAt;
    if (saved == null || _now().difference(saved) >= progressSaveInterval) unawaited(_save(part));
    _notifySoon();
  }

  void _finished(_Part part, DownloadFinished event) {
    final total = event.videoTotal + event.audioTotal;
    part.running = false;
    part.refresh?.cancel();
    part.refresh = null;
    part.choice = null;
    part.strikes = 0;
    part.entry = part.entry.copyWith(videoTotal: event.videoTotal, audioTotal: event.audioTotal);
    _setItem(
      part,
      part.item.copyWith(state: OfflineState.done, bytes: total, totalBytes: total, bps: 0, clearFailure: true),
    );
    _unseen = true;
    unawaited(_saveLibrary());
    logger.info(LogCategory.app, 'offline finished', {
      'cid': part.cid,
      'quality': part.item.quality,
      'mb': (total / (1 << 20)).round(),
      'danmaku': part.entry.danmakuComplete,
    });
    // One more go at what failed alongside the media.
    _saveDanmakuAlongside(part);
    unawaited(refreshFreeSpace());
    _pump();
    _maybeEndGrace();
  }

  void _downloadFailed(_Part part, DownloadFailed event) {
    final epoch = part.epoch;
    part.running = false;
    part.refresh?.cancel();
    part.refresh = null;
    logger.warn(LogCategory.app, 'offline download failed', {
      'cid': part.cid,
      'failure': event.failure.name,
      'track': event.track?.name ?? '',
      'detail': event.detail,
      'osError': ?event.osError,
      'strikes': part.strikes,
    });
    switch (event.failure) {
      case DownloadFailure.expired || DownloadFailure.sizeChanged:
        part.strikes += 1;
        if (part.strikes > maxStrikes) {
          // One video's refused streams say nothing about the others, so this doesn't hold the queue as network does.
          _fail(part, epoch, OfflineFailure.unknown, StateError(event.failure.name));
          return;
        }
        final track = event.track;
        final restart = event.failure == DownloadFailure.sizeChanged
            ? (track == null ? {...TrackKind.values} : {track})
            : const <TrackKind>{};
        final pause = retryGaps.isEmpty ? Duration.zero : retryGaps[math.min(part.strikes, retryGaps.length) - 1];
        part.refresh = Timer(pause, () {
          part.refresh = null;
          if (_isLive(part, epoch)) _startRenew(part, epoch, expired: true, restart: restart);
        });
      case DownloadFailure.network:
        _fail(part, epoch, OfflineFailure.network, StateError('network'));
      case DownloadFailure.disk:
        _fail(part, epoch, OfflineFailure.disk, StateError('disk'));
      case DownloadFailure.file:
        _fail(part, epoch, OfflineFailure.unknown, StateError('file ${event.osError ?? ''}'.trim()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // iOS treats a transfer started from the background as discretionary (it waits for power and Wi-Fi, often for
      // hours), so the hand-off starts as the app begins to leave, while it is still in the foreground. Control
      // Center and the app switcher pass through here too; their return takes the transfers back.
      case AppLifecycleState.inactive when host.backgroundTransfers:
        _beginLeaving();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _beginLeaving();
      case AppLifecycleState.resumed:
        if (!_backgrounded) return;
        _backgrounded = false;
        _graceRunning = false;
        unawaited(_queue(_comeBack));
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  void _beginLeaving() {
    if (_backgrounded || !_started) return;
    _backgrounded = true;
    unawaited(_queue(_leave));
  }

  Future<void> _queue(Future<void> Function() step) {
    final next = _lifecycle.then((_) => step()).catchError((Object error, StackTrace stack) {
      logger.error(LogCategory.app, 'offline lifecycle failed', {'error': _reason(error)});
    });
    _lifecycle = next;
    _track(next);
    return next;
  }

  /// Leaving the foreground with parts downloading: iOS's background transfers take over what the engine still
  /// lacks, or, without them, the engine goes on in the time iOS gives until it says the time is up.
  Future<void> _leave() async {
    _flushPositions();
    if (!_backgrounded) return;
    final active = [
      for (final part in _parts.values)
        if (part.item.state == OfflineState.downloading) part,
    ];
    if (active.isEmpty) return;
    try {
      await host.beginGrace();
      _graceOpen = true;
      _graceRunning = _backgrounded;
    } catch (error) {
      logger.warn(LogCategory.app, 'offline grace refused', {'error': _reason(error)});
    }
    if (!host.backgroundTransfers) {
      logger.info(LogCategory.app, 'offline grace', {'parts': active.length});
      return;
    }
    final leaving = Stopwatch()..start();
    final engine = _engine;
    final stopped = <_Part, DownloadGaps>{};
    Future<void> stop(_Part part, PlaybackEngine engine) async {
      part.running = false;
      part.refresh?.cancel();
      part.refresh = null;
      try {
        stopped[part] = await engine.stopDownload('${part.cid}');
      } catch (error) {
        logger.warn(LogCategory.app, 'offline stop failed', {'cid': part.cid, 'error': _reason(error)});
      }
    }

    if (engine != null) {
      await Future.wait([
        for (final part in active)
          if (part.running) stop(part, engine),
      ]);
    }
    final perPart = <List<BackgroundRange>>[];
    final handed = <_Part>{};
    for (final MapEntry(key: part, value: gaps) in stopped.entries) {
      final known = [if (gaps.videoTotal > 0) ...gaps.video, if (gaps.audioTotal > 0) ...gaps.audio];
      var choice = part.choice;
      if (known.isEmpty || choice == null) continue;
      if (_nearDeadline(choice, handOffMargin)) {
        try {
          final streams = await _askStreams(part, part.epoch);
          if (streams == null || streams.changed.isNotEmpty) continue;
          part.choice = choice = streams.choice;
        } catch (error) {
          logger.warn(LogCategory.app, 'offline hand-off urls failed', {'cid': part.cid, 'error': _reason(error)});
          continue;
        }
      }
      perPart.add(
        backgroundRanges(
          id: '${part.cid}',
          gaps: gaps,
          choice: choice,
          videoPath: files.video(part.cid),
          audioPath: files.audio(part.cid),
        ),
      );
      handed.add(part);
    }
    final ranges = roundRobin(perPart);
    if (ranges.isNotEmpty) {
      try {
        await host.handOff(ranges);
        final ms = leaving.elapsedMilliseconds;
        // True means the last transfers were queued from the background, where iOS may hold them back.
        final queuedLate = await host.inBackground().catchError((Object _) => false);
        _handedOff = true;
        for (final part in handed) {
          part.bytesBeforeHandOff = part.item.bytes;
          part.handedOffDone = 0;
          _setItem(part, part.item.copyWith(bps: 0), save: false);
        }
        logger.info(LogCategory.app, 'offline handed off', {
          'parts': handed.length,
          'ranges': ranges.length,
          'mb': (ranges.fold(0, (sum, range) => sum + range.end - range.start + 1) / (1 << 20)).round(),
          'ms': ms,
          'late': queuedLate,
        });
      } catch (error) {
        logger.warn(LogCategory.app, 'offline hand-off failed', {'error': _reason(error)});
        handed.clear();
      }
    }
    // What wasn't handed off at all (sizes not known yet, finished, a refusal) goes on in the engine for as long as
    // iOS gives. A part with one track handed off waits for the return: the engine would write over the transfers.
    final leftover = [
      for (final part in stopped.keys)
        if (!handed.contains(part)) part,
    ];
    for (final part in leftover) {
      if (_isLive(part, part.epoch) && _mayDownload) _launch(part);
    }
    _maybeEndGrace();
  }

  /// iOS's time is nearly up: the engine stops (its writes flushed) and the time is given back.
  void _graceEnding() {
    _graceRunning = false;
    unawaited(
      _queue(() async {
        if (!_backgrounded) return;
        final engine = _engine;
        var stopped = 0;
        for (final part in _parts.values) {
          if (!part.running || engine == null) continue;
          part.running = false;
          part.refresh?.cancel();
          part.refresh = null;
          await _stopQuietly(engine, part.cid);
          stopped += 1;
        }
        logger.info(LogCategory.app, 'offline grace ended', {'stopped': stopped});
        await _endGrace();
      }),
    );
  }

  void _maybeEndGrace() {
    if (!_backgrounded || !_graceOpen) return;
    final busy = _parts.values.any((part) => part.running || part.preparing != null || part.refresh != null);
    if (!busy) unawaited(_queue(_endGrace));
  }

  Future<void> _endGrace() async {
    if (!_graceOpen) return;
    _graceOpen = false;
    _graceRunning = false;
    try {
      await host.endGrace();
    } catch (error) {
      logger.warn(LogCategory.app, 'offline grace not ended', {'error': _reason(error)});
    }
  }

  /// Back in the foreground (or launched): what the background session still had queued is cancelled, and every
  /// downloading part starts again in the engine, which first takes in what the transfers wrote.
  Future<void> _comeBack({bool launch = false}) async {
    if (_backgrounded) return;
    await _endGrace();
    var results = const <BackgroundRangeResult>[];
    if (host.backgroundTransfers) {
      try {
        results = await host.takeBack();
      } catch (error) {
        logger.warn(LogCategory.app, 'offline take back failed', {'error': _reason(error)});
      }
    }
    if (results.isNotEmpty || _handedOff) {
      final done = results.where((result) => result.done).toList();
      final failed = results.where((result) => !result.done && result.status != 0).toList();
      // What iOS had fetched of the ranges it didn't finish: whether it ran them at all while the app was away.
      final partial = results.where((result) => !result.done && result.received > 0).toList();
      logger.info(LogCategory.app, 'offline taken back', {
        'ranges': results.length,
        'done': done.length,
        'failed': failed.length,
        'cancelled': results.length - done.length - failed.length,
        'mb': (done.fold(0, (sum, result) => sum + result.end - result.start + 1) / (1 << 20)).round(),
        'started': partial.length,
        'partialMb': (partial.fold(0, (sum, result) => sum + result.received) / (1 << 20)).round(),
        'statuses': {for (final result in failed) result.status}.join(','),
        'launch': launch,
      });
    }
    _handedOff = false;
    _held = false;
    for (final part in _parts.values) {
      part.bytesBeforeHandOff = null;
      if (part.item.state == OfflineState.downloading && !part.running) _launch(part);
    }
    _pump();
    unawaited(refreshFreeSpace());
  }

  /// A background transfer finished while the app was alive in the background: the part's bytes move on.
  void _rangeFinished(BackgroundRangeResult result) {
    final cid = int.tryParse(result.id);
    final part = cid == null ? null : _parts[cid];
    final before = part?.bytesBeforeHandOff;
    if (part == null || before == null || !result.done) return;
    part.handedOffDone += result.end - result.start + 1;
    final bytes = before + part.handedOffDone;
    final total = part.item.totalBytes;
    _setItem(part, part.item.copyWith(bytes: total > 0 ? math.min(bytes, total) : bytes), save: false);
  }

  void _setItem(_Part part, OfflineItem item, {bool save = true, bool notify = true}) {
    part.entry = part.entry.copyWith(item: item);
    _sorted = null;
    if (save) unawaited(_save(part));
    if (notify) _notifyNow();
  }

  /// The part's `entry.json` as it is now; writes of one part go one after another.
  Future<void> _save(_Part part) {
    part.savedAt = _now();
    final json = part.entry.toJson();
    final path = files.entry(part.cid);
    return _partWrite(part, () async {
      await Directory(files.part(part.cid)).create(recursive: true);
      await writeJsonAtomically(path, json);
    });
  }

  Future<bool> _writeFile(_Part part, String path, List<int> bytes) async {
    var written = false;
    await _partWrite(part, () async {
      await File(path).parent.create(recursive: true);
      await writeAtomically(path, bytes);
      written = true;
    });
    return written;
  }

  Future<void> _partWrite(_Part part, Future<void> Function() write) {
    final next = part.writes.then((_) async {
      if (!identical(_parts[part.cid], part)) return;
      try {
        await write();
      } catch (error) {
        logger.warn(LogCategory.app, 'offline write failed', {'cid': part.cid, 'error': _reason(error)});
        if (error case FileSystemException(:final osError?) when _isDiskFull(osError)) _diskFull(part, error);
      }
    });
    part.writes = next;
    return next;
  }

  /// A part not yet finished stops as [OfflineFailure.disk], and the queue waits, as when the engine meets it.
  void _diskFull(_Part part, Object error) {
    final state = part.item.state;
    if (state != OfflineState.waiting && state != OfflineState.downloading) return;
    _halt(part);
    _setItem(part, part.item.copyWith(state: OfflineState.failed, failure: OfflineFailure.disk, bps: 0));
    logger.warn(LogCategory.app, 'offline failed', {'cid': part.cid, 'failure': 'disk', 'error': _reason(error)});
    _held = true;
    _maybeEndGrace();
  }

  Future<void> _saveLibrary() {
    final json = {'concurrency': _concurrency, 'unseen': _unseen};
    final next = _libraryWrites.then((_) async {
      try {
        await writeJsonAtomically(files.library, json);
      } catch (error) {
        logger.warn(LogCategory.app, 'offline library not saved', {'error': _reason(error)});
      }
    });
    _libraryWrites = next;
    return next;
  }

  void _notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _notifiedAt = _now();
    if (!_disposed) notifyListeners();
  }

  /// Progress reaches listeners at most about once a second, however many parts download.
  void _notifySoon() {
    if (_notifyTimer != null) return;
    final last = _notifiedAt;
    final since = last == null ? progressInterval : _now().difference(last);
    if (since >= progressInterval) {
      _notifyNow();
      return;
    }
    _notifyTimer = Timer(progressInterval - since, _notifyNow);
  }

  void _track(Future<void> work) {
    late final Future<void> tracked;
    tracked = work
        .catchError((Object error) {
          logger.error(LogCategory.app, 'offline task failed', {'error': _reason(error)});
        })
        .whenComplete(() => _tasks.remove(tracked));
    _tasks.add(tracked);
  }

  /// Runs [cid]'s address refresh now instead of near the deadline; for tests.
  @visibleForTesting
  Future<void> refreshUrls(int cid) async {
    final part = _parts[cid];
    if (part == null || !part.running) return;
    part.refresh?.cancel();
    part.refresh = null;
    _startRenew(part, part.epoch);
    await part.renewal;
  }

  /// Waits until nothing the library started is still running; for tests.
  @visibleForTesting
  Future<void> settled() async {
    for (var round = 0; round < 100; round++) {
      await Future<void>.delayed(Duration.zero);
      await Future.wait([
        ..._tasks,
        _lifecycle,
        _libraryWrites,
        ?_loading,
        for (final part in _parts.values) ...[part.writes, part.stopping],
      ]);
      await Future<void>.delayed(Duration.zero);
      if (_tasks.isEmpty) return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _notifyTimer?.cancel();
    for (final part in _parts.values) {
      part.refresh?.cancel();
      part.positionSave?.cancel();
    }
    unawaited(_events?.cancel());
    host.onGraceEnding = null;
    host.onRangeFinished = null;
    super.dispose();
  }

  static Future<Uint8List> _download(Uri url) => ImageDiskCache.download(url, null);

  static VideoCodec _playerCodec() => PlayerPrefs.shared.codec ?? VideoCodec.hevc;

  /// What failed, never a URL or a path: BiliError's text is its code, an OS error its reason.
  static String _reason(Object error) => switch (error) {
    BiliError() => '$error',
    FileSystemException(:final osError?) => osError.message,
    FileSystemException(:final message) => message,
    RipperError(:final kind) => 'engine ${kind.name}',
    PlaybackError(:final kind) => kind.name,
    PictureDownloadException(:final reason) => reason,
    NetworkImageLoadException(:final statusCode) => 'status $statusCode',
    StateError(:final message) => message,
    _ => '${error.runtimeType}',
  };
}

/// What [DiskOfflineLibrary._askStreams] found: the streams to download, which tracks differ from the ones begun, the
/// quality's name and the video's length in seconds.
typedef _Streams = ({TrackChoice choice, Set<TrackKind> changed, String qualityName, int duration});

final class _Part {
  _Part(this.entry, {this.extraBytes = 0});

  OfflineEntry entry;
  OfflineItem get item => entry.item;
  int get cid => entry.cid;

  /// Signed addresses, only ever in memory.
  TrackChoice? choice;
  int duration = 0;

  /// Bumped by every pause, delete and failure: work begun before stops at its next step.
  int epoch = 0;

  /// The epoch whose run is on its way to the engine.
  int? preparing;

  /// The engine holds its download.
  bool running = false;

  /// The epoch of the run that last asked the engine to start.
  int? engineEpoch;

  /// The bytes the engine reported as its download started; null until it does.
  int? progressBase;
  Future<void>? run;
  Future<void>? renewal;
  Future<void> stopping = Future.value();
  Future<void> writes = Future.value();
  Future<void>? pictures;
  Future<void>? danmaku;
  Timer? refresh;
  Timer? positionSave;
  DateTime? savedAt;

  /// Fresh addresses or restarted tracks since the last bytes fetched.
  int strikes = 0;

  /// Its cover, face, danmaku and entry.
  int extraBytes;

  /// While handed off: the bytes the engine had, and what the transfers finished since.
  int? bytesBeforeHandOff;
  int handedOffDone = 0;
}
