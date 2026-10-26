import 'package:bili_core/api.dart' hide RichText, VideoPage;
import 'package:bilifast/dynamic/card/dynamic_card.dart';
import 'package:bilifast/dynamic/card/dynamic_pictures.dart';
import 'package:bilifast/dynamic/card/dynamic_rich_text.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'card_host.dart';

const _video = DynamicVideo(
  aid: 1,
  bvid: 'BV1card00001',
  title: '视频标题',
  cover: '',
  durationText: '00:56',
  duration: 56,
  plays: '37.1万',
  danmaku: '1233',
  badge: '动态视频',
);

Finder _toast(String text) => find.descendant(of: find.byKey(const ValueKey('toast')), matching: find.text(text));

/// Taps the run of [text] inside the rich text [paragraph] by firing its recognizer, as a finger on it would.
void _tapRun(WidgetTester tester, Finder paragraph, String text) {
  final rich = tester.widget<RichText>(paragraph);
  TextSpan? found;
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text == text) {
      found = span;
      return false;
    }
    return true;
  });
  expect(found, isNotNull, reason: 'a run reading $text');
  (found!.recognizer! as TapGestureRecognizer).onTap!();
}

/// Lets a toast run its two seconds and fade.
Future<void> _toastGone(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Finder _paragraphOf(String id) =>
    find.descendant(of: find.byKey(ValueKey('dynamic-text-$id')), matching: find.byType(RichText)).first;

void main() {
  group('the text', () {
    const long = '第一行\n第二行\n第三行\n第四行\n第五行不该出现';

    testWidgets('over four lines it ends in ... 全文, which opens the post', (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(
          item: post('1', kind: DynamicKind.draw, nodes: const [DynamicTextNode(long)]),
        ),
      );
      final text = _paragraphOf('1');
      final plain = tester.widget<RichText>(text).text.toPlainText();
      expect(plain, endsWith('第四行... 全文'));
      expect(plain, isNot(contains('第五行')));
      _tapRun(tester, text, '全文');
      expect(host.opened.posts.single, (id: '1', toComments: false));
    });

    testWidgets('a text the server cut shows ... 全文 even when it fits', (tester) async {
      await pumpCardHost(tester, DynamicCard(item: post('1', nodes: const [DynamicTextNode('短短一行')], folded: true)));
      expect(tester.widget<RichText>(_paragraphOf('1')).text.toPlainText(), '短短一行... 全文');
    });

    testWidgets('a short text that the server left whole shows as it is', (tester) async {
      await pumpCardHost(tester, DynamicCard(item: post('1', nodes: const [DynamicTextNode('短短一行')])));
      expect(tester.widget<RichText>(_paragraphOf('1')).text.toPlainText(), '短短一行');
    });

    testWidgets("a video post's 展开 opens the text in place", (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(
          item: post('1', kind: DynamicKind.video, nodes: const [DynamicTextNode(long)], major: _video),
        ),
      );
      final text = _paragraphOf('1');
      expect(tester.widget<RichText>(text).text.toPlainText(), endsWith('... 展开'));
      _tapRun(tester, text, '展开');
      await tester.pump();
      expect(tester.widget<RichText>(_paragraphOf('1')).text.toPlainText(), long);
      expect(host.opened.posts, isEmpty);
      expect(host.opened.videos, isEmpty);
    });

    testWidgets('a cut never splits an emoji, and … follows the last word, not the line break', (tester) async {
      await pumpCardHost(tester, DynamicCard(item: post('1', nodes: const [DynamicTextNode('一\n二\n三\n四😀😀\n五')])));
      expect(tester.widget<RichText>(_paragraphOf('1')).text.toPlainText(), '一\n二\n三\n四😀😀... 全文');
    });

    testWidgets('topics and badges toast, @names open the space, links and video links open', (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            nodes: const [
              DynamicBadgeNode('互动抽奖', kind: 'lottery'),
              DynamicTopicNode('#话题#'),
              DynamicMentionNode('@某人', mid: 42),
              DynamicLinkNode('网页链接', url: 'https://example.com/a'),
              DynamicLinkNode('视频链接', url: 'https://www.bilibili.com/video/BV1link00001'),
              DynamicVideoLinkNode('「视频」', bvid: 'BV1link00002'),
              DynamicEmojiNode('[打call]', url: 'https://i0.hdslb.com/bfs/emote/call.png'),
            ],
          ),
        ),
      );
      final text = _paragraphOf('1');
      _tapRun(tester, text, '#话题#');
      await tester.pump();
      expect(_toast('暂未开放'), findsOneWidget);
      _tapRun(tester, text, '@某人');
      expect(host.opened.spaces, [42]);
      _tapRun(tester, text, '网页链接');
      await tester.pump();
      expect(host.opened.links, [Uri.parse('https://example.com/a')]);
      _tapRun(tester, text, '视频链接');
      _tapRun(tester, text, '「视频」');
      expect(host.opened.videos.map((route) => route.bvid), ['BV1link00001', 'BV1link00002']);
      _tapRun(tester, text, '互动抽奖');
      await tester.pump();
      expect(find.byType(RemoteImage), findsWidgets, reason: 'the emote drawn inline');
      expect(find.image(const AssetImage('assets/images/dynamic/gift_lottery_line.png')), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('DynamicRichText alone draws its nodes with no fold', (tester) async {
      await pumpCardHost(
        tester,
        const DynamicRichText(nodes: [DynamicTextNode('甲'), DynamicTopicNode('#乙#')], style: TextStyle(fontSize: 17)),
      );
      expect(find.textContaining('甲#乙#', findRichText: true), findsOneWidget);
    });
  });

  group('the pictures', () {
    DynamicPicture shaped(int width, int height) => DynamicPicture(url: '', width: width, height: height);
    List<Rect> layout(List<DynamicPicture> pictures, {bool detail = false}) =>
        DynamicPictureGrid.layout(pictures, 416, detail: detail);

    test('one wide picture spans the width at its shape, a tall one two cells wide at most 3:4', () {
      expect(layout([shaped(1920, 1080)]).single, const Rect.fromLTWH(0, 0, 416, 234));
      expect(layout([shaped(3000, 1000)]).single.height, closeTo(416 * 9 / 16, 0.01), reason: 'no wider than 16:9');
      final tall = layout([shaped(1000, 3000)]).single;
      expect(tall.width, closeTo(DynamicCardTheme.pictureCell * 2 + DynamicCardTheme.pictureGap, 0.01));
      expect(tall.height, closeTo(tall.width * DynamicCardTheme.pictureTallest, 0.01));
    });

    test("two to four two a row in 127's cells, tall ones about 3:4, square ones square", () {
      final four = layout([for (var i = 0; i < 4; i++) shaped(1080, 2340)]);
      const cell = DynamicCardTheme.pictureCell, gap = DynamicCardTheme.pictureGap;
      expect(four.map((frame) => frame.left).toList(), [0, cell + gap, 0, cell + gap]);
      expect(four[2].top, closeTo(cell * DynamicCardTheme.pictureTallest + gap, 0.01));
      expect(four.first.width, cell);
      final two = layout([shaped(500, 500), shaped(500, 500)]);
      expect(two.map((frame) => frame.top).toSet(), {0});
      expect(two.first.height, cell);
      final three = layout([for (var i = 0; i < 3; i++) shaped(500, 500)]);
      expect(three[2].topLeft, const Offset(0, cell + gap), reason: 'two a row');
    });

    test('five to nine three a row, square; the post page fills its width six apart', () {
      final nine = layout([for (var i = 0; i < 9; i++) shaped(1000, 1500)]);
      const cell = DynamicCardTheme.pictureCell, gap = DynamicCardTheme.pictureGap;
      expect(nine[2].left, closeTo((cell + gap) * 2, 0.01));
      expect(nine[3].topLeft, const Offset(0, cell + gap));
      expect(nine.every((frame) => (frame.width - frame.height).abs() < 0.001), isTrue);
      final detail = DynamicPictureGrid.layout([for (var i = 0; i < 9; i++) shaped(1, 1)], 400, detail: true);
      expect(detail[2].right, closeTo(400, 0.01));
      expect(detail[1].left - detail[0].right, closeTo(DynamicCardTheme.detailPictureGap, 0.01));
    });

    testWidgets('a tap opens the viewer over everything at that picture; back closes it first', (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            kind: DynamicKind.draw,
            major: DynamicPictures(pictures: [for (var i = 0; i < 3; i++) shaped(500, 500)]),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-picture-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await navigator.maybePop(), isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dynamic-picture-0')));
      await tester.pump();
      await tester.tapAt(const Offset(220, 478));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsNothing, reason: 'a tap closes it too');
      expect(await navigator.maybePop(), isFalse, reason: 'nothing left over on the route');
    });
  });

  group('the footer', () {
    testWidgets('counts as Bilibili writes them, a zero as its word', (tester) async {
      await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1', stat: const DynamicStat(forward: 24000, comment: 858, like: 11000))),
            DynamicCard(item: post('2', stat: const DynamicStat(forward: 9, comment: 100, like: 388))),
            DynamicCard(item: post('3')),
          ],
        ),
      );
      for (final text in ['2.4万', '858', '1.1万', '9', '100', '388', '转发', '评论', '点赞']) {
        expect(find.textContaining(text, findRichText: true), findsWidgets, reason: text);
      }
    });

    testWidgets('转发 toasts; 评论 opens the post at its comments, or a video post its video', (tester) async {
      final host = await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1', kind: DynamicKind.draw)),
            DynamicCard(
              item: post('2', kind: DynamicKind.video, major: _video),
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-forward')).first);
      await tester.pump();
      expect(_toast('暂未开放'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dynamic-comment')).first);
      expect(host.opened.posts.single, (id: '1', toComments: true));
      await tester.tap(find.byKey(const ValueKey('dynamic-comment')).last);
      await tester.pump();
      expect(host.opened.videos.single.bvid, _video.bvid);
      await _toastGone(tester);
    });

    testWidgets("直播 and 番剧 aren't built: their 评论 and 全文 toast too, opening nothing", (tester) async {
      const long = '第一行\n第二行\n第三行\n第四行\n第五行';
      final host = await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1', kind: DynamicKind.live, nodes: const [DynamicTextNode(long)])),
            DynamicCard(item: post('2', kind: DynamicKind.pgc, nodes: const [DynamicTextNode(long)])),
          ],
        ),
      );
      for (final (index, id) in ['1', '2'].indexed) {
        await tester.tap(find.byKey(const ValueKey('dynamic-comment')).at(index));
        await tester.pump();
        expect(_toast('暂未开放'), findsOneWidget);
        await _toastGone(tester);
        _tapRun(tester, _paragraphOf(id), '全文');
        await tester.pump();
        expect(_toast('暂未开放'), findsOneWidget);
        await _toastGone(tester);
      }
      expect(host.opened.posts, isEmpty);
    });

    testWidgets('👍 shows at once, pink with its count, and every card of the post agrees', (tester) async {
      final host = await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1', stat: const DynamicStat(like: 388))),
            DynamicCard(
              key: const ValueKey('again'),
              item: post('1', stat: const DynamicStat(like: 388)),
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-like')).first);
      await tester.pump();
      expect(find.textContaining('389', findRichText: true), findsNWidgets(2));
      expect(host.api.likes.single, (id: '1', on: true));
      final liked = tester.widget<Image>(
        find.descendant(of: find.byKey(const ValueKey('dynamic-like')).last, matching: find.byType(Image)),
      );
      expect(liked.color, DynamicCardTheme.footerLiked);
      expect((liked.image as AssetImage).assetName, 'assets/images/dynamic/dy_ic_hand_thumbsup_fill_24.png');
    });

    testWidgets('👍 refused by Bilibili goes back as it was, with a toast', (tester) async {
      final api = FakeDynamicApi()..failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
      await pumpCardHost(
        tester,
        DynamicCard(item: post('1', stat: const DynamicStat(like: 388))),
        api: api,
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-like')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('388', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('toast')), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('logged out, 👍 asks for the login and sends nothing', (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(item: post('1', stat: const DynamicStat(like: 3))),
        loggedIn: false,
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-like')));
      await tester.pump();
      expect(host.gate.requests, 1);
      expect(host.api.likes, isEmpty);
      expect(find.textContaining('3', findRichText: true), findsWidgets);
      expect(find.byKey(const ValueKey('toast')), findsNothing);
    });
  });

  group('the card', () {
    testWidgets('a tap opens a video post straight in the player, any other post its page', (tester) async {
      final host = await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(
              item: post('1', kind: DynamicKind.video, major: _video),
            ),
            DynamicCard(item: post('2', kind: DynamicKind.word)),
            DynamicCard(item: post('3', kind: DynamicKind.live)),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-text-1')));
      await tester.pump();
      expect(host.opened.videos.single.bvid, _video.bvid);
      expect(host.opened.videos.single.title, _video.title);
      await tester.tap(find.byKey(const ValueKey('dynamic-text-2')));
      expect(host.opened.posts.single, (id: '2', toComments: false));
      await tester.tap(find.byKey(const ValueKey('dynamic-text-3')));
      await tester.pump();
      expect(_toast('暂未开放'), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('the face and the name open the space; the author row shows name, time and action', (tester) async {
      const author = DynamicAuthor(
        mid: 99,
        name: '某UP',
        face: '',
        pubTime: '4小时前',
        pubAction: '发布了动态视频',
        vipPink: true,
        verify: DynamicVerify.organisation,
        decoration: DynamicDecoration(cardUrl: '', number: '000011'),
      );
      final host = await pumpCardHost(tester, DynamicCard(item: post('1', author: author)));
      expect(tester.widget<Text>(find.text('某UP')).style?.color, DynamicCardTheme.nameVipInk);
      expect(find.textContaining('4小时前', findRichText: true), findsOneWidget);
      expect(find.textContaining('发布了动态视频', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-verified')), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-decoration-number')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dynamic-face')));
      await tester.tap(find.byKey(const ValueKey('dynamic-name')));
      expect(host.opened.spaces, [99, 99]);
    });

    testWidgets("UP主的推荐 draws its item; 去看看 toasts", (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            goods: const DynamicGoods(
              headText: 'UP主的推荐',
              items: [DynamicGoodsItem(name: '演示红包', cover: '', brief: '最高12345元', jumpText: '去看看')],
            ),
          ),
        ),
      );
      expect(find.text('UP主的推荐'), findsOneWidget);
      expect(find.text('演示红包'), findsOneWidget);
      expect(find.text('最高12345元'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dynamic-goods-go')));
      await tester.pump();
      expect(_toast('暂未开放'), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets("UP主的推荐's head too long for the row ends in an ellipsis", (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            goods: DynamicGoods(
              headText: '很长的推荐标题' * 12,
              items: const [DynamicGoodsItem(name: '演示红包', cover: '', brief: '', jumpText: '去看看')],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final head = find.byKey(const ValueKey('dynamic-goods-head'));
      expect(tester.widget<Text>(head).overflow, TextOverflow.ellipsis);
      expect(tester.getRect(head).right, lessThanOrEqualTo(440 - DynamicCardTheme.gutter));
    });

    testWidgets("the fan card's number ends at the same place however wide it is (127, 139)", (tester) async {
      DynamicAuthor fan(String number) => DynamicAuthor(
        mid: 9,
        name: '某UP',
        face: '',
        decoration: DynamicDecoration(cardUrl: '', number: number),
      );
      await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1', author: fan('000012'))),
            DynamicCard(item: post('2', author: fan('9'))),
          ],
        ),
      );
      final numbers = find.byKey(const ValueKey('dynamic-decoration-number'));
      final cards = [for (final id in ['1', '2']) tester.getRect(find.byKey(ValueKey('dynamic-card-$id')))];
      final first = tester.getRect(numbers.first), second = tester.getRect(numbers.last);
      expect(first.right, closeTo(cards[0].right - 42 - DynamicCardTheme.decorationNumberRight, 0.01));
      expect(second.right, closeTo(first.right, 0.01));
      expect(second.width, lessThan(first.width));
      expect(first.top - cards[0].top, closeTo(DynamicCardTheme.decorationTop + 55 / 3, 0.01));
    });

    testWidgets('136: an avatar frame shrinks the face to 26 about (40, 32) and moves the row and the text', (
      tester,
    ) async {
      const plain = DynamicAuthor(mid: 1, name: '某UP', face: '', pubTime: '3小时前');
      const fanOnly = DynamicAuthor(
        mid: 2,
        name: '某UP',
        face: '',
        pubTime: '3小时前',
        decoration: DynamicDecoration(cardUrl: '', number: '000011'),
      );
      const framed = DynamicAuthor(
        mid: 2,
        name: '某UP',
        face: '',
        pubTime: '3小时前',
        pendant: 'https://i0.hdslb.com/bfs/garb/item/frame.png',
        decoration: DynamicDecoration(cardUrl: '', number: '000011'),
      );
      await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1', author: plain)),
            DynamicCard(item: post('2', author: fanOnly)),
            DynamicCard(item: post('3', author: framed)),
          ],
        ),
      );
      Rect within(String id, Finder finder) {
        final card = tester.getRect(find.byKey(ValueKey('dynamic-card-$id')));
        return tester.getRect(find.descendant(of: find.byKey(ValueKey('dynamic-card-$id')), matching: finder))
            .shift(-card.topLeft);
      }

      expect(find.byKey(const ValueKey('dynamic-pendant')), findsOneWidget);
      final face = within('3', find.byType(ClipOval));
      expect(face.center, const Offset(40, 32));
      expect(face.size, const Size.square(26));
      final frame = within('3', find.byKey(const ValueKey('dynamic-pendant')));
      expect(frame.center, const Offset(40, 32));
      expect(frame.width, closeTo(26 * 1.75, 0.01));
      expect(within('3', find.byKey(const ValueKey('dynamic-name'))).left, closeTo(226 / 3, 0.01));
      expect(within('1', find.byKey(const ValueKey('dynamic-name'))).left, 60);
      final time = within('3', find.byKey(const ValueKey('dynamic-time'))).center.dy;
      expect(time - within('1', find.byKey(const ValueKey('dynamic-time'))).center.dy, closeTo(1.5, 0.01));
      final more = within('3', find.byKey(const ValueKey('dynamic-more'))).center.dy;
      expect(within('1', find.byKey(const ValueKey('dynamic-more'))).center.dy - more, closeTo(5.5, 0.01));
      final fan = within('3', find.byKey(const ValueKey('dynamic-decoration'))).top;
      expect(within('2', find.byKey(const ValueKey('dynamic-decoration'))).top - fan, closeTo(7, 0.01));
      final text = within('3', find.byKey(const ValueKey('dynamic-text-3'))).top;
      expect(text - within('1', find.byKey(const ValueKey('dynamic-text-1'))).top, closeTo(6.5, 0.01));
    });

    testWidgets('a space draws the lighter band under its cards', (tester) async {
      await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(item: post('1')),
            DynamicCard(item: post('2'), space: true),
          ],
        ),
      );
      final bands = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((box) => box.color)
          .where((color) => color == DynamicCardTheme.bandInk || color == DynamicCardTheme.spaceBandInk)
          .toList();
      expect(bands, containsAllInOrder([DynamicCardTheme.bandInk, DynamicCardTheme.spaceBandInk]));
    });
  });
}
