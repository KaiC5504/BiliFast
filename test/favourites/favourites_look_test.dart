import 'dart:io';

import 'package:bili_core/api.dart' show FavFolder;
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/favourites/favourites_page.dart';
import 'package:bilifast/favourites/folder_page.dart';
import 'package:bilifast/favourites/new_folder_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'favourites_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

// Made-up folders and rows shaped like 80's, 81's and 83's: the same lengths and scripts, so lines sit and end where
// theirs do.
final _rows = [
  favVideo(1, title: '每日练习', owner: '甲 NyaKo', duration: 11, play: 8040, danmaku: 0),
  favVideo(2, title: '嗯...就这点本事吗', owner: '鸢鸢喜欢欧尼那', duration: 53, play: 21000, danmaku: 1),
  favVideo(3, title: '春日野穹cos', owner: '一只小猫', duration: 18, play: 2746, danmaku: 1),
  favVideo(4, title: '春日野穹', owner: '翊翊爱吃肉', duration: 12, play: 37000, danmaku: 0),
  favVideo(5, title: '你到底要不要', owner: 'Ykiise', duration: 12, play: 2153, danmaku: 0),
  favVideo(6, title: '在干嘛 还不来找我', owner: '摆烂小瑶 TnT', duration: 12, play: 13000, danmaku: 1),
  favVideo(7, title: '想我了给我打电话我不会接的', owner: '摆烂小瑶 TnT', duration: 8, play: 753, danmaku: 0),
  favVideo(8, title: '打响新年第一次', owner: '猫酱_baby', duration: 18, play: 18000, danmaku: 0),
];

FakeFavouritesApi _api() => FakeFavouritesApi(
  ownerName: 'Demo1234',
  folders: [favFolder(1, '默认收藏夹', isDefault: true), favFolder(2, '二次', count: 8, private: true)],
  contents: {1: const [], 2: _rows},
);

