import 'dart:async';
import 'dart:convert';

import 'package:bili_core/api.dart' show Dash, DashStream, QualityOption, VideoDetail, VideoPage, VideoView;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ByteRange;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/phone_frame.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';
import '../../support/fake_player_session.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../landscape_chrome_test.dart' show DanmakuRig;

/// The panel layer over a page as KaiC's iPhone has it (440×956, the player under the 62 pt status bar), with the
/// services 缓存 reaches: [library] as 离线缓存, no network anywhere.
final class SheetRig {
  SheetRig(this.session, this.ui, this.library, this.orientation);

  final FakePlayerSession session;
  final PlayerUi ui;
  final FakeOfflineLibrary library;
  final OrientationController orientation;

  PanelController get panels => ui.panels;

  static const shot = ValueKey('sheet-shot');

  /// Where the small player ends: under the status bar, 16:9 across the screen.
  static const playerBottom = 62 + 440 / BiliMetrics.videoAspect;
}

/// Mounts the layer in [presentation] (the small player or 竖屏). [look] draws at 3× under the system font's
/// stand-ins for a look-alike shot; otherwise at 1× with the phone's insets.
Future<SheetRig> pumpSheetRig(
  WidgetTester tester, {
  Presentation presentation = Presentation.inline,
  FakePlayerSession? session,
  FakeOfflineLibrary? library,
  PageDetails? details,
  bool danmaku = true,
  bool look = false,
}) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  if (look) {
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
  } else {
    const padding = PhoneFrame.portraitPadding;
    final fake = FakeViewPadding(top: padding.top, bottom: padding.bottom);
    tester.view
      ..physicalSize = PhoneFrame.portrait
      ..devicePixelRatio = 1
      ..padding = fake
      ..viewPadding = fake;
    addTearDown(tester.view.reset);
  }
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(),
    logger: logger,
  );
  final playback = AppPlayback(() => Completer<PlaybackController>().future);
  addTearDown(playback.dispose);
  final offline = library ?? FakeOfflineLibrary();
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    offline: offline,
  );
  // The services' font store sets the family; the shot is the phone's system font.
  if (look) BiliFonts.family = BiliFonts.system;
  final fake = session ?? FakePlayerSession();
  final orientation = OrientationController();
  if (presentation == Presentation.vertical) orientation.enterVertical();
  final chrome = ChromeState();
  final panels = PanelController();
  final rig = DanmakuRig();
  final ui = PlayerUi(
    session: fake,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () {},
    details: details,
    danmaku: danmaku ? rig.session : null,
  );
  final vertical = presentation == Presentation.vertical;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: BiliFonts.family,
        fontFamilyFallback: BiliFonts.fallback,
        textTheme: BiliFonts.untracked,
      ),
      builder: (context, child) => AppScope(services: services, child: child!),
      home: RepaintBoundary(
        key: SheetRig.shot,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: BiliColors.card)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: vertical ? null : SheetRig.playerBottom,
              bottom: vertical ? 0 : null,
              child: const ColoredBox(color: BiliColors.videoBackground),
            ),
            Positioned.fill(
              child: PanelLayer(ui: ui, playerBottom: vertical ? null : SheetRig.playerBottom),
            ),
          ],
        ),
      ),
    ),
  );
  addTearDown(() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    fake.dispose();
    rig.dispose();
  });
  return SheetRig(fake, ui, offline, orientation);
}

DashStream stream(int id, int bandwidth, {int codecid = 12, String codecs = 'hev1.1.6.L150.90'}) => DashStream(
  id: id,
  baseURL: '',
  backupURLs: const [],
  bandwidth: bandwidth,
  mimeType: id >= 30000 ? 'audio/mp4' : 'video/mp4',
  codecs: id >= 30000 ? 'mp4a.40.2' : codecs,
  codecid: id >= 30000 ? 0 : codecid,
  width: 1920,
  height: 1080,
  frameRate: null,
  initialization: ByteRange(0, 999),
  indexRange: ByteRange(1000, 1999),
);

/// 1080P 60帧 (大会员), 1080P 高清, 720P and 480P, each in HEVC, with 192K audio.
final dash = Dash(
  duration: 383,
  video: [
    stream(116, 3000000),
    stream(80, 1500000),
    stream(80, 1700000, codecid: 7, codecs: 'avc1.640032'),
    stream(64, 900000),
    stream(32, 400000),
  ],
  audio: [stream(30280, 200000), stream(30216, 64000)],
);

