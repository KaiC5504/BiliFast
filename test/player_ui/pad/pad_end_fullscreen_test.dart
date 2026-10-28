import 'package:bili_core/api.dart' show VideoCard;
import 'package:bilifast/player_ui/pad/pad_end_fullscreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';
import 'pad_rig.dart';

VideoCard card(int n) => VideoCard(
  aid: n,
  bvid: 'BV$n',
  cid: n,
  title: '推荐 $n',
  cover: '',
  duration: 255,
  ownerMid: 1,
  ownerName: 'UP',
  views: 1703000,
  danmaku: 679,
  likes: 0,
);

void main() {
  final shared = <Uri>[];

  Future<PadRig> mount(WidgetTester tester, {PadRig? rig, int related = 12, bool landscape = true}) async {
    final padRig = rig ?? rig08();
    padRig.session
      ..ended = true
      ..shareLink = Uri.parse('https://b23.tv/BV1')
      ..related = [for (var i = 0; i < related; i++) card(i)];
    shared.clear();
    await padRig.mount(
      tester,
      PadEndFullScreen(
        ui: padRig.ui,
        share: (link) async {
          shared.add(link);
          return true;
        },
      ),
      landscape: landscape,
    );
    await tester.pumpAndSettle();
    return padRig;
  }

  FakeVideoActions actionsOf(PadRig rig) => rig.details!.actions! as FakeVideoActions;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('16: ‹, the uploader with + 关注 and 为TA充电, 重播 | 点赞 不喜欢 投币 收藏 分享, 推荐视频', (tester) async {
    await mount(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('山顶小松鼠'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('为TA充电'), findsOneWidget);
    for (final title in ['重播', '点赞', '不喜欢', '投币', '收藏', '分享', '推荐视频']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(centreOf(tester, 'pad-end-share').dx, closeTo(1121, 1));
    expect(centreOf(tester, 'pad-end-like').dx, closeTo(841, 1));
    expect(centreOf(tester, 'pad-end-replay').dx, closeTo(726, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('pad-end-follow'))), within(distance: 1, from: const Offset(98.2, 112.2)));
    // The duration keeps its leading zero, as 16's covers do.
    expect(find.text('04:15'), findsWidgets);
  });

  testWidgets('推荐视频 is four columns of 16:10 covers, 12.5 pt apart from 22 pt in, a row every 237 pt', (tester) async {
    await mount(tester);
    Rect cardRect(int n) => tester.getRect(find.bySemanticsLabel('推荐 $n'));
    expect(cardRect(0).left, closeTo(22, 0.5));
    expect(cardRect(1).left - cardRect(0).right, closeTo(12.5, 0.5));
    expect(cardRect(3).right, closeTo(1194 - 22, 0.5));
    expect(cardRect(4).left, closeTo(22, 0.5));
    expect(cardRect(4).top - cardRect(0).top, closeTo(237, 1.5));
    expect(cardRect(0).top, closeTo(210, 1.5));
    expect(cardRect(0).width / (cardRect(0).width / 1.6), 1.6);
  });

  testWidgets('every action does what the phone end screen does', (tester) async {
    final rig = await mount(tester);
    final actions = actionsOf(rig);
    await tap(tester, 'pad-end-replay');
    expect(rig.session.calls, ['replay']);
    await tap(tester, 'pad-end-like');
    await tap(tester, 'pad-end-dislike');
    await tap(tester, 'pad-end-coin');
    await tap(tester, 'pad-end-favourite');
    await tap(tester, 'pad-end-share');
    await tap(tester, 'pad-end-follow');
    expect(actions.calls, ['toggleLike', 'toggleDislike', 'ask coin', 'ask favourites', 'ask share', 'tapFollow']);

    await tap(tester, 'pad-end-charge');
    expect(find.text('暂不支持充电'), findsOneWidget);
    await drainToast(tester);

    await tap(tester, 'pad-end-back');
    expect(rig.backs, 1);

    await tester.tap(find.bySemanticsLabel('推荐 1'));
    await tester.pump();
    expect(rig.session.calls.last, 'playRelated BV1');
  });

  testWidgets('followed, the pill reads 已关注; without the page\'s actions 分享 shares the link itself', (tester) async {
    final rig = rig08();
    actionsOf(rig).following = true;
    await mount(tester, rig: rig);
    expect(find.text('已关注'), findsOneWidget);

    final bare = PadRig();
    bare.session.title = 'x';
    await mount(tester, rig: bare);
    await tap(tester, 'pad-end-share');
    expect(shared, [Uri.parse('https://b23.tv/BV1')]);
    expect(find.byKey(const ValueKey('pad-end-like')), findsNothing);
  });

  testWidgets('the page scrolls to the last row; upright it keeps four columns at 834 wide', (tester) async {
    await mount(tester, related: 16);
    final scroll = find.byKey(const ValueKey('pad-end-scroll'));
    await tester.drag(scroll, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.bySemanticsLabel('推荐 15')).bottom, lessThanOrEqualTo(834));

    await mount(tester, landscape: false);
    expect(tester.takeException(), isNull);
    final width = (834 - 44 - 12.5 * 3) / 4;
    expect(tester.getSize(find.bySemanticsLabel('推荐 0')).width, closeTo(width, 0.5));
  });
}
