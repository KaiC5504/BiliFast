import 'package:bili_core/api.dart' hide RichText;
import 'package:bili_core/logic.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/desc_text.dart';
import 'package:bilifast/video/intro/title_block.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _published = DateTime(2026, 10, 11, 21, 5);

VideoDetail _detail({
  String? honor,
  int copyright = 0,
  List<DescPart> desc = const [],
  String title = '恭喜你，终于触发了B站大保底！',
  String bvid = 'BV1PdJD6iEFb',
  String? argue,
}) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: title,
  cover: '',
  pubdate: _published.millisecondsSinceEpoch ~/ 1000,
  duration: 100,
  desc: '',
  descParts: desc,
  copyright: copyright,
  owner: VideoOwner.empty,
  stat: const VideoStat(view: 37000, danmaku: 337, reply: 0, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: honor,
  redirectURL: null,
  argueMessage: argue,
);

const _notice = '个人观点，仅供参考';

const _desc = [
  DescPart(text: '从03:15开始，高潮在1:02:03。看 https://example.com/a?b=1。和 www.bilibili.com/read 还有 '),
  DescPart(text: '小明', mentionMid: 42),
  DescPart(
    text: ' 相关：BV1AB411c7mD、av170001 与 https://www.bilibili.com/video/BV1GJ411x7h7?p=2 和 https://www.bilibili.com/video/av2/',
  ),
];

const _tags = [
  VideoTag(id: 1, name: '必剪创作', kind: VideoTagKind.normal),
  VideoTag(id: 2, name: '星穹铁道创作者激励计划', kind: VideoTagKind.topic),
  VideoTag(id: 3, name: '战无不胜进行曲', kind: VideoTagKind.bgm),
  VideoTag(id: 4, name: '游戏', kind: VideoTagKind.normal),
];

final class Rig {
  Rig({String? online}) : online = ValueNotifier(online);

  final ValueNotifier<String?> online;
  final seeks = <double>[];
  final videos = <String>[];
  final links = <Uri>[];
  bool linkOpens = true;
  Object? linkThrows;
  bool _disposes = false;

  Future<bool> openLink(Uri link) async {
    links.add(link);
    if (linkThrows case final error?) throw error;
    return linkOpens;
  }

