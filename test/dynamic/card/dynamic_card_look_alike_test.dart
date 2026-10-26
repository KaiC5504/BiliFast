import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/card/dynamic_card.dart';
import 'package:bilifast/dynamic/card/dynamic_open.dart';
import 'package:bilifast/dynamic/card/dynamic_repost.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import 'card_host.dart';

/// The cards as KaiC's iPhone draws them (127, 128, 135, 136, 139, and 132's repost block on the post page), under the
/// system font, 440 wide at 3×. With BILIFAST_SHOTS naming a folder outside the repo, each card's shot is saved there
/// for tools/screen_diff.py. Names and words are made up, of the screenshots' lengths and scripts.
void main() {
  const author127 = DynamicAuthor(
    mid: 11,
    name: '测试用户',
    face: '',
    pubTime: '3小时前',
    vipPink: true,
    verify: DynamicVerify.personal,
    decoration: DynamicDecoration(cardUrl: '', number: '000011', colour: 0xFF83BF54),
  );
  const official = DynamicAuthor(
    mid: 12,
    name: '演示官方账号',
    face: '',
    pubTime: '4小时前',
    pubAction: '发布了动态视频',
    vipPink: true,
    verify: DynamicVerify.organisation,
  );
  final cards = <String, DynamicItem>{
    '127': post(
      'a127',
      kind: DynamicKind.draw,
      author: author127,
      nodes: const [
        DynamicTextNode('演示了！今天测试，文字长到这里\n演示区随便写一行文字凑够100行长度\n这几行字都是演示的！！\n还是演示用的！！，每行都要够长！凑数的！！ 再写一行让它折起来'),
      ],
      folded: true,
      major: DynamicPictures(
        pictures: [for (var i = 0; i < 4; i++) const DynamicPicture(url: '', width: 1080, height: 2340)],
      ),
      goods: const DynamicGoods(
        headText: 'UP主的推荐',
        items: [DynamicGoodsItem(name: '测试11.11红包', cover: '', brief: '最高12345元', jumpText: '去看看')],
      ),
      stat: const DynamicStat(forward: 9, comment: 100, like: 388),
    ),
    '128': post(
      'a128',
      kind: DynamicKind.video,
      author: official,
      nodes: const [
        DynamicTopicNode('#演示官方账号#'),
        DynamicTextNode(' '),
        DynamicTopicNode('#测试话题的第二个#'),
        DynamicTextNode(' '),
        DynamicTopicNode('#演示话题的第三个#'),
        DynamicTextNode('\n\n「这里只是演示文字用来占位置，测试就到这里！」\n\n后面还有几行，敬请期待4.7版本演示文字。'),
      ],
      major: const DynamicVideo(
        aid: 1,
        bvid: 'BV1look00128',
        title: '演示视频标题文字',
        cover: '',
        durationText: '00:56',
        duration: 56,
        plays: '37.1万',
        danmaku: '1233',
        badge: '动态视频',
      ),
      stat: const DynamicStat(forward: 24000, comment: 858, like: 11000),
    ),
    '135': post(
      'a135',
      kind: DynamicKind.draw,
      author: const DynamicAuthor(
        mid: 12,
        name: '演示官方账号',
        face: '',
        pubTime: '4小时前',
        vipPink: true,
        verify: DynamicVerify.organisation,
      ),
      nodes: const [
        DynamicBadgeNode('互动抽奖', kind: 'lottery'),
        DynamicTextNode(' '),
        DynamicTopicNode('#演示官方账号#'),
        DynamicTextNode(' '),
        DynamicTopicNode('#测试话题的第二个#'),
        DynamicTextNode(' '),
        DynamicTopicNode('#演示话题的第三个#'),
        DynamicTextNode('\n\n「演示视频标题文字」第六话 | 测试'),
      ],
      folded: true,
      major: const DynamicPictures(pictures: [DynamicPicture(url: '', width: 1920, height: 1080)]),
      stat: const DynamicStat(forward: 24000, comment: 858, like: 11000),
    ),
    '136': post(
      'a136',
      kind: DynamicKind.forward,
      author: const DynamicAuthor(
        mid: 13,
        name: 'Tester___',
        face: '',
        pubTime: '2025年6月27日',
        pendant: 'https://i0.hdslb.com/bfs/garb/item/look-alike-frame.png',
        decoration: DynamicDecoration(cardUrl: '', number: '012591', colour: 0xFFE7B657),
      ),
      nodes: const [DynamicTextNode('演示出行，开始')],
      original: post(
        'o136',
        kind: DynamicKind.draw,
        author: const DynamicAuthor(mid: 14, name: '测试小程序-演示地图', face: '', following: false),
        nodes: const [DynamicTextNode('演示啊啊 这是一段测试用的文字')],
        major: const DynamicPictures(
          pictures: [
            DynamicPicture(url: '', width: 1014, height: 1212),
            DynamicPicture(url: '', width: 912, height: 1212),
            DynamicPicture(url: '', width: 900, height: 1212),
          ],
        ),
      ),
    ),
    '139': post(
      'a139',
      kind: DynamicKind.video,
      author: const DynamicAuthor(
        mid: 15,
        name: '演示用户名',
        face: '',
        pubTime: '3天前',
        pubAction: '投稿了视频',
        vipPink: true,
        verify: DynamicVerify.personal,
        decoration: DynamicDecoration(cardUrl: '', number: '000012', colour: 0xFF83BF54),
      ),
      nodes: const [],
      major: const DynamicVideo(
        aid: 2,
        bvid: 'BV1look00139',
        title: '【演示7.2测试码】300文字！10.26中午12点过期！演示7.2前瞻直播测试码',
        cover: '',
        durationText: '00:38',
        duration: 38,
        plays: '47.2万',
        danmaku: '52',
      ),
      stat: const DynamicStat(forward: 12, comment: 1370, like: 17000),
    ),
  };

  testWidgets('the cards under the system font, 440 wide at 3×', (tester) async {
    await pumpCardHost(
      tester,
      Column(
        children: [
          for (final MapEntry(:key, :value) in cards.entries)
            RepaintBoundary(
              key: ValueKey('shot-$key'),
              child: DynamicCard(item: value, space: key == '136'),
            ),
          RepaintBoundary(
            key: const ValueKey('shot-132-block'),
            child: DynamicRepostBlock(
              detail: true,
              original: post(
                'o132',
                kind: DynamicKind.video,
                author: const DynamicAuthor(mid: 16, name: '测试是我了_DemoGaming', face: ''),
                nodes: const [],
                major: const DynamicVideo(
                  aid: 3,
                  bvid: 'BV1look00132',
                  title: '演示标题测试吗！给演示加点字数吗？测试强势！大演示哥无脑抽卡测试',
                  cover: '',
                  durationText: '21:50',
                  duration: 1310,
                  plays: '5.6万',
                  danmaku: '348',
                ),
              ),
            ),
          ),
        ],
      ),
      systemFont: true,
    );
    showAsPhone(tester);
    await tester.runAsync(() async {
      final context = tester.element(find.byType(DynamicCard).first);
      for (final asset in [
        DynamicArt.forward,
        DynamicArt.comment,
        DynamicArt.like,
        DynamicArt.more,
        DynamicArt.gift,
        DynamicArt.lock,
        DynamicArt.tv,
        'assets/images/loading/cover_placeholder.png',
        'assets/images/noface.jpeg',
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('... 全文', findRichText: true), findsWidgets);
    expect(find.textContaining('... 展开', findRichText: true), findsOneWidget);
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots == null) return;
    for (final key in [...cards.keys, '132-block']) {
      await tester.ensureVisible(find.byKey(ValueKey('shot-$key')));
      await tester.pump();
      await saveShot(tester, find.byKey(ValueKey('shot-$key')), '$shots/dynamic-$key-ours.png');
    }
  });

  testWidgets("⋮'s sheet (137) under the system font", (tester) async {
    const screen = ValueKey('screen');
    await pumpCardHost(tester, DynamicCard(item: cards['135']!), systemFont: true, screen: screen);
    showAsPhone(tester);
    await tester.runAsync(() async {
      final context = tester.element(find.byType(DynamicCard));
      for (final asset in [DynamicArt.share, DynamicArt.unfollow, DynamicArt.report]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.tap(find.byKey(const ValueKey('dynamic-more')));
    await tester.pumpAndSettle();
    expect(find.text('取消关注'), findsOneWidget);
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(screen), '$shots/dynamic-137-ours.png');
  });
}
