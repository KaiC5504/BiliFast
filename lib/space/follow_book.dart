import 'package:flutter/foundation.dart';

/// Every 关注 change that Bilibili accepted, wherever it was made, so the video page, the uploader sheet and any
/// space showing that uploader agree.
class FollowBook extends ChangeNotifier {
  ({int mid, bool following})? _last;
  final _known = <int, bool>{};

  /// The latest accepted change.
  ({int mid, bool following})? get last => _last;

  /// [mid]'s 关注 as last changed this run, null if it wasn't; a view built after the change starts from this rather
  /// than the answer it was given before it.
  bool? following(int mid) => _known[mid];

  void changed(int mid, {required bool following}) {
    _last = (mid: mid, following: following);
    _known[mid] = following;
    notifyListeners();
  }

  /// Another account's 关注 aren't this one's.
  void clear() {
    if (_last == null) return;
    _last = null;
    _known.clear();
    notifyListeners();
  }
}
