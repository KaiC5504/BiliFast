import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/space/own/own_space_page.dart';
import 'package:bilifast/space/space_api.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;

const _screen = ValueKey('screen');
const _banner = 'https://i0.hdslb.com/bfs/garb/look-banner.png';
const _vipLabel = 'https://i1.hdslb.com/bfs/vip/look-label.png';

/// KaiC's own space as 108, 114 and 115 show it: a 年度大会员 at LV5 with 14805/28800, the 空间头图's label, four tabs.
SpaceProfile _kaic({SpaceTabKind defaultTab = SpaceTabKind.contribute}) => SpaceProfile(
  mid: 1,
  name: 'KaiC5504',
  face: '',
  level: 5,
  vip: true,
  vipLabel: _vipLabel,
  fans: 0,
  following: 13,
  likes: 0,
  tagLines: const [SpaceTagLine(text: 'IP属地：澳大利亚')],
  tabs: const [
    SpaceTab(kind: SpaceTabKind.home, title: '主页'),
    SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
    SpaceTab(kind: SpaceTabKind.favourite, title: '收藏'),
    SpaceTab(kind: SpaceTabKind.bangumi, title: '追番'),
  ],
  defaultTab: defaultTab,
  own: const OwnSpace(
    exp: 14805,
    nextExp: 28800,
    pendant: 'https://i0.hdslb.com/bfs/garb/look-pendant.png',
    vipBadge: true,
    banner: _banner,
    bannerLabel: SpaceBannerLabel(title: '幸运塔罗星 金牛座', subtitle: 'NO.000067'),
  ),
);

final class _Api implements SpaceApi {
  _Api(this.answer);

  final SpaceProfile answer;

  @override
  Future<SpaceProfile> ownProfile(int mid) async => answer;

  @override
  Future<SpaceProfile> profile(int mid) async => answer;

  @override
  Future<SpaceBangumiPage> bangumi(int mid, {required int page}) async =>
      const SpaceBangumiPage(items: [], hasMore: false, total: 0);

  @override
  Future<SpaceVideoPage> videos(int mid, {required SpaceOrder order, String? next}) async =>
      const SpaceVideoPage(items: [], hasMore: false, total: 0);

  @override
  Future<SpaceVideoPage> chipVideos(int mid, SpaceChip chip, {String? next}) async =>
      const SpaceVideoPage(items: [], hasMore: false);
}

/// 115's skin: the dark second-page bar with white text.
final _skin = Skin(
  equip: const SkinEquip(
    id: 1,
    name: '幸运塔罗星',
    ver: 1,
    packageUrl: '',
    packageMd5: '',
    colors: SkinColors(color: 0xFFFFFFFF, colorSecondPage: 0xFF161513, lightText: true),
  ),
);

/// Drawn stand-ins (never the official art) put in the image cache under the addresses the page asks for: a dark
/// banner, so the label's white reads as on 108, and a 年度大会员 pill the size of 108's.
Future<void> _cacheStandIns(WidgetTester tester) async {
  Future<ui.Image> draw(int width, int height, void Function(Canvas canvas, Size size) paint) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    return recorder.endRecording().toImage(width, height);
  }

  void cache(String url, ui.Image image) => PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url, headers: BiliClient.mediaHeaders),
    () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image))),
  );

  await tester.runAsync(() async {
    final banner = await draw(
      1320,
      900,
      (canvas, size) => canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2A2322)),
    );
    final label = await draw(204, 44, (canvas, size) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)),
        Paint()..color = const Color(0xFFFF568D),
      );
      final text = TextPainter(
        text: const TextSpan(
          text: '年度大会员',
          style: TextStyle(
            fontFamily: 'PingFang SC',
            fontSize: 33,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset((size.width - text.width) / 2, (size.height - text.height) / 2));
    });
    cache(sizedImageUrl(_banner, width: 1320, height: 900), banner);
    cache(_vipLabel, label);
  });
}