  Future<void> mount(
    WidgetTester tester,
    VideoDetail detail, {
    List<VideoTag> tags = _tags,
    bool disableAnimations = false,
  }) async {
    if (!_disposes) addTearDown(online.dispose);
    _disposes = true;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: const Size(440, 956), disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          // Overlay.wrap passes a remount's new block through, so its state sees didUpdateWidget.
          child: Overlay.wrap(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 440,
                child: TitleBlock(
                  detail: detail,
                  online: online,
                  tags: tags,
                  onSeek: seeks.add,
                  onOpenVideo: videos.add,
                  openLink: openLink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.text(_detail().title));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tapOnText(find.textRange.ofSubstring(text));
  await tester.pump();
}

/// The toast fades in, waits two seconds and fades out, each step starting a frame after the last ends.
Future<void> _expireToast(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('collapsed', () {
    testWidgets('the title is one line and the details are hidden', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(copyright: 1, desc: _desc));

      final title = tester.widget<Text>(find.text(_detail().title));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(find.text('BV1PdJD6iEFb'), findsNothing);
      expect(find.text('未经作者授权禁止转载'), findsNothing);
      expect(find.text('必剪创作'), findsNothing);
      expect(find.textContaining('03:15'), findsNothing);
    });

    testWidgets('a long title is cut with … and wraps once expanded', (tester) async {
      final rig = Rig();
      final long = _detail(title: '很长的标题' * 12);
      await rig.mount(tester, long);
      final collapsed = tester.getSize(find.text(long.title)).height;

      await tester.tap(find.text(long.title));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(long.title)).maxLines, isNull);
      expect(tester.getSize(find.text(long.title)).height, greaterThan(collapsed * 2));
    });
  });

  group('活动', () {
    testWidgets('comes before the title when the video has an honor', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(honor: '全站排行榜最高第3名'));
      expect(find.text('活动'), findsOneWidget);
      expect(tester.getCenter(find.text('活动')).dx, lessThan(tester.getTopLeft(find.text(_detail().title)).dx));
      expect(tester.renderObject<RenderParagraph>(find.text('活动')).text.style?.color, BiliColors.pink);
    });

    testWidgets('is absent without one', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail());
      expect(find.text('活动'), findsNothing);
    });
  });

  group('meta line', () {
    testWidgets('plays, danmaku, the local date and N人正在看', (tester) async {
      final rig = Rig(online: '53');
      await rig.mount(tester, _detail());
      expect(find.text('3.7万'), findsOneWidget);
      expect(find.text('337'), findsOneWidget);
      expect(find.text('2026年10月11日 21:05'), findsOneWidget);
      expect(find.text(TimeFormat.publish(_detail().pubdate)), findsOneWidget);
      expect(find.text('53人正在看'), findsOneWidget);
    });

    testWidgets('N人正在看 waits for the count and follows it', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail());
      expect(find.textContaining('人正在看'), findsNothing);

      rig.online.value = '1000+';
      await tester.pump();
      expect(find.text('1000+人正在看'), findsOneWidget);

      rig.online.value = '';
      await tester.pump();
      expect(find.textContaining('人正在看'), findsNothing);
    });
  });

  group('notice', () {
    late String? font;
    setUp(() {
      font = BiliFonts.family;
      BiliFonts.family = null;
    });
    tearDown(() => BiliFonts.family = font);

    testWidgets('ⓘ and the text sit a 16 pt line 2 under the meta line, grey at 12, after the ▶ column', (
      tester,
    ) async {
      final rig = Rig();
      await rig.mount(tester, _detail(argue: _notice));

      final notice = find.text(_notice);
      expect(notice, findsOneWidget);
      final date = find.text('2026年10月11日 21:05');
      expect(
        tester.getCenter(notice).dy - tester.getCenter(date).dy,
        moreOrLessEquals(IntroTheme.noticeGap + IntroTheme.noticeLine),
      );
      expect(
        tester.getTopLeft(notice).dx,
        moreOrLessEquals(BiliMetrics.gutter + IntroTheme.metaLead + IntroTheme.noticeIcon + IntroTheme.noticeIconGap),
      );
      final style = tester.renderObject<RenderParagraph>(notice).text.style!;
      expect(style.color, BiliColors.secondaryText);
      expect(style.fontSize, 12);
      expect(style.fontFamily, isNull);
      expect(tester.widget<Text>(notice).maxLines, 1);
    });

    testWidgets('is absent without a message', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail());
      expect(find.text(_notice), findsNothing);
    });

    testWidgets('collapsed, the block grows 16 for it; expanded, the BV line moves 18', (tester) async {
      final plain = Rig();
      await plain.mount(tester, _detail(bvid: 'BV1plain'));
      final collapsed = tester.getSize(find.byType(TitleBlock)).height;
      await plain.toggle(tester);
      final bv = tester.getCenter(find.text('BV1plain')).dy;

      final noted = Rig();
      await noted.mount(tester, _detail(bvid: 'BV1noted', argue: _notice));
      expect(
        tester.getSize(find.byType(TitleBlock)).height - collapsed,
        moreOrLessEquals(IntroTheme.noticeGap + IntroTheme.noticeLine - IntroTheme.noticeHang),
      );
      expect(IntroTheme.noticeGap + IntroTheme.noticeLine - IntroTheme.noticeHang, 16);
      await noted.toggle(tester);
      expect(tester.getCenter(find.text('BV1noted')).dy - bv, moreOrLessEquals(18));
      expect(find.text(_notice), findsOneWidget);
    });
  });

  group('expanded', () {
    testWidgets('tapping the title row shows the BV id, the description and the plain tags, and again hides them', (
      tester,
    ) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      await rig.toggle(tester);

      expect(find.text('BV1PdJD6iEFb'), findsOneWidget);
      expect(find.textContaining('从03:15开始'), findsOneWidget);
      expect(find.text('必剪创作'), findsOneWidget);
      expect(find.text('游戏'), findsOneWidget);
      // Topics and BGM are the chips under the actions, not here.
      expect(find.text('星穹铁道创作者激励计划'), findsNothing);
      expect(find.text('战无不胜进行曲'), findsNothing);
      // The ⌄ is now a ⌃.
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0.5);

      await rig.toggle(tester);
      expect(find.text('BV1PdJD6iEFb'), findsNothing);
      expect(find.text('必剪创作'), findsNothing);
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0);
    });

    testWidgets('expanding grows the block over time, and at once when animations are off', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      final collapsed = tester.getSize(find.byType(TitleBlock)).height;

      await tester.tap(find.text(_detail().title));
      await tester.pump();
      // Frame by frame, as a screen draws it.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final midway = tester.getSize(find.byType(TitleBlock)).height;
      await tester.pumpAndSettle();
      final open = tester.getSize(find.byType(TitleBlock)).height;
      expect(midway, greaterThan(collapsed));
      expect(midway, lessThan(open));

      final still = Rig();
      await still.mount(tester, _detail(desc: _desc, bvid: 'BV1other'), disableAnimations: true);
      await tester.tap(find.text(_detail().title));
      await tester.pump();
      expect(tester.getSize(find.byType(TitleBlock)).height, open);
    });

    testWidgets('the title row presses through accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      final rig = Rig();
      await rig.mount(tester, _detail());

      tester.semantics.tap(find.semantics.byLabel(_detail().title));
      await tester.pumpAndSettle();
      expect(find.text('BV1PdJD6iEFb'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the reprint notice shows for an original only', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(copyright: 1));
      await rig.toggle(tester);
      expect(find.text('未经作者授权禁止转载'), findsOneWidget);
      expect(tester.getCenter(find.text('未经作者授权禁止转载')).dy, tester.getCenter(find.text('BV1PdJD6iEFb')).dy);

      final reprint = Rig();
      await reprint.mount(tester, _detail(copyright: 2, bvid: 'BV1other'));
      await reprint.toggle(tester);
      expect(find.text('未经作者授权禁止转载'), findsNothing);
    });

    testWidgets('a new video starts collapsed', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail());
      await rig.toggle(tester);
      expect(find.text('BV1PdJD6iEFb'), findsOneWidget);

      await rig.mount(tester, _detail(bvid: 'BV1next'));
      expect(find.text('BV1next'), findsNothing);
    });
  });

  group('description', () {
    testWidgets('timestamps seek', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      await rig.toggle(tester);

      await _tapText(tester, '03:15');
      await _tapText(tester, '1:02:03');
      expect(rig.seeks, [195, 3723]);
    });

    testWidgets('web addresses open in the browser, without the punctuation after them', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      await rig.toggle(tester);

      await _tapText(tester, 'example.com');
      await _tapText(tester, 'www.bilibili.com/read');
      expect(rig.links, [Uri.parse('https://example.com/a?b=1'), Uri.parse('http://www.bilibili.com/read')]);
      expect(rig.videos, isEmpty);
    });

    testWidgets('BV and av ids, and video addresses on bilibili.com, open the video', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      await rig.toggle(tester);

      await _tapText(tester, 'BV1AB411c7mD');
      await _tapText(tester, 'av170001');
      await _tapText(tester, 'video/BV1GJ411x7h7');
      await _tapText(tester, 'video/av2');
      expect(rig.videos, ['BV1AB411c7mD', 'av170001', 'BV1GJ411x7h7', 'av2']);
      expect(rig.links, isEmpty);
    });

    testWidgets('a web address that cannot open says so, whether the browser declines or throws', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      await rig.toggle(tester);

      await _tapText(tester, 'example.com');
      expect(find.text('无法打开链接'), findsNothing);

      rig.linkOpens = false;
      await _tapText(tester, 'example.com');
      expect(find.text('无法打开链接'), findsOneWidget);
      await _expireToast(tester);
      expect(find.text('无法打开链接'), findsNothing);

      rig.linkThrows = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      await _tapText(tester, 'example.com');
      expect(find.text('无法打开链接'), findsOneWidget);
      await _expireToast(tester);
      expect(rig.links, hasLength(3));
    });

    testWidgets('mentions are blue but lead nowhere yet; plain text stays grey', (tester) async {
      final rig = Rig();
      await rig.mount(tester, _detail(desc: _desc));
      await rig.toggle(tester);

      final root = tester.widget<Text>(find.textContaining('@小明')).textSpan! as TextSpan;
      final spans = root.children!.cast<TextSpan>();
      final mention = spans.singleWhere((span) => span.text == '@小明');
      expect(mention.style?.color, BiliColors.link);
      expect(mention.recognizer, isNull);
      expect(root.style?.color, BiliColors.secondaryText);
      expect(spans.firstWhere((span) => span.text == '03:15').style?.color, BiliColors.link);

      await _tapText(tester, '@小明');
      expect(rig.seeks, isEmpty);
      expect(rig.videos, isEmpty);
      expect(rig.links, isEmpty);
    });

    test('runs: mentions from desc_v2, addresses cut out before ids and timestamps', () {
      expect(
        descriptionRuns(const [
          DescPart(text: '看 https://www.bilibili.com/video/BV1GJ411x7h7。03:15 '),
          DescPart(text: '@小明', mentionMid: 42),
          DescPart(text: ' BV1AB411c7mD'),
        ]),
        const [
          RichRun.text('看 '),
          RichRun.link(
            title: 'https://www.bilibili.com/video/BV1GJ411x7h7',
            url: 'https://www.bilibili.com/video/BV1GJ411x7h7',
          ),
          RichRun.text('。'),
          RichRun.timestamp(label: '03:15', seconds: 195),
          RichRun.text(' '),
          RichRun.mention(name: '@小明', mid: 42),
          RichRun.text(' '),
          RichRun.video(id: 'BV1AB411c7mD'),
        ],
      );
    });

    test('leading spaces, full-width or not, stay in the runs', () {
      const text = '第一段\n　　第二段\n  第三段';
      expect(descriptionRuns(const [DescPart(text: text)]), const [RichRun.text(text)]);
    });

    testWidgets('a tab that opens a line indents it to the next 28 pt stop; one mid-line and leading spaces stay', (
      tester,
    ) async {
      // MiSans's tightening would move the text after the stop by a tenth of a point.
      final font = BiliFonts.family;
      BiliFonts.family = null;
      addTearDown(() => BiliFonts.family = font);
      final rig = Rig();
      await rig.mount(
        tester,
        _detail(
          desc: const [
            DescPart(text: '\t第一段\n第二段\n\t\t第三段\n'),
            DescPart(text: '\t第四段'),
            DescPart(text: '\n　　第五段 03:15\t第六'),
          ],
        ),
      );
      await rig.toggle(tester);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(DescriptionText), matching: find.byType(RichText)),
      );
      final plain = paragraph.text.toPlainText();
      double x(String text) => paragraph.getOffsetForCaret(TextPosition(offset: plain.indexOf(text)), Rect.zero).dx;
      expect(x('第一段'), moreOrLessEquals(IntroTheme.descTabStop));
      expect(x('第二段'), moreOrLessEquals(0));
      expect(x('第三段'), moreOrLessEquals(2 * IntroTheme.descTabStop));
      expect(x('第四段'), moreOrLessEquals(IntroTheme.descTabStop));
      expect(plain, contains('　　第五段'));
      expect(x('第五段'), greaterThan(0));
      expect(plain, contains('03:15\t第六'));

      final widths = <double?>[];
      paragraph.text.visitChildren((span) {
        if (span is WidgetSpan) widths.add((span.child as SizedBox).width);
        return true;
      });
      expect(widths, [IntroTheme.descTabStop, 2 * IntroTheme.descTabStop, IntroTheme.descTabStop]);
    });

    test('an address written twice is a link both times', () {
      final runs = descriptionRuns(const [DescPart(text: 'https://a.cn 和 https://a.cn')]);
      expect(runs.whereType<LinkRun>(), hasLength(2));
    });

    test('link targets: video addresses on bilibili.com open in the app', () {
      expect(linkTarget(const RichRun.link(title: 't', url: 'https://m.bilibili.com/video/BV1GJ411x7h7')), (
        video: 'BV1GJ411x7h7',
        web: null,
      ));
      expect(linkTarget(const RichRun.link(title: 't', url: 'https://www.bilibili.com/video/av170001?p=2')), (
        video: 'av170001',
        web: null,
      ));
      expect(linkTarget(const RichRun.link(title: 't', url: 'https://www.bilibili.com/video/online.html')), (
        video: null,
        web: Uri.parse('https://www.bilibili.com/video/online.html'),
      ));
      expect(linkTarget(const RichRun.link(title: 't', url: 'https://b23.tv/abc')), (
        video: null,
        web: Uri.parse('https://b23.tv/abc'),
      ));
      expect(linkTarget(const RichRun.link(title: 't', url: 'javascript:alert(1)')), isNull);
      expect(linkTarget(const RichRun.text('x')), isNull);
    });
  });

  testWidgets('expanded, the plain tags keep their room below them; without tags the block ends at its text', (
    tester,
  ) async {
    final rig = Rig();
    await rig.mount(tester, _detail(desc: _desc));
    await rig.toggle(tester);
    final block = tester.getRect(find.byType(TitleBlock));
    expect(block.bottom - tester.getRect(find.byType(Wrap)).bottom, moreOrLessEquals(IntroTheme.tagsBottom));

    final bare = Rig();
    await bare.mount(
      tester,
      _detail(desc: _desc, bvid: 'BV1other'),
      tags: const [],
    );
    await bare.toggle(tester);
    expect(
      tester.getRect(find.byType(TitleBlock)).bottom,
      moreOrLessEquals(tester.getRect(find.byType(DescriptionText)).bottom),
    );
  });

  testWidgets('without a description or plain tags the expanded block is just the BV line', (tester) async {
    final rig = Rig();
    await rig.mount(
      tester,
      _detail(),
      tags: const [VideoTag(id: 2, name: '话题', kind: VideoTagKind.topic)],
    );
    await rig.toggle(tester);
    expect(find.text('BV1PdJD6iEFb'), findsOneWidget);
    expect(find.byType(DescriptionText), findsNothing);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('swapping the description swaps its links', (tester) async {
    final rig = Rig();
    await rig.mount(tester, _detail(desc: const [DescPart(text: '看03:15')]));
    await rig.toggle(tester);
    await rig.mount(tester, _detail(desc: const [DescPart(text: '看04:00')]));
    await _tapText(tester, '04:00');
    expect(rig.seeks, [240]);
  });
}
