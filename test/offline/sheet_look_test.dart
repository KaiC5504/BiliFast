import 'dart:io';

import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/offline/sheet/sheet_art.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../player_ui/panels/sheet_rig.dart';
import '../support/look_alike.dart';

/// The portrait ⋮ sheet (42, 43) and 缓存 (141, 142, 144, 153, 154) as KaiC's iPhone draws them, under the system
/// font. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  final shots = Platform.environment['BILIFAST_SHOTS'];

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.runAsync(loadIconFonts);
    await tester.runAsync(() async {
      final context = tester.element(find.byKey(SheetRig.shot));
      for (final asset in const [
        SheetArt.dislike,
        SheetArt.watchLater,
        SheetArt.download,
        SheetArt.miniPlayer,
        SheetArt.cast,
        SheetArt.share,
        SheetArt.done,
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (shots != null) await saveShot(tester, find.byKey(SheetRig.shot), '$shots/$name.png');
  }

  OfflineItem item(int cid, OfflineState state, {int bytes = 0, int total = 0}) => OfflineItem(
    request: OfflineRequest(
      bvid: 'BV$cid',
      aid: cid,
      cid: cid,
      title: '',
      duration: 1,
      cover: '',
      ownerMid: 0,
      ownerName: '',
    ),
    state: state,
    addedAt: DateTime(2026, 10, 30),
    bytes: bytes,
    totalBytes: total,
  );

  testWidgets('42: ⋮ under the small player', (tester) async {
    final rig = await pumpSheetRig(tester, look: true, session: singleVideo());
    await openSheet(tester, rig, PlayerPanel.more);
    await shoot(tester, '42-ours');
  });

  testWidgets('43: ⋮ in 竖屏', (tester) async {
    final rig = await pumpSheetRig(tester, look: true, presentation: Presentation.vertical, session: singleVideo());
    rig.session
      ..playing = 116
      ..autoplayNext = false;
    await openSheet(tester, rig, PlayerPanel.more);
    await shoot(tester, '43-ours');
  });

  testWidgets('141: 缓存 for a video downloading', (tester) async {
    final library = FakeOfflineLibrary(free: 79886391705)..put(item(501, OfflineState.downloading, total: 100));
    final rig = await pumpSheetRig(tester, look: true, session: singleVideo(vip: false), library: library);
    await library.enqueue(const []);
    await openSheet(tester, rig, PlayerPanel.download);
    await shoot(tester, '141-ours');
  });

  testWidgets('142: 画质 over 缓存', (tester) async {
    final library = FakeOfflineLibrary(free: 79886391705)..put(item(501, OfflineState.downloading, total: 100));
    final rig = await pumpSheetRig(tester, look: true, session: singleVideo(vip: false), library: library);
    await openSheet(tester, rig, PlayerPanel.download);
    await tester.tap(find.byKey(const ValueKey('download-quality')));
    await tester.pumpAndSettle();
    await shoot(tester, '142-ours');
    final sizes = find.byKey(const ValueKey('download-quality-size'));
    expect(sizes, findsWidgets);
    final card = tester.getRect(find.byKey(const ValueKey('download-quality-sheet')));
    for (final element in sizes.evaluate()) {
      expect(tester.getRect(find.byWidget(element.widget)).right, closeTo(card.right - 32, 0.01));
    }
  });

  testWidgets('153: 缓存 for a video cached', (tester) async {
    final library = FakeOfflineLibrary(free: 80745385164)
      ..put(item(501, OfflineState.done, bytes: 82418074, total: 82418074));
    final rig = await pumpSheetRig(
      tester,
      look: true,
      session: singleVideo(title: '师姐的脸软乎乎的～'),
      library: library,
    );
    await library.enqueue(const []);
    await openSheet(tester, rig, PlayerPanel.download);
    await shoot(tester, '153-ours');
  });

  testWidgets('144: 缓存 for a 合集', (tester) async {
    final library = FakeOfflineLibrary(free: 79886391705)
      ..put(item(9999, OfflineState.done, bytes: 82418074, total: 82418074));
    final rig = await pumpSheetRig(tester, look: true, session: collectionVideo(playing: 4), library: library);
    await library.enqueue(const []);
    await openSheet(tester, rig, PlayerPanel.download);
    await shoot(tester, '144-ours');
  });

  testWidgets('154: a 合集 with its states', (tester) async {
    final library = FakeOfflineLibrary(free: 80315771699)
      ..put(item(700, OfflineState.downloading, bytes: 90, total: 100))
      ..put(item(701, OfflineState.done, bytes: 10066329, total: 10066329))
      ..put(item(702, OfflineState.done, bytes: 74750000, total: 74750000));
    final rig = await pumpSheetRig(tester, look: true, session: collectionVideo(), library: library);
    await library.enqueue(const []);
    await openSheet(tester, rig, PlayerPanel.download);
    await shoot(tester, '154-ours');
  });
}
