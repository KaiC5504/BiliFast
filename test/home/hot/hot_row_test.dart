import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/home/hot/hot_row.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../support/space_host.dart';
import 'hot_support.dart';

void main() {
  group('HotFormat', () {
    final now = DateTime.utc(2026, 11, 16, 9, 59);
    String date(DateTime published) => HotFormat.date(published, now: now, utcOffset: Duration.zero);

    test('hours within a day, then 昨天 HH:mm, then N天前 for two and three days back, then the date', () {
      expect(date(DateTime.utc(2026, 11, 16, 9, 30)), '29分钟前');
      expect(date(DateTime.utc(2026, 11, 15, 10, 59)), '23小时前');
      expect(date(DateTime.utc(2026, 11, 15, 8, 20)), '昨天 08:20');
      expect(date(DateTime.utc(2026, 11, 14, 22, 0)), '2天前');
      expect(date(DateTime.utc(2026, 11, 13, 1, 0)), '3天前');
      expect(date(DateTime.utc(2026, 11, 12, 23, 0)), '11月12日');
      expect(date(DateTime.utc(2025, 11, 1)), '2025-11-01');
      expect(HotFormat.date(null, now: now), '');
    });

    test('a day back by the clock but two by the calendar reads 2天前, not 昨天', () {
      expect(date(DateTime.utc(2026, 11, 14, 23, 0)), '2天前');
    });

    test('the ▷ line: the plays with 播放, the date after a dot, or the plays alone', () {
      final video = hotVideo(1, views: 1831000);
      final dated = PopularVideo(card: video.card, published: DateTime.utc(2026, 11, 15, 8, 20));
      expect(HotFormat.plays(dated, now: now, utcOffset: Duration.zero), '183.1万播放 · 昨天 08:20');
      expect(HotFormat.plays(PopularVideo(card: video.card), now: now), '183.1万播放');
      final few = PopularVideo(card: hotVideo(2, views: 9876).card);
      expect(HotFormat.plays(few, now: now), '9876播放');
    });
  });

  group('HotRow', () {
    late List<String> opened;
    late int mores;

    setUp(() {
      opened = [];
      mores = 0;
    });

    Future<void> pumpRow(WidgetTester tester, PopularVideo video) => pumpSpaceHost(
      tester,
      SizedBox(
        width: 440,
        child: HotRow(video: video, now: hotNow, onOpen: () => opened.add(video.card.bvid), onMore: () => mores++),
      ),
    );

    testWidgets("204's row: its words, the cover at 12, 10 and the line across the page 114 down", (tester) async {
      await pumpRow(tester, hotVideo(1, owner: '测试作者', views: 238000, duration: 4908, age: const Duration(hours: 3)));
      expect(find.text('测试热门视频 1'), findsOneWidget);
      expect(find.text('测试作者', findRichText: true), findsOneWidget);
      expect(find.text('23.8万播放 · 3小时前', findRichText: true), findsOneWidget);
      expect(find.text('1:21:48'), findsOneWidget);
      expect(tester.getSize(find.byType(HotRow)).height, moreOrLessEquals(344 / 3));
      expect(tester.getRect(find.byKey(const ValueKey('hot-cover-placeholder'))), const Rect.fromLTWH(12, 10, 167, 94));
      final line = tester.getRect(
        find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == HotListTheme.hairlineInk),
      );
      expect(line, const Rect.fromLTWH(0, 114, 440, 0.5));
    });

    testWidgets('a long title runs to two lines and is cut', (tester) async {
      final long = '一个很长很长的测试标题' * 6;
      await pumpRow(tester, hotVideo(1, title: long));
      final title = find.byKey(const ValueKey('hot-title-BV1hot1'));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      // Flutter rounds each line to whole points.
      expect(tester.getSize(title).height, moreOrLessEquals(HotListTheme.titleLine * 2, epsilon: 1));
      expect(tester.getRect(title).right, lessThanOrEqualTo(440 - HotListTheme.titleRight));
    });

    testWidgets('no duration, no pill', (tester) async {
      await pumpRow(tester, hotVideo(1, duration: 0));
      expect(find.text('0:00'), findsNothing);
      expect(find.byKey(const ValueKey('hot-cover-placeholder')), findsOneWidget);
    });

    testWidgets('a tap opens the video; ⋮ its sheet', (tester) async {
      await pumpRow(tester, hotVideo(1));
      await tester.tap(find.byKey(const ValueKey('hot-title-BV1hot1')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('hot-cover-placeholder')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot1')));
      await pumpRoute(tester);
      expect(opened, ['BV1hot1', 'BV1hot1']);
      expect(mores, 1);
      expect(openSpaces(tester), isEmpty);
    });

    testWidgets("the uploader's name opens their space with the row's face, not the video", (tester) async {
      await pumpRow(
        tester,
        hotVideo(1, owner: '测试作者', ownerMid: 501, face: 'https://i1.hdslb.com/bfs/face/made-up.jpg'),
      );
      await tester.tap(find.byKey(const ValueKey('hot-uploader-BV1hot1')));
      await pumpRoute(tester);
      final space = openSpaces(tester).single;
      expect((space.mid, space.name, space.face), (501, '测试作者', 'https://i1.hdslb.com/bfs/face/made-up.jpg'));
      expect(opened, isEmpty);
    });

    testWidgets("the name's target is as wide as the drawn name; past it the row opens the video", (tester) async {
      await pumpRow(tester, hotVideo(1, owner: '测试作者'));
      final target = tester.getRect(find.byKey(const ValueKey('hot-uploader-BV1hot1')));
      final drawn = tester.getRect(find.text('测试作者', findRichText: true));
      expect(target.right, moreOrLessEquals(drawn.right, epsilon: 0.01));
      expect(target.left, moreOrLessEquals(HotListTheme.metaLeft));
      final plays = tester.getRect(find.byKey(const ValueKey('hot-plays-BV1hot1')));
      final upTop = plays.top - (HotListTheme.upCentreAbove - HotListTheme.playsCentreAbove);
      expect(target.top, moreOrLessEquals(upTop - HotListTheme.uploaderSlopAbove), reason: 'from 6 above the line');
      expect(
        target.bottom,
        moreOrLessEquals((upTop + HotListTheme.metaLine + plays.top) / 2),
        reason: "half way down to the ▷ line",
      );
      await tester.tapAt(Offset(target.right + 12, target.center.dy));
      await pumpRoute(tester);
      expect(opened, ['BV1hot1']);
      expect(openSpaces(tester), isEmpty);
    });

    testWidgets('without a mid the name is part of the row', (tester) async {
      final base = hotVideo(1, owner: '测试作者');
      final card = base.card;
      final nameless = PopularVideo(
        card: VideoCard(
          aid: card.aid,
          bvid: card.bvid,
          cid: card.cid,
          title: card.title,
          cover: '',
          duration: card.duration,
          ownerMid: 0,
          ownerName: card.ownerName,
          views: card.views,
          danmaku: 0,
          likes: 0,
        ),
      );
      await pumpRow(tester, nameless);
      expect(find.byKey(const ValueKey('hot-uploader-BV1hot1')), findsNothing);
      await tester.tap(find.text('测试作者', findRichText: true), warnIfMissed: false);
      await pumpRoute(tester);
      expect(opened, ['BV1hot1']);
      expect(openSpaces(tester), isEmpty);
    });

    testWidgets('VoiceOver: the row says its title, uploader, length and plays; the name and ⋮ are buttons', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpRow(tester, hotVideo(1, owner: '测试作者', age: const Duration(hours: 3)));
      final row = find.semantics.byPredicate((node) => node.label == '测试热门视频 1，测试作者，5:58，183.1万播放 · 3小时前');
      expect(row, findsOne);
      tester.semantics.tap(row);
      final name = find.semantics.byPredicate(
        (node) => node.label == '测试作者' && node.getSemanticsData().hasAction(SemanticsAction.tap),
      );
      tester.semantics.tap(name);
      tester.semantics.tap(find.semantics.byLabel('更多操作'));
      await pumpRoute(tester);
      expect(opened, ['BV1hot1']);
      expect(mores, 1);
      expect(openSpaces(tester), hasLength(1));
      semantics.dispose();
    });
  });
}
