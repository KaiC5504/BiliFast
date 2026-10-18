import 'package:bili_core/api.dart' show Chapter, QualityOption, VideoCard, VideoCodec, VideoPage, VideoView;
import 'package:bilifast/playback/overlay_stats.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/player_readout.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/foundation.dart';

import 'fake_player.dart';

/// A [PlayerSession] for widget tests: fields the test sets, and [calls] recording what the controls asked for.
/// Change a field, then [changed] to notify.
class FakePlayerSession extends ChangeNotifier implements PlayerSession {
  FakePlayerSession({FakePlayer? player, PlaybackClock? clock}) : player = player ?? FakePlayer(), clock = clock ?? PlaybackClock() {
    readout = PlayerReadout(clock: this.clock, events: this.player.events);
  }

  @override
  final FakePlayer player;

  @override
  final PlaybackClock clock;

  @override
  late final PlayerReadout readout;

  final List<String> calls = [];

  void changed() => notifyListeners();

  @override
  final ValueNotifier<double> duration = ValueNotifier(0);

  @override
  VideoView? video;

  @override
  VideoPage? part;

  @override
  String title = '';

  @override
  bool isVertical = false;

  @override
  List<Chapter> chapters = const [];

  @override
  List<VideoCard> related = const [];

  @override
  List<Episode> episodes = const [];

  @override
  bool episodesAreParts = true;

  @override
  Uri? shareLink;

  @override
  void togglePlay() => calls.add('togglePlay');

  @override
  final ValueNotifier<double?> scrubbing = ValueNotifier(null);

  @override
  double get position => scrubbing.value ?? readout.seconds.value;

  @override
  void scrub(double seconds) {
    calls.add('scrub $seconds');
    scrubbing.value = seconds;
  }

  @override
  void hint(double seconds) => calls.add('hint $seconds');

  @override
  void cancelScrub() {
    calls.add('cancelScrub');
    scrubbing.value = null;
  }

  @override
  Future<void> commitSeek(double seconds) async {
    calls.add('commitSeek $seconds');
    scrubbing.value = null;
  }

  @override
  double rate = 1;

  @override
  Future<void> setRate(double rate) async {
    calls.add('setRate $rate');
    this.rate = rate;
    notifyListeners();
  }

  @override
  bool speedingUp = false;

  @override
  void speedUp(bool on) {
    calls.add('speedUp $on');
    speedingUp = on;
    notifyListeners();
  }

  @override
  FitMode fit = FitMode.fit;

  @override
  Future<void> setFit(FitMode fit) async {
    calls.add('setFit ${fit.name}');
    this.fit = fit;
    notifyListeners();
  }

  @override
  bool mirrored = false;

  @override
  Future<void> setMirrored(bool on) async {
    calls.add('setMirrored $on');
    mirrored = on;
    notifyListeners();
  }

  @override
  LoopMode loop = LoopMode.off;

  @override
  void setLoop(LoopMode mode) {
    calls.add('setLoop ${mode.name}');
    loop = mode;
    notifyListeners();
  }

  @override
  bool autoplayNext = true;

  @override
  void setAutoplayNext(bool on) {
    calls.add('setAutoplayNext $on');
    autoplayNext = on;
    notifyListeners();
  }

  @override
  Duration? sleepTimer;

  @override
  final ValueNotifier<Duration?> sleepRemaining = ValueNotifier(null);

  @override
  void setSleepTimer(Duration? after) {
    calls.add('setSleepTimer ${after?.inMinutes}');
    sleepTimer = after;
    sleepRemaining.value = after;
    notifyListeners();
  }

  @override
  bool danmakuOn = true;

  @override
  void setDanmakuOn(bool on) {
    calls.add('setDanmakuOn $on');
    danmakuOn = on;
    notifyListeners();
  }

  @override
  bool showStats = false;

  @override
  void setShowStats(bool on) {
    calls.add('setShowStats $on');
    showStats = on;
    notifyListeners();
  }

  @override
  final ValueNotifier<OverlayStats> stats = ValueNotifier(const OverlayStats());

  @override
  bool btr = true;

  @override
  Future<void> setBtr(bool on) async {
    calls.add('setBtr $on');
    btr = on;
    notifyListeners();
  }

  @override
  List<QualityOption> qualities = const [];

  @override
  int quality = 80;

  @override
  String qualityName(int qn) => qualities.where((option) => option.id == qn).firstOrNull?.name ?? '$qn';

  @override
  bool isVip = false;

  @override
  Future<void> setQuality(int qn) async {
    calls.add('setQuality $qn');
    quality = qn;
    notifyListeners();
  }

  @override
  VideoCodec codec = VideoCodec.hevc;

  @override
  Future<void> setCodec(VideoCodec codec) async {
    calls.add('setCodec ${codec.name}');
    this.codec = codec;
    notifyListeners();
  }

  @override
  bool ended = false;

  @override
  Episode? next;

  @override
  Future<void> replay() async => calls.add('replay');

  @override
  void playEpisode(Episode episode) => calls.add('playEpisode ${episode.bvid} ${episode.cid}');

  @override
  void playRelated(VideoCard card) => calls.add('playRelated ${card.bvid}');

  String watchLaterToast = '已添加至稍后再看';

  @override
  Future<String> watchLater() async {
    calls.add('watchLater');
    return watchLaterToast;
  }

  @override
  bool pictureInPictureSupported = true;

  @override
  Future<void> startPictureInPicture() async => calls.add('startPictureInPicture');

  @override
  bool canCaptureFrame = true;

  String captureToast = '已保存到相册';

  @override
  Future<String> captureFrame() async {
    calls.add('captureFrame');
    return captureToast;
  }

  @override
  void dispose() {
    readout.dispose();
    duration.dispose();
    scrubbing.dispose();
    sleepRemaining.dispose();
    stats.dispose();
    super.dispose();
  }
}
