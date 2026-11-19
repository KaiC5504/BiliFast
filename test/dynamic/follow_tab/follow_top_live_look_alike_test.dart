import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import 'follow_fixtures.dart';

const _bars = AssetImage('assets/images/live/live_ing.gif');

/// 263's 最常访问 with two of the followed live, as KaiC's iPhone draws it under the system font, measured in px / 3
/// (names made up, as long as 263's). With BILIFAST_SHOTS naming a folder outside the repo, the 3× shot is saved
/// there for tools/screen_diff.py.
void main() {
  testWidgets('263: two live faces in their rings and pills, the line, the faces; 2人直播中 · 更多 ›', (tester) async {
    await showShell(
      tester,
      phone: true,
      api: FakeDynamicApi(
        posts: posts(4),
        liveUps: const [
          DynamicLiveUp(mid: 201, name: '演示影月月', face: '', roomId: 30001),
          DynamicLiveUp(mid: 202, name: '演示某人', face: '', roomId: 30002),
        ],
        upList: const [
          DynamicUp(mid: 101, name: '演示小元补给屋', face: '', hasUpdate: true),
          DynamicUp(mid: 102, name: '演示饱饱噜', face: '', hasUpdate: true),
          DynamicUp(mid: 103, name: '演示星穹铁道', face: '', hasUpdate: true),
          DynamicUp(mid: 104, name: '演示梦轩da', face: ''),
        ],
      ),
    );
    await settle(tester, 20);
    final context = tester.element(find.byType(MainShell));
    var barsCached = false;
    await tester.runAsync(() async {
      for (final art in ['follow_write', 'follow_pointer']) {
        await precacheImage(AssetImage('assets/images/dynamic/$art.png'), context);
      }
      unawaited(precacheImage(_bars, context).then((_) => barsCached = true));
    });
    // An animated gif hands out its first frame only from a drawn frame, which runAsync never pumps.
    for (var i = 0; i < 100 && !barsCached; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(barsCached, isTrue);
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await settle(tester, 20);

    Rect face(String key) =>
        tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ClipOval)));
    // 263: the rings' outer edges 51-219 and 273-441 px across, 503.5 down; the line 489-492 × 552-624; the first other
    // face 549-705; the pills' pink 57.5-212.5 × 627.5-674.5, the bars' first column from 72.
    expect(face('follow-live-201'), Rect.fromCenter(center: const Offset(45, 196), width: 52, height: 52));
    expect(face('follow-live-202'), Rect.fromCenter(center: const Offset(119, 196), width: 52, height: 52));
    expect(
      tester.getRect(find.byKey(const ValueKey('follow-live-rule'))),
      Rect.fromCenter(center: const Offset(163.5, 196), width: 1, height: 24),
    );
    expect(face('follow-face-101'), Rect.fromCenter(center: const Offset(209, 196), width: 52, height: 52));
    expect(
      tester.getRect(find.byKey(const ValueKey('follow-live-pill-201'))),
      Rect.fromCenter(center: const Offset(45, 217), width: 54, height: 18),
    );
    final bars = find.descendant(of: find.byKey(const ValueKey('follow-live-201')), matching: find.image(_bars));
    expect(tester.getRect(bars).topLeft, const Offset(21, 210));
    expect(tester.widget<RawImage>(find.descendant(of: bars, matching: find.byType(RawImage))).image, isNotNull);
    // 更多 › where 127 has it; 2人直播中's 中 ends 14 pt before 更.
    expect(tester.getRect(find.text('更多')).left, moreOrLessEquals(388, epsilon: 0.7));

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(shellScreen), '$shots/263-live-faces-ours.png');
  });
}
