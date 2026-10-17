import 'danmaku_filter.dart';

/// Hands out each danmaku once as the playhead passes it. The player's time drives it, so a stall or
/// a seek never repeats or skips what was already shown.
final class DanmakuTimeline {
  static const int _maxStepMs = 1000;

  List<DisplayDanmaku> _items = [];
  int _last = -1;

  void add(List<DisplayDanmaku> items) {
    if (items.isEmpty) return;
    final all = [..._items, ...items];
    // The sort must be stable: danmaku at the same millisecond keep the order they arrived in.
    final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
    indexed.sort((a, b) {
      final byTime = a.$2.elem.progressMs.compareTo(b.$2.elem.progressMs);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    _items = [for (final entry in indexed) entry.$2];
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
