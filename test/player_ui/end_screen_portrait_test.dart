import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/end_screen_portrait.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';

/// No cover address, so the image stays a grey box and nothing is fetched.
const _card = VideoCard(
  aid: 1,
  bvid: 'BV1next',
  cid: 2,
  title: 'EX-咖喱棒',
  cover: '',
  duration: 48,
  ownerMid: 3,
  ownerName: '後藤の独',
  views: 1357000,
  danmaku: 284,
  likes: 0,
);

final class Rig {
  Rig({this.details});

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

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
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
        child: Center(
          child: SizedBox(width: 440, height: 247.5, child: EndScreenPortrait(ui: ui, share: share)),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('推荐视频 shows the first related video, and both its cover and 立即播放 play it', (tester) async {
    final rig = Rig();
    rig.session.related = const [
      _card,
      VideoCard(
        aid: 9,
        bvid: 'BV1other',
        cid: 9,
        title: '另一个',
        cover: '',
        duration: 1,
        ownerMid: 9,
        ownerName: '',
        views: 0,
        danmaku: 0,
        likes: 0,
      ),
    ];
    await rig.mount(tester);

    expect(find.text('推荐视频'), findsOneWidget);
    expect(find.text('EX-咖喱棒'), findsOneWidget);
    expect(find.text('後藤の独'), findsOneWidget);
    expect(find.text('135.7万'), findsOneWidget);
    expect(find.text('284'), findsOneWidget);
    expect(find.text('0:48'), findsOneWidget);
    expect(find.text('另一个'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('end-play-now')));
    await tester.tap(find.byKey(const ValueKey('end-cover')));
    expect(rig.session.calls, ['playRelated BV1next', 'playRelated BV1next']);
  });

  testWidgets('重播 replays', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-replay')));
    expect(rig.session.calls, ['replay']);
  });

