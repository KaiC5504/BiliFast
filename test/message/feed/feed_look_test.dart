import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/feed/likes_page.dart';
import 'package:bilifast/message/feed/new_fans_page.dart';
import 'package:bilifast/message/feed/replies_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../dynamic/following/following_support.dart' show skinOf, violetSkin;
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import 'feed_support.dart';

final _now = DateTime(2026, 11, 16, 10);
final _april = DateTime(2026, 4, 2, 9);

// Made-up rows shaped like 197's: the same lengths and scripts, an UP tag, likes, one and two lines.
final _replies = [
  reply(
    1,
    user: person(1, name: 'Example_W'),
    fromUploader: true,
    text: '演示一下哦[doge]',
    targetText: '建议可以增加ABC的演示说明',
    time: _now.subtract(const Duration(days: 3)),
  ),
  reply(
    2,
    user: person(2, name: '测试漫游S08'),
    text: '不需要改',
    targetText: '12测12演21示需要改吗',
    time: _april,
  ),
  reply(
    3,
    user: person(3, name: 'demo_neko'),
    text: '这是演示用的一句话，测试长度和原来差不多',
    targetText: '12测12演21示需要改吗',
    liked: true,
    time: _april,
  ),
  reply(
    4,
    user: person(4, name: '测试Demo演示'),
    text: '演示文字测试一下这一行的长度是不是二十四个字，然后第二行继续写一些演示的内容让它被截断成省略号的样子吧好的',
    targetText: '12测12演21示需要改吗',
    liked: true,
    time: _april,
  ),
];

// 198's five rows, made up the same way, each second name starting with the glyph 198's does. The first starts with a
// combining ゚ (U+309A), which draws over the 、's corner and takes no room.
final _likes = [
  like(
    1,
    users: [
      person(1, name: '演示Channel'),
      person(2, name: '\u{309A}嫦测试'),
    ],
    count: 12,
    title: '核心是演示或测试时，人都在看',
    time: DateTime(2026, 10, 1),
  ),
  like(
    3,
    users: [person(3, name: '会演示的猫')],
    title: '12测12演21示需要改吗',
    time: _april,
  ),
  like(
    4,
    users: [
      person(4, name: '演示大鱼干'),
      person(5, name: '吃演示了'),
    ],
    count: 2,
    title: '有没有开放演示测试[大哭]',
    time: DateTime(2023, 11, 19),
  ),
  like(
    6,
    users: [
      person(6, name: '演示生梦'),
      person(7, name: 'cat--demo'),
    ],
    count: 2,
    title: '请问演示可以测试吗？[doge]',
    time: DateTime(2023, 10, 25),
  ),
  like(
    8,
    users: [person(8, name: 'demo_12345678901')],
    business: '弹幕',
    title: '需要晚上',
    time: DateTime(2023, 1, 19),
  ),
];

/// The shot's ink (any channel 60 off the white page) in [band], in pt: runs of touching columns along x, each with its
/// ink's top and bottom.
Future<List<({double left, double right, double top, double bottom})>> _inkRuns(WidgetTester tester, Rect band) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final width = image.width;
  image.dispose();
  bool ink(int x, int y) {
    final i = (y * width + x) * 4;
    return [0, 1, 2].any((c) => 255 - bytes.getUint8(i + c) > 60);
  }

  final runs = <({double left, double right, double top, double bottom})>[];
  int? start;
  var end = 0;
  var top = 0;
  var bottom = 0;
  for (var x = (band.left * 3).round(); x < (band.right * 3).round(); x++) {
    final ys = [
      for (var y = (band.top * 3).round(); y < (band.bottom * 3).round(); y++)
        if (ink(x, y)) y,
    ];
    if (ys.isEmpty) continue;
    if (start != null && x == end + 1) {
      end = x;
      top = ys.first < top ? ys.first : top;
      bottom = ys.last > bottom ? ys.last : bottom;
      continue;
    }
    if (start != null) runs.add((left: start / 3, right: (end + 1) / 3, top: top / 3, bottom: (bottom + 1) / 3));
    (start, end, top, bottom) = (x, x, ys.first, ys.last);
  }
  if (start != null) runs.add((left: start / 3, right: (end + 1) / 3, top: top / 3, bottom: (bottom + 1) / 3));
  return runs;
}

void _near(Rect actual, Rect expected) {
  for (final (a, b) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, closeTo(b, 0.01), reason: '$actual against $expected');
  }
}

