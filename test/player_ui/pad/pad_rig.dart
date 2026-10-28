import 'package:bili_core/api.dart' show Chapter, UploaderCard, VideoDetail;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';
import '../../support/fake_video_actions.dart';
import '../../support/look_alike.dart';
import '../landscape_chrome_test.dart' show CountingChrome, DanmakuRig;

/// The iPad's full screen as the video page hands it out, on KaiC's iPad Pro 11" (1194 × 834 sideways, or 834 × 1194
/// upright) at 2×, over fakes: nothing reaches the network.
final class PadRig {
  PadRig({this.details, this.danmaku});

  final session = FakePlayerSession();
  final chrome = CountingChrome();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
  final FakePageDetails? details;
  final DanmakuRig? danmaku;
  int backs = 0;

  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: orientation.controls,
    onBack: () => backs += 1,
    details: details,
    danmaku: danmaku?.session,
  );

  /// [child] (built from [ui]) over [background], filling the screen.
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    bool landscape = true,
    Widget background = const ColoredBox(color: Colors.black),
    ThemeData? theme,
  }) async {
    showAsPad(tester, landscape: landscape);
    addTearDown(dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Material(
          type: MaterialType.transparency,
          child: Stack(fit: StackFit.expand, children: [background, child]),
        ),
      ),
    );
  }

  void dispose() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    session.dispose();
    details?.dispose();
    danmaku?.dispose();
  }
}

/// 08's video: 小猫们找朋友大会 at 00:00 of 04:14 with its five chapters (09's strip), 3959 likes, 4000+人正在看.
PadRig rig08({bool danmaku = true}) {
  final rig = PadRig(
    details: FakePageDetails(
      actions: FakeVideoActions(likeCount: 3959),
      uploader: const UploaderCard(
        mid: 1,
        name: '山顶小松鼠',
        face: '',
        fans: 30000,
        videos: 10,
        isVip: false,
        following: false,
      ),
      online: '4000+',
    ),
    danmaku: danmaku ? DanmakuRig() : null,
  );
  rig.session
    ..title = '小猫们找朋友大会：深林山洞篇【AI全城创作者】'
    ..detail = VideoDetail.fromJson({
      'bvid': 'BV1',
      'owner': {'mid': 1, 'name': '山顶小松鼠', 'face': ''},
    })
    ..quality = 112
    ..chapters = const [
      Chapter(from: 0, to: 20.1, title: '开场'),
      Chapter(from: 20.1, to: 92.3, title: '寻找好位置'),
      Chapter(from: 92.3, to: 204.9, title: '队长出发'),
      Chapter(from: 204.9, to: 224, title: '游戏结束'),
      Chapter(from: 224, to: 254, title: 'qwnrt'),
    ]
    ..duration.value = 254;
  return rig;
}

Offset centreOf(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

/// Frames through a toast's fade in, its two seconds and its fade out.
Future<void> drainToast(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
