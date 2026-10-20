import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/video/intro/action_row.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/intro/desc_text.dart';
import 'package:bilifast/video/intro/part_strip.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/video/intro/tag_chips.dart';
import 'package:bilifast/video/intro/title_block.dart';
import 'package:bilifast/video/intro/uploader_row.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';
import '../mixed_lines.dart';

VideoDetail _detail({
  String title = '恭喜你终于触发了大保底',
  String? argue,
  List<DescPart> desc = const [],
  List<StaffMember> staff = const [],
}) => VideoDetail(
  bvid: 'BV1PdJD6iEFb',
  aid: 1,
  title: title,
  cover: '',
  pubdate: DateTime(2026, 10, 11, 21, 5).millisecondsSinceEpoch ~/ 1000,
  duration: 100,
  desc: '',
  descParts: desc,
  copyright: 0,
  owner: const VideoOwner(mid: 7, name: '星宇动漫社', face: ''),
  stat: const VideoStat(view: 37000, danmaku: 337, reply: 0, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: staff,
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
  argueMessage: argue,
);

Future<void> _block(WidgetTester tester, VideoDetail detail, {List<VideoTag> tags = const [], String? online}) async {
  final count = ValueNotifier<String?>(online);
  addTearDown(count.dispose);
  await tester.pumpWidget(
    appHost(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 440,
          child: TitleBlock(
            key: UniqueKey(),
            detail: detail,
            online: count,
            tags: tags,
            onSeek: (_) {},
            onOpenVideo: (_) {},
            openLink: (_) async => true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _top(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(appHost(Align(alignment: Alignment.topLeft, child: SizedBox(width: 440, child: child))));
  await tester.pumpAndSettle();
}

void main() {
  group('under the system font a line mixing Latin and Chinese sits on the Chinese line', () {
    testWidgets('the title, collapsed and expanded', (tester) async {
      await useSystemFont(tester);
      await expectMixedOnChineseLines(tester, show: (title) => _block(tester, _detail(title: title)));

      await _block(tester, _detail(title: chineseLines));
      await _expand(tester, chineseLines);
      final chinese = baselinesOf(tester, find.text(chineseLines), strut: false);
      await _block(tester, _detail(title: mixedLines));
      await _expand(tester, mixedLines);
      expectOnChineseLines(tester, find.text(mixedLines), chinese);
    });

    testWidgets('the notice and the meta line', (tester) async {
      await useSystemFont(tester);
      await expectMixedOnChineseLines(tester, show: (notice) => _block(tester, _detail(argue: notice)));
      await _block(tester, _detail(), online: '53');
      expectOnChineseLine(tester, find.text('2026年10月11日 21:05'));
      expectOnChineseLine(tester, find.text('3.7万'));
      expectOnChineseLine(tester, find.text('53人正在看'));
    });

    testWidgets('the description and the plain tags', (tester) async {
      await useSystemFont(tester);
      Future<void> description(String text) async {
        await _block(tester, _detail(desc: [DescPart(text: text)]));
        await _expand(tester, _detail().title);
      }

      await description(chineseLines);
      final lines = baselinesOf(tester, find.byType(DescriptionText), strut: false);
      await description(mixedLines);
      expectOnChineseLines(tester, find.byType(DescriptionText), lines);

      await expectMixedOnChineseLines(
        tester,
        show: (name) async {
          await _block(tester, _detail(), tags: [VideoTag(id: 1, name: name, kind: VideoTagKind.normal)]);
          await _expand(tester, _detail().title);
        },
      );
    });

    testWidgets('a topic chip', (tester) async {
      await useSystemFont(tester);
      await expectMixedOnChineseLines(
        tester,
        show: (name) => _top(tester, TagChips(tags: [VideoTag(id: 1, name: name, kind: VideoTagKind.topic)])),
      );
    });

    testWidgets('the 合集 row', (tester) async {
      await useSystemFont(tester);
      final episodes = [const Episode(bvid: 'BV1', cid: 1, title: '第一集', current: true)];
      await _top(tester, CollectionRow(title: mixedLine, episodes: episodes, onOpen: () {}));
      expectOnChineseLine(tester, find.text('合集 · $mixedLine'));
    });

    testWidgets('a part chip, over both its lines', (tester) async {
      await useSystemFont(tester);
      await expectMixedOnChineseLines(
        tester,
        chinese: chineseLines,
        mixed: mixedLines,
        show: (title) => _top(
          tester,
          PartStrip(
            parts: [Episode(bvid: 'BV1', cid: 1, title: title, current: false)],
            onChoose: (_) {},
            onOpenList: () {},
          ),
        ),
        finder: (title) => find.text(title, findRichText: true),
      );
    });

    testWidgets('a related video\'s title and uploader', (tester) async {
      await useSystemFont(tester);
      Future<void> show(String text) async {
        final card = VideoCard(
          aid: 1,
          bvid: 'BV1',
          cid: 1,
          title: text * 4,
          cover: '',
          duration: 175,
          ownerMid: 1,
          ownerName: text,
          views: 4815000,
          danmaku: 17000,
          likes: 0,
        );
        await tester.pumpWidget(
          appHost(
            CustomScrollView(slivers: [RelatedSliver(cards: [card], onOpen: (_) {}, onWatchLater: (_) {})]),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(chineseLine);
      final title = baselinesOf(tester, find.text(chineseLine * 4), strut: false);
      final owner = baselinesOf(tester, find.text(chineseLine), strut: false);
      await show(mixedLine);
      expectOnChineseLines(tester, find.text(mixedLine * 4), title);
      expectOnChineseLines(tester, find.text(mixedLine), owner);
      expectOnChineseLine(tester, find.text('481.5万'));
    });

    testWidgets('the uploader\'s name and counts, and the staff\'s names and roles', (tester) async {
      await useSystemFont(tester);
      UploaderCard card(String name) => UploaderCard(
        mid: 7,
        name: name,
        face: '',
        fans: 475000,
        videos: 410,
        isVip: false,
        following: false,
        official: OfficialKind.none,
      );
      await expectMixedOnChineseLines(
        tester,
        show: (name) => _top(tester, UploaderRow(detail: _detail(), card: card(name))),
      );
      expectOnChineseLine(tester, find.text('47.5万粉丝  410视频', findRichText: true));

      Future<void> staff(String text) => _top(
        tester,
        UploaderRow(
          detail: _detail(
            staff: [
              StaffMember(mid: 1, title: text.substring(0, 4), name: text, face: ''),
              const StaffMember(mid: 2, title: '剪辑', name: '小明', face: ''),
            ],
          ),
        ),
      );
      await staff(chineseLine);
      final name = baselinesOf(tester, find.text(chineseLine), strut: false);
      final role = baselinesOf(tester, find.text(chineseLine.substring(0, 4)), strut: false);
      await staff(mixedLine);
      expectOnChineseLines(tester, find.text(mixedLine), name);
      expectOnChineseLines(tester, find.text(mixedLine.substring(0, 4)), role);
    });

    testWidgets('an action\'s count beside a label', (tester) async {
      await useSystemFont(tester);
      final actions = FakeVideoActions(favCount: 123456);
      addTearDown(actions.dispose);
      await _top(tester, ActionRow(actions: actions));
      expectOnChineseLines(tester, find.text('12.3万'), baselinesOf(tester, find.text('不喜欢'), strut: false));
    });
  });
}
