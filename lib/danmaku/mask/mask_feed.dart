import 'dart:ui';

import 'package:bili_core/api.dart' show DanmakuMaskInfo;
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

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
    throw UnimplementedError();
