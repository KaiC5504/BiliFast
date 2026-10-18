import 'package:bili_core/api.dart' show Chapter, QualityOption, VideoCard, VideoCodec, VideoPage, VideoView;
import 'package:flutter/foundation.dart';

import '../playback/overlay_stats.dart';
import '../player/bili_player.dart';
import '../player/playback_clock.dart';
import '../player_ui/player_readout.dart';

enum LoopMode {
  single('单集循环'),
  list('列表循环'),
  off('不循环');

  const LoopMode(this.label);

  final String label;
}

/// A part of this video, or an episode of the 合集 section holding it: what 选集 lists and 自动连播 plays next.
@immutable
final class Episode {
  const Episode({required this.bvid, required this.cid, required this.title, required this.current});

  final String bvid;
  final int cid;
  final String title;

  /// The one playing.
  final bool current;

  @override
  bool operator ==(Object other) =>
      other is Episode && other.bvid == bvid && other.cid == cid && other.title == title && other.current == current;

  @override
  int get hashCode => Object.hash(bvid, cid, title, current);
}

/// What the player's controls, gestures and panels read and do, for the video page's one video (the player half of
/// BiliNative `VideoPageModel.swift`). It notifies on every change that isn't a listenable of its own.
abstract interface class PlayerSession implements Listenable {
  BiliPlayer get player;

  PlaybackClock get clock;

  PlayerReadout get readout;

  /// Seconds; 0 until the player reports it.
  ValueListenable<double> get duration;

  VideoView? get video;

  VideoPage? get part;

  /// The full-screen title: the part's name for a video in parts, otherwise the video's.
  String get title;

  bool get isVertical;

  /// 看点, empty without them.
  List<Chapter> get chapters;

  /// For the end screens; empty until loaded.
  List<VideoCard> get related;

  /// The parts when there are several, otherwise the 合集 section holding this video; empty without either.
  List<Episode> get episodes;

  bool get episodesAreParts;

  /// What 分享 hands the share sheet.
  Uri? get shareLink;

  void togglePlay();

  /// Where a bar drag or a sideways drag aims, null when none runs.
  ValueListenable<double?> get scrubbing;

  /// [scrubbing] while there is one, otherwise the playhead.
  double get position;

  void scrub(double seconds);

  /// The finger rests at [seconds] during a drag, so the engine can start loading there.
  void hint(double seconds);

  /// The drag ended without a seek.
  void cancelScrub();

  /// Seeks at the keyframe nearest [seconds] (not precise) and holds [scrubbing] there until the seek lands.
  Future<void> commitSeek(double seconds);

  /// The chosen speed; it stays for the next part.
  double get rate;

  Future<void> setRate(double rate);

  /// Hold to speed up: 2× while on, then back to [rate].
  void speedUp(bool on);

  bool get speedingUp;

  FitMode get fit;

  Future<void> setFit(FitMode fit);

  bool get mirrored;

  Future<void> setMirrored(bool on);

  LoopMode get loop;

  void setLoop(LoopMode mode);

  bool get autoplayNext;

  void setAutoplayNext(bool on);

  /// 定时关闭: how long it was set for, null when off.
  Duration? get sleepTimer;

  /// Counts down to the pause; null when off.
  ValueListenable<Duration?> get sleepRemaining;

  void setSleepTimer(Duration? after);

  bool get danmakuOn;

  void setDanmakuOn(bool on);

  /// The 测试 card's 显示统计.
  bool get showStats;

  void setShowStats(bool on);

  ValueListenable<OverlayStats> get stats;

  /// The 测试 card's BTR 加速.
  bool get btr;

  Future<void> setBtr(bool on);

  List<QualityOption> get qualities;

  /// The quality asked for.
  int get quality;

  String qualityName(int qn);

  /// Logged in with 大会员: 大会员 qualities play rather than toasting 开通大会员后可观看.
  bool get isVip;

  Future<void> setQuality(int qn);

  VideoCodec get codec;

  Future<void> setCodec(VideoCodec codec);

  /// The video played to its end and nothing plays next: the end screen's moment.
  bool get ended;

  /// What 自动连播 would play at the end.
  Episode? get next;

  Future<void> replay();

  void playEpisode(Episode episode);

  void playRelated(VideoCard card);

  /// 稍后再看; completes with the toast's text.
  Future<String> watchLater();

  bool get pictureInPictureSupported;

  Future<void> startPictureInPicture();

  bool get canCaptureFrame;

  /// The screenshot button; completes with the toast's text (已保存到相册 or 保存失败).
  Future<String> captureFrame();
}
