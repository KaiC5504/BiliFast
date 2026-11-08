import 'dart:ui';

import 'package:bili_core/api.dart' show DanmakuMaskInfo;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/mask/mask_feed.dart';
import 'package:flutter/foundation.dart';

/// A 人像防挡 feed a test fills by hand: [frames] answers [frameAt], and [land] changes it as frames arriving would.
final class FakeMaskFeed extends ChangeNotifier implements MaskFeed {
  FakeMaskFeed([this.info, this.fetch]);

  final DanmakuMaskInfo? info;
  final MaskFetch? fetch;

  MaskFrame? Function(double seconds) frames = (_) => null;

  /// Every [follow], in order.
  final followed = <double>[];

  /// Every [frameAt], in order.
  final asked = <double>[];
  bool disposed = false;

  bool get listened => hasListeners;

  void land(MaskFrame? Function(double seconds) next) {
    frames = next;
    notifyListeners();
  }

  @override
  MaskFrame? frameAt(double seconds) {
    asked.add(seconds);
    return frames(seconds);
  }

  @override
  void follow(double seconds) => followed.add(seconds);

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Makes [FakeMaskFeed]s for a session and keeps them, oldest first.
final class FakeMaskFeeds {
  final made = <FakeMaskFeed>[];

  MaskFeed call(DanmakuMaskInfo info, {required MaskFetch fetch, Logger? logger}) {
    final feed = FakeMaskFeed(info, fetch);
    made.add(feed);
    return feed;
  }
}

/// A frame of a [box] whose filled area is [allowed] (its viewBox units, y down).
MaskFrame maskFrame(Rect allowed, {Size box = const Size(160, 90)}) => (path: Path()..addRect(allowed), box: box);
