import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/dynamic/card/dynamic_card.dart';
import 'package:bilifast/dynamic/card/dynamic_repost.dart';
import 'package:bilifast/dynamic/card/dynamic_rich_text.dart';
import 'package:bilifast/dynamic/card/dynamic_video_box.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'card_host.dart';

const _style = TextStyle(fontSize: 10, height: 2);

const _video = DynamicVideo(
  aid: 1,
  bvid: 'BV1rich00001',
  title: '视频标题',
  cover: '',
  durationText: '00:56',
  duration: 56,
  plays: '37.1万',
  danmaku: '1233',
);

Finder get _paragraph => find.descendant(of: find.byType(DynamicRichText), matching: find.byType(RichText)).first;

String _plain(WidgetTester tester) => tester.widget<RichText>(_paragraph).text.toPlainText();

/// Where the caret before the character at [offset] sits.
Offset _caret(WidgetTester tester, int offset) =>
    tester.renderObject<RenderParagraph>(_paragraph).getOffsetForCaret(TextPosition(offset: offset), Rect.zero);

Future<void> _pumpText(WidgetTester tester, List<DynamicNode> nodes, {bool wide = false, double width = 400}) =>
    pumpCardHost(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: DynamicRichText(nodes: nodes, style: _style, wideTopicGaps: wide),
        ),
      ),
    );

