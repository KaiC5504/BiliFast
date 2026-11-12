import 'package:bili_core/api.dart' show BiliClientStory, BiliClientVideo, OfficialIdentity, VideoCard, VideoDetail;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

import '../../playback/playback_controller.dart';
import '../page_playback.dart';
import '../watch_reporter.dart';
import 'story_feed.dart';
import 'story_list.dart';

/// The app's 竖屏 feed for [playback]'s video: the official feed while the client holds an iPhone token and reports
/// are allowed (never in a `--fake-account` run), else the related lists.
StoryFeed pageStoryFeed(PagePlayback playback) {
  final environment = playback.environment;
  final client = environment.client;
  final official = client.appToken?.identity == OfficialIdentity.iphone && WatchReporter.canReport(environment);
  return StoryList(
    host: _PlaybackHost(playback),
    official: official ? client.storyFeed : null,
    related: (bvid) => client.related(bvid: bvid),
    // The signed view, as the open's own resolve asks it, so the answer stands in for that call.
    detail: (bvid) async {
      await client.ensureRiskCookies();
      return client.videoDetail(bvid: bvid);
    },
    // Windows' mpv reads the files through open-ended ranges that never meet a primed segment, and the PC is only a
    // check bench: the next video is loaded ahead on the phone alone.
    warmsNext: defaultTargetPlatform == TargetPlatform.iOS,
  );
}

/// The page's playback as the feed sees it, notifying on the playback's changes and its controller's (the details
/// arrive through the controller).
final class _PlaybackHost extends StoryHost {
  _PlaybackHost(this._playback) {
    _playback.addListener(_changed);
    _attach();
  }

  final PagePlayback _playback;
  PlaybackController? _controller;

  void _attach() {
    final controller = _playback.controller;
    if (controller == null || identical(controller, _controller)) return;
    _controller?.removeListener(_changed);
    _controller = controller..addListener(_changed);
  }

  void _changed() {
    _attach();
    notifyListeners();
  }

  @override
  String get bvid => _playback.bvid;

  @override
  StoryEntry? get playing => _playback.storyEntry;

  @override
  String? get framed {
    final controller = _playback.controller;
    return controller != null && controller.hasPlayed ? controller.video?.bvid : null;
  }

  @override
  List<VideoCard>? loadedRelated(String bvid) {
    final session = _playback.session;
    if (session == null || session.video?.bvid != bvid || session.related.isEmpty) return null;
    return session.related;
  }

  /// The official app reports a video swiped to as played on its own (auto_play 99), and the entered video swiped back
  /// to as it does when 竖屏 opens on it (0).
  @override
  void open(StoryEntry entry, {required bool entered, VideoDetail? detail}) =>
      _playback.openOnPage(entry.bvid, cid: entry.cid, followed: !entered, source: entry.source, detail: detail);

  @override
  bool get halted => _playback.storyHalted;

  @override
  void halt() => _playback.haltStory();

  @override
  bool get comfortable => _playback.controller?.comfortable ?? false;

  @override
  Future<void> warm(StoryEntry entry, VideoDetail detail) =>
      _playback.warmNext(entry.bvid, cid: entry.cid, detail: detail);

  @override
  void dropWarm() => _playback.dropWarm();

  @override
  void dispose() {
    _playback.removeListener(_changed);
    _controller?.removeListener(_changed);
    super.dispose();
  }
}
