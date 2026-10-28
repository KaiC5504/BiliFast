import 'dart:math' as math;
import 'dart:ui';

import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';

import '../app/form_factor.dart';
import '../device/orientation.dart';
import '../shared/theme.dart';
import 'danmaku_sprites.dart';

/// What the danmaku are drawn with (BiliNative `DanmakuSettings.swift`); `DanmakuSettings.display` makes them from
/// the 弹幕设置 values.
@immutable
final class DanmakuOptions {
  const DanmakuOptions({
    this.area = 0.5,
    this.opacity = 1,
    this.scale = 1,
    this.scrollDuration = 7,
    this.presentation = Presentation.inline,
    this.formFactor = FormFactor.phone,
  });

  /// Share of the video's height the lanes may use.
  final double area;
  final double opacity;
  final double scale;

  /// Seconds a scrolling danmaku takes to cross the screen.
  final double scrollDuration;

  /// The player they fly over: the small player, landscape and 竖屏 each size them their own way.
  final Presentation presentation;

  /// The iPad sizes them its own way (`PadDanmakuTheme`).
  final FormFactor formFactor;

  bool get fullScreen => presentation.fullScreen;

  @override
  bool operator ==(Object other) =>
      other is DanmakuOptions &&
      other.area == area &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.scrollDuration == scrollDuration &&
      other.presentation == presentation &&
      other.formFactor == formFactor;

  @override
  int get hashCode => Object.hash(area, opacity, scale, scrollDuration, presentation, formFactor);
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
    required this.danmaku,
    required this.kind,
    required this.reverse,
    required this.start,
    required this.travel,
    required this.y,
    required this.x,
    this.gone = false,
  });

  final DanmakuSprite sprite;
  final DisplayDanmaku danmaku;
  final LaneKind kind;
  final bool reverse;

  /// Video time, in seconds, at which it entered.
  final double start;

  /// [start] on the travel clock, which scrolling danmaku move by.
  final double travel;

  /// The centre of its lane.
  final double y;
  double x;

  /// Left the screen before a re-lay; kept, undrawn, only while the re-lay places the danmaku that met it.
  final bool gone;

  String get text => danmaku.text;
}

/// The clock scrolling danmaku move by. It runs with the video at [reference]'s pace over the current crossing
/// time, so a 弹幕速度 change bends it from that moment on: what is flying carries on from where it is, faster or
/// slower, and the lanes, kept in travel time, stay right.
final class _Travel {
  /// Remembered long enough for a re-lay to place everything it looks back over the way it was placed.
  static const _memory = 30.0;

  double reference = 7;
  double current = 7;

  /// (video time, travel time, travel seconds per video second), oldest first.
  final List<(double, double, double)> _bends = [(0, 0, 1)];

  void reset(double time, double duration) {
    reference = duration;
    current = duration;
    _bends
      ..clear()
      ..add((time, time, 1));
  }

  void bend(double time, double duration) {
    final travel = at(time);
    current = duration;
    while (_bends.isNotEmpty && _bends.last.$1 >= time) {
      _bends.removeLast();
    }
    _bends.add((time, travel, reference / duration));
    while (_bends.length > 1 && _bends[1].$1 < time - _memory) {
      _bends.removeAt(0);
    }
  }

  double at(double time) {
    var bend = _bends.first;
    for (var i = 1; i < _bends.length && _bends[i].$1 <= time; i++) {
      bend = _bends[i];
    }
    return bend.$2 + (time - bend.$1) * bend.$3;
  }

  /// The longest crossing in the remembered stretch, in video seconds.
  double get longest {
    var slowest = _bends.first.$3;
    for (final bend in _bends) {
      slowest = math.min(slowest, bend.$3);
    }
    return reference / slowest;
  }
}

