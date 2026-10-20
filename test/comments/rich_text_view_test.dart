import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/rich_text_view.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 15, height: 25 / 15, color: BiliColors.text);
const _emoteUrl = 'https://i0.hdslb.com/bfs/emote/a.png';

final class Rig {
  final seeks = <int>[];
  final videos = <String>[];
  final links = <Uri>[];
  bool linkOpens = true;
  Object? linkThrows;

  Future<bool> openLink(Uri link) async {
    links.add(link);
    if (linkThrows case final error?) throw error;
    return linkOpens;
  }

  Future<void> mount(
    WidgetTester tester,
    List<RichRun> runs, {
    bool seeks = true,
    bool videos = true,
    InlineSpan? leading,
    int? maxLines,
    bool marksReplyTarget = true,
    TextStyle style = _style,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 956)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay.wrap(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 372,
                child: CommentText(
                  runs: runs,
                  style: style,
                  leading: leading,
                  maxLines: maxLines,
                  onSeek: seeks ? this.seeks.add : null,
                  onOpenVideo: videos ? this.videos.add : null,
                  openLink: openLink,
                  marksReplyTarget: marksReplyTarget,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Finder get _paragraph => find.descendant(of: find.byType(CommentText), matching: find.byType(RichText));

Text _text(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(of: find.byType(CommentText), matching: find.byType(Text)));

TextSpan _root(WidgetTester tester) => _text(tester).textSpan! as TextSpan;

TextSpan _span(WidgetTester tester, String text) =>
    _root(tester).children!.whereType<TextSpan>().singleWhere((span) => span.text == text);

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
  testWidgets('plain text as it is, the leading span first, and an ellipsis once maxLines runs out', (tester) async {
    final rig = Rig();
    const leading = TextSpan(
      text: 'HYSSNH: ',
      style: TextStyle(color: BiliColors.secondaryText),
    );
    await rig.mount(tester, const [RichRun.text('但拳头关于这个规定是如果不符合回合中立即进行回溯的情况')], leading: leading);
    expect(_root(tester).children!.first, same(leading));
    expect(find.text('HYSSNH: 但拳头关于这个规定是如果不符合回合中立即进行回溯的情况', findRichText: true), findsOneWidget);
    expect(_root(tester).style, isNull);
    expect(_text(tester).style, _style);
    expect(_text(tester).overflow, isNull);

    await rig.mount(tester, [RichRun.text('回溯' * 60)], maxLines: 2);
    final paragraph = tester.renderObject<RenderParagraph>(_paragraph);
    expect(paragraph.maxLines, 2);
    expect(paragraph.overflow, TextOverflow.ellipsis);
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(tester.getSize(_paragraph).height, 50);
  });

  group('emotes', () {
    testWidgets('inline at 4/3 of the text size, twice that for a large one, the token as text without a url', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final rig = Rig();
      await rig.mount(tester, const [
        RichRun.text('也不能再重打了'),
        RichRun.emote(token: '[无语]', url: _emoteUrl, size: 1),
        RichRun.emote(token: '[热词系列_大]', url: _emoteUrl, size: 2),
        RichRun.emote(token: '[空]', url: '', size: 1),
      ]);
      final images = tester.widgetList<RemoteImage>(find.byType(RemoteImage)).toList();
      expect(images, hasLength(2));
      expect(images.map((image) => image.fit), everyElement(BoxFit.contain));
      expect(images.map((image) => image.placeholder), everyElement(isNotNull));
      expect(tester.getSize(find.byType(RemoteImage).first).width, moreOrLessEquals(20));
      expect(tester.getSize(find.byType(RemoteImage).last).width, moreOrLessEquals(40));
      expect(images.first.size!.width, moreOrLessEquals(20));
      expect(find.textContaining('[空]', findRichText: true), findsOneWidget);
      expect(find.textContaining('[无语]', findRichText: true), findsNothing);
      expect(find.bySemanticsLabel('[无语]'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('two emotes in a row stand 4 pt apart (24 pt between their lefts beside 15 pt text); one after text '
        'gets no gap', (tester) async {
      final rig = Rig();
      await rig.mount(tester, const [
        RichRun.text('吗？'),
        RichRun.emote(token: '[笑哭]', url: _emoteUrl, size: 1),
        RichRun.emote(token: '[笑哭]', url: _emoteUrl, size: 1),
      ]);
      final emotes = find.byType(RemoteImage);
      final first = tester.getRect(emotes.first);
      final second = tester.getRect(emotes.last);
      expect(first.left - tester.getTopLeft(_paragraph).dx, moreOrLessEquals(30));
      expect(second.left - first.left, moreOrLessEquals(24));
      expect(second.width, moreOrLessEquals(20));
    });

    testWidgets('an emote is centred on the Chinese glyphs beside it, and its line grows 2 pt below the text', (
      tester,
    ) async {
      final rig = Rig();
      await rig.mount(tester, const [RichRun.text('重打了')]);
      final plainHeight = tester.getSize(_paragraph).height;

      await rig.mount(tester, const [RichRun.text('重打了'), RichRun.emote(token: '[无语]', url: _emoteUrl, size: 1)]);
      expect(tester.getSize(_paragraph).height, moreOrLessEquals(plainHeight + CommentTextTheme.emoteLineGrowth));
      // The line grows below its text only, so its baseline is the text's.
      final painter = TextPainter(
        text: const TextSpan(text: '重打了', style: _style),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      final baseline =
          tester.getTopLeft(_paragraph).dy + painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final emote = tester.getRect(find.byType(RemoteImage));
      expect(emote.center.dy, moreOrLessEquals(baseline - 15 * CommentTextTheme.emoteRise));

      // A 40 pt emote reaches 25.25 above the baseline and 14.75 below it: the line grows to hold exactly it.
      await rig.mount(tester, const [RichRun.emote(token: '[大]', url: _emoteUrl, size: 2), RichRun.text('大')]);
      expect(tester.getRect(find.byType(RemoteImage)).top, moreOrLessEquals(tester.getTopLeft(_paragraph).dy));
      expect(tester.getSize(_paragraph).height, moreOrLessEquals(40));
    });

    testWidgets('only the line holding the emote grows; plain lines keep their height', (tester) async {
      final rig = Rig();
      final line = '回溯' * 10;
      // The first character of each line: 0, 21 and, after the emote's placeholder and the line break, 43.
      List<double> lineTops(List<int> starts) => [
        for (final start in starts)
          tester
              .renderObject<RenderParagraph>(_paragraph)
              .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + 1))
              .single
              .top,
      ];
      await rig.mount(tester, [RichRun.text('$line\n$line\n$line')]);
      final plain = tester.getSize(_paragraph).height;
      expect(plain, moreOrLessEquals(75));
      final plainTops = lineTops([0, 21, 42]);

      await rig.mount(tester, [
        RichRun.text('$line\n$line'),
        const RichRun.emote(token: '[无语]', url: _emoteUrl, size: 1),
        RichRun.text('\n$line'),
      ]);
      expect(tester.getSize(_paragraph).height, moreOrLessEquals(plain + CommentTextTheme.emoteLineGrowth));
      final tops = lineTops([0, 21, 43]);
      expect(tops[0], moreOrLessEquals(plainTops[0]));
      expect(tops[1], moreOrLessEquals(plainTops[1]));
      expect(tops[2], moreOrLessEquals(plainTops[2] + CommentTextTheme.emoteLineGrowth));

      await rig.mount(tester, [RichRun.text(line), const RichRun.emote(token: '[空]', url: '', size: 1)]);
      expect(tester.getSize(_paragraph).height, moreOrLessEquals(25));
    });
  });

  group('votes and notes', () {
    testWidgets('a vote is a 投票 link to its page; a 笔记 link reads [笔记] and opens the note', (tester) async {
      final rig = Rig();
      await rig.mount(tester, const [
        RichRun.link(title: '笔记标题', url: 'https://www.bilibili.com/h5/note-app/view?cvid=1234', note: true),
        RichRun.text('选一个'),
        RichRun.link(title: '投票: 选哪个', url: 'https://t.bilibili.com/vote/h5/index?vote_id=4321#/result'),
      ]);
      expect(find.text('[笔记] 选一个投票: 选哪个', findRichText: true), findsOneWidget);
      expect(_span(tester, '[笔记] ').style?.color, CommentTextTheme.link);
      expect(_span(tester, '投票: 选哪个').style?.color, CommentTextTheme.link);

      await _tapText(tester, '[笔记]');
      await _tapText(tester, '投票');
      expect(rig.links, [
        Uri.parse('https://www.bilibili.com/h5/note-app/view?cvid=1234'),
        Uri.parse('https://t.bilibili.com/vote/h5/index?vote_id=4321#/result'),
      ]);
    });
  });

  group('mentions', () {
    testWidgets('@name in the link blue opens the space page in the browser', (tester) async {
      final rig = Rig();
      await rig.mount(tester, const [RichRun.text('看 '), RichRun.mention(name: '小明', mid: 42)]);
      expect(_span(tester, '@小明').style?.color, CommentTextTheme.link);
      expect(_span(tester, '看 ').style, isNull);

      await _tapText(tester, '@小明');
      expect(rig.links, [Uri.parse('https://space.bilibili.com/42')]);
      expect(rig.seeks, isEmpty);
      expect(rig.videos, isEmpty);
    });

    testWidgets('a reply target with no mid is blue and leads nowhere', (tester) async {
      final rig = Rig();
      await rig.mount(tester, const [RichRun.text('回复 @小红 :说得对'), RichRun.timestamp(label: '1:02', seconds: 62)]);
      final mention = _span(tester, '@小红');
      expect(mention.style?.color, CommentTextTheme.link);
      expect(mention.recognizer, isNull);
      expect(find.text('回复 @小红 :说得对1:02', findRichText: true), findsOneWidget);
      await _tapText(tester, '@小红');
      expect(rig.links, isEmpty);

      await rig.mount(tester, const [RichRun.text('回复 @小红 :说得对')], marksReplyTarget: false);
      expect(_root(tester).children!.whereType<TextSpan>().map((span) => span.text), ['回复 @小红 :说得对']);
    });

    test('markingReplyTarget', () {
      expect(markingReplyTarget(const [RichRun.text('回复 @小红 :说得对'), RichRun.text('!')]), const [
        RichRun.text('回复 '),
        RichRun.mention(name: '小红', mid: 0),
        RichRun.text(' :说得对'),
        RichRun.text('!'),
      ]);
      expect(markingReplyTarget(const [RichRun.text('回复 @小红：好')]), const [
        RichRun.text('回复 '),
        RichRun.mention(name: '小红', mid: 0),
        RichRun.text('：好'),
      ]);
      const untouched = [
        [RichRun.text('回复 @小红 没有冒号')],
        [RichRun.text('回复 @ :空名字')],
        [RichRun.text('回复 '), RichRun.mention(name: '小红', mid: 7), RichRun.text(' :好')],
        <RichRun>[],
      ];
      for (final runs in untouched) {
        expect(markingReplyTarget(runs), same(runs));
      }
    });
  });

  group('links', () {
    const runs = [
      RichRun.text('看'),
      RichRun.link(title: '网页', url: 'https://example.com/a?b=1'),
      RichRun.text('、'),
      RichRun.link(title: '那个视频', url: 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2'),
      RichRun.text('、'),
      RichRun.link(title: '老视频', url: 'https://www.bilibili.com/video/av2/'),
      RichRun.text('、'),
      RichRun.link(title: '搜索词', url: 'bilibili://search?keyword=x'),
    ];

    testWidgets('a video address opens in the app, anything else on the web in the browser', (tester) async {
      final rig = Rig();
      await rig.mount(tester, runs);
      for (final title in ['网页', '那个视频', '老视频']) {
        expect(_span(tester, title).style?.color, CommentTextTheme.link, reason: title);
      }
      final word = _span(tester, '搜索词');
      expect(word.style, isNull);
      expect(word.recognizer, isNull);

      await _tapText(tester, '网页');
      await _tapText(tester, '那个视频');
      await _tapText(tester, '老视频');
      await _tapText(tester, '搜索词');
      expect(rig.links, [Uri.parse('https://example.com/a?b=1')]);
      expect(rig.videos, ['BV1GJ411x7h7', 'av2']);
    });

    testWidgets('with nowhere to open videos, a video address goes to the browser', (tester) async {
      final rig = Rig();
      await rig.mount(tester, runs, videos: false);
      await _tapText(tester, '那个视频');
      expect(rig.links, [Uri.parse('https://www.bilibili.com/video/BV1GJ411x7h7?p=2')]);
    });

    testWidgets('a link nothing could open says so', (tester) async {
      final rig = Rig()..linkOpens = false;
      await rig.mount(tester, runs);
      await _tapText(tester, '网页');
      expect(find.text('无法打开链接'), findsOneWidget);
      await _expireToast(tester);
      expect(find.text('无法打开链接'), findsNothing);

      rig.linkThrows = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      await _tapText(tester, '网页');
      expect(find.text('无法打开链接'), findsOneWidget);
      await _expireToast(tester);
      expect(rig.links, hasLength(2));
    });
  });

  testWidgets('video ids open the video; without a handler they stay plain', (tester) async {
    final rig = Rig();
    const runs = [
      RichRun.text('相关：'),
      RichRun.video(id: 'BV1AB411c7mD'),
      RichRun.text('、'),
      RichRun.video(id: 'av170001'),
    ];
    await rig.mount(tester, runs);
    expect(_span(tester, 'BV1AB411c7mD').style?.color, CommentTextTheme.link);
    await _tapText(tester, 'BV1AB411c7mD');
    await _tapText(tester, 'av170001');
    expect(rig.videos, ['BV1AB411c7mD', 'av170001']);

    await rig.mount(tester, runs, videos: false);
    final plain = _span(tester, 'BV1AB411c7mD');
    expect(plain.style, isNull);
    expect(plain.recognizer, isNull);
  });

  testWidgets('timestamps seek; without a handler they stay plain', (tester) async {
    final rig = Rig();
    const runs = [RichRun.text('名场面在'), RichRun.timestamp(label: '1:02:03', seconds: 3723)];
    await rig.mount(tester, runs);
    expect(_span(tester, '1:02:03').style?.color, CommentTextTheme.link);
    await _tapText(tester, '1:02:03');
    expect(rig.seeks, [3723]);

    await rig.mount(tester, runs, seeks: false);
    final plain = _span(tester, '1:02:03');
    expect(plain.style, isNull);
    expect(plain.recognizer, isNull);
  });

  testWidgets('recognizers are made once per runs list', (tester) async {
    final rig = Rig();
    TapGestureRecognizer recognizer() => _span(tester, '0:30').recognizer! as TapGestureRecognizer;
    await rig.mount(tester, const [RichRun.text('看'), RichRun.timestamp(label: '0:30', seconds: 30)]);
    final first = recognizer();

    await rig.mount(tester, [const RichRun.text('看'), const RichRun.timestamp(label: '0:30', seconds: 30)]);
    expect(recognizer(), same(first));

    await rig.mount(tester, const [RichRun.text('再看'), RichRun.timestamp(label: '0:30', seconds: 30)]);
    expect(recognizer(), isNot(same(first)));

    await rig.mount(tester, const [RichRun.text('再看'), RichRun.timestamp(label: '0:30', seconds: 30)], seeks: false);
    expect(_span(tester, '0:30').recognizer, isNull);
  });
}
