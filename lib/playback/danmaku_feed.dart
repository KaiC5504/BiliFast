import 'dart:async';
import 'dart:isolate';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

/// One video's danmaku (the fetching half of DanmakuController.swift): `seg.so` segments fetched as the
/// playhead reaches them, filtered, and added to one timeline that the player stage draws from. At most the
/// next segment is fetched ahead, and only while playing. A segment holds thousands of danmaku, so it is decoded
/// and filtered in a short-lived isolate rather than between frames.
class DanmakuFeed extends ChangeNotifier {
  DanmakuFeed({required this._client, Logger? logger, this.options = const DanmakuFilterOptions()})
      : _logger = logger ?? Logger.shared;

  final BiliClient _client;
  final Logger _logger;
  final DanmakuFilterOptions options;

  int _cid = 0;
  int _durationMs = 0;

  /// Bumped by every load, so a segment for the previous video is dropped.
  int _loads = 0;

  /// Loaded, in flight or failed: `DanmakuSegments.needed` skips them.
  final Set<int> _attempted = {};
  final Set<int> _failed = {};
  final Set<int> _added = {};
  final Map<int, Future<void>> _inFlight = {};
  int _lastSegment = 0;
  DanmakuTimeline? _timeline;
  bool _closed = false;
  bool _disposed = false;

  /// Null until the first segment arrives, and after the uploader closed danmaku.
  DanmakuTimeline? get timeline => _timeline;

  /// The uploader closed danmaku for this video.
  bool get closed => _closed;

  int get cid => _cid;

  /// Starts over for a new video; a cid of 0 means none.
  void load({required int cid, required int durationMs}) {
    _loads += 1;
    _cid = cid;
    _durationMs = durationMs;
    _attempted.clear();
    _failed.clear();
    _added.clear();
    _inFlight.clear();
    _lastSegment = 0;
    _timeline = null;
    _closed = false;
    _notify();
  }

  void clear() => load(cid: 0, durationMs: 0);

  /// The player's duration once it knows it; the view's page duration until then.
  set durationMs(int value) {
    if (value > 0) _durationMs = value;
  }

  /// Called as the playhead moves.
  void update({required int positionMs, required bool playing}) {
    if (_cid == 0 || _closed) return;
    final segment = DanmakuSegments.indexForMs(positionMs);
    if (segment != _lastSegment) {
      _lastSegment = segment;
      _retryFailed();
    }
    for (final index in DanmakuSegments.needed(atMs: positionMs, loaded: _attempted, durationMs: _durationMs)) {
      if (playing || index == segment) _fetch(index);
    }
  }

  void seeked(int ms) {
    _lastSegment = DanmakuSegments.indexForMs(ms);
    _retryFailed();
  }

  /// Waits for the segment requests in flight (tests).
  Future<void> settle() async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.values.toList());
    }
  }

  /// A failed segment is asked again only when the playhead enters another segment or seeks, never in a loop.
  void _retryFailed() {
    if (_failed.isEmpty) return;
    _attempted.removeAll(_failed);
    _failed.clear();
  }

  void _fetch(int index) {
    _attempted.add(index);
    final future = _run(index, _loads, _cid);
    _inFlight[index] = future;
    unawaited(future.whenComplete(() {
      if (identical(_inFlight[index], future)) _inFlight.remove(index);
    }));
  }

  Future<void> _run(int index, int load, int cid) async {
    try {
      final data = await _client.danmakuSegmentData(cid: cid, index: index);
      if (load != _loads || _disposed) return;
      final segment = await _decode(data, index, options);
      if (load != _loads || _disposed) return;
      _received(segment, index);
    } catch (error) {
      if (load != _loads || _disposed) return;
      _logger.warn(LogCategory.api, 'danmaku segment failed', {'index': index, 'error': '$error'});
      _failed.add(index);
    }
  }

  /// Static, so the isolate's closure captures only its arguments.
  static Future<_Segment> _decode(Uint8List data, int index, DanmakuFilterOptions options) => Isolate.run(() {
        final segment = BiliClientDanmaku.decodeDanmakuSegment(data, index: index);
        return (
          closed: segment.closed,
          count: segment.elems.length,
          items: DanmakuFilter.apply(segment.elems, options: options, rules: const []),
        );
      });

  void _received(_Segment segment, int index) {
    if (segment.closed) {
      _logger.info(LogCategory.player, 'danmaku closed by the uploader', {'cid': _cid});
      _closed = true;
      _timeline = null;
      _notify();
      return;
    }
    // DanmakuTimeline does not dedupe, so a segment must only ever be added once.
    if (!_added.add(index)) return;
    final items = segment.items;
    _logger.info(LogCategory.player, 'danmaku segment', {'index': index, 'count': segment.count, 'shown': items.length});
    final timeline = _timeline;
    if (timeline != null) {
      timeline.add(items);
      return;
    }
    _timeline = DanmakuTimeline()..add(items);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loads += 1;
    super.dispose();
  }
}

typedef _Segment = ({bool closed, int count, List<DisplayDanmaku> items});