/// Port of DanmakuView.swift: which danmaku are on screen and where, for the video time each [step] is given.
/// The player's own clock drives it, so pausing, the rate, stalls and seeks carry over without any events.
///
/// The 弹幕设置 values apply mid-flight, where Swift clears the screen: 弹幕速度 bends the travel clock, and
/// 显示区域 and 字体大小 re-lay what is showing at once, from the danmaku of the last moments. A bigger 字体大小 can
/// leave fewer lanes than were showing; what does not fit flies on rows past the area until it leaves, rather than
/// vanishing, and nothing that was not showing appears.
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
  final _Travel _travel = _Travel();

  /// Handed out by the timeline, in time order, and not placed yet.
  final List<DisplayDanmaku> _backlog = [];

  /// While a 字体大小 re-lay runs: the danmaku that were showing and have no place yet.
  Set<DisplayDanmaku>? _keep;

  /// ...and those waiting in the backlog then, which may still take a lane if one is free. Anything else from
  /// before [_shownUntil] had its chance and was dropped.
  Set<DisplayDanmaku> _waiting = const {};
  double _shownUntil = 0;

  (Size, Presentation, double, double, FormFactor)? _geometry;
  int _lanes = 0;
  double _laneHeight = 0;
  double _basePointSize = BiliMetrics.danmakuFont;
  double? _lastTime;
  DanmakuTimeline? _timeline;

  /// Danmaku from a seek are still being laid out, so frames are needed even while the clock stands still.
  bool get catchingUp => _backlog.isNotEmpty || _keep != null;

  List<DanmakuOnScreen> get visible => [
    for (final item in _items)
      if (!item.gone)
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

  /// The height of one lane, in points (tests).
  double get laneHeight => _laneHeight;

  /// One frame at video time [seconds]. Listeners hear about it only when something on screen moved or changed.
  void step(double seconds, {required DanmakuTimeline timeline, DanmakuOptions options = const DanmakuOptions()}) {
    if (!seconds.isFinite || size.isEmpty) {
      _backlog.clear();
      return;
    }
    var time = math.max(seconds, 0.0);
    var jumped = _lastTime == null;
    final last = _lastTime;
    if (last != null) {
      if (time < last) {
        // The player's clock can step back by a hair; only a real jump is a seek.
        if (last - time < 0.2) {
          time = last;
        } else {
          jumped = true;
        }
      } else if (time - last > 0.9) {
        // Under the timeline's 1 s jump limit, so a jump is always re-laid rather than skipped.
        jumped = true;
      }
    }
    if (!identical(timeline, _timeline)) {
      _timeline = timeline;
      jumped = true;
    }
    if (jumped) {
      _travel.reset(time, options.scrollDuration);
    } else if (options.scrollDuration != _travel.current) {
      _travel.bend(time, options.scrollDuration);
    }
    var relay = jumped;
    var scaled = false;
    final geometry = (size, options.presentation, options.area, options.scale, options.formFactor);
    if (geometry != _geometry) {
      final old = _geometry;
      scaled = !jumped && old != null && old.$1 == size && old.$2 == options.presentation && old.$3 == options.area;
      _geometry = geometry;
      _configure(options);
      relay = true;
    }
    final ms = (time * 1000).floor();
    final hadItems = _items.isNotEmpty;
    if (relay) {
      if (scaled) {
        // One already running keeps its own idea of what was waiting.
        if (_keep == null) {
          _waiting = Set<DisplayDanmaku>.identity()..addAll(_backlog);
          _shownUntil = last ?? time;
        }
        _keep = Set<DisplayDanmaku>.identity()
          ..addAll(_keep ?? const [])
          ..addAll([for (final item in _items) if (!item.gone) item.danmaku]);
      } else {
        _keep = null;
      }
      _clear();
      _backlog.addAll(_catchUp(timeline, ms));
    } else {
      _backlog.addAll(timeline.advance(ms));
    }
    if (!relay && !catchingUp && time == _lastTime) return;
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
    _keep = null;
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  void paint(Canvas canvas) {
    // Top and bottom danmaku stay readable over the ones that were already passing when they appeared.
    for (final item in _items) {
      if (item.kind == LaneKind.scroll && !item.gone) _draw(canvas, item);
    }
    for (final item in _items) {
      if (item.kind != LaneKind.scroll && !item.gone) _draw(canvas, item);
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
    final vertical = options.presentation == Presentation.vertical;
    final pad = options.formFactor.isPad;
    _basePointSize =
        options.scale *
        switch (options.presentation) {
          Presentation.inline when pad =>
            PadDanmakuTheme.fontFullScreen * math.min(size.width / PadDanmakuTheme.fullScreenWidth, 1.0),
          Presentation.landscape when pad => PadDanmakuTheme.fontFullScreen,
          Presentation.inline => BiliMetrics.danmakuFont,
          Presentation.landscape => BiliMetrics.danmakuFontFullScreen,
          // The iPad has no 竖屏.
          Presentation.vertical => BiliMetrics.danmakuFontVertical,
        };
    // Tiny fonts: the outline and own box padding must still fit, or neighbouring lanes would touch. 竖屏's lanes are
    // tighter than PingFang's line (118), as the iPad's are (25), so there only the glyphs' em must.
    final fits = vertical || pad
        ? _basePointSize + (BiliMetrics.danmakuOutline + BiliMetrics.danmakuOwnPadY) * 2
        : sprites.lineHeight(_basePointSize).ceilToDouble() + BiliMetrics.danmakuOwnPadY * 2;
    _laneHeight = math.max(
      vertical ? options.scale * BiliMetrics.danmakuLaneVertical : _basePointSize * BiliMetrics.danmakuLaneHeight,
      fits,
    );
    _lanes = _laneHeight > 0 ? math.max((size.height * options.area / _laneHeight).floor(), 0) : 0;
  }

  void _clear() {
    _items.clear();
    _backlog.clear();
    _layout.reset(lanes: _lanes, width: size.width, scrollDuration: _travel.reference);
  }

  /// For a re-lay, the danmaku of the last moments, each placed with its own start so it shows mid-flight. Those
  /// that have left by now still take their lanes, as they did while showing, so a re-lay for 显示区域 keeps
  /// everything else in its lane. The timeline counts any step over a second as a jump and hands out nothing, so
  /// it is walked in steps.
  List<DisplayDanmaku> _catchUp(DanmakuTimeline timeline, int ms) {
    final lookbackMs = (math.max(_travel.longest, staticDuration) * 2000).round();
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
    final keep = _keep;
    if (keep == null || _backlog.isNotEmpty) return;
    final left = keep.toList()..sort((a, b) => a.elem.progressMs.compareTo(b.elem.progressMs));
    for (final danmaku in left) {
      if (sprites.layouts >= budget) break;
      _overflow(danmaku, time);
      keep.remove(danmaku);
    }
    if (keep.isEmpty) _keep = null;
  }

  static LaneKind _kindOf(DanmakuElem elem) => switch (elem.mode) {
    4 => LaneKind.bottom,
    5 => LaneKind.top,
    _ => LaneKind.scroll,
  };

  DanmakuSprite _spriteOf(DisplayDanmaku danmaku) {
    final fontSize = danmaku.elem.fontSize > 0 ? danmaku.elem.fontSize : 25;
    return sprites.of(danmaku, pointSize: _basePointSize * fontSize / 25);
  }

  bool _goneBy(double time, {required LaneKind kind, required double start, required double travel}) =>
      kind == LaneKind.scroll ? _travel.at(time) - travel >= _travel.reference : time - start >= staticDuration;

  void _place(DisplayDanmaku danmaku, double time) {
    final elem = danmaku.elem;
    final start = elem.progressMs / 1000;
    final kind = _kindOf(elem);
    final travel = _travel.at(start);
    final gone = _goneBy(time, kind: kind, start: start, travel: travel);
    final keep = _keep;
    if (keep != null) {
      if (gone) {
        keep.remove(danmaku);
      } else if (start <= _shownUntil && !keep.contains(danmaku) && !_waiting.contains(danmaku)) {
        return;
      }
    }
    final at = kind == LaneKind.scroll ? travel : start;
    // Most of a dense catch-up finds every lane taken; those are dropped before their text is laid out.
    if (!_layout.hasRoom(kind, at: at)) return;
    final sprite = _spriteOf(danmaku);
    final width = sprite.size.width;
    int? placed;
    if (kind == LaneKind.scroll) {
      // LaneLayout keeps each kind to itself. A lane where this one would run into a top or bottom danmaku
      // still showing is left marked as taken, which keeps the next few off it as well, and the next lane
      // is tried.
      for (var attempt = 0; attempt <= _lanes; attempt++) {
        final lane = _layout.place(LaneKind.scroll, width: width, at: at);
        if (lane == null) break;
        if (!_runsIntoStatic(y: lane * _laneHeight + _laneHeight / 2, sprite: sprite.size, travel: travel)) {
          placed = lane;
          break;
        }
      }
    } else {
      placed = _layout.place(kind, width: width, at: at);
    }
    // A scrolling one that has left needs nothing more than its lane; a static one stays, undrawn, for the
    // scrolling ones placed after it to keep clear of.
    if (placed == null || (gone && kind == LaneKind.scroll)) return;
    keep?.remove(danmaku);
    final top = kind == LaneKind.bottom ? size.height - (_lanes - placed) * _laneHeight : placed * _laneHeight;
    _items.add(_Item(
      sprite: sprite,
      danmaku: danmaku,
      kind: kind,
      reverse: elem.mode == 6,
      start: start,
      travel: travel,
      y: top + _laneHeight / 2,
      x: (size.width - width) / 2,
      gone: gone,
    ));
  }

  /// A danmaku that was showing before 字体大小 grew and has no lane now. It takes the first row past the area,
  /// counted from its own edge, where it meets nothing until it leaves; then a free row inside the area; on a
  /// screen too full for either, the row where it meets the fewest. LaneLayout never hands out the rows past the
  /// area, so what enters later keeps clear of it.
  void _overflow(DisplayDanmaku danmaku, double time) {
    final elem = danmaku.elem;
    final start = elem.progressMs / 1000;
    final kind = _kindOf(elem);
    final travel = _travel.at(start);
    if (_goneBy(time, kind: kind, start: start, travel: travel)) return;
    final sprite = _spriteOf(danmaku);
    final now = _travel.at(time);
    final rows = math.max((size.height / _laneHeight).floor(), 1);
    _Item? best;
    var fewest = 0;
    for (final row in [for (var r = _lanes; r < rows; r++) r, for (var r = 0; r < math.min(_lanes, rows); r++) r]) {
      final top = kind == LaneKind.bottom ? size.height - (row + 1) * _laneHeight : row * _laneHeight;
      final candidate = _Item(
        sprite: sprite,
        danmaku: danmaku,
        kind: kind,
        reverse: elem.mode == 6,
        start: start,
        travel: travel,
        y: top + _laneHeight / 2,
        x: (size.width - sprite.size.width) / 2,
      );
      var meets = 0;
      for (final item in _items) {
        if (!item.gone && _meet(candidate, item, now)) meets += 1;
      }
      if (best == null || meets < fewest) {
        best = candidate;
        fewest = meets;
      }
      if (meets == 0) break;
    }
    if (best != null) _items.add(best);
  }

  /// Whether two danmaku on overlapping rows touch between travel time [now] and when the first of them leaves.
  /// Each moves at a steady pace, so apart in the same order at both ends means apart throughout.
  bool _meet(_Item a, _Item b, double now) {
    if ((a.y - b.y).abs() >= (a.sprite.size.height + b.sprite.size.height) / 2) return false;
    final end = math.max(math.min(_endOf(a), _endOf(b)), now);
    if (_gap(a, b, now) > 0) return _gap(a, b, end) <= 0;
    if (_gap(b, a, now) > 0) return _gap(b, a, end) <= 0;
    return true;
  }

  /// How far [b]'s left edge is right of [a]'s right edge at travel time [at].
  double _gap(_Item a, _Item b, double at) => _xAt(b, at) - (_xAt(a, at) + a.sprite.size.width);

  double _xAt(_Item item, double at) {
    final width = item.sprite.size.width;
    if (item.kind != LaneKind.scroll) return (size.width - width) / 2;
    final travelled = (at - item.travel) / _travel.reference * (size.width + width);
    return item.reverse ? travelled - width : size.width - travelled;
  }

  /// When it leaves, on the travel clock.
  double _endOf(_Item item) =>
      item.kind == LaneKind.scroll ? item.travel + _travel.reference : _travel.at(item.start + staticDuration);

  /// Whether a scrolling danmaku entering at [travel] on row [y] reaches a centred top or bottom one on that row
  /// before it disappears.
  bool _runsIntoStatic({required double y, required Size sprite, required double travel}) {
    final screen = size.width;
    final speed = (screen + sprite.width) / _travel.reference;
    for (final item in _items) {
      if (item.kind == LaneKind.scroll) continue;
      if ((item.y - y).abs() >= (item.sprite.size.height + sprite.height) / 2) continue;
      final reaches = travel + (screen - item.sprite.size.width) / 2 / speed;
      if (reaches < _travel.at(item.start + staticDuration)) return true;
    }
    return false;
  }

  /// x = W - (t - start) × (W + w) / D for a scrolling danmaku on the travel clock, mirrored for reverse ones.
  void _move(double time) {
    final width = size.width;
    final travel = _travel.at(time);
    var index = 0;
    while (index < _items.length) {
      final item = _items[index];
      final scrolls = item.kind == LaneKind.scroll;
      final age = scrolls ? travel - item.travel : time - item.start;
      final lifetime = scrolls ? _travel.reference : staticDuration;
      // At exactly its lifetime a static danmaku's lane is already handed to the next one.
      if (item.gone ? _backlog.isEmpty : age < 0 || age >= lifetime) {
        _items[index] = _items.last;
        _items.removeLast();
        continue;
      }
      if (scrolls) {
        final travelled = age / _travel.reference * (width + item.sprite.size.width);
        item.x = item.reverse ? travelled - item.sprite.size.width : width - travelled;
      }
      index += 1;
    }
  }
}
