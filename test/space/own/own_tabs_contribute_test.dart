import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/own/own_contribute_tab.dart';
import 'package:bilifast/space/own/own_tab_glyphs.dart';
import 'package:bilifast/space/space_videos.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'own_tabs_support.dart';

void main() {
  Future<FakeSpaceApi> show(WidgetTester tester, {required int videoCount, List<VideoRoute>? opened}) async {
    final space = FakeSpaceApi(videoList: [for (var i = 0; i < videoCount; i++) ownVideo(i)]);
    final services = await ownTabServices(spaceApi: space);
    await pumpOwnTab(
      tester,
      services,
      OwnContributeSliver(
        profile: ownProfile(null, videoCount: videoCount),
        open: opened == null ? null : (context, route) => opened.add(route),
      ),
    );
    await settle(tester);
    return space;
  }

  testWidgets('no videos: 108’s empty page, asking nothing', (tester) async {
    final space = await show(tester, videoCount: 0);
    expect(find.byKey(const ValueKey('own-contribute-empty')), findsOneWidget);
    expect(find.byType(UploadGlyph), findsOneWidget);
    expect(find.text('发布第一个视频，领新人福利'), findsOneWidget);
    expect(find.text('我要投稿'), findsOneWidget);
    expect(find.text('去创作中心领奖'), findsOneWidget);
    expect(find.byType(SpaceVideosSliver), findsNothing);
    expect(space.calls, isEmpty);
  });

  testWidgets('108’s places: the disc, the words, the pill and the link down the middle', (tester) async {
    await show(tester, videoCount: 0);
    final disc = tester.getRect(find.ancestor(of: find.byType(UploadGlyph), matching: find.byType(DecoratedBox)).first);
    expect(disc.width, moreOrLessEquals(48));
    expect(disc.height, moreOrLessEquals(48));
    expect(disc.center.dx, moreOrLessEquals(220));
    expect(disc.center.dy, moreOrLessEquals(190 / 3, epsilon: 0.01));
    expect(
      tester.getCenter(find.text('发布第一个视频，领新人福利')).dy,
      moreOrLessEquals(OwnSpaceTabsTheme.emptyTextCentre, epsilon: 0.01),
    );
    final pill = tester.getRect(find.byKey(const ValueKey('own-contribute-upload')));
    expect(pill.width, moreOrLessEquals(140));
    expect(pill.height, moreOrLessEquals(44));
    expect(pill.center.dx, moreOrLessEquals(220));
    expect(pill.center.dy, moreOrLessEquals(520 / 3, epsilon: 0.01));
    expect(tester.getCenter(find.text('去创作中心领奖')).dy, moreOrLessEquals(677.5 / 3, epsilon: 0.01));
  });

  testWidgets('我要投稿 and 去创作中心领奖 say 暂未开放', (tester) async {
    await show(tester, videoCount: 0);
    for (final key in ['own-contribute-upload', 'own-contribute-reward']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await settle(tester, 2);
      expect(find.text('暂未开放'), findsOneWidget, reason: key);
      await toastGone(tester);
    }
  });

  testWidgets('with videos: 投稿’s list, its rows opening their videos', (tester) async {
    final opened = <VideoRoute>[];
    final space = await show(tester, videoCount: 3, opened: opened);
    expect(find.byKey(const ValueKey('own-contribute-empty')), findsNothing);
    expect(find.byType(SpaceVideosSliver), findsOneWidget);
    expect(space.calls, ['videos mid=$ownMid order=pubdate next=null']);
    await tester.tap(find.byKey(const ValueKey('space-row-BV1owntest1')));
    await settle(tester);
    expect(opened.map((route) => route.bvid), ['BV1owntest1']);
  });
}
