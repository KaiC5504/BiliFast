import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

const _screen = ValueKey('screen');

const _threeTabs = [
  SpaceTab(kind: SpaceTabKind.home, title: '主页'),
  SpaceTab(kind: SpaceTabKind.dynamic, title: '动态'),
  SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
];

/// 63: the default banner, LV5, one 小店 card, five tabs.
const _jojo = SpaceProfile(
  mid: 63,
  name: 'JOJO和乔乔',
  face: '',
  level: 5,
  fans: 7037,
  following: 2,
  likes: 174000,
  tagLines: [SpaceTagLine(text: 'IP属地：吉林')],
  entries: [SpaceEntry(kind: SpaceEntryKind.shop, title: '小店', note: '1件商品')],
  tabs: [
    SpaceTab(kind: SpaceTabKind.home, title: '主页'),
    SpaceTab(kind: SpaceTabKind.dynamic, title: '动态'),
    SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
    SpaceTab(kind: SpaceTabKind.shop, title: '小店'),
    SpaceTab(kind: SpaceTabKind.favourite, title: '收藏'),
  ],
);

/// 69: a long bio cut short, no cards, three tabs.
const _firefly = SpaceProfile(
  mid: 69,
  name: '小小小小小小小流萤',
  face: '',
  sign: '感谢您为我驻足！主要制作动漫混剪，喜欢二次元的大大可以入股哦，有什么想看的可以私信我哦',
  level: 6,
  fans: 30000,
  following: 12,
  likes: 969000,
  tagLines: [SpaceTagLine(text: 'IP属地：广西')],
  tabs: _threeTabs,
);

/// 70 and 71: a 大会员 who takes 充电, followed.
const _wallpaper = SpaceProfile(
  mid: 70,
  name: 'Wallpaper__壁纸推荐',
  face: '',
  sign: '每日壁纸合集推荐 | 关注我 -每天都有不一样的壁纸！',
  level: 6,
  vip: true,
  fans: 178000,
  following: 18,
  likes: 2841000,
  tagLines: [SpaceTagLine(text: 'IP属地：广东')],
  entries: [SpaceEntry(kind: SpaceEntryKind.charge, title: '充电', note: '5人充电')],
  chargeable: true,
  tabs: _threeTabs,
);

/// 72 and 73: another space, scrolled until the bar is up.
const _popcorn = SpaceProfile(
  mid: 72,
  name: '睡到自然醒的鸡米花',
  face: '',
  sign: '【解说奶爸】解说奶爸直播切片',
  level: 6,
  seniorMember: true,
  fans: 1249,
  following: 2801,
  likes: 25000,
  tagLines: [SpaceTagLine(text: 'IP属地：韩国')],
  entries: [SpaceEntry(kind: SpaceEntryKind.charge, title: '充电', note: '1人充电')],
  tabs: _threeTabs,
  defaultTab: SpaceTabKind.home,
);

/// The space for [profile] at 3× under the system font, as KaiC's iPhone draws it, inside a boundary keyed [_screen].
Future<void> _show(WidgetTester tester, SpaceProfile profile, {bool following = false}) async {
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
    pageApi: FakePageApi(
      uploader: UploaderCard(
        mid: profile.mid,
        name: profile.name,
        face: '',
        fans: profile.fans,
        videos: 0,
        isVip: profile.vip,
        following: following,
      ),
    ),
    spaceApi: FakeSpaceApi(profileFor: (_) => profile),
  );
  BiliFonts.family = BiliFonts.system;
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
      SwipeBackPageRoute<void>(builder: (_) => SpacePage(uploader: UploaderRef(mid: profile.mid))),
    ),
  );
  await tester.pumpAndSettle();
  // Asset decoding needs real async; without it the face is blank.
  await tester.runAsync(
    () => precacheImage(const AssetImage(DefaultAvatar.asset), tester.element(find.byType(SpacePage))),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final shots = Platform.environment['BILIFAST_SHOTS'];
  if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/$name-ours.png');
}

Rect _rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

