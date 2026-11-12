import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart' show SpaceProfile, SpaceVideo, UploaderCard;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/uploader_sheet.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

class _Gate implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// The uploader sheet over 竖屏 as 181 has it (枫泽雨畔, the sheet's top at 947 px), at 3× under the system font. With
/// BILIFAST_SHOTS naming a folder outside the repo, the shot is saved there for tools/screen_diff.py.
void main() {
  const top = 947 / 3;
  const ref = UploaderRef(mid: 7, name: '枫泽雨畔', face: '');
  const titles = ['这就是我要抓的因缘精灵吗', '对的对的，全部梭哈', '这汤烧心', '诶！总有一个宇宙....', '此事亦有记载', '嘉豪汤姆'];
  const plays = [453000, 200000, 28000, 1516000, 59000, 45000];
  const dates = ['11月8日', '11月1日', '10月17日', '10月2日', '10月1日', '5月3日'];
  const durations = [78, 78, 168, 72, 155, 141];

  testWidgets('181: the uploader sheet risen over 竖屏', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);

    final logger = Logger(session: 'test');
    final environment = await tester.runAsync(
      () => AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
        http: Canned.http(),
        logger: logger,
      ),
    );
    await tester.runAsync(environment!.refreshAccount);
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: (await tester.runAsync(() => RecentStore.load(null, logger: logger)))!,
      pageApi: FakePageApi(
        uploader: const UploaderCard(mid: 0, name: '', face: '', fans: 0, videos: 0, isVip: false, following: false),
      ),
      spaceApi: FakeSpaceApi(
        profileFor: (mid) => SpaceProfile(
          mid: mid,
          name: '枫泽雨畔',
          face: '',
          fans: 428000,
          videoCount: 210,
          likes: 11295000,
        ),
        videoList: [
          for (var i = 0; i < titles.length; i++)
            SpaceVideo(
              aid: i + 1,
              bvid: 'BV181video$i',
              title: titles[i],
              cover: '',
              duration: durations[i],
              play: plays[i],
              publishedText: dates[i],
            ),
        ],
      ),
      loginGate: _Gate(),
    );
    final sheet = UploaderSheetController();
    addTearDown(sheet.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('screen'),
          child: AppScope(services: services, child: child!),
        ),
        home: Material(
          color: BiliColors.videoBackground,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 181's picture, shrunk into the room above the sheet.
              const Positioned(
                left: 448 / 3,
                top: 333 / 3,
                width: 420 / 3,
                height: 406 / 3,
                child: ColoredBox(color: Color(0xFF8E8460)),
              ),
              Positioned.fill(
                child: UploaderSheetLayer(controller: sheet, top: top, playingBvid: 'BV181video0'),
              ),
            ],
          ),
        ),
      ),
    );
    // The environment applies its stored font as it starts; 181 has the phone's own.
    BiliFonts.family = BiliFonts.system;
    sheet.open(ref);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/vertical-181.png');
    expect(tester.getTopLeft(find.byKey(const ValueKey('uploader-sheet'))).dy, closeTo(top, 0.5));
    expect(find.text('枫泽雨畔'), findsWidgets);
  });
}