/// The own space for [profile] at 3× under the system font, as KaiC's iPhone draws it, inside a boundary keyed [_screen].
Future<void> _show(WidgetTester tester, SpaceProfile profile, {Skin? skin}) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  await tester.runAsync(loadSystemFontStandIns);
  showAsPhone(tester);
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(),
    logger: logger,
  );
  environment.useFakeAccount();
  final playback = AppPlayback(() => Completer<PlaybackController>().future);
  addTearDown(playback.dispose);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    fonts: FontStore.memory()..select(FontChoice.system),
    pageApi: FakePageApi(),
    spaceApi: _Api(profile),
    favouritesApi: FakeFavouritesApi(),
  );
  BiliFonts.family = BiliFonts.system;
  await _cacheStandIns(tester);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _screen,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      SwipeBackPageRoute<void>(
        builder: (_) => OwnSpacePage(
          uploader: UploaderRef(mid: profile.mid),
          skin: ValueNotifier(skin),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Asset decoding needs real async; without it the face is blank.
  await tester.runAsync(
    () => precacheImage(const AssetImage(DefaultAvatar.asset), tester.element(find.byType(OwnSpacePage))),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final shots = Platform.environment['BILIFAST_SHOTS'];
  if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/$name-ours.png');
}

Rect _rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

/// The own space against KaiC's official screenshots (px / 3). With BILIFAST_SHOTS naming a folder outside the repo,
/// the 3× shots are saved there for tools/screen_diff.py.
void main() {
  testWidgets('108: the tall banner with its label, the face, 编辑资料, the name line, the level and 投稿', (tester) async {
    await _show(tester, _kaic());
    await _shoot(tester, '108');
    // 108's measures, in pt.
    expect(_rect(tester, 'own-space-banner').bottom, closeTo(295.67, 0.01));
    expect(
      _rect(tester, 'own-space-edit'),
      rectMoreOrLessEquals(const Rect.fromLTRB(156, 340.67, 428, 370.67), epsilon: 0.5),
    );
    expect(_rect(tester, 'own-space-fans').center.dx, closeTo(199.83, 0.5));
    expect(_rect(tester, 'own-space-following').center.dx, closeTo(291.83, 0.5));
    expect(_rect(tester, 'own-space-likes').center.dx, closeTo(384.5, 1));
    expect(_rect(tester, 'own-space-name').center.dy, closeTo(400.5, 0.5));
    final badge = _rect(tester, 'own-space-vip-badge');
    expect(badge.center, offsetMoreOrLessEquals(const Offset(97.33, 342.33), epsilon: 0.5));
    expect(badge.width, 24);
    final medal = _rect(tester, 'own-space-medal');
    expect(medal.height, 16);
    expect(medal.center.dy, closeTo(400.33, 0.5));
    // The stand-in's Latin draws KaiC5504 2 pt wider than SF, so the line is placed by its gaps: the label 6.67
    // after the name, the pills 6.67 after the label and 6.33 apart.
    final label = _rect(tester, 'own-space-vip-label');
    expect(label.width, closeTo(68 + OwnSpaceTheme.vipLabelGap, 0.1));
    expect(label.height, closeTo(14.67, 0.01));
    expect(medal.left - label.right, closeTo(6.67, 0.01));
    expect(medal.width, closeTo(65.33, 1.5));
    expect(_rect(tester, 'own-space-fan-medal').left - medal.right, closeTo(6.33, 0.01));
    expect(_rect(tester, 'space-level').center.dy, closeTo(427.67, 0.5));
    expect(
      _rect(tester, 'own-space-exp-bar'),
      rectMoreOrLessEquals(const Rect.fromLTRB(12, 436.67, 113.67, 438.67), epsilon: 0.1),
    );
    expect(_rect(tester, 'own-space-exp-fill').right, closeTo(64.17, 0.5));
    expect(_rect(tester, 'own-space-bio').center.dy, closeTo(461.67, 0.5));
    expect(_rect(tester, 'space-tabs').top, closeTo(509.67, 0.01));
    expect(
      _rect(tester, 'space-tab-indicator'),
      rectMoreOrLessEquals(const Rect.fromLTRB(157, 543.67, 171, 545.67), epsilon: 0.5),
    );
    for (final (kind, centre) in [('home', 51.67), ('contribute', 163.5), ('favourite', 275.83), ('bangumi', 387.67)]) {
      expect(_rect(tester, 'space-tab-$kind').center.dx, closeTo(centre, 1), reason: kind);
    }
    expect(_rect(tester, 'own-space-label-title').center.dy, closeTo(267.83, 0.5));
    expect(_rect(tester, 'own-space-label-subtitle').center.dy, closeTo(284, 0.5));
    expect(_rect(tester, 'own-space-label-subtitle').right, closeTo(389.33, 1));
    expect(_rect(tester, 'own-space-skin').center, offsetMoreOrLessEquals(const Offset(418, 275.33), epsilon: 0.5));
  });

  testWidgets('114: opened on 主页, the tab row\'s 主页 pink over its bar', (tester) async {
    await _show(tester, _kaic(defaultTab: SpaceTabKind.home));
    await _shoot(tester, '114');
    expect(
      _rect(tester, 'space-tab-indicator'),
      rectMoreOrLessEquals(const Rect.fromLTRB(45, 543.67, 59, 545.67), epsilon: 0.5),
    );
  });

  testWidgets('115: scrolled, the skin\'s dark bar with the name and the tabs pinned under it', (tester) async {
    await _show(tester, _kaic(defaultTab: SpaceTabKind.home), skin: _skin);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await _shoot(tester, '115');
    expect(_rect(tester, 'own-space-bar').bottom, 94);
    expect(_rect(tester, 'space-tabs').top, closeTo(94, 0.01));
    expect(_rect(tester, 'own-space-bar-name').center, offsetMoreOrLessEquals(const Offset(220.5, 69), epsilon: 1));
  });
}