  testWidgets('分享 hands the video\'s link to the share seam', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-share')));
    await tester.pump();
    expect(rig.shared, [Uri.parse('https://www.bilibili.com/video/BV1this')]);
  });

  testWidgets('on a video page 分享 goes through the actions, so the share is counted', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions));
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-share')));
    await tester.pump();
    expect(actions.calls, ['ask share']);
    expect(rig.shared, isEmpty);

    tester.semantics.tap(find.semantics.byLabel('分享'));
    expect(actions.calls, ['ask share', 'ask share']);
  });

  for (final (status, answer, counted) in [
    ('a share', 'com.apple.UIKit.activity.Message', true),
    ('a dismissed sheet', '', false),
    ('unavailable, as on Windows', 'dev.fluttercommunity.plus/share/unavailable', false),
  ]) {
    testWidgets('the system share counts ${counted ? '' : 'nothing for '}$status', (tester) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return answer;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(await shareThroughSystem(Uri.parse('https://www.bilibili.com/video/BV1this')), counted);
      expect(calls.single.method, 'share');
    });
  }

  testWidgets('before the page\'s actions arrive 分享 shares by itself', (tester) async {
    final rig = Rig(details: FakePageDetails());
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-share')));
    await tester.pump();
    expect(rig.shared, [Uri.parse('https://www.bilibili.com/video/BV1this')]);
  });

  for (final (name, share, message) in <(String, ShareLink, String)>[
    ('fails', (_) async => throw StateError('no sheet'), 'Bad state: no sheet'),
    ('throws at once', (_) => throw StateError('no plugin'), 'Bad state: no plugin'),
  ]) {
    testWidgets('a share that $name is caught, logged with its error and says 分享失败', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      final rig = Rig();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => EndScreenPortrait(ui: rig.ui, share: share))],
          ),
        ),
      );
      addTearDown(rig.session.dispose);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('end-share')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('分享失败'), findsOneWidget);
      final failure = logs.events.singleWhere((event) => event.msg == 'share failed');
      expect(failure.f['error']?.toJson(), message);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('分享失败'), findsNothing);
    });
  }

  testWidgets('立即播放 is 26\'s pill, 12 from the edge on the cover\'s bottom line, with a 44 point target', (
    tester,
  ) async {
    final rig = Rig();
    rig.session.related = const [_card];
    await rig.mount(tester);

    final target = tester.getRect(find.byKey(const ValueKey('end-play-now')));
    final pill = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('end-play-now')), matching: find.byType(Container)),
    );
    final screen = tester.getRect(find.byType(EndScreenPortrait));
    final cover = tester.getRect(find.byKey(const ValueKey('end-cover')));
    expect(pill.size, const Size(78, 30));
    expect(pill.right, screen.right - 12);
    expect(pill.bottom, cover.bottom);
    expect(target.height, greaterThanOrEqualTo(44));
    expect(target.bottom, pill.bottom);

    await tester.tapAt(Offset(pill.center.dx, pill.top - 10));
    expect(rig.session.calls, ['playRelated BV1next'], reason: 'a touch just above the pill still plays');
  });

  testWidgets('the counts carry Bilibili\'s own icons, 5 before each count and 12.3 after it', (tester) async {
    final rig = Rig();
    rig.session.related = const [_card];
    await rig.mount(tester);

    expect(find.byType(Icon), findsNothing);
    final icons = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.size == const Size(BiliMetrics.endCountIconWidth, BiliMetrics.endCountIconHeight),
    );
    expect(icons, findsNWidgets(2));
    final views = tester.getRect(icons.first), danmaku = tester.getRect(icons.last);
    final viewsCount = tester.getRect(find.text('135.7万')), danmakuCount = tester.getRect(find.text('284'));
    expect(viewsCount.left - views.right, closeTo(5, 0.01));
    expect(danmaku.left - viewsCount.right, closeTo(12.3, 0.01));
    expect(danmakuCount.left - danmaku.right, closeTo(5, 0.01));
    expect(tester.renderObject(icons.first), paints..rrect(color: BiliColors.endMeta)..path(color: BiliColors.endMeta));
    expect(
      tester.renderObject(icons.last),
      paints
        ..rrect(color: BiliColors.endMeta)
        ..circle(color: BiliColors.endMeta)
        ..line(color: BiliColors.endMeta)
        ..circle(color: BiliColors.endMeta)
        ..line(color: BiliColors.endMeta),
    );
  });

  testWidgets('large text leaves the UP badge\'s fixed box alone', (tester) async {
    final rig = Rig();
    rig.session.related = const [_card];
    await rig.mount(tester);
    final normal = tester.getSize(find.text('UP'));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 440, height: 247.5, child: EndScreenPortrait(ui: rig.ui, share: rig.share)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.text('UP')), normal);
  });

  testWidgets('without related videos only 重播 and 分享 show', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    expect(find.text('推荐视频'), findsNothing);
    expect(find.text('立即播放'), findsNothing);
    expect(find.text('重播'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });

  testWidgets('without a link there is no 分享', (tester) async {
    final rig = Rig();
    rig.session.shareLink = null;
    await rig.mount(tester);

    expect(find.text('重播'), findsOneWidget);
    expect(find.text('分享'), findsNothing);
  });

  testWidgets('back and ⋮ work from the end screen too', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-back')));
    expect(rig.backs, 1);
    await tester.tap(find.byKey(const ValueKey('end-more')));
    expect(rig.panels.value, PlayerPanel.more);
  });

  testWidgets('every button carries a label', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    rig.session.related = const [_card];
    await rig.mount(tester);
    for (final label in ['返回', '更多', '播放：EX-咖喱棒', '立即播放', '重播', '分享']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    semantics.dispose();
  });

  testWidgets('the parts rise in one after another', (tester) async {
    final rig = Rig();
    rig.session.related = const [_card];
    await rig.mount(tester, settle: false);

    double opacityOf(String text) =>
        tester.widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first).opacity;

    expect(opacityOf('推荐视频'), 0);
    await tester.pump(const Duration(milliseconds: 300));
    final card = opacityOf('推荐视频');
    final actions = opacityOf('重播');
    expect(card, greaterThan(0));
    expect(actions, lessThan(card), reason: 'the actions come last');

    await tester.pumpAndSettle();
    expect(opacityOf('推荐视频'), 1);
    expect(opacityOf('重播'), 1);
  });
}
