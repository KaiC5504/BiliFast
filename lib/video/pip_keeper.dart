import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

/// A video page's playback as the keeper sees it ([PagePlayback]).
abstract interface class KeptPlayback {
  /// The small window is playing its video.
  bool get pipActive;

  /// The video it plays, for the log.
  String get bvid;

  /// Its page left while the small window plays it: it goes on with no page, 自动连播 and 定时关闭 included.
  void keep();

  /// A page took it back.
  void returned();

  /// Stops and frees everything it holds.
  void close();

  /// Pushes a page around it on top of whatever the app shows; false when none can be pushed.
  bool pushPage();
}

/// Keeps a closed video page's playback alive while the small window plays it (port of PiPKeeper.swift): the restore
/// button pushes the page back on it, ✕ closes it, and another video starting releases it first. One per app, on
/// AppServices. It notifies when [showing] may have changed.
class PipKeeper with ChangeNotifier {
  PipKeeper({this._restoreGrace = const Duration(seconds: 1), Logger? logger}) : _logger = logger ?? Logger.shared;

  final Duration _restoreGrace;
  final Logger _logger;

  KeptPlayback? _kept;
  KeptPlayback? _restoring;
  KeptPlayback? _inPiP;
  Timer? _grace;

  /// The playback whose page left while the small window plays it.
  KeptPlayback? get kept => _kept;

  /// The kept playback the restore button asked for, until its page shows.
  KeptPlayback? get restoring => _restoring;

  /// A page's video is in the small window, or kept for it: 推荐's big card plays nothing meanwhile.
  bool get showing => _kept != null || _inPiP != null;

  /// A page left its stack: its playback is kept while the small window plays it, closed otherwise.
  void pageRemoved(KeptPlayback playback) {
    if (!playback.pipActive) {
      playback.close();
      return;
    }
    if (identical(_kept, playback)) return;
    release();
    _kept = playback;
    playback.keep();
    _logger.info(LogCategory.ui, 'pip kept', {'bvid': playback.bvid});
    notifyListeners();
  }

  /// Every page reports here when it shows; the answer is whether it may resume its own playback. The kept playback
  /// goes back to its page. A page that opens releases any other kept one first, before its own video loads. A page
  /// uncovered by going back leaves the small window playing and stays paused until it is played. Going back can show
  /// the page below before the popped page in the small window is reported removed, so the answer follows whichever
  /// playback is in the small window, kept yet or not.
  bool pageShown(KeptPlayback playback, {required bool opened}) {
    if (identical(_kept, playback)) {
      _kept = null;
      _restoring = null;
      _grace?.cancel();
      _grace = null;
      playback.returned();
      _logger.info(LogCategory.ui, 'pip restored', {'bvid': playback.bvid});
      notifyListeners();
      return true;
    }
    if (opened) {
      release();
      return true;
    }
    final inPiP = _inPiP;
    if (inPiP != null && !identical(inPiP, playback)) return false;
    return _kept == null;
  }

  /// Before a page plays: one video at a time.
  void willPlay(KeptPlayback playback) {
    final kept = _kept;
    if (kept == null || identical(kept, playback)) return;
    release();
  }

  /// The kept playback's restore button: a page around it goes on top. False when nothing will show it again.
  bool restore(KeptPlayback playback) {
    if (!identical(_kept, playback)) return false;
    if (!playback.pushPage()) return false;
    _restoring = playback;
    return true;
  }

  void pipStarted(KeptPlayback playback) {
    _inPiP = playback;
    notifyListeners();
  }

  void pipStopped(KeptPlayback playback) {
    if (identical(_inPiP, playback)) {
      _inPiP = null;
      notifyListeners();
    }
    if (!identical(_kept, playback)) return;
    if (!identical(_restoring, playback)) {
      release();
      return;
    }
    // A restore normally shows the page before the window has finished closing; this covers it arriving late, or
    // never.
    _grace?.cancel();
    _grace = Timer(_restoreGrace, () {
      _grace = null;
      if (identical(_kept, playback)) release();
    });
  }

  /// Stops and frees the kept playback.
  void release() {
    final playback = _kept;
    if (playback == null) return;
    _kept = null;
    _restoring = null;
    _grace?.cancel();
    _grace = null;
    if (identical(_inPiP, playback)) _inPiP = null;
    _logger.info(LogCategory.ui, 'pip released', {'bvid': playback.bvid});
    playback.close();
    notifyListeners();
  }
}
