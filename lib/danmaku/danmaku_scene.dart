import 'dart:math' as math;
import 'dart:ui';

import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';

import '../shared/theme.dart';
import 'danmaku_sprites.dart';

/// What the danmaku are drawn with (BiliNative `DanmakuSettings.swift`); the 弹幕设置 panel comes in slice 5.
@immutable
final class DanmakuOptions {
  const DanmakuOptions({
    this.area = 0.5,
    this.opacity = 1,
    this.scale = 1,
    this.scrollDuration = 7,
    this.fullScreen = false,
  });

  /// Share of the video's height the lanes may use.
  final double area;
  final double opacity;
  final double scale;

  /// Seconds a scrolling danmaku takes to cross the screen.
  final double scrollDuration;
  final bool fullScreen;

  @override
  bool operator ==(Object other) =>
      other is DanmakuOptions &&
      other.area == area &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.scrollDuration == scrollDuration &&
      other.fullScreen == fullScreen;

  @override
  int get hashCode => Object.hash(area, opacity, scale, scrollDuration, fullScreen);
}

/// A danmaku on screen and where it is (tests).
final class DanmakuOnScreen {
  const DanmakuOnScreen({required this.text, required this.kind, required this.rect, required this.start});

  final String text;
  final LaneKind kind;
  final Rect rect;
  final double start;

  @override
  String toString() => 'DanmakuOnScreen("$text", ${kind.name}, $rect)';
}

final class _Item {
  _Item({
    required this.sprite,
    required this.text,
    required this.kind,
    required this.reverse,
    required this.start,
    required this.y,
    required this.x,
  });

  final DanmakuSprite sprite;
  final String text;
  final LaneKind kind;
  final bool reverse;

  /// Video time, in seconds, at which it entered.
  final double start;

  /// The centre of its lane.
  final double y;
  double x;
}

/// Port of DanmakuView.swift: which danmaku are on screen and where, for the video time each [step] is given.
/// The player's own clock drives it, so pausing, the rate, stalls and seeks carry over without any events.
final class DanmakuScene extends ChangeNotifier {
  DanmakuScene({DanmakuSprites? sprites}) : sprites = sprites ?? DanmakuSprites();

  static const staticDuration = 4.0;

  /// Text layouts one frame may do. A seek into a dense stretch can hand out hundreds of danmaku at once; the
  /// rest wait for the next frames, still placed where they would be by then.
  static const maxLayoutsPerFrame = 40;

  final DanmakuSprites sprites;

  /// The area the danmaku are laid out in; the layer sets it from its constraints.
  Size size = Size.zero;

  final LaneLayout _layout = LaneLayout(lanes: 0, width: 0, scrollDuration: 7);
  final List<_Item> _items = [];

  /// Handed out by the timeline, in time order, and not placed yet.
  final List<DisplayDanmaku> _backlog = [];
  Object? _geometry;
  int _lanes = 0;
  double _laneHeight = 0;
  double _basePointSize = BiliMetrics.danmakuFont;
  double _scrollDuration = 7;
  double? _lastTime;
  DanmakuTimeline? _timeline;

  /// Danmaku from a seek are still being laid out, so frames are needed even while the clock stands still.
  bool get catchingUp => _backlog.isNotEmpty;

  List<DanmakuOnScreen> get visible => [
    for (final item in _items)
      DanmakuOnScreen(
        text: item.text,
        kind: item.kind,
        rect: Rect.fromLTWH(
          item.x,
          item.y - item.sprite.size.height / 2,
          item.sprite.size.width,
          item.sprite.size.height,
        ),
        start: item.start,
      ),
  ];

  /// One frame at video time [seconds]. Listeners hear about it only when something on screen moved or changed.
  void step(double seconds, {required DanmakuTimeline timeline, DanmakuOptions options = const DanmakuOptions()}) {
    if (!seconds.isFinite || size.isEmpty) {
      _backlog.clear();
      return;
    }
    var time = math.max(seconds, 0.0);
    var relay = _lastTime == null;
    final geometry = (size, options.fullScreen, options.area, options.scale, options.scrollDuration);
    if (geometry != _geometry) {
      _geometry = geometry;
      _configure(options);
      relay = true;
    }
    final last = _lastTime;
    if (last != null) {
      if (time < last) {
        // The player's clock can step back by a hair; only a real jump is a seek.
        if (last - time < 0.2) {
          time = last;
        } else {
          relay = true;
        }
      } else if (time - last > 0.9) {
        // Under the timeline's 1 s jump limit, so a jump is always re-laid rather than skipped.
        relay = true;
      }
    }
    if (!identical(timeline, _timeline)) {
      _timeline = timeline;
      relay = true;
    }
    final ms = (time * 1000).floor();
    final hadItems = _items.isNotEmpty;
    if (relay) {
      _clear();
      _backlog.addAll(_catchUp(timeline, ms));
    } else {
      _backlog.addAll(timeline.advance(ms));
    }
    if (!relay && _backlog.isEmpty && time == _lastTime) return;
    _lastTime = time;
    _placeBacklog(time);
    _move(time);
    // An empty screen that stays empty needs no repaint.
    if (hadItems || _items.isNotEmpty) notifyListeners();
  }

