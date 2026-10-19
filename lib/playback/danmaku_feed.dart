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
  DanmakuFeed({required this._client, Logger? logger, this._options = const DanmakuFilterOptions()})
      : _logger = logger ?? Logger.shared;

  final BiliClient _client;
  final Logger _logger;
  DanmakuFilterOptions _options;
  List<BlockRule> _rules = const [];
  String? _ownHash;

  /// Bumped whenever the filter, the rules or the account change, so a segment filtered under older ones is
  /// filtered again.
  int _filterVersion = 0;

  int _cid = 0;
  int _durationMs = 0;
  int? _positionMs;

  /// Bumped by every load, so a segment for the previous video is dropped.
  int _loads = 0;

  /// Loaded, in flight or failed: `DanmakuSegments.needed` skips them.
  final Set<int> _attempted = {};
  final Set<int> _failed = {};
  final Map<int, Future<void>> _inFlight = {};

  /// The segments as they came, so a filter change can filter them again. The bytes rather than the decoded
  /// danmaku: bytes cross to an isolate as one copy, thousands of objects would be copied on the UI isolate.
  final Map<int, Uint8List> _data = {};
  final Map<int, _Shown> _shown = {};
  final List<DisplayDanmaku> _own = [];
  final List<DanmakuElem> _hidden = [];
  Future<void>? _refilterRun;
  bool _refilterAgain = false;

  int _lastSegment = 0;
  DanmakuTimeline? _timeline;
  bool _closed = false;
  bool _disposed = false;

  /// Null until the first segment arrives, and after the uploader closed danmaku. Replaced by a new one when what
  /// shows changes (the filter, an own danmaku, a hidden one), and the stage then lays the screen out again from
  /// the playhead, as Swift's rebuild does.
  DanmakuTimeline? get timeline => _timeline;

  /// The uploader closed danmaku for this video.
  bool get closed => _closed;

  int get cid => _cid;

  DanmakuFilterOptions get options => _options;

  /// Starts over for a new video; a cid of 0 means none.
  void load({required int cid, required int durationMs}) {
    _loads += 1;
    _cid = cid;
    _durationMs = durationMs;
    _positionMs = null;
    _attempted.clear();
    _failed.clear();
    _inFlight.clear();
    _data.clear();
    _shown.clear();
    _own.clear();
    _hidden.clear();
    _refilterRun = null;
    _refilterAgain = false;
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
    _positionMs = positionMs;
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
    _positionMs = ms;
    _lastSegment = DanmakuSegments.indexForMs(ms);
    _retryFailed();
  }

  /// The 弹幕设置 filter and the 屏蔽词 to apply; what is loaded already is filtered again, off the UI isolate.
  void setFilter(DanmakuFilterOptions options, List<BlockRule> rules) {
    if (options == _options && listEquals(rules, _rules)) return;
    _options = options;
    _rules = List.unmodifiable(rules);
    _filterChanged();
  }

  /// The signed-in account, whose own danmaku get the white box; 0 when logged out.
  set ownMid(int mid) {
    final hash = mid > 0 ? MidHash.of(mid) : null;
    if (hash == _ownHash) return;
    _ownHash = hash;
    _filterChanged();
  }

  /// A danmaku the user just sent, shown at once in its white box.
  void addOwn(DanmakuDraft draft, {required int dmid}) {
    if (_cid == 0 || _closed) return;
    // At the playhead rather than where the send began, as Swift's showOwn does, so it enters from the edge.
    final elem = DanmakuElem(
      id: dmid,
      idStr: dmid > 0 ? '$dmid' : '',
      progressMs: _positionMs ?? draft.progressMs,
      mode: draft.mode,
      fontSize: draft.fontSize,
      color: draft.color,
      midHash: _ownHash ?? '',
      content: draft.text,
      ctime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      colorful: draft.gradient ? 60001 : 0,
    );
    var at = _own.length;
    while (at > 0 && _own[at - 1].elem.progressMs > elem.progressMs) {
      at -= 1;
    }
    _own.insert(at, DisplayDanmaku(elem: elem, text: draft.text, isOwn: true));
    // A new timeline rather than an add: the timeline hands out nothing the playhead has passed, and the stage
    // lays a new one out from the playhead, paused or not.
    _rebuild();
  }

  /// 当前弹幕列表's 屏蔽弹幕: this danmaku goes, for this video.
  void hide(DanmakuElem elem) {
    if (_hidden.contains(elem)) return;
    _hidden.add(elem);
    if (_timeline != null) _rebuild();
  }

  /// 当前弹幕列表: the danmaku shown up to [ms], latest last, at most [limit].
  List<DanmakuElem> recent(int ms, {int limit = 100}) {
    if (limit <= 0 || _closed) return const [];
    final latestFirst = <DisplayDanmaku>[];
    // Segments cover consecutive stretches, so walking back from the latest stops once there are enough.
    for (final index in _shown.keys.toList()..sort((a, b) => b.compareTo(a))) {
      final items = _shown[index]!.items;
      for (var i = _upperBound(items, ms) - 1; i >= 0 && latestFirst.length < limit; i--) {
        if (!_isHidden(items[i].elem)) latestFirst.add(items[i]);
      }
      if (latestFirst.length >= limit) break;
    }
    final ordered = _stableByTime([
      ...latestFirst.reversed,
      for (final item in _own)
        if (item.elem.progressMs <= ms && !_isHidden(item.elem)) item,
    ]);
    return [for (final item in ordered.skip(ordered.length > limit ? ordered.length - limit : 0)) item.elem];
  }

  /// Waits for the segment requests in flight and any re-filter (tests).
  Future<void> settle() async {
    while (_inFlight.isNotEmpty || _refilterRun != null) {
      await Future.wait([..._inFlight.values, ?_refilterRun]);
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
      final version = _filterVersion;
      final segment = await _decode(data, index, _filter);
      if (load != _loads || _disposed) return;
      _received(segment, data, index, version);
    } catch (error) {
      if (load != _loads || _disposed) return;
      _logger.warn(LogCategory.api, 'danmaku segment failed', {'index': index, 'error': '$error'});
      _failed.add(index);
    }
  }

  _Filter get _filter => (options: _options, rules: _rules, ownHash: _ownHash);

  /// Static, so the isolate's closure captures only its arguments.
  static Future<_Segment> _decode(Uint8List data, int index, _Filter filter) => Isolate.run(() {
        final segment = BiliClientDanmaku.decodeDanmakuSegment(data, index: index);
        return (closed: segment.closed, count: segment.elems.length, items: _apply(segment.elems, filter));
      });

  static Future<Map<int, List<DisplayDanmaku>>> _refilterAll(Map<int, Uint8List> data, _Filter filter) =>
      Isolate.run(() => {
            for (final MapEntry(key: index, value: bytes) in data.entries)
              index: _apply(BiliClientDanmaku.decodeDanmakuSegment(bytes, index: index).elems, filter),
          });

  static List<DisplayDanmaku> _apply(List<DanmakuElem> elems, _Filter filter) =>
      DanmakuFilter.apply(elems, options: filter.options, rules: filter.rules, ownHash: filter.ownHash);

  void _received(_Segment segment, Uint8List data, int index, int version) {
    if (segment.closed) {
      _logger.info(LogCategory.player, 'danmaku closed by the uploader', {'cid': _cid});
      _closed = true;
      _timeline = null;
      _notify();
      return;
    }
    // DanmakuTimeline does not dedupe, so a segment must only ever be added once.
    if (_shown.containsKey(index)) return;
    final items = segment.items;
    _data[index] = data;
    _shown[index] = (version: version, items: items);
    _logger.info(LogCategory.player, 'danmaku segment', {'index': index, 'count': segment.count, 'shown': items.length});
    // Filtered under a filter that changed while it was on its way: shown as it is for now, and filtered again.
    if (version != _filterVersion) _refilter();
    final visible = _hidden.isEmpty ? items : [for (final item in items) if (!_isHidden(item.elem)) item];
    final timeline = _timeline;
    if (timeline != null) {
      timeline.add(visible);
      return;
    }
    _timeline = DanmakuTimeline()
      ..add(visible)
      ..add(_visibleOwn());
    _notify();
  }

  /// Own danmaku are added unfiltered, so only what came from the server needs filtering again.
  void _filterChanged() {
    _filterVersion += 1;
    if (_data.isNotEmpty) _refilter();
  }

  /// One re-filter at a time; a change while one runs asks for another once it is done.
  void _refilter() {
    if (_refilterRun != null) {
      _refilterAgain = true;
      return;
    }
    final load = _loads;
    final version = _filterVersion;
    late final Future<void> run;
    run = () async {
      try {
        final shown = await _refilterAll(Map.of(_data), _filter);
        if (load != _loads || _disposed) return;
        if (version == _filterVersion) {
          for (final MapEntry(key: index, value: items) in shown.entries) {
            _shown[index] = (version: version, items: items);
          }
        }
      } catch (error) {
        if (load != _loads || _disposed) return;
        _logger.warn(LogCategory.player, 'danmaku re-filter failed', {'error': '$error'});
      } finally {
        if (identical(_refilterRun, run)) _refilterRun = null;
      }
      if (load != _loads || _disposed) return;
      if (_refilterAgain || _shown.values.any((segment) => segment.version != _filterVersion)) {
        _refilterAgain = false;
        _refilter();
        if (version != _filterVersion) return;
      }
      if (!_closed) _rebuild();
    }();
    _refilterRun = run;
  }

  void _rebuild() {
    final timeline = DanmakuTimeline();
    for (final index in _shown.keys.toList()..sort()) {
      final items = _shown[index]!.items;
      timeline.add(_hidden.isEmpty ? items : [for (final item in items) if (!_isHidden(item.elem)) item]);
    }
    timeline.add(_visibleOwn());
    _timeline = timeline;
    _notify();
  }

  List<DisplayDanmaku> _visibleOwn() => [for (final item in _own) if (!_isHidden(item.elem)) item];

  bool _isHidden(DanmakuElem elem) => _hidden.isNotEmpty && _hidden.contains(elem);

  /// Index of the first item later than [ms].
  static int _upperBound(List<DisplayDanmaku> items, int ms) {
    var low = 0;
    var high = items.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (items[mid].elem.progressMs <= ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// List.sort isn't stable; ties keep their order.
  static List<DisplayDanmaku> _stableByTime(List<DisplayDanmaku> items) {
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final byTime = a.$2.elem.progressMs.compareTo(b.$2.elem.progressMs);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    return [for (final (_, item) in indexed) item];
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

typedef _Filter = ({DanmakuFilterOptions options, List<BlockRule> rules, String? ownHash});

typedef _Segment = ({bool closed, int count, List<DisplayDanmaku> items});

typedef _Shown = ({int version, List<DisplayDanmaku> items});