const qualities = [
  QualityOption(id: 116, name: '高清 1080P60'),
  QualityOption(id: 80, name: '高清 1080P'),
  QualityOption(id: 64, name: '高清 720P'),
  QualityOption(id: 32, name: '清晰 480P'),
  QualityOption(id: 16, name: '流畅 360P'),
];

VideoDetail detailJson(Map<String, Object?> json) => VideoDetail.fromJson(jsonDecode(jsonEncode(json)));

/// A video of one part, playing, its streams known.
FakePlayerSession singleVideo({String title = '神枪看小羊崽复播：你看这次她真的自己打的，她表情会动', bool vip = true}) {
  const page = VideoPage(cid: 501, page: 1, part: '', duration: 383);
  return FakePlayerSession()
    ..video = VideoView(bvid: 'BV1single', aid: 11, title: title, owner: '火播君', pages: const [page])
    ..part = page
    ..detail = detailJson({
      'bvid': 'BV1single',
      'aid': 11,
      'title': title,
      'pic': 'https://i0.hdslb.com/single.jpg',
      'duration': 383,
      'owner': {'mid': 7, 'name': '火播君', 'face': 'https://i0.hdslb.com/face.jpg'},
      'pages': [
        {'cid': 501, 'page': 1, 'part': '', 'duration': 383},
      ],
    })
    ..title = title
    ..episodesAreParts = false
    ..qualities = qualities
    ..isVip = vip
    ..dash = dash;
}

/// A video in three parts, playing the second.
FakePlayerSession partsVideo() {
  const pages = [
    VideoPage(cid: 601, page: 1, part: '开头', duration: 100),
    VideoPage(cid: 602, page: 2, part: '中间', duration: 200),
    VideoPage(cid: 603, page: 3, part: '结尾', duration: 300),
  ];
  return FakePlayerSession()
    ..video = const VideoView(bvid: 'BV1parts', aid: 12, title: '三段', owner: 'UP', pages: pages)
    ..part = pages[1]
    ..detail = detailJson({
      'bvid': 'BV1parts',
      'aid': 12,
      'title': '三段',
      'pic': 'https://i0.hdslb.com/parts.jpg',
      'owner': {'mid': 8, 'name': 'UP', 'face': ''},
      'pages': [
        for (final page in pages) {'cid': page.cid, 'page': page.page, 'part': page.part, 'duration': page.duration},
      ],
    })
    ..title = '中间'
    ..episodesAreParts = true
    ..qualities = qualities
    ..isVip = true
    ..dash = dash;
}

const collectionTitles = [
  '终末命途前置解读！各体系大补强时代，老东西终于要站起来了？',
  '真珠虚照怎么抽？直接读评论区问题，放心对号入座',
  '绯英队伍怎么抽？虚照、真珠、爻光怎么选？对号入座直接解决！',
  '陈致逸复出首选为何是他？价值观太契合了！',
  '披着动物保护皮反殖民?恰斯卡传说任务杂谈',
];

const collectionSeconds = [411, 219, 179, 433, 253];

/// A video in a 合集 of [collectionTitles], playing the one at [playing].
FakePlayerSession collectionVideo({int playing = 1, String cover = ''}) {
  final page = VideoPage(cid: 700 + playing, page: 1, part: '', duration: collectionSeconds[playing]);
  return FakePlayerSession()
    ..video = VideoView(
      bvid: 'BV1ep$playing',
      aid: 800 + playing,
      title: collectionTitles[playing],
      owner: '问寒不留白',
      pages: [page],
    )
    ..part = page
    ..detail = detailJson({
      'bvid': 'BV1ep$playing',
      'aid': 800 + playing,
      'title': collectionTitles[playing],
      'owner': {'mid': 9, 'name': '问寒不留白', 'face': ''},
      'pages': [
        {'cid': page.cid, 'page': 1, 'part': '', 'duration': page.duration},
      ],
      'ugc_season': {
        'id': 4001,
        'title': '星铁',
        'sections': [
          {
            'id': 1,
            'title': '正片',
            'episodes': [
              for (final (index, title) in collectionTitles.indexed)
                {
                  'aid': 800 + index,
                  'bvid': 'BV1ep$index',
                  'cid': 700 + index,
                  'title': title,
                  'arc': {'pic': cover, 'duration': collectionSeconds[index]},
                },
            ],
          },
        ],
      },
    })
    ..title = collectionTitles[playing]
    ..episodesAreParts = false
    ..qualities = qualities
    ..isVip = true
    ..dash = dash;
}

/// Opens [panel] and lets the sheet come in.
Future<void> openSheet(WidgetTester tester, SheetRig rig, PlayerPanel panel) async {
  rig.panels.open(panel);
  await tester.pumpAndSettle();
}
