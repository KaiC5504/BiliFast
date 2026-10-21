import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/watch_later/fake_watch_later_api.dart';
import 'package:bilifast/watch_later/watch_later_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../search/results/results_support.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

// Made up and shaped like 86's row: the same scripts and punctuation in the same places, so its title breaks where
// 86's does.
const _row = WatchLaterItem(
  aid: 82000001,
  bvid: 'BV1look0001',
  cid: 141000001,
  title: '演示标题！测试很长！假名字-假名字最佳配装，假装定论！【演示用测试】',
  cover: '',
  ownerMid: 1,
  ownerName: '测试UP',
  duration: 412,
  progress: 1,
  play: 104000,
  danmaku: 175,
);

const _folders = [
  FavFolder(id: 1, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
  FavFolder(id: 2, title: '二号', count: 8, isPrivate: true, contains: false, isDefault: false),
];

/// 稍后再看 as KaiC's iPhone draws it, under the system font, against 85, 86 and 93-98 (px / 3). With BILIFAST_SHOTS
/// naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> show(WidgetTester tester, {List<WatchLaterItem> items = const [_row]}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final AppServices services = await resultServices(loggedIn: true, api: FakePageApi());
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    final api = FakeWatchLaterApi(items: items, folderList: _folders);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, page) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: services, child: page!),
        ),
        home: WatchLaterPage(api: api, open: (_, _) {}),
      ),
    );
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester, 20);
  }

  testWidgets('85: the empty page', (tester) async {
    await show(tester, items: const []);
    await shoot(tester, '85-watch-later-empty-ours');
    expect(find.text(WatchLaterPage.emptyMessage), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('later-chip-all'))), const Rect.fromLTWH(12, 358 / 3, 42, 77 / 3));
  });

  testWidgets('86: one row and the note', (tester) async {
    await show(tester);
    await shoot(tester, '86-watch-later-list-ours');
    expect(tester.getTopLeft(find.byKey(const ValueKey('later-row-BV1look0001'))).dy + 10, closeTo(506 / 3, 0.01));
    final title = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('later-title-BV1look0001')));
    expect(title.didExceedMaxLines, isFalse);
    expect(find.text(WatchLaterPage.note), findsOneWidget);
  });

  testWidgets('93: 管理’s sheet over 未看完', (tester) async {
    await show(tester);
    await tap(tester, 'later-chip-unfinished');
    await tap(tester, 'later-manage');
    await shoot(tester, '93-watch-later-manage-ours');
    expect(tester.getTopLeft(find.byKey(const ValueKey('later-manage-sheet'))).dy, closeTo(2156 / 3, 0.5));
  });

  testWidgets('94: a row’s ⋮ sheet', (tester) async {
    await show(tester);
    await tap(tester, 'later-chip-unfinished');
    await tap(tester, 'later-more-BV1look0001');
    await shoot(tester, '94-watch-later-row-more-menu-ours');
    expect(tester.getTopLeft(find.byKey(const ValueKey('later-row-sheet'))).dy, closeTo(2478 / 3, 0.5));
  });

  Future<void> bulk(WidgetTester tester) async {
    await show(tester);
    await tap(tester, 'later-chip-unfinished');
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-批量管理');
  }

  testWidgets('95: the edit mode', (tester) async {
    await bulk(tester);
    await shoot(tester, '95-watch-later-bulk-ours');
    final title = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('later-title-BV1look0001')));
    expect(title.didExceedMaxLines, isTrue, reason: 'cut with … as 95');
  });

  testWidgets('96: the row chosen', (tester) async {
    await bulk(tester);
    await tap(tester, 'later-open-BV1look0001');
    await shoot(tester, '96-watch-later-bulk-selected-ours');
    expect(find.text('取消选择 (1)'), findsOneWidget);
  });

  for (final (key, name) in [('copy', '97-watch-later-copy-to-folder'), ('move', '98-watch-later-move-to-folder')]) {
    testWidgets('${name.substring(0, 2)}: the folders for $key', (tester) async {
      await bulk(tester);
      await tap(tester, 'later-open-BV1look0001');
      await tap(tester, 'later-edit-$key');
      await shoot(tester, '$name-ours');
      expect(find.text('公开 · 0个内容'), findsOneWidget);
    });
  }
}
