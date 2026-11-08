import 'dart:isolate';
import 'dart:ui';

import 'package:bili_core/api.dart' show DanmakuMaskInfo;
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'mask_svg.dart';

/// One mask frame ready to clip with: [path] in the mask's own box ([box], its SVG's viewBox size, y down, potrace's
/// flip already undone), filled where danmaku may draw.
typedef MaskFrame = ({Path path, Size box});

/// Reads bytes [start] to [end] (inclusive; null to the end) of the mask file at [url] (BiliClient.maskRange).
typedef MaskFetch = Future<Uint8List> Function(Uri url, {required int start, int? end});

/// 人像防挡's frames for one part, loaded around the playhead. It notifies when frames for the playhead arrive, so a
/// paused picture gets its mask too.
abstract interface class MaskFeed implements Listenable {
  /// The frame showing at [seconds] of the video (the playhead, not danmaku's pace), or null when none is loaded for
  /// that time; the danmaku then draw unclipped.
  MaskFrame? frameAt(double seconds);

  /// Loads what [seconds] needs (its segment and the next), dropping segments far from it; called as the playhead
  /// moves and after a seek.
  void follow(double seconds);

  void dispose();
}

/// A feed for [info]'s mask over [fetch]. The address in [info] is signed: never logged.
MaskFeed createMaskFeed(DanmakuMaskInfo info, {required MaskFetch fetch, Logger? logger}) =>
    WebMaskFeed(info, fetch: fetch, logger: logger);

/// [MaskFeed] over a `.webmask` file read by ranges: its head, then the playhead's segment, the next one at once
/// after a jump or in the playhead's segment's last [prefetchMs], and the previous one kept for a small seek back.
final class WebMaskFeed extends ChangeNotifier implements MaskFeed {
  WebMaskFeed(this._info, {required this._fetch, Logger? logger, this.retryDelay = const Duration(seconds: 5)})
    : _logger = logger ?? Logger.shared;

  static const maxFailures = 3;
  static const prefetchMs = 3000;

  final DanmakuMaskInfo _info;
  final MaskFetch _fetch;
  final Logger _logger;

  /// After a failure nothing is asked until a follow this long after it, so a dropped connection isn't spent at once.
  final Duration retryDelay;

  WebMaskIndex? _index;
  final Map<int, List<_Frame>> _loaded = {};
  int? _playheadMs;

  /// The playhead's segment at the last follow once the head is known; -1 before the first segment.
  int? _current;

  /// The segment the last jump (the first follow, a seek) landed in, whose next one is asked at once.
  int? _jumpedTo;

  Future<void>? _run;
  bool _busy = false;
  int _failures = 0;
  final _sinceFailure = Stopwatch();
  bool _disposed = false;

  /// The last frames handed out, so a repaint between mask frames doesn't build the path again.
  final List<(_Frame, MaskFrame)> _built = [];

  /// The segments held, in order (tests).
  @visibleForTesting
  List<int> get loadedSegments => _loaded.keys.toList()..sort();

  /// Waits until nothing is being read (tests).
  @visibleForTesting
  Future<void> settle() async {
    while (_busy) {
      await _run;
    }
  }

  @override
  MaskFrame? frameAt(double seconds) {
    final index = _index;
    if (_disposed || index == null || !seconds.isFinite) return null;
    final ms = seconds * 1000;
    final k = index.segmentAt(ms.floor());
    if (k == null) return null;
    final frames = _loaded[k];
    if (frames == null) return null;
    // A segment's first frame can come a little after its start; the one before it is still showing then.
    final frame = _lastAtOrBefore(frames, ms) ?? _loaded[k - 1]?.lastOrNull;
    return frame == null ? null : _maskOf(frame);
  }

  @override
  void follow(double seconds) {
    if (_disposed || !seconds.isFinite) return;
    _playheadMs = seconds <= 0 ? 0 : (seconds * 1000).floor();
    _place();
    _pump();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loaded.clear();
    _built.clear();
    super.dispose();
  }

  void _place() {
    final index = _index;
    final ms = _playheadMs;
    if (index == null || ms == null) return;
    final current = index.segmentAt(ms) ?? -1;
    final last = _current;
    if (last == null || (current != last && current != last + 1)) _jumpedTo = current;
    _current = current;
    _loaded.removeWhere((k, _) => !_keeps(k));
  }

