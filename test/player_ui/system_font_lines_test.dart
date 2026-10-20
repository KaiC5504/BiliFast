import 'package:bili_core/api.dart'
    show
        Chapter,
        QualityOption,
        UgcSeason,
        UploaderCard,
        VideoCard,
        VideoDetail,
        VideoOwner,
        VideoStat,
        VideoTag,
        VideoTagKind;
import 'package:bilifast/player_ui/end_screen_portrait.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart' show LandscapeCornerOnline;
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import '../support/stand_in_fonts.dart';
import 'end_screen_landscape_test.dart' as end_landscape;
import 'end_screen_portrait_test.dart' as end_portrait;
import 'landscape_chrome_test.dart' as landscape;
import 'panels/panel_layer_test.dart' as panels;
import 'vertical_chrome_test.dart' as vertical;

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

const _mixed = 'LOUD 8K HDR 我们接受了 VIT 的回溯 2024 总决赛 Game 5 赛后采访';

Future<void> _useSystemFont(WidgetTester tester) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  BiliFonts.family = BiliFonts.system;
  await tester.runAsync(loadSystemFontStandIns);
}

RenderParagraph _paragraph(WidgetTester tester, Finder text) => tester.renderObject<RenderParagraph>(
  find.descendant(of: text, matching: find.byType(RichText), matchRoot: true).first,
);

/// Every line of [text] where a Chinese line in the same style sits: the paragraph as tall, each baseline as low.
void _expectChineseLines(WidgetTester tester, Finder text) {
  final paragraph = _paragraph(tester, text);
  final width = paragraph.softWrap ? paragraph.size.width : double.infinity;
  TextPainter laid(InlineSpan span, {StrutStyle? strut, int? maxLines}) => TextPainter(
    text: span,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: maxLines,
    strutStyle: strut,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: width);
  final drawn = laid(paragraph.text, strut: paragraph.strutStyle, maxLines: paragraph.maxLines);
  final lines = drawn.computeLineMetrics();
  final chinese = laid(TextSpan(text: '设置版本' * 60, style: paragraph.text.style), maxLines: lines.length);
  final reference = chinese.computeLineMetrics();
  expect(reference, hasLength(lines.length));
  // The text's own height: a box around it may squeeze the paragraph.
  expect(drawn.height, closeTo(chinese.height, 0.01), reason: '${paragraph.text.toPlainText()}: height');
  for (final (index, line) in lines.indexed) {
    expect(line.baseline, closeTo(reference[index].baseline, 0.01), reason: 'line ${index + 1}\'s baseline');
  }
  drawn.dispose();
  chinese.dispose();
}

/// How far down the screen [text]'s first baseline is.
double _baselineOf(WidgetTester tester, Finder text) {
  final paragraph = _paragraph(tester, text);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    strutStyle: paragraph.strutStyle,
  )..layout(maxWidth: paragraph.softWrap ? paragraph.size.width : double.infinity);
  final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter.dispose();
  return paragraph.localToGlobal(Offset.zero).dy + baseline;
}

Finder _key(String key) => find.byKey(ValueKey(key));

const _uploader = UploaderCard(
  mid: 7,
  name: 'PRORES 8K 官方',
  face: '',
  fans: 61290,
  videos: 0,
  isVip: true,
  following: false,
);

VideoDetail _detail() => VideoDetail.fromJson({
  'bvid': 'BV1',
  'title': _mixed,
  'owner': {'mid': 7, 'name': 'PRORES 8K 官方', 'face': ''},
  'stat': {'view': 56000},
});

