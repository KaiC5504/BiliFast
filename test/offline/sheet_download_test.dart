import 'package:bili_core/api.dart' show Dash;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/offline/offline_size.dart';
import 'package:bilifast/offline/sheet/download_mark.dart';
import 'package:bilifast/offline/sheet/download_rows.dart';
import 'package:bilifast/offline/sheet/sheet_art.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../player_ui/panels/sheet_rig.dart';

void main() {
  int estimate(int quality, int seconds) => estimateBytes(dash, quality: quality, seconds: seconds)!;

  OfflineItem item(OfflineRequest request, OfflineState state, {int total = 0}) => OfflineItem(
    request: request,
    state: state,
    addedAt: DateTime(2026, 10, 30),
    bytes: state == OfflineState.done ? total : 0,
    totalBytes: total,
  );

  Finder row(String title) => find.ancestor(of: find.textContaining(title), matching: find.byType(DownloadRow)).first;

  DownloadMark mark(WidgetTester tester, String title) =>
      tester.widget<DownloadMark>(find.descendant(of: row(title), matching: find.byType(DownloadMark)));

  group('a video of one part', () {
    testWidgets('opens on the highest quality offered and queues the part at it, built from the detail', (
      tester,
    ) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.download);
      expect(find.text('1080P 60帧'), findsOneWidget);
      expect(mark(tester, '神枪看').item, isNull);

      await tester.tap(row('神枪看'));
      await tester.pumpAndSettle();
      final queued = rig.library.enqueued.single;
      expect(queued.quality, 116);
      final request = queued.parts.single;
      expect(
        (request.bvid, request.aid, request.cid, request.duration, request.page, request.partTitle),
        ('BV1single', 11, 501, 383, 1, null),
      );
      expect(request.title, startsWith('神枪看小羊崽'));
      expect((request.cover, request.ownerMid, request.ownerName), ('https://i0.hdslb.com/single.jpg', 7, '火播君'));
      expect(request.collection, isNull);
      expect(mark(tester, '神枪看').item?.state, OfflineState.waiting, reason: 'the row shows its state once queued');
    });

    testWidgets('without 大会员 it opens on the best quality the account gets', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo(vip: false));
      await openSheet(tester, rig, PlayerPanel.download);
      expect(find.text('1080P 高清'), findsOneWidget);
    });

    testWidgets('opens on the best stream the account gets, picked again when the streams arrive', (tester) async {
      // Logged out: the list names 1080P, the streams stop at 480P.
      final session = singleVideo(vip: false)..dash = null;
      final rig = await pumpSheetRig(tester, session: session);
      await openSheet(tester, rig, PlayerPanel.download);
      expect(find.text('1080P 高清'), findsOneWidget, reason: 'the list decides while the streams are unknown');

      final low = Dash(duration: 383, video: [dash.video[4]], audio: dash.audio);
      session
        ..dash = low
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('480P 标清'), findsOneWidget);
      final size = estimateBytes(low, quality: 32, seconds: 383)!;
      expect(find.text('约 ${formatBytes(size)}'), findsOneWidget);
    });

    testWidgets("the streams arriving keep the user's pick", (tester) async {
      final session = singleVideo()..dash = null;
      final rig = await pumpSheetRig(tester, session: session);
      await openSheet(tester, rig, PlayerPanel.download);
      await tester.tap(find.byKey(const ValueKey('download-quality')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('download-quality-64')));
      await tester.pumpAndSettle();

      session
        ..dash = dash
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('720P 准高清'), findsOneWidget);
    });

    testWidgets('the row shows its size at the chosen quality; 画质 lists every size and a pick changes both', (
      tester,
    ) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.download);
      expect(find.text('约 ${formatBytes(estimate(116, 383))}'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('download-quality')));
      await tester.pumpAndSettle();
      for (final quality in const [116, 80, 64, 32]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('download-quality-$quality')),
            matching: find.text('约 ${formatBytes(estimate(quality, 383))}'),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('大会员'), findsOneWidget, reason: '142 tags the 大会员 quality');
      expect(find.text('360P 流畅'), findsOneWidget, reason: 'listed without a size: the playurl had no stream of it');

      await tester.tap(find.byKey(const ValueKey('download-quality-64')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('download-quality-sheet')), findsNothing);
      expect(find.text('720P 准高清'), findsOneWidget);
      expect(find.text('约 ${formatBytes(estimate(64, 383))}'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('download-all')));
      await tester.pumpAndSettle();
      expect(rig.library.enqueued.single.quality, 64);
    });

    testWidgets('a tap outside 画质 closes it and keeps the quality', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.download);
      await tester.tap(find.byKey(const ValueKey('download-quality')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(220, 100));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('download-quality-sheet')), findsNothing);
      expect(rig.panels.value, PlayerPanel.download, reason: 'only the picker went');
      expect(find.text('1080P 60帧'), findsOneWidget);
    });

    testWidgets("each state's mark: the ring, the progress, 153's ✓; a cached part shows its real size", (
      tester,
    ) async {
      final session = singleVideo();
      final request = OfflineRequest(
        bvid: 'BV1single',
        aid: 11,
        cid: 501,
        title: 't',
        duration: 383,
        cover: '',
        ownerMid: 7,
        ownerName: '',
      );
      final library = FakeOfflineLibrary()..put(item(request, OfflineState.downloading, total: 1000));
      final rig = await pumpSheetRig(tester, session: session, library: library);
      await openSheet(tester, rig, PlayerPanel.download);
      expect(mark(tester, '神枪看').item?.state, OfflineState.downloading);
      expect(find.text('1000B'), findsOneWidget);

      library.put(item(request, OfflineState.done, total: 82208358));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: row('神枪看'),
          matching: find.byWidgetPredicate((w) => w is SheetIcon && w.asset == SheetArt.done),
        ),
        findsOneWidget,
      );
      expect(find.text('78.4MB'), findsOneWidget);

      await tester.tap(row('神枪看'));
      await tester.pumpAndSettle();
      expect(library.enqueued, isEmpty, reason: 'a cached part is not queued again');
    });

    testWidgets('a paused part resumes on a tap', (tester) async {
      final request = OfflineRequest(
        bvid: 'BV1single',
        aid: 11,
        cid: 501,
        title: 't',
        duration: 383,
        cover: '',
        ownerMid: 7,
        ownerName: '',
      );
      final library = FakeOfflineLibrary()..put(item(request, OfflineState.paused, total: 1000));
      final rig = await pumpSheetRig(tester, session: singleVideo(), library: library);
      await openSheet(tester, rig, PlayerPanel.download);
      await tester.tap(row('神枪看'));
      await tester.pumpAndSettle();
      expect(library.item(501)?.state, OfflineState.waiting);
    });

    testWidgets('the bar: the space line, the red dot once something is new, 查看缓存 a button', (tester) async {
      final handle = tester.ensureSemantics();
      final library = FakeOfflineLibrary(free: 79886391705);
      final rig = await pumpSheetRig(tester, session: singleVideo(), library: library);
      await openSheet(tester, rig, PlayerPanel.download);
      expect(find.byKey(const ValueKey('download-unseen')), findsNothing);
      final space = tester.widget<Text>(find.byKey(const ValueKey('download-space')));
      expect(space.textSpan!.toPlainText(), '已使用 - / 剩余 74.4G');

      tester.semantics.tap(find.semantics.byLabel('缓存全部'));
      await tester.pumpAndSettle();
      expect(rig.library.enqueued, hasLength(1));
      expect(find.byKey(const ValueKey('download-unseen')), findsOneWidget);
      expect(find.semantics.byLabel('查看缓存，有新内容'), findsOne);
      handle.dispose();
    });

    testWidgets('closes when the phone turns to landscape', (tester) async {
      final rig = await pumpSheetRig(tester, session: singleVideo());
      await openSheet(tester, rig, PlayerPanel.download);
      rig.orientation.enterLandscape();
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
    });
  });

  testWidgets("a video in parts: title rows, the playing one pink; 缓存全部 queues those not cached", (tester) async {
    final library = FakeOfflineLibrary()
      ..put(
        item(
          const OfflineRequest(
            bvid: 'BV1parts',
            aid: 12,
            cid: 601,
            title: '三段',
            duration: 100,
            cover: '',
            ownerMid: 8,
            ownerName: 'UP',
          ),
          OfflineState.done,
          total: 10,
        ),
      );
    final rig = await pumpSheetRig(tester, session: partsVideo(), library: library);
    await openSheet(tester, rig, PlayerPanel.download);
    expect(find.byType(RemoteImage), findsNothing, reason: 'parts draw no cover');
    expect(find.text('内容到底啦'), findsNothing);
    final tops = [
      for (final title in ['P1 开头', 'P2 中间', 'P3 结尾']) tester.getTopLeft(row(title)).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(find.text('约 ${formatBytes(estimate(116, 300))}'), findsOneWidget, reason: "each part's own length");

    await tester.tap(find.byKey(const ValueKey('download-all')));
    await tester.pumpAndSettle();
    final queued = rig.library.enqueued.single;
    expect([for (final part in queued.parts) (part.cid, part.page, part.partTitle)], [(602, 2, '中间'), (603, 3, '结尾')]);
    expect(queued.parts.every((part) => part.title == '三段' && part.bvid == 'BV1parts'), isTrue);
  });

  testWidgets('a 合集: cover cards, the playing one pink, 内容到底啦; each queued as its own video in the 合集', (tester) async {
    final rig = await pumpSheetRig(tester, session: collectionVideo(playing: 4));
    await openSheet(tester, rig, PlayerPanel.download);
    expect(find.byType(RemoteImage), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('内容到底啦'),
      100,
      scrollable: find.descendant(of: find.byKey(const ValueKey('download-list')), matching: find.byType(Scrollable)),
    );
    expect(find.text('内容到底啦'), findsOneWidget);

    await tester.tap(row('陈致逸'));
    await tester.pumpAndSettle();
    final request = rig.library.enqueued.single.parts.single;
    expect((request.bvid, request.aid, request.cid, request.duration), ('BV1ep3', 803, 703, 433));
    expect(request.collection, const OfflineCollection(id: 4001, title: '星铁'));
    expect((request.ownerMid, request.ownerName), (9, '问寒不留白'));
  });

  testWidgets('every row answers an accessibility press with its title and state', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await pumpSheetRig(tester, session: partsVideo(), presentation: Presentation.vertical);
    await openSheet(tester, rig, PlayerPanel.download);
    tester.semantics.tap(find.semantics.byLabel(RegExp('^P3 结尾，未缓存')));
    await tester.pumpAndSettle();
    expect(rig.library.enqueued.single.parts.single.cid, 603);
    handle.dispose();
  });
}