  /// The previous segment, the playhead's and the next: at most three.
  bool _keeps(int k) {
    final current = _current;
    return current != null && k >= current - 1 && k <= current + 1;
  }

  List<int> _wanted() {
    final index = _index!;
    final current = _current!;
    final ms = _playheadMs!;
    final next = current + 1;
    return [
      if (current >= 0 && !_loaded.containsKey(current)) current,
      if (next < index.segments.length &&
          !_loaded.containsKey(next) &&
          (current < 0 || _jumpedTo == current || ms >= index.segments[next].startMs - prefetchMs))
        next,
    ];
  }

  void _pump() {
    if (_disposed || _busy || _playheadMs == null || _failures >= maxFailures) return;
    if (_failures > 0 && _sinceFailure.elapsed < retryDelay) return;
    final Future<void> Function() piece;
    if (_index == null) {
      piece = _readHead;
    } else {
      final wanted = _wanted();
      if (wanted.isEmpty) return;
      piece = () => _readSegment(wanted.first);
    }
    _busy = true;
    _run = () async {
      try {
        await piece();
      } catch (error) {
        if (!_disposed) _failed(error);
        // Asked again only by a later follow, never straight on.
        return;
      } finally {
        _busy = false;
      }
      _pump();
    }();
  }

  Future<void> _readHead() async {
    const prefix = WebMaskIndex.prefixLength;
    final first = await _fetch(_info.url, start: 0, end: prefix - 1);
    if (_disposed) return;
    if (first.length != prefix) throw const FormatException('short mask head');
    final length = WebMaskIndex.headerLengthOf(first);
    final rest = await _fetch(_info.url, start: prefix, end: length - 1);
    if (_disposed) return;
    if (rest.length != length - prefix) throw const FormatException('short mask head');
    _index = WebMaskIndex.parse(
      Uint8List(length)
        ..setAll(0, first)
        ..setAll(prefix, rest),
    );
    _place();
  }

  Future<void> _readSegment(int k) async {
    final (:start, :end) = _index!.rangeOf(k);
    final bytes = await _fetch(_info.url, start: start, end: end);
    if (_disposed || !_keeps(k)) return;
    if (end != null && bytes.length != end - start + 1) throw const FormatException('short mask segment');
    final decoded = await _decode(bytes);
    if (_disposed || !_keeps(k)) return;
    _loaded[k] = decoded.frames;
    _logger.info(LogCategory.player, 'danmaku mask segment', {
      'cid': _info.cid,
      'index': k,
      'frames': decoded.frames.length,
      'skipped': decoded.skipped,
    });
    if (k == _current) notifyListeners();
  }

  /// Static, so the isolate's closure captures only its arguments.
  static Future<_Decoded> _decode(Uint8List bytes) => Isolate.run(() {
    final shapes = <_Frame>[];
    var skipped = 0;
    for (final frame in decodeWebMaskSegment(bytes)) {
      try {
        shapes.add((ms: frame.ms, shape: MaskShape.parse(frame.svg)));
      } on FormatException {
        skipped += 1;
      }
    }
    return (frames: shapes, skipped: skipped);
  });

  void _failed(Object error) {
    _failures += 1;
    _sinceFailure
      ..reset()
      ..start();
    // The error's text can carry the signed address, so only its type is kept.
    _logger.warn(LogCategory.api, 'danmaku mask failed', {'cid': _info.cid, 'error': '${error.runtimeType}'});
    if (_failures >= maxFailures) _logger.info(LogCategory.player, 'danmaku mask given up', {'cid': _info.cid});
  }

  MaskFrame _maskOf(_Frame frame) {
    for (final (built, mask) in _built) {
      if (identical(built, frame)) return mask;
    }
    final mask = (path: frame.shape.toPath(), box: frame.shape.box);
    _built.insert(0, (frame, mask));
    if (_built.length > 2) _built.removeLast();
    return mask;
  }

  static _Frame? _lastAtOrBefore(List<_Frame> frames, double ms) {
    var low = 0;
    var high = frames.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (frames[mid].ms <= ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low == 0 ? null : frames[low - 1];
  }
}

typedef _Frame = ({int ms, MaskShape shape});

typedef _Decoded = ({List<_Frame> frames, int skipped});
