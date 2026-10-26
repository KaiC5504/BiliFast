import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import 'follow_fixtures.dart';

/// 关注 as KaiC's iPhone draws it under the system font, against 127 (全部), 128 (视频) and 139 (the face sheet),
/// measured in px / 3. The cards are judged in `dynamic_card_look_alike_test.dart`, so only the header, the switch,
/// 最常访问, 我的追番 · 追剧 and the sheet are judged here. With BILIFAST_SHOTS naming a folder outside the repo, the 3×
/// shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> openFollow(WidgetTester tester, FakeDynamicApi api) async {
    await showShell(tester, api: api, phone: true);
    await settle(tester, 20);
    final context = tester.element(find.byType(MainShell));
    await tester.runAsync(() async {
      for (final art in ['follow_write', 'follow_pointer']) {
        await precacheImage(AssetImage('assets/images/dynamic/$art.png'), context);
      }
    });
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await settle(tester, 20);
  }

  Future<void> save(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(shellScreen), '$shots/$name-ours.png');
  }

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('127: the header, 全部 chosen, 最常访问 with 更多 and four faces with their dots', (tester) async {
    await openFollow(tester, FakeDynamicApi(posts: posts(4), upList: faces));
    expect(rectOf(tester, 'follow-header'), const Rect.fromLTWH(0, 0, 440, 88));
    expect(rectOf(tester, 'follow-switch-all'), const Rect.fromLTRB(12, 96, 216, 122));
    expect(rectOf(tester, 'follow-switch-video'), const Rect.fromLTRB(224, 96, 428, 122));
    for (final (i, up) in faces.indexed) {
      final face = tester.getRect(
        find.descendant(of: find.byKey(ValueKey('follow-face-${up.mid}')), matching: find.byType(ClipOval)),
      );
      expect(face, Rect.fromCenter(center: Offset(45 + 74.0 * i, 196), width: 52, height: 52), reason: up.name);
    }
    expect(find.byKey(const ValueKey('follow-faces-more')), findsOneWidget);
    await save(tester, '127');
  });

  testWidgets('128: 视频 chosen, 最常访问 without 更多, then 我的追番 · 追剧 with its posters', (tester) async {
    await openFollow(
      tester,
      FakeDynamicApi(
        posts: posts(4),
        upList: [faces[1], faces[0], faces[2], faces[3]],
        bangumiList: const [
          FollowedBangumi(seasonId: 1, title: '星之丘 白羽小骑士', cover: '', progress: '全23话'),
          FollowedBangumi(seasonId: 2, title: '星之丘 第三季', cover: '', progress: '全13话'),
          FollowedBangumi(seasonId: 3, title: '星之丘 远方之歌', cover: '', progress: '全4话'),
          FollowedBangumi(seasonId: 4, title: '星之丘', cover: '', progress: '全13话'),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('follow-switch-video')));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('follow-faces-more')), findsNothing);
    expect(rectOf(tester, 'follow-bangumi'), const Rect.fromLTWH(0, 284, 440, 152));
    for (var i = 0; i < 3; i++) {
      final poster = tester.getRect(
        find.descendant(of: find.byKey(ValueKey('follow-poster-${i + 1}')), matching: find.byType(ClipRRect)),
      );
      expect(poster, Rect.fromLTWH(12 + 119.0 * i, 327, 113, 70));
    }
    await save(tester, '128');
  });

  testWidgets('139: the face sheet over the frosted screen, the faces raised and the pointer under the chosen one', (
    tester,
  ) async {
    const ups = [
      DynamicUp(mid: 101, name: '晚风的星星', face: '', hasUpdate: true),
      DynamicUp(mid: 104, name: '云海', face: '', hasUpdate: true),
      DynamicUp(mid: 102, name: '云舟mimi', face: ''),
      DynamicUp(mid: 103, name: '星海远航计划', face: ''),
    ];
    await openFollow(tester, FakeDynamicApi(posts: posts(4, mid: 101), upList: ups));
    await tester.tap(find.byKey(const ValueKey('follow-face-101')));
    await settle(tester, 20);
    expect(rectOf(tester, 'face-sheet').top, 189);
    final pointer = rectOf(tester, 'face-sheet-pointer');
    expect(pointer.center.dx, moreOrLessEquals(45, epsilon: 0.01));
    expect(pointer.bottom, moreOrLessEquals(189 + 1 / 3, epsilon: 0.01));
    final face = tester.getRect(
      find.descendant(
        of: find.descendant(
          of: find.byKey(const ValueKey('face-sheet-faces')),
          matching: find.byKey(const ValueKey('follow-face-101')),
        ),
        matching: find.byType(ClipOval),
      ),
    );
    expect(face.top, moreOrLessEquals(78.33, epsilon: 0.01));
    await save(tester, '139');
  });
}