/// 回复与@, 收到喜欢 and 新增粉丝 as KaiC's iPhone draws them, under the system font and his skin's bar, against 197-199,
/// 213 and 214 (px / 3). With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for
/// tools/screen_diff.py.
void main() {
  Future<FakeMessageApi> show(WidgetTester tester, Widget page, {FakeMessageApi? api}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final messages = api ?? FakeMessageApi(replyList: _replies, likeList: _likes);
    final services = await feedServices(messages);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await pumpFeed(tester, services, page, sized: false);
    // The default faces, the glyphs and the empty picture are assets, decoded off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    return messages;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('197: the bar, the chips and the replies', (tester) async {
    await show(tester, RepliesPage(skin: skinOf(violetSkin), now: () => _now));
    await shoot(tester, '197-message-reply-at-ours');

    _near(tester.getRect(byKey('feed-bar')), const Rect.fromLTRB(0, 0, 440, 350 / 3));
    _near(tester.getRect(byKey('feed-chip-all')), const Rect.fromLTRB(12, 128, 54, 156));
    _near(tester.getRect(byKey('feed-chip-at')), const Rect.fromLTRB(62, 128, 105, 156));
    expect(tester.getRect(byKey('feed-reply-1')).top, closeTo(168, 0.01));
    expect(tester.getRect(byKey('feed-reply-2')).top, closeTo(794 / 3, 0.01));
    expect(tester.getRect(byKey('feed-reply-3')).top, closeTo(358, 0.01));
    expect(tester.getRect(byKey('feed-reply-4')).top, closeTo(1355 / 3, 0.34));
    expect(tester.getRect(byKey('feed-reply-face-2')).top, closeTo(841 / 3, 0.01));
    // 建议可以, the first row's side line, as on 197: its ink from 388.67 to 427.
    final side = await _inkRuns(tester, const Rect.fromLTRB(380, 187, 438, 197.33));
    expect(side.first.left, closeTo(388.67, 0.5));
    expect(side.last.right, closeTo(427, 0.5));
  });

  testWidgets('213: @我 with nothing', (tester) async {
    await show(tester, RepliesPage(skin: skinOf(violetSkin), mentions: true, now: () => _now));
    await shoot(tester, '213-message-at-me-empty-ours');
    final picture = find.descendant(of: byKey('feed-mentions-list'), matching: find.byType(Image));
    expect(tester.getRect(picture).top, closeTo(168 + MessageFeedTheme.emptyTop, 0.01));
  });

  testWidgets('214: a row\'s ⋮ sheet', (tester) async {
    await show(tester, RepliesPage(skin: skinOf(violetSkin), now: () => _now));
    await tester.tap(byKey('feed-reply-more-1'));
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    await shoot(tester, '214-message-reply-row-more-sheet-ours');
    _near(tester.getRect(byKey('feed-sheet')), const Rect.fromLTRB(0, 787, 440, 956));
    expect(tester.getRect(byKey('feed-sheet-mute')).top, closeTo(806, 0.01));
    expect(tester.getRect(byKey('feed-sheet-delete')).top, closeTo(858, 0.01));
  });

  testWidgets('198: who liked what', (tester) async {
    await show(tester, LikesPage(skin: skinOf(violetSkin), now: () => _now));
    await shoot(tester, '198-message-likes-ours');
    expect(tester.getRect(byKey('feed-like-1')).top, closeTo(350 / 3, 0.01));
    expect(tester.getRect(byKey('feed-like-3')).top, closeTo(569 / 3, 0.34));
  });

  // 198's pairs, measured on its ink: the first name's end to the 、, and the 、's start to the second name's (past a
  // combining mark over the 、). The 、's own ink isn't compared: the stand-in's is 0.67 wider than PingFang's.
  testWidgets('198: the 、 between two names sits where 198 puts it', (tester) async {
    await show(tester, LikesPage(skin: skinOf(violetSkin), now: () => _now));
    for (final (id, before, after) in [(1, 14 / 3, 41 / 3), (4, 14 / 3, 14.0), (6, 13 / 3, 14.0)]) {
      final line = tester.getRect(byKey('feed-like-line-$id'));
      final middle = line.center.dy;
      final runs = await _inkRuns(tester, Rect.fromLTRB(60, line.top, 300, line.bottom));
      final comma = runs.indexWhere((run) => run.top > middle);
      final next = runs.skip(comma + 1).firstWhere((run) => run.bottom > middle);
      expect(runs[comma].left - runs[comma - 1].right, closeTo(before, 0.5), reason: 'row $id: before the 、');
      expect(next.left - runs[comma].left, closeTo(after, 0.5), reason: 'row $id: the 、 to the second name');
    }
  });

  testWidgets('198: the side column where 198 draws it', (tester) async {
    await show(tester, LikesPage(skin: skinOf(violetSkin), now: () => _now));
    // 有没有开 on 198's third row, as there: its ink from 388.67, the line's middle 24.17 under the row's top. Its end
    // isn't compared: 198's 10 pt characters step about 9.85 (有 to 有 is 19.67), ours 10.
    final row = tester.getRect(byKey('feed-like-4'));
    final runs = await _inkRuns(tester, Rect.fromLTRB(380, row.top + 18, 438, row.top + 30));
    expect(runs.first.left, closeTo(388.67, 0.5));
    expect((runs.first.top + runs.first.bottom) / 2 - row.top, closeTo(24.17, 0.5));
  });

  testWidgets('199: 新增粉丝 with nobody', (tester) async {
    await show(tester, const NewFansPage(), api: FakeMessageApi());
    await shoot(tester, '199-message-new-fans-empty-ours');
    final picture = find.descendant(of: byKey('feed-fans-list'), matching: find.byType(Image));
    expect(tester.getRect(picture).top, closeTo(62 + 44 + MessageFeedTheme.fansEmptyTop, 0.01));
  });
}