/// 我的收藏 as KaiC's iPhone draws it, under the system font, against 80-84 (px / 3). With BILIFAST_SHOTS naming a
/// folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> show(WidgetTester tester, Widget page, FakeFavouritesApi api) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    // The services' font store puts MiSans back, so the system font comes after them.
    final AppServices services = await favouritesServices(loggedIn: true, api: api);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: services, child: child!),
        ),
        home: page,
      ),
    );
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('80: the bar, the chips and two folder cards', (tester) async {
    await show(tester, const FavouritesPage(), _api());
    await settle(tester);
    await shoot(tester, '80-favourites-folders-ours');

    expect(tester.getRect(find.byKey(const ValueKey('fav-folder-1'))), const Rect.fromLTRB(12, 166, 428, 304));
    expect(tester.getRect(find.byKey(const ValueKey('fav-folder-2'))), const Rect.fromLTRB(12, 312, 428, 475));
    final chip = tester.getRect(find.byKey(const ValueKey('fav-chip-folders')));
    expect(chip.top, 118);
    expect(chip.left, 12);
    expect(chip.height, 28);
    expect(chip.width, closeTo(164 / 3, 0.5));
    final pill = tester.getRect(find.byKey(const ValueKey('fav-new-folder')));
    expect(pill.top, 533);
    expect(pill.height, 34);
    expect(pill.width, closeTo(305 / 3, 0.5));
  });

  testWidgets('99: the folders as a list', (tester) async {
    favouritesLayout = FavouritesLayout.list;
    addTearDown(() => favouritesLayout = FavouritesLayout.cards);
    await show(tester, const FavouritesPage(), _api());
    await settle(tester);
    await shoot(tester, '99-favourites-folders-list-layout-ours');

    expect(tester.getRect(find.byKey(const ValueKey('fav-folder-1'))), const Rect.fromLTRB(12, 166, 428, 258));
    expect(tester.getRect(find.byKey(const ValueKey('fav-folder-2'))), const Rect.fromLTRB(12, 266, 428, 358));
    expect(tester.getRect(find.byKey(const ValueKey('fav-play-2'))), const Rect.fromLTRB(364, 300, 416, 324));
    expect(tester.getRect(find.byKey(const ValueKey('fav-new-folder'))).top, 416);
    final toggle = tester.getRect(find.byKey(const ValueKey('fav-layout-list')));
    expect(toggle.center.dx, closeTo(418, 0.5));
    expect(toggle.width, 16);
  });

  testWidgets('100 and 101: 创建, then 封面’s sheet', (tester) async {
    Future<FavFolder> create({
      required String title,
      required String intro,
      required bool isPrivate,
      String cover = '',
    }) async => favFolder(9, title);
    Future<String> upload({required List<int> bytes, required String filename}) async => '';
    await show(tester, NewFolderPage(create: create, uploadCover: upload), _api());
    await shoot(tester, '100-favourites-new-folder-ours');

    expect(tester.getRect(find.byKey(const ValueKey('fav-new-cover'))), const Rect.fromLTRB(0, 116, 440, 180));
    final title = tester.getRect(find.byKey(const ValueKey('fav-new-title')));
    expect(title.left, 88);
    expect(title.right, 428);
    expect(title.center.dy, closeTo(211, 0.5));
    final intro = tester.getRect(find.byKey(const ValueKey('fav-new-intro')));
    expect(intro.top, closeTo(244 + 1 / 3 + 68 / 3 - 10 - 1, 0.01));
    final toggle = tester.getRect(find.byType(CupertinoSwitch));
    expect(toggle.center.dx, 404.5);
    expect(toggle.center.dy, closeTo(420 + 1 / 3, 0.01));

    await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
    await settle(tester);
    await shoot(tester, '101-favourites-new-folder-cover-picker-ours');
    final sheet = tester.getRect(find.byKey(const ValueKey('fav-new-cover-sheet')));
    expect(sheet.left, 8);
    expect(sheet.right, 432);
    expect(sheet.bottom, 922);
    expect(sheet.top, closeTo(742 + 2 / 3, 0.01));
  });

  testWidgets('81: a folder', (tester) async {
    final api = _api();
    await show(tester, FolderPage(folder: favFolder(2, '二次', count: 8, private: true), api: api), api);
    await shoot(tester, '81-favourites-folder-inside-ours');

    expect(tester.getTopLeft(find.byKey(const ValueKey('fav-folder-row-7001'))).dy + 12, 220);
    expect(tester.getTopLeft(find.byKey(const ValueKey('fav-folder-row-7002'))).dy + 12, 320);
  });

  testWidgets('82: a row’s ⋮ sheet', (tester) async {
    final api = _api();
    await show(tester, FolderPage(folder: favFolder(2, '二次', count: 8, private: true), api: api), api);
    await tester.tap(find.byKey(const ValueKey('fav-folder-more-7001')));
    await settle(tester);
    await shoot(tester, '82-favourites-row-more-menu-ours');

    // 82's band starts 862 down, 取消收藏's section 103 above it.
    expect(tester.getRect(find.byKey(const ValueKey('fav-sheet'))).top, closeTo(759, 0.34));
  });

  testWidgets('83 and 84: 视频, then its end', (tester) async {
    await show(tester, const FavouritesPage(), _api());
    await tester.tap(find.byKey(const ValueKey('fav-chip-videos')));
    await settle(tester);
    await shoot(tester, '83-favourites-videos-ours');
    expect(tester.getTopLeft(find.byKey(const ValueKey('fav-videos-row-7001'))).dy + 12, 170);
    final list = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const ValueKey('fav-videos-list')), matching: find.byType(Scrollable)),
    );
    list.position.jumpTo(list.position.maxScrollExtent);
    await settle(tester);
    await shoot(tester, '84-favourites-videos-end-ours');
    // 84's ink is centred 40.5 under the last row; the line's ink sits 0.67 below its box's middle.
    final last = tester.getRect(find.byKey(const ValueKey('fav-videos-row-7008')));
    expect(tester.getCenter(find.byKey(const ValueKey('fav-videos-end'))).dy - last.bottom, closeTo(119.5 / 3, 0.34));
  });
}