  /// Takes everything off; the next [step] lays the screen out again.
  void reset() {
    _lastTime = null;
    _backlog.clear();
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  void paint(Canvas canvas) {
    // Top and bottom danmaku stay readable over the ones that were already passing when they appeared.
    for (final item in _items) {
      if (item.kind == LaneKind.scroll) _draw(canvas, item);
    }
    for (final item in _items) {
      if (item.kind != LaneKind.scroll) _draw(canvas, item);
    }
  }

  static void _draw(Canvas canvas, _Item item) {
    canvas
      ..save()
      ..translate(item.x, item.y - item.sprite.size.height / 2)
      ..drawPicture(item.sprite.picture)
      ..restore();
  }

  void _configure(DanmakuOptions options) {
    _scrollDuration = options.scrollDuration;
    _basePointSize =
        options.scale * (options.fullScreen ? BiliMetrics.danmakuFontFullScreen : BiliMetrics.danmakuFont);
    final lineHeight = sprites.lineHeight(_basePointSize);
    // Tiny fonts: the outline and own box padding must still fit, or neighbouring lanes would touch.
    _laneHeight = math.max(lineHeight * 1.2, lineHeight.ceilToDouble() + BiliMetrics.danmakuOwnPadY * 2);
    _lanes = _laneHeight > 0 ? math.max((size.height * options.area / _laneHeight).floor(), 0) : 0;
  }

  void _clear() {
    _items.clear();
    _backlog.clear();
    _layout.reset(lanes: _lanes, width: size.width, scrollDuration: _scrollDuration);
  }

  /// After a seek, what would still be on screen, each with its own start so it is placed mid-flight. The
  /// timeline counts any step over a second as a jump and hands out nothing, so it is walked in steps.
  List<DisplayDanmaku> _catchUp(DanmakuTimeline timeline, int ms) {
    final lookbackMs = (math.max(_scrollDuration, staticDuration) * 1000).round();
    var cursor = math.max(ms - lookbackMs, -1);
    timeline.seek(cursor);
    final items = <DisplayDanmaku>[];
    while (cursor < ms) {
      cursor = math.min(cursor + 1000, ms);
      items.addAll(timeline.advance(cursor));
    }
    return items;
  }

  void _placeBacklog(double time) {
    final budget = sprites.layouts + maxLayoutsPerFrame;
    var placed = 0;
    while (placed < _backlog.length && sprites.layouts < budget) {
      _place(_backlog[placed], time);
      placed += 1;
    }
    _backlog.removeRange(0, placed);
  }

  void _place(DisplayDanmaku danmaku, double time) {
    final elem = danmaku.elem;
    final start = elem.progressMs / 1000;
    final kind = switch (elem.mode) {
      4 => LaneKind.bottom,
      5 => LaneKind.top,
      _ => LaneKind.scroll,
    };
    // Re-laid after a seek: one that would already have left is not drawn at all.
    if (time - start >= (kind == LaneKind.scroll ? _scrollDuration : staticDuration)) return;
    // Most of a dense catch-up finds every lane taken; those are dropped before their text is laid out.
    if (!_layout.hasRoom(kind, at: start)) return;
    final fontSize = elem.fontSize > 0 ? elem.fontSize : 25;
    final sprite = sprites.of(danmaku, pointSize: _basePointSize * fontSize / 25);
    final width = sprite.size.width;
    int? placed;
    if (kind == LaneKind.scroll) {
      // LaneLayout keeps each kind to itself. A lane where this one would run into a top or bottom danmaku
      // still showing is left marked as taken, which keeps the next few off it as well, and the next lane
      // is tried.
      for (var attempt = 0; attempt <= _lanes; attempt++) {
        final lane = _layout.place(LaneKind.scroll, width: width, at: start);
        if (lane == null) break;
        if (!_runsIntoStatic(y: lane * _laneHeight + _laneHeight / 2, sprite: sprite.size, start: start)) {
          placed = lane;
          break;
        }
      }
    } else {
      placed = _layout.place(kind, width: width, at: start);
    }
    if (placed == null) return;
    final top = kind == LaneKind.bottom ? size.height - (_lanes - placed) * _laneHeight : placed * _laneHeight;
    _items.add(_Item(
      sprite: sprite,
      text: danmaku.text,
      kind: kind,
      reverse: elem.mode == 6,
      start: start,
      y: top + _laneHeight / 2,
      x: (size.width - width) / 2,
    ));
  }

  /// Whether a scrolling danmaku entering at [start] on row [y] reaches a centred top or bottom one on that
  /// row before it disappears.
  bool _runsIntoStatic({required double y, required Size sprite, required double start}) {
    final screen = size.width;
    final speed = (screen + sprite.width) / _scrollDuration;
    for (final item in _items) {
      if (item.kind == LaneKind.scroll) continue;
      if ((item.y - y).abs() >= (item.sprite.size.height + sprite.height) / 2) continue;
      final reaches = start + (screen - item.sprite.size.width) / 2 / speed;
      if (reaches < item.start + staticDuration) return true;
    }
    return false;
  }

  /// x = W - (t - start) × (W + w) / D for a scrolling danmaku, mirrored for reverse ones.
  void _move(double time) {
    final width = size.width;
    var index = 0;
    while (index < _items.length) {
      final item = _items[index];
      final age = time - item.start;
      final lifetime = item.kind == LaneKind.scroll ? _scrollDuration : staticDuration;
      // At exactly its lifetime a static danmaku's lane is already handed to the next one.
      if (age < 0 || age >= lifetime) {
        _items[index] = _items.last;
        _items.removeLast();
        continue;
      }
      if (item.kind == LaneKind.scroll) {
        final travelled = age / _scrollDuration * (width + item.sprite.size.width);
        item.x = item.reverse ? travelled - item.sprite.size.width : width - travelled;
      }
      index += 1;
    }
  }
}