/// UP主空间 against KaiC's official screenshots (px / 3). With BILIFAST_SHOTS naming a folder outside the repo, the 3×
/// shots are saved there for tools/screen_diff.py.
void main() {
  testWidgets('63: the default banner, the face, the counts, + 关注, the name, 小店 and five tabs', (tester) async {
    await _show(tester, _jojo);
    await _shoot(tester, '63');
    // 63's measures, in pt.
    expect(_rect(tester, 'space-follow'), rectMoreOrLessEquals(const Rect.fromLTRB(156, 232.67, 428, 262.67), epsilon: 0.5));
    expect(_rect(tester, 'space-fans').center.dx, closeTo(199.5, 0.5));
    expect(_rect(tester, 'space-following').center.dx, closeTo(292, 0.5));
    expect(_rect(tester, 'space-likes').center.dx, closeTo(384, 1));
    expect(_rect(tester, 'space-name').center.dy, closeTo(292.5, 0.5));
    expect(_rect(tester, 'space-bio').center.dy, closeTo(322.83, 0.5));
    expect(
      _rect(tester, 'space-entry-shop'),
      rectMoreOrLessEquals(const Rect.fromLTRB(12, 366.67, 428, 406.67), epsilon: 0.5),
    );
    expect(_rect(tester, 'space-tabs').top, closeTo(422.67, 0.5));
    expect(_rect(tester, 'space-tab-indicator'), rectMoreOrLessEquals(const Rect.fromLTRB(213, 456.67, 227, 458.67), epsilon: 0.5));
    for (final (kind, centre) in [('home', 40.33), ('dynamic', 130.17), ('shop', 309.17), ('favourite', 399.0)]) {
      expect(_rect(tester, 'space-tab-$kind').center.dx, closeTo(centre, 1), reason: kind);
    }
  });

  testWidgets('69: a long bio and three tabs, no cards', (tester) async {
    await _show(tester, _firefly);
    await _shoot(tester, '69');
    expect(_rect(tester, 'space-tabs').top, closeTo(370.67, 0.5), reason: 'no cards: 16 under the tag row');
    for (final (kind, centre) in [('home', 70.17), ('dynamic', 219.67), ('contribute', 368.83)]) {
      expect(_rect(tester, 'space-tab-$kind').center.dx, closeTo(centre, 1), reason: kind);
    }
  });

  testWidgets('70: followed, with 充电, 已关注 and ▽', (tester) async {
    await _show(tester, _wallpaper, following: true);
    await _shoot(tester, '70');
    expect(_rect(tester, 'space-charge'), rectMoreOrLessEquals(const Rect.fromLTRB(156, 232.67, 239, 262.67), epsilon: 0.5));
    expect(_rect(tester, 'space-followed'), rectMoreOrLessEquals(const Rect.fromLTRB(243, 232.67, 396, 262.67), epsilon: 0.5));
    expect(
      _rect(tester, 'space-follow-more'),
      rectMoreOrLessEquals(const Rect.fromLTRB(398, 232.67, 428, 262.67), epsilon: 0.5),
    );
    expect(_rect(tester, 'space-face-badge'), rectMoreOrLessEquals(const Rect.fromLTRB(90, 225.67, 114, 249.67), epsilon: 0.5));
  });

  testWidgets('71: 已关注 opens its sheet over the dimmed page', (tester) async {
    await _show(tester, _wallpaper, following: true);
    await tester.tap(find.byKey(const ValueKey('space-followed')));
    await tester.pumpAndSettle();
    await _shoot(tester, '71');
    expect(_rect(tester, 'space-sheet').top, closeTo(731, 0.5));
    expect(_rect(tester, 'space-sheet-cancel').center.dy, closeTo(914.33, 0.5));
  });

  testWidgets('73: scrolled, the white bar with the tabs pinned under it', (tester) async {
    await _show(tester, _popcorn);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await _shoot(tester, '73');
    expect(_rect(tester, 'space-bar').bottom, 94);
    expect(_rect(tester, 'space-tabs').top, closeTo(94, 0.01));
    final pill = _rect(tester, 'space-pill');
    expect(pill.center, offsetMoreOrLessEquals(const Offset(220, 69), epsilon: 0.5));
    expect(pill.height, 30);
    expect(pill.width, closeTo(91.33, 1));
  });
}