void main() {
  group('landscape', () {
    testWidgets('the title, the uploader and bgm chips and N人正在看 keep the Chinese line', (tester) async {
      await _useSystemFont(tester);
      final details = FakePageDetails(
        actions: FakeVideoActions(),
        uploader: _uploader,
        online: '1.2万',
        tags: const [VideoTag(id: 2, name: '发现《Whatever It Takes》 2024 Remix', kind: VideoTagKind.bgm)],
      );
      final rig = landscape.Rig(details: details)
        ..session.title = _mixed
        ..session.detail = _detail();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      _expectChineseLines(tester, _key('landscape-title'));
      _expectChineseLines(tester, _key('landscape-uploader-name'));
      _expectChineseLines(tester, find.text('发现《Whatever It Takes》 2024 Remix'));
      _expectChineseLines(tester, find.text('1.2万人正在看'));

      rig.chrome.hide();
      await tester.pumpAndSettle();
      _expectChineseLines(tester, find.descendant(of: _key('landscape-corner-online'), matching: find.byType(Text)));
    });

    testWidgets('UP主已关闭弹幕 sits where 发个友善的弹幕见证当下 does', (tester) async {
      await _useSystemFont(tester);
      final open = landscape.Rig(danmaku: landscape.DanmakuRig());
      await open.mount(tester);
      final chinese = _baselineOf(tester, find.text('发个友善的弹幕见证当下'));

      final closed = landscape.Rig(danmaku: landscape.DanmakuRig(closed: true));
      await closed.mount(tester);
      expect(_baselineOf(tester, find.text('UP主已关闭弹幕')), closeTo(chinese, 0.01));
      _expectChineseLines(tester, find.text('UP主已关闭弹幕'));
    });

    testWidgets('the corner count keeps the Chinese line outside the chrome too', (tester) async {
      await _useSystemFont(tester);
      final rig = landscape.Rig(details: FakePageDetails(online: '1000+'));
      await tester.pumpWidget(
        MaterialApp(
          home: LandscapeCornerOnline(ui: rig.ui, shown: true),
        ),
      );
      await tester.pumpAndSettle();
      _expectChineseLines(tester, find.text('1000+人正在看'));
      addTearDown(() {
        rig.chrome.dispose();
        rig.panels.dispose();
        rig.orientation.dispose();
        rig.session.dispose();
        rig.details?.dispose();
      });
    });
  });

  group('竖屏', () {
    testWidgets('both lines of the title keep the Chinese pitch', (tester) async {
      await _useSystemFont(tester);
      final rig = vertical.Rig()..session.title = '$_mixed $_mixed';
      await rig.mount(tester);
      _expectChineseLines(tester, _key('vertical-title'));
      expect(_paragraph(tester, _key('vertical-title')).size.height, greaterThan(40), reason: 'two lines');
    });

    testWidgets('the name, 粉丝, N人正在看 and UP主已关闭弹幕 keep the Chinese line', (tester) async {
      await _useSystemFont(tester);
      final rig = vertical.Rig()
        ..session.title = '标题'
        ..session.detail = _detail()
        ..details = FakePageDetails(actions: FakeVideoActions(), uploader: _uploader, online: '1.2万')
        ..danmaku = vertical.DanmakuRig(closed: true);
      await rig.mount(tester);
      await tester.pumpAndSettle();
      _expectChineseLines(tester, _key('vertical-name'));
      _expectChineseLines(tester, _key('vertical-fans'));
      _expectChineseLines(tester, find.text('1.2万人正在看'));
      _expectChineseLines(tester, find.text('UP主已关闭弹幕'));
    });

    testWidgets('UP主已关闭弹幕 sits where 已关闭弹幕 does', (tester) async {
      await _useSystemFont(tester);
      final off = vertical.Rig();
      off.session.danmakuOn = false;
      await off.mount(tester);
      final chinese = _baselineOf(tester, find.text('已关闭弹幕'));

      final closed = vertical.Rig()..danmaku = vertical.DanmakuRig(closed: true);
      await closed.mount(tester);
      expect(_baselineOf(tester, find.text('UP主已关闭弹幕')), closeTo(chinese, 0.01));
    });
  });

  group('end screens', () {
    const card = VideoCard(
      aid: 1,
      bvid: 'BV1next',
      cid: 2,
      title: _mixed,
      cover: '',
      duration: 48,
      ownerMid: 3,
      ownerName: 'PRORES 8K 官方',
      views: 1357000,
      danmaku: 284,
      likes: 0,
    );

    testWidgets('landscape: the uploader, both lines of a related title and its uploader keep the Chinese line', (
      tester,
    ) async {
      await _useSystemFont(tester);
      final rig = end_landscape.Rig(details: FakePageDetails(actions: FakeVideoActions()))
        ..session.detail = _detail()
        ..session.related = const [card];
      await rig.mount(tester);
      _expectChineseLines(tester, find.text('PRORES 8K 官方').first);
      _expectChineseLines(tester, find.text('PRORES 8K 官方').last);
      _expectChineseLines(tester, find.text(_mixed));
      expect(_paragraph(tester, find.text(_mixed)).size.height, greaterThan(25), reason: 'two lines');
    });

    testWidgets('portrait: the related title and its uploader keep the Chinese line', (tester) async {
      await _useSystemFont(tester);
      final rig = end_portrait.Rig()..session.related = const [card];
      addTearDown(() {
        rig.chrome.dispose();
        rig.panels.dispose();
        rig.orientation.dispose();
        rig.session.dispose();
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: BiliFonts.family, fontFamilyFallback: BiliFonts.fallback, fontSize: 14),
            child: Center(
              child: SizedBox(width: 440, height: 247.5, child: EndScreenPortrait(ui: rig.ui, share: rig.share)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectChineseLines(tester, find.text(_mixed));
      _expectChineseLines(tester, find.text('PRORES 8K 官方'));
    });
  });

  testWidgets('a chapter title over the bar keeps the Chinese line', (tester) async {
    await _useSystemFont(tester);
    final repaint = ValueNotifier(0);
    addTearDown(repaint.dispose);
    var position = 0.0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(fontFamily: BiliFonts.family, fontFamilyFallback: BiliFonts.fallback),
          child: Center(
            child: SizedBox(
              width: 218,
              child: SeekBar(
                position: () => position,
                duration: () => 100,
                buffered: () => 0,
                repaint: repaint,
                onScrub: (seconds) {
                  position = seconds;
                  repaint.value++;
                },
                onCommit: (_) {},
                onCancel: () {},
                chapters: const [Chapter(from: 0, to: 100, title: 'OP 开场 Part 1')],
              ),
            ),
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byType(SeekBar));
    final gesture = await tester.startGesture(bar.centerLeft + const Offset(30, 0));
    await gesture.moveBy(const Offset(4, 0));
    await tester.pumpAndSettle();
    _expectChineseLines(tester, find.text('OP 开场 Part 1'));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('panels', () {
    testWidgets('清晰度\'s rows and 大会员 badges keep the Chinese line', (tester) async {
      await _useSystemFont(tester);
      final session = FakePlayerSession()
        ..qualities = const [QualityOption(id: 120, name: '超清 4K'), QualityOption(id: 112, name: '高清 1080P+')];
      final rig = await panels.pumpLayer(tester, panels.Shape.landscape, session: session);
      await panels.open(tester, rig, PlayerPanel.quality);
      _expectChineseLines(tester, find.text('4K 超高清'));
      _expectChineseLines(tester, find.text('1080P 高码率'));
      _expectChineseLines(tester, find.text('大会员').first);
    });

    testWidgets('选集\'s 合集 sheet: the intro, an episode\'s two title lines and its date keep the Chinese line', (
      tester,
    ) async {
      await _useSystemFont(tester);
      final episode = Episode(
        bvid: 'BV1',
        cid: 1,
        title: '$_mixed $_mixed',
        current: false,
        cover: '',
        duration: 32,
        pubdate: DateTime(2023, 8, 28).millisecondsSinceEpoch ~/ 1000,
        views: 209000,
        danmaku: 237,
      );
      final session = FakePlayerSession()
        ..episodesAreParts = false
        ..episodes = [episode, Episode(bvid: 'BV2', cid: 2, title: 'P2 第二集', current: true)]
        ..detail = VideoDetail(
          bvid: 'BV2',
          aid: 2,
          title: '',
          cover: '',
          pubdate: 0,
          duration: 66,
          desc: '',
          descParts: const [],
          copyright: 1,
          owner: VideoOwner.empty,
          stat: VideoStat.zero,
          pages: const [],
          season: const UgcSeason(id: 1, title: 'MAD 系列 2024', intro: 'Thanks 求订阅！谢谢大家 2024', sections: []),
          staff: const [],
          width: 1920,
          height: 1080,
          honor: null,
          redirectURL: null,
        );
      final rig = await panels.pumpLayer(tester, panels.Shape.portrait, session: session);
      await panels.open(tester, rig, PlayerPanel.episodes);
      _expectChineseLines(tester, find.text('MAD 系列 2024'));
      _expectChineseLines(tester, find.text('Thanks 求订阅！谢谢大家 2024'));
      _expectChineseLines(tester, find.text('$_mixed $_mixed', findRichText: true));
      expect(
        _paragraph(tester, find.text('$_mixed $_mixed', findRichText: true)).size.height,
        greaterThan(30),
        reason: 'two lines',
      );
      _expectChineseLines(tester, find.text('2023年8月28日'));

      await tester.tap(find.byKey(const ValueKey('sheet-intro')));
      await tester.pumpAndSettle();
      _expectChineseLines(tester, find.text('Thanks 求订阅！谢谢大家 2024 收起', findRichText: true));
    });

    testWidgets('选集 for parts keeps a part\'s title on the Chinese line', (tester) async {
      await _useSystemFont(tester);
      final session = FakePlayerSession()
        ..episodes = const [
          Episode(bvid: 'BV1', cid: 1, title: 'P1 OP 开场 1080P', current: true, duration: 95),
          Episode(bvid: 'BV1', cid: 2, title: 'P2 第二部分', current: false),
        ];
      final rig = await panels.pumpLayer(tester, panels.Shape.portrait, session: session);
      await panels.open(tester, rig, PlayerPanel.episodes);
      _expectChineseLines(tester, find.text('P1 OP 开场 1080P'));
    });
  });
}
