import 'package:flutter/foundation.dart';

/// Every 关注 change that Bilibili accepted, wherever it was made, so the video page, the uploader sheet and any
/// space showing that uploader agree.
class FollowBook extends ChangeNotifier {
  ({int mid, bool following})? _last;

  /// The latest accepted change.
  ({int mid, bool following})? get last => _last;

  void changed(int mid, {required bool following}) {
    _last = (mid: mid, following: following);
    notifyListeners();
  }
}
