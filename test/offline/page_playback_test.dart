import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/offline/page/offline_page_body.dart' show offlinePageSize;
import 'package:bilifast/offline/page/offline_playback.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart' show LoopMode;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';

/// A finished part's local playback (158): engine.prepareLocal → player.load with no call to Bilibili, its failures
/// told plainly, its saved danmaku read from the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late FakeTimers timers;
  late PlaybackController controller;
  late FakeOfflineLibrary library;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    timers = FakeTimers();
    library = FakeOfflineLibrary.demo();
    final logger = Logger(session: 'test');
    controller = PlaybackController(
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger),
      engine: engine,
      player: player,
      clock: ManualClock(1000).clock,
      startTimer: timers.start,
      logger: logger,
    );
    addTearDown(controller.dispose);
  });

  Future<LocalVideo?> part(int cid) async {
    final files = await library.playback(cid);
    return files == null ? null : localVideoOf(files);
  }

  test('a cached part prepares locally from its start and never asks Bilibili', () async {
    await controller.openLocal(() => part(7003), start: 23);
    await settle();
    expect(engine.localPrepared.single.videoPath, 'offline/7003/v.m4s');
    expect(engine.prepared, isEmpty);
    expect(player.loaded?.startSeconds, 23);
    expect(player.loaded?.autoplay, isTrue);
    expect(player.loaded?.headers, isEmpty);
    expect(controller.activeMode, PlaybackMode.local);
    expect(controller.isLocal, isTrue);
    expect(controller.page?.cid, 7003);
    expect(controller.video?.title, '神枪看小羊崽复播：你看这次她真的自己打的，她表情会动');
    expect(controller.qualities.single.id, 80);
    expect(controller.selectedQuality, 80);
    expect(controller.videoSize, (width: 1920, height: 1080));

    player
      ..emit(const DurationChanged(383))
      ..emit(const StatusChanged(PlayerStatus.playing));
    await controller.setQuality(120);
    await controller.setCodec(VideoCodec.av1);
    await controller.setMode(PlaybackMode.direct);
    await settle();
    expect(engine.localPrepared, hasLength(1), reason: 'quality, codec and mode are the files\'');
    expect(engine.prepared, isEmpty);
    expect(timers.active, isEmpty, reason: 'no URL refresh');
    expect(http.requests, isEmpty);
  });

  test('a codec the player refuses fails once with its own words, no other codec tried', () async {
    await controller.openLocal(() => part(7003));
    await settle();
    player
      ..emit(const StatusChanged(PlayerStatus.playing))
      ..emit(const PlayerFailed('Cannot Decode', formatRejected: true));
    await settle();
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, PlaybackFailure.localUnplayable.userMessage);
    expect(engine.localPrepared, hasLength(1));
    expect(engine.prepared, isEmpty);
    expect(http.requests, isEmpty);
  });

  test('an init the engine finds unplayable fails at once', () async {
    engine.prepareErrors.add(const PlaybackError(PlaybackErrorKind.codecUnplayable, 'dvh1'));
    await controller.openLocal(() => part(7003));
    await settle();
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, PlaybackFailure.localUnplayable.userMessage);
    expect(engine.localPrepared, hasLength(1));
  });

  test('missing or broken files say so', () async {
    await controller.openLocal(() async => null);
    expect(controller.error, PlaybackFailure.localMissing.userMessage);

    engine.prepareErrors.add(const PlaybackError(PlaybackErrorKind.noSidx));
    await controller.openLocal(() => part(7003));
    await settle();
    expect(controller.error, PlaybackFailure.localMissing.userMessage);
    expect(http.requests, isEmpty);
  });

  test('a lost local server is prepared again once, then the playback fails', () async {
    await controller.openLocal(() => part(7003), start: 10);
    await settle();
    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const PlayerFailed('lost', domain: 'NSURLErrorDomain', code: -1004));
    await settle();
    expect(engine.localPrepared, hasLength(2));
    expect(engine.released, ['local1']);
    player
      ..emit(const StatusChanged(PlayerStatus.loading))
      ..emit(const StatusChanged(PlayerStatus.playing))
      ..emit(const PlayerFailed('lost', domain: 'NSURLErrorDomain', code: -1004));
    await settle();
    expect(engine.localPrepared, hasLength(2));
    expect(controller.phase, PlaybackPhase.failed);
    expect(http.requests, isEmpty);
  });

  test('an online open after a local one asks Bilibili again', () async {
    await controller.openLocal(() => part(7003));
    await settle();
    await controller.openVideo('BV1GJ411x7h7', cid: 137649199, start: 0);
    await settle();
    expect(controller.isLocal, isFalse);
    expect(engine.prepared, hasLength(1));
    expect(http.paths, contains('/x/player/wbi/playurl'));
  });

  test('where a part starts: its saved place, or 0 near the end', () {
    expect(offlineStart(library.item(7003)), 23);
    expect(offlineStart(library.item(7001)), 0);
    final near = library.item(7003)!.copyWith(position: 380);
    expect(offlineStart(near), 0);
    expect(offlineStart(null), 0);
  });

  test('sizes as the page writes them', () {
    expect(offlinePageSize(82208358), '78.4M');
    expect(offlinePageSize(78643200), '75.0M');
    expect(offlinePageSize(10066329), '9.6M');
    expect(offlinePageSize(1288490188), '1.2G');
  });

  group('danmaku', () {
    late Directory folder;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('offline-danmaku');
      addTearDown(() => folder.deleteSync(recursive: true));
    });

    test('come from the saved segments, never from Bilibili', () async {
      File('${folder.path}/1.so').writeAsBytesSync(danmakuSegmentBytes([(1000, '前方高能'), (2000, '来了')]));
      final feed = controller.danmaku;
      feed.loadLocal(cid: 7003, durationMs: 383000, folder: folder.path, segments: 1);
      feed.update(positionMs: 0, playing: true);
      await feed.settle();
      expect([for (final elem in feed.recent(360000)) elem.content], ['前方高能', '来了']);
      expect(http.requests, isEmpty);
    });

    test('a segment past the saved ones or gone holds nothing', () async {
      File('${folder.path}/1.so').writeAsBytesSync(danmakuSegmentBytes([(1000, '一')]));
      final feed = controller.danmaku;
      feed.loadLocal(cid: 7003, durationMs: 800000, folder: folder.path, segments: 2);
      feed.seeked(400000);
      feed.update(positionMs: 400000, playing: true);
      await feed.settle();
      expect(feed.closed, isFalse);
      expect(http.requests, isEmpty);
    });

    test('a part saved without danmaku plays without them, own sends still shown', () async {
      final feed = controller.danmaku;
      feed.loadLocal(cid: 7003, durationMs: 383000, folder: null, segments: 3);
      feed.update(positionMs: 0, playing: true);
      await feed.settle();
      expect(feed.timeline, isNull);
      feed.addOwn(
        const DanmakuDraft(
          cid: 7003,
          bvid: 'BV1fake00003',
          text: '我的',
          mode: 1,
          fontSize: 25,
          color: 0xFFFFFF,
          gradient: false,
          progressMs: 0,
        ),
        dmid: 9,
      );
      expect([for (final elem in feed.recent(1000)) elem.content], ['我的']);
      expect(http.requests, isEmpty);
    });

    test('the controller hands the part\'s folder to the feed', () async {
      File('${folder.path}/1.so').writeAsBytesSync(danmakuSegmentBytes([(1000, '弹')]));
      Future<LocalVideo?> withDanmaku() async {
        final files = (await library.playback(7003))!;
        return localVideoOf(
          OfflinePlayback(item: files.item, files: files.files, danmakuFolder: folder.path, danmakuSegments: 1),
        );
      }

      await controller.openLocal(withDanmaku);
      await settle();
      player.emit(const PositionChanged(seconds: 0.5, hostMs: 0, rate: 1));
      await controller.danmaku.settle();
      expect(controller.danmaku.cid, 7003);
      expect([for (final elem in controller.danmaku.recent(5000)) elem.content], ['弹']);
      expect(http.requests, isEmpty);
    });
  });

  group("an offline page's session", () {
    late List<String> opened;

    PagePlayerSession offlineSession({PlayerPrefs? prefs}) {
      opened = [];
      final session = PagePlayerSession(
        controller: controller,
        client: BiliClient(
          transport: http,
          cookies: CookieJar(Canned.cookies),
          logger: Logger(session: 'test'),
        ),
        open: (bvid, {cid}) => opened.add('$bvid $cid'),
        isVip: () => false,
        isLoggedIn: () => false,
        requestLogin: () {},
        prefs: prefs ?? PlayerPrefs.memory(),
        playlist: OfflinePlaylist(library),
        coverFile: (url) async => fail('an offline page asks for no picture'),
        startTimer: timers.start,
      );
      addTearDown(session.dispose);
      return session;
    }

    test('the lock screen shows the cached part: its title, uploader and saved cover; no 人像防挡 mask', () async {
      final cover = '${Directory.systemTemp.path}${Platform.pathSeparator}7003${Platform.pathSeparator}cover.jpg';
      library.put(library.item(7003)!.copyWith(coverFile: cover));
      final session = offlineSession();
      await controller.openLocal(() => part(7003));
      await settle();
      expect(player.nowPlaying, isNull, reason: 'not before it plays');
      player
        ..emit(const DurationChanged(383))
        ..emit(const StatusChanged(PlayerStatus.playing));
      await settle();
      expect(
        player.nowPlaying,
        NowPlayingInfo(
          title: '神枪看小羊崽复播：你看这次她真的自己打的，她表情会动',
          artist: '火播君',
          artworkPath: cover,
          hasPrevious: true,
          hasNext: true,
        ),
      );
      expect(session.danmakuMask.value, isNull);
      expect(http.requests, isEmpty);
    });

    test('后台听视频 and 后台连播 as online: nothing pauses in the background, and the next cached part opens', () async {
      final session = offlineSession();
      expect(player.calls, contains('background true'));
      await controller.openLocal(() => part(7003));
      await settle();
      player
        ..emit(const DurationChanged(383))
        ..emit(const StatusChanged(PlayerStatus.playing));
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(timers.activeWith(PagePlayerSession.backgroundGrace), isNull);
      player.emit(const StatusChanged(PlayerStatus.ended));
      await settle();
      expect(opened, ['BV1fake00002 7002']);
    });

    /// Cached parts in 离线缓存's order: 7003, 7002, then 7001.
    Future<void> endInBackground(PagePlayerSession session, int cid) async {
      await controller.openLocal(() => part(cid));
      await settle();
      player
        ..emit(const DurationChanged(100))
        ..emit(const StatusChanged(PlayerStatus.playing));
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      player.emit(const StatusChanged(PlayerStatus.ended));
      await settle();
    }

    test('in the background the last cached part ends: the end screen, nothing opens, no ⏭ on the lock screen',
        () async {
      final session = offlineSession();
      await endInBackground(session, 7001);
      expect(opened, isEmpty);
      expect(session.ended, isTrue);
      expect(player.nowPlaying?.hasNext, isFalse);
    });

    test('后台连播 goes to the next cached part with 自动连播 off, and 列表循环 wraps to the first', () async {
      final session = offlineSession(prefs: PlayerPrefs.memory()..autoplay = false);
      await endInBackground(session, 7003);
      expect(opened, ['BV1fake00002 7002']);
      session.dispose();

      final looping = offlineSession(prefs: PlayerPrefs.memory()..loop = LoopMode.list);
      await endInBackground(looping, 7001);
      expect(opened, ['BV1fake00003 7003']);
    });

    test('with 后台连播 off the part ends in the background, the next cached part not opened', () async {
      final session = offlineSession(prefs: PlayerPrefs.memory()..backgroundNext = false);
      await endInBackground(session, 7003);
      expect(opened, isEmpty);
      expect(session.ended, isTrue);
    });

    test("the lock screen's ◀◀ goes to the cached part before", () async {
      offlineSession();
      await controller.openLocal(() => part(7002));
      await settle();
      player
        ..emit(const DurationChanged(100))
        ..emit(const StatusChanged(PlayerStatus.playing));
      await settle();
      expect(player.nowPlaying, isNotNull);
      player.emit(const RemoteCommand(RemoteCommandKind.previous));
      await settle();
      expect(opened, ['BV1fake00003 7003']);
    });
  });

  test('DanmakuFeed.loadLocal with no folder asks nothing even when told it has segments', () async {
    final feed = DanmakuFeed(
      client: BiliClient(
        transport: http,
        cookies: CookieJar(Canned.cookies),
        logger: Logger(session: 'test'),
      ),
    );
    addTearDown(feed.dispose);
    feed.loadLocal(cid: 1, durationMs: 60000, folder: null, segments: 5);
    feed.update(positionMs: 0, playing: true);
    await feed.settle();
    expect(http.requests, isEmpty);
  });
}
