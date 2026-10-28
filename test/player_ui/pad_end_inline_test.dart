import 'package:bili_core/api.dart' show Chapter, VideoCard;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/pad/pad_end_inline.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';

/// No cover address, so the image stays a grey box and nothing is fetched.
const _card = VideoCard(
  aid: 1,
  bvid: 'BV1next',
  cid: 2,
  title: '奶家人躲猫猫大赛-南瓜庄园篇【AI全民制作人】',
  cover: '',
  duration: 255,
  ownerMid: 3,
  ownerName: '奶史_',
  views: 1703000,
  danmaku: 679,
  likes: 0,
);

/// 17's player.
const _box = Size(756.5, 425.5);

final class EndRig {
  EndRig({this.details});

  final session = FakePlayerSession()
    ..ended = true
    ..shareLink = Uri.parse('https://www.bilibili.com/video/BV1this');
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController();
  final FakePageDetails? details;
  final shared = <Uri>[];
  int backs = 0;

  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () => backs++,
    details: details,
  );

  Future<bool> share(Uri link) async {
    shared.add(link);
    return true;
  }

  Future<void> mount(WidgetTester tester, {Size box = _box}) async {
    tester.view
      ..physicalSize = const Size(1194, 834)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
      details?.dispose();
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: box, child: PadEndInline(ui: ui, share: share)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));
}

void main() {
  testWidgets('推荐视频 shows the first related video and its cover plays it', (tester) async {
    final rig = EndRig()..session.related = const [_card];
    await rig.mount(tester);

    expect(find.text('推荐视频'), findsOneWidget);
    expect(find.text(_card.title), findsOneWidget);
    expect(find.text('奶史_'), findsOneWidget);
    expect(find.text('170.3万'), findsOneWidget);
    expect(find.text('679'), findsOneWidget);
    expect(find.text('04:15'), findsOneWidget, reason: '17 writes the minutes with two digits');

    await tester.tap(find.byKey(const ValueKey('end-cover')));
    expect(rig.session.calls, ['playRelated BV1next']);
  });

  testWidgets('without related videos only 重播 and 分享 are there', (tester) async {
    final rig = EndRig();
    await rig.mount(tester);
    expect(find.text('推荐视频'), findsNothing);
    expect(find.byKey(const ValueKey('end-replay')), findsOneWidget);
    expect(find.byKey(const ValueKey('end-share')), findsOneWidget);
  });

  testWidgets('重播 replays, back leaves and ⋮ opens 更多', (tester) async {
    final rig = EndRig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-replay')));
    expect(rig.session.calls, ['replay']);
    await tester.tap(find.byKey(const ValueKey('end-back')));
    expect(rig.backs, 1);
    await tester.tap(find.byKey(const ValueKey('end-more')));
    expect(rig.panels.value, PlayerPanel.more);
  });

  testWidgets('分享 hands the link to the share seam, or on a video page goes through the actions', (tester) async {
    final rig = EndRig();
    await rig.mount(tester);
    await tester.tap(find.byKey(const ValueKey('end-share')));
    await tester.pump();
    expect(rig.shared, [Uri.parse('https://www.bilibili.com/video/BV1this')]);

    final actions = FakeVideoActions();
    final page = EndRig(details: FakePageDetails(actions: actions));
    await page.mount(tester);
    await tester.tap(find.byKey(const ValueKey('end-share')));
    await tester.pump();
    expect(actions.calls, ['ask share']);
    expect(page.shared, isEmpty);
  });

  testWidgets('without a link there is no 分享', (tester) async {
    final rig = EndRig()..session.shareLink = null;
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('end-share')), findsNothing);
  });

  testWidgets('every button presses through accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = EndRig()..session.related = const [_card];
    await rig.mount(tester);

    tester.semantics.tap(find.semantics.byLabel('返回'));
    tester.semantics.tap(find.semantics.byLabel('重播'));
    tester.semantics.tap(find.semantics.byLabel('播放：${_card.title}'));
    tester.semantics.tap(find.semantics.byLabel('分享'));
    await tester.pump();
    expect(rig.backs, 1);
    expect(rig.session.calls, ['replay', 'playRelated BV1next']);
    expect(rig.shared, hasLength(1));
    semantics.dispose();
  });

  testWidgets('17: the cover, the caption, the title and the actions sit where 17 has them', (tester) async {
    final rig = EndRig()..session.related = const [_card];
    await rig.mount(tester);
    const middle = 425.5 / 2;

    final cover = rig.rect(tester, 'end-cover');
    expect(cover, Rect.fromLTWH(50, middle - 18.75, 224, 126));
    expect(tester.getRect(find.text('推荐视频')).left, 51);
    expect(tester.getRect(find.text('推荐视频')).center.dy, closeTo(middle - 34.25, 0.5));
    expect(rig.rect(tester, 'end-title').left, 285);
    expect(rig.rect(tester, 'end-title').center.dy, closeTo(middle + 0.75, 0.5));
    expect(rig.rect(tester, 'end-back').center, within(distance: 0.01, from: const Offset(21.5, 42)));
    expect(rig.rect(tester, 'end-more').center, within(distance: 0.01, from: const Offset(756.5 - 21.5, 42)));
    expect(rig.rect(tester, 'end-share').right, closeTo(756.5 - 67.5, 0.01));
    expect(rig.rect(tester, 'end-share').center.dy, closeTo(middle - 33.75, 0.01));
    expect(rig.rect(tester, 'end-replay').center.dy, closeTo(middle - 33.75, 0.01));
    expect(rig.rect(tester, 'end-share').left - rig.rect(tester, 'end-replay').right, closeTo(PadInlineControlsTheme.endActionSpacing, 0.01));
  });

  testWidgets('the chapters stay under the dim, as 17 shows', (tester) async {
    final rig = EndRig()
      ..session.duration.value = 254
      ..session.chapters = const [Chapter(from: 0, to: 100, title: '引言'), Chapter(from: 100, to: 254, title: '猎手出动')];
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('pad-chapter-strip')), findsOneWidget);
    expect(find.text('猎手出动'), findsOneWidget);
  });
}
