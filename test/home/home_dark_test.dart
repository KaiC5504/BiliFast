import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/appearance.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'feed_fakes.dart';

const _screen = ValueKey('screen');

FeedHttp _feed() => FeedHttp()
  ..pages[1] = [
    feedItem('BV1aaa', title: '南瓜哈基米竟是白送?!又有放烟花拿钻!万圣节活动速览', reason: '1千点赞'),
    feedItem('BV1bbb', title: '员工晒黄仁勋私人飞机内照：教主瘫坐刷手机，真实又接地气'),
    feedItem('BV1ccc', title: '与康康搭档双决斗'),
    feedItem('BV1ddd', title: '神枪看simon超帅拉枪'),
  ];

/// 首页 in 深色模式 at 3× under the system font, inside a boundary keyed [_screen].
Future<void> _showHome(WidgetTester tester) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  await tester.runAsync(loadSystemFontStandIns);
  showAsPhone(tester, dark: true);
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: _feed(),
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() => throw StateError('no playback here'));
  addTearDown(playback.dispose);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    searchApi: FakeSearchApi(defaultWord: '甘泽成谣雨成诗·16小时前更新'),
  );
  BiliFonts.family = BiliFonts.system;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: BiliFonts.family,
        fontFamilyFallback: BiliFonts.fallback,
        textTheme: BiliFonts.untracked,
        brightness: Brightness.dark,
      ),
      builder: (context, child) => RepaintBoundary(
        key: _screen,
        child: AppScope(services: services, child: child!),
      ),
      home: const MainShell(),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The screen's pixels at 3×, as the phone's, read back as colours at points.
Future<Color Function(Offset)> _pixels(WidgetTester tester) async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_screen));
  final read = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    final data = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (data!, width);
  });
  final (ByteData data, int width) = read!;
  return (Offset point) {
    final i = ((point.dy * 3).floor() * width + (point.dx * 3).floor()) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  };
}

SystemUiOverlayStyle _statusBar(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(of: find.byType(HomePage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).first,
    )
    .value;

void main() {
  testWidgets("首页 in 深色模式: the page, cards, words and bottom bar in 239's colours", (tester) async {
    await _showHome(tester);
    final at = await _pixels(tester);

    // 239: the header and the bar on #17181A, the gaps between cards #0A0B0C, words #E7E9EB.
    expect(at(const Offset(220, 30)), const Color(0xFF17181A), reason: 'the header behind the status bar');
    final first = tester.getRect(find.byKey(const ValueKey('feed-card-BV1aaa')));
    final second = tester.getRect(find.byKey(const ValueKey('feed-card-BV1bbb')));
    expect(at(Offset((first.right + second.left) / 2, first.center.dy)), const Color(0xFF0A0B0C));
    expect(at(Offset(first.center.dx, first.bottom - 2)), const Color(0xFF17181A), reason: 'the card');
    final bar = tester.getRect(find.byType(HomeTabBar));
    expect(at(Offset(bar.left + 2, bar.bottom - 4)), const Color(0xFF17181A), reason: 'the bottom bar');
    expect(at(Offset(bar.left + 2, bar.top)), const Color(0xFF2F3134), reason: "the bar's hairline");

    final title = tester.renderObject<RenderParagraph>(find.textContaining('南瓜哈基米'));
    expect(title.text.style?.color, const Color(0xFFE7E9EB));

    expect(_statusBar(tester), SystemUiOverlayStyle.light, reason: 'light icons over the dark header');

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/239-dark-home-ours.png');
  });

  testWidgets('首页 turned back to light in place takes its light colours again', (tester) async {
    await _showHome(tester);
    BiliTheme.dark = false;
    redrawAll(tester.element(find.byType(MaterialApp)));
    await tester.pump();
    final at = await _pixels(tester);
    final first = tester.getRect(find.byKey(const ValueKey('feed-card-BV1aaa')));
    final second = tester.getRect(find.byKey(const ValueKey('feed-card-BV1bbb')));
    expect(at(Offset((first.right + second.left) / 2, first.center.dy)), const Color(0xFFF1F2F3));
    expect(at(Offset(first.center.dx, first.bottom - 2)), const Color(0xFFFFFFFF));
    expect(_statusBar(tester), SystemUiOverlayStyle.dark);
  });
}
