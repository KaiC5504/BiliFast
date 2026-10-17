import 'danmaku_filter.dart';

/// Hands out each danmaku once as the playhead passes it. The player's time drives it, so a stall or
/// a seek never repeats or skips what was already shown.
final class DanmakuTimeline {
  static const int _maxStepMs = 1000;

  List<DisplayDanmaku> _items = [];
  int _last = -1;

  /// Merged into what is already there, so a segment costs its own length rather than a sort of everything.
  /// Danmaku at the same millisecond keep the order they arrived in.
  void add(List<DisplayDanmaku> items) {
    if (items.isEmpty) return;
    final incoming = _sorted(items);
    final existing = _items;
    final merged = <DisplayDanmaku>[];
    var i = 0;
    var j = 0;
    while (i < existing.length && j < incoming.length) {
      // Ties take the existing one first: it arrived earlier.
      if (incoming[j].elem.progressMs < existing[i].elem.progressMs) {
        merged.add(incoming[j++]);
      } else {
        merged.add(existing[i++]);
      }
    }
    merged
      ..addAll(existing.getRange(i, existing.length))
      ..addAll(incoming.getRange(j, incoming.length));
    _items = merged;
  }

  /// DanmakuFilter hands them out sorted already; anything else gets a stable sort.
  static List<DisplayDanmaku> _sorted(List<DisplayDanmaku> items) {
    var sorted = true;
    for (var i = 1; i < items.length && sorted; i++) {
      sorted = items[i].elem.progressMs >= items[i - 1].elem.progressMs;
    }
    if (sorted) return items;
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final byTime = a.$2.elem.progressMs.compareTo(b.$2.elem.progressMs);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  List<DisplayDanmaku> advance(int ms) {
    if (ms < _last || ms - _last > _maxStepMs) {
      seek(ms);
      return [];
    }
    final start = _firstIndexAfter(_last);
    var end = start;
    while (end < _items.length && _items[end].elem.progressMs <= ms) {
      end += 1;
    }
    _last = ms;
    return _items.sublist(start, end);
  }

  void seek(int ms) {
    _last = ms;
  }

  /// Index of the first item with `progressMs > ms`.
  int _firstIndexAfter(int ms) {
    var low = 0;
    var high = _items.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_items[mid].elem.progressMs <= ms) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