void main() {
  group('@names', () {
    testWidgets('run together in the answer, each is set apart from the words around it (29)', (tester) async {
      await _pumpText(tester, const [
        DynamicTextNode('恭喜'),
        DynamicMentionNode('@甲', mid: 1),
        DynamicMentionNode('@乙', mid: 2),
        DynamicMentionNode('@丙', mid: 3),
        DynamicTextNode('等十位同学'),
      ]);
      expect(_plain(tester), '恭喜@甲 @乙 @丙 等十位同学');
      final advance = _caret(tester, 1).dx - _caret(tester, 0).dx;
      expect(_caret(tester, 2).dx - _caret(tester, 1).dx, closeTo(advance + DynamicCardTheme.mentionLead, 0.01));
      final space = _caret(tester, 11).dx - _caret(tester, 10).dx;
      expect(
        _caret(tester, 5).dx - _caret(tester, 4).dx,
        closeTo(space + DynamicCardTheme.mentionLead, 0.01),
        reason: 'the space after @甲 and the lead of @乙',
      );
    });

    testWidgets('keep the space, punctuation and start they come with', (tester) async {
      await _pumpText(tester, const [
        DynamicMentionNode('@甲 ', mid: 1),
        DynamicTextNode('你好//'),
        DynamicMentionNode('@乙', mid: 2),
        DynamicTextNode('：原文'),
      ]);
      expect(_plain(tester), '@甲 你好//@乙：原文');
      expect(_caret(tester, 0).dx, 0);
      final slash = _caret(tester, 6).dx - _caret(tester, 5).dx;
      expect(_caret(tester, 7).dx - _caret(tester, 6).dx, closeTo(slash, 0.01), reason: 'no lead after /');
    });

    testWidgets('still open the space, the added space not part of the name', (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            nodes: const [DynamicTextNode('恭喜'), DynamicMentionNode('@甲', mid: 42), DynamicTextNode('中奖')],
          ),
        ),
      );
      final rich = tester.widget<RichText>(
        find.descendant(of: find.byKey(const ValueKey('dynamic-text-1')), matching: find.byType(RichText)).first,
      );
      final names = <String>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) names.add(span.text!);
        return true;
      });
      expect(names, ['@甲']);
      expect(rich.text.toPlainText(), '恭喜@甲 中奖');
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '@甲') (span.recognizer! as TapGestureRecognizer).onTap!();
        return true;
      });
      expect(host.opened.spaces, [42]);
    });
  });

  group('topics', () {
    const nodes = [
      DynamicBadgeNode('互动抽奖', kind: 'lottery'),
      DynamicTextNode(' '),
      DynamicTopicNode('#甲#'),
      DynamicTextNode(' '),
      DynamicTopicNode('#乙#'),
    ];

    testWidgets("in a 图文 post's text on 关注 the spaces beside them are wider (135, 29)", (tester) async {
      await _pumpText(tester, nodes);
      // The gift is one placeholder: 互动抽奖 runs 1-4, the first topic starts at 6 and the second at 10.
      final plain = [_caret(tester, 6).dx, _caret(tester, 10).dx];
      await _pumpText(tester, nodes, wide: true);
      expect(_plain(tester), '￼互动抽奖 #甲# #乙#');
      expect(_caret(tester, 6).dx - plain[0], closeTo(DynamicCardTheme.topicGap, 0.01));
      expect(_caret(tester, 10).dx - plain[1], closeTo(DynamicCardTheme.topicGap * 2, 0.01));
    });

    testWidgets('a long one breaks inside itself at the line end, and either half toasts', (tester) async {
      await _pumpText(tester, const [DynamicTextNode('一二三四五 '), DynamicTopicNode('#六七八九#')], width: 85);
      final first = _caret(tester, 6);
      final last = _caret(tester, 10);
      expect(first.dy, 0, reason: '# stays on the first line');
      expect(last.dy, greaterThan(0), reason: 'the rest goes on to the second');
      final paragraph = tester.renderObject<RenderParagraph>(_paragraph);
      final origin = paragraph.localToGlobal(Offset.zero);
      for (final offset in [6, 9]) {
        final box = paragraph.getBoxesForSelection(TextSelection(baseOffset: offset, extentOffset: offset + 1)).single;
        await tester.tapAt(origin + box.toRect().center);
        await tester.pump();
        expect(find.descendant(of: find.byKey(const ValueKey('toast')), matching: find.text('暂未开放')), findsOneWidget);
        for (final wait in const [200, 2000, 200, 200]) {
          await tester.pump(Duration(milliseconds: wait));
        }
        expect(find.byKey(const ValueKey('toast')), findsNothing);
      }
    });
  });

  group("a post's own text", () {
    final repost = post(
      '1',
      kind: DynamicKind.forward,
      nodes: const [DynamicTextNode('恭喜'), DynamicMentionNode('@甲', mid: 1), DynamicTextNode('中奖')],
      original: post('o1', kind: DynamicKind.draw, nodes: const [DynamicTopicNode('#话题#')]),
    );

    testWidgets("a repost's on 关注 sits at 图文's top and pitch, its topics spaced as 图文's (29, 243)", (tester) async {
      await pumpCardHost(tester, DynamicCard(item: repost));
      final card = tester.getRect(find.byKey(const ValueKey('dynamic-card-1')));
      final text = find.byKey(const ValueKey('dynamic-text-1'));
      expect(tester.getRect(text).top - card.top, DynamicCardTheme.opusTextTop);
      final rich = tester.widget<DynamicRichText>(text);
      expect(rich.style.height! * rich.style.fontSize!, closeTo(DynamicCardTheme.opusTextLine, 0.01));
      expect(rich.wideTopicGaps, isTrue);
    });

    testWidgets("a repost's in a space keeps the plain top and pitch (136)", (tester) async {
      await pumpCardHost(tester, DynamicCard(item: repost, space: true));
      final card = tester.getRect(find.byKey(const ValueKey('dynamic-card-1')));
      final text = find.byKey(const ValueKey('dynamic-text-1'));
      expect(tester.getRect(text).top - card.top, DynamicCardTheme.textTop);
      final rich = tester.widget<DynamicRichText>(text);
      expect(rich.style.height! * rich.style.fontSize!, closeTo(DynamicCardTheme.textLine, 0.01));
      expect(rich.wideTopicGaps, isFalse);
    });

    testWidgets("a video post's text keeps the plain spaces", (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post('1', kind: DynamicKind.video, nodes: const [DynamicTopicNode('#话题#')], major: _video),
        ),
      );
      expect(tester.widget<DynamicRichText>(find.byKey(const ValueKey('dynamic-text-1'))).wideTopicGaps, isFalse);
    });
  });

  group("the original's block", () {
    DynamicItem original({DynamicKind kind = DynamicKind.draw, List<DynamicNode>? nodes, DynamicMajor? major}) => post(
      'o1',
      kind: kind,
      author: const DynamicAuthor(mid: 9, name: '原作者', face: '', following: true),
      nodes: nodes ?? const [DynamicTopicNode('#话题#'), DynamicTextNode(' 原文')],
      major: major,
    );

    Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

    DynamicRichText textOf(WidgetTester tester) =>
        tester.widget<DynamicRichText>(find.byKey(const ValueKey('dynamic-repost-text-o1')));

    testWidgets('on 关注: the @name higher, the text 16 pt at its 图文 pitch, topics spaced (29)', (tester) async {
      await pumpCardHost(tester, DynamicRepostBlock(original: original()));
      final block = rectOf(tester, 'dynamic-repost-block');
      final name = rectOf(tester, 'dynamic-repost-name');
      expect(name.top - block.top, closeTo(DynamicCardTheme.followRepostTop, 0.01));
      final text = rectOf(tester, 'dynamic-repost-text-o1');
      expect(
        text.top - block.top,
        closeTo(
          DynamicCardTheme.followRepostTop + DynamicCardTheme.repostNameLine + DynamicCardTheme.followRepostTextGap,
          0.01,
        ),
      );
      final rich = textOf(tester);
      expect(rich.style.fontSize, DynamicCardTheme.followRepostText);
      expect(rich.style.height! * rich.style.fontSize!, closeTo(DynamicCardTheme.followRepostTextLine, 0.01));
      expect(rich.wideTopicGaps, isTrue);
    });

    testWidgets("on 关注 with no text its body sits 9.33 under the @name's line (243)", (tester) async {
      await pumpCardHost(
        tester,
        DynamicRepostBlock(
          original: original(kind: DynamicKind.video, nodes: const [], major: _video),
        ),
      );
      final block = rectOf(tester, 'dynamic-repost-block');
      final box = tester.getRect(find.byType(DynamicVideoBox));
      expect(
        box.top - block.top,
        closeTo(
          DynamicCardTheme.followRepostTop + DynamicCardTheme.repostNameLine + DynamicCardTheme.followRepostBodyGap,
          0.01,
        ),
      );
    });

    testWidgets("a video original's topics keep the plain spaces", (tester) async {
      await pumpCardHost(
        tester,
        DynamicRepostBlock(
          original: original(kind: DynamicKind.video, major: _video),
        ),
      );
      expect(textOf(tester).wideTopicGaps, isFalse);
    });

    testWidgets("in a space it stays 136's", (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post('1', kind: DynamicKind.forward, original: original()),
          space: true,
        ),
      );
      final block = rectOf(tester, 'dynamic-repost-block');
      expect(rectOf(tester, 'dynamic-repost-name').top - block.top, closeTo(DynamicCardTheme.repostTop, 0.01));
      final text = rectOf(tester, 'dynamic-repost-text-o1');
      expect(
        text.top - block.top,
        closeTo(DynamicCardTheme.repostTop + DynamicCardTheme.repostNameLine + DynamicCardTheme.repostTextGap, 0.01),
      );
      final rich = textOf(tester);
      expect(rich.style.fontSize, DynamicCardTheme.text);
      expect(rich.style.height! * rich.style.fontSize!, closeTo(DynamicCardTheme.textLine, 0.01));
      expect(rich.wideTopicGaps, isFalse);
    });

    testWidgets('on the post page it stays 132\'s', (tester) async {
      await pumpCardHost(tester, DynamicRepostBlock(original: original(), detail: true));
      final block = rectOf(tester, 'dynamic-repost-block');
      expect(rectOf(tester, 'dynamic-repost-name').top - block.top, closeTo(DynamicCardTheme.repostDetailTop, 0.01));
      expect(textOf(tester).style.fontSize, DynamicCardTheme.text);
      expect(textOf(tester).wideTopicGaps, isFalse);
    });
  });
}
