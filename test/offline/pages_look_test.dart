import 'dart:io';

import 'package:bili_core/api.dart' show SkinColors, SkinEquip;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/offline/pages/downloading_page.dart';
import 'package:bilifast/offline/pages/offline_group_page.dart';
import 'package:bilifast/offline/pages/offline_list_page.dart';
import 'package:bilifast/offline/pages/offline_shelf.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

int _bytes(double mb) => (mb * _mb).round();

/// A library whose 已使用 is the shot's own (the official app counts it its own way).
class _ShotLibrary extends FakeOfflineLibrary {
  _ShotLibrary({super.items, required double used, required double freeGb})
    : _used = _bytes(used),
      super(free: (freeGb * _gb).round());

  final int _used;

  @override
  int get usedBytes => _used;
}

/// KaiC's skin as 143 shows it: #D9E8D3 behind black words.
final _green = ValueNotifier<Skin?>(
  const Skin(
    equip: SkinEquip(
      id: 1,
      name: '测试装扮',
      ver: 1,
      packageUrl: '',
      packageMd5: '',
      colors: SkinColors(color: 0xFF000000, colorSecondPage: 0xFFD9E8D3, lightText: true),
    ),
  ),
);

final _added = DateTime(2026, 10, 30, 17);
const _season = OfflineCollection(id: 77, title: '原神/星铁普通质量杂谈');
const _xingtie = OfflineCollection(id: 88, title: '星铁');

OfflineItem _item(
  int cid,
  String title, {
  OfflineState state = OfflineState.done,
  OfflineCollection? collection,
  String owner = '火播君',
  int duration = 383,
  double mb = 78.4,
  double? totalMb,
  double position = 0,
  bool vip = false,
  int minute = 0,
}) => OfflineItem(
  request: OfflineRequest(
    bvid: 'BV1look$cid',
    aid: cid,
    cid: cid,
    title: title,
    duration: duration,
    cover: '',
    ownerMid: cid,
    ownerName: owner,
    collection: collection,
  ),
  state: state,
  addedAt: _added.add(Duration(minutes: minute)),
  bytes: _bytes(mb),
  totalBytes: _bytes(totalMb ?? mb),
  position: position,
  vipOnly: vip,
);

OfflineItem _shenqiang({double position = 23, OfflineState state = OfflineState.done, double mb = 78.4}) =>
    _item(1, '神枪看小羊崽复播：你看这次她真的自己打的，她表情会动', state: state, mb: mb, totalMb: 78.4, position: position);

/// 145-150's four 合集 episodes, queued in this order: the first downloading [first] MB, the rest waiting.
List<OfflineItem> _season4({
  double first = 18.6,
  OfflineState lead = OfflineState.downloading,
  OfflineState rest = OfflineState.waiting,
  double second = 0,
}) => [
  _item(11, '只能靠法大王对抗深渊吗？不妨把视野投向群星的深处去', collection: _season, state: lead, mb: first, totalMb: 128.6, minute: 7),
  _item(12, '千星纪游·其三 | 全篇复核与逐行字幕', collection: _season, state: rest, mb: second, totalMb: 96.2, minute: 8),
  _item(13, '预告-崩铁4.7大结局预测', collection: _season, state: rest, mb: 0, totalMb: 40.1, minute: 9),
  _item(14, '披着动物保护皮反殖民?恰斯卡传说任务杂谈', collection: _season, state: rest, mb: 0, totalMb: 61.3, minute: 10),
];

List<OfflineItem> _xingtie3() => [
  _item(
    21,
    '终末命途前置解读！各体系大补强时代，老东西终于要站起来了？',
    collection: _xingtie,
    owner: '问寒不留白',
    duration: 411,
    mb: 75.0,
    vip: true,
    minute: 20,
  ),
  _item(
    22,
    '真珠虚照怎么抽？直接读评论区问题，放心对号入座',
    collection: _xingtie,
    owner: '问寒不留白',
    duration: 219,
    mb: 9.6,
    position: 3,
    vip: true,
    minute: 21,
  ),
  _item(
    23,
    '绯英队伍怎么抽？虚照、真珠、爻光怎么选？对号入座直接解决！',
    collection: _xingtie,
    owner: '问寒不留白',
    duration: 179,
    mb: 8.1,
    vip: true,
    minute: 22,
  ),
];

/// 离线缓存's pages as KaiC's iPhone draws them, under the system font and his skin's bar, against 143-157 (px / 3).
/// With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<AppServices> services(FakeOfflineLibrary offline) async {
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() async => throw UnimplementedError());
    addTearDown(playback.dispose);
    return AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: FakeLoginGate(),
      offline: offline,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> show(WidgetTester tester, FakeOfflineLibrary offline, Widget page) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final app = await services(offline);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: app, child: child!),
        ),
        home: page,
      ),
    );
    await settle(tester);
    // The cover placeholder is an asset, decoded off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  Rect rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('143: one part downloading', (tester) async {
    await show(
      tester,
      _ShotLibrary(
        items: [_shenqiang(position: 0, state: OfflineState.downloading, mb: 66.5)],
        used: 59.7,
        freeGb: 74.4,
      ),
      OfflineListPage(skin: _green),
    );
    await shoot(tester, '143-offline-one-downloading-ours');

    expect(rect(tester, 'offline-bar'), const Rect.fromLTRB(0, 0, 440, 106));
    expect(rect(tester, 'offline-row-queue'), const Rect.fromLTRB(0, 149, 440, 251));
    expect(find.text('1个内容'), findsOneWidget);
    expect(find.text('缓存中: 66.5MB/78.4MB'), findsOneWidget);
    expect(find.text('已使用59.7MB / 剩余74.4GB'), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-edit')), findsNothing);
    expect(tester.getCenter(find.byKey(const ValueKey('offline-search'))).dx, 416);
  });

  testWidgets('145: 正在缓存 and 已缓存视频', (tester) async {
    await show(
      tester,
      _ShotLibrary(items: [..._season4(first: 15.0), _shenqiang()], used: 94.4, freeGb: 74.0),
      OfflineListPage(skin: _green),
    );
    await shoot(tester, '145-offline-list-ours');

    expect(find.text('4个内容'), findsOneWidget);
    expect(find.text('原神/星铁普通质量杂谈'), findsOneWidget);
    expect(rect(tester, 'offline-row-1'), const Rect.fromLTRB(0, 294, 440, 396));
    expect(find.text('00:23 / 06:23'), findsOneWidget);
    expect(tester.getCenter(find.byKey(const ValueKey('offline-search'))).dx, 380);
    expect(tester.getCenter(find.byKey(const ValueKey('offline-edit'))).dx, 416);
  });

  testWidgets('146: 正在缓存', (tester) async {
    await show(tester, _ShotLibrary(items: _season4(), used: 96.4, freeGb: 74.0), DownloadingPage(skin: _green));
    await shoot(tester, '146-downloading-page-ours');

    final all = rect(tester, 'offline-all');
    expect(all.left, 12);
    expect(all.top, 118);
    expect(all.right, closeTo(107.67, 0.5));
    expect(all.bottom, 150);
    expect(rect(tester, 'offline-row-11'), const Rect.fromLTRB(0, 162, 440, 264));
    expect(rect(tester, 'offline-row-14').bottom, 570);
    expect(find.text('同时缓存数量：1'), findsOneWidget);
  });

  testWidgets('147: 同时缓存数量 open', (tester) async {
    await show(
      tester,
      _ShotLibrary(items: _season4(first: 21.6), used: 96.4, freeGb: 74.0),
      DownloadingPage(skin: _green),
    );
    await tester.tap(find.byKey(const ValueKey('offline-concurrency')));
    await settle(tester);
    await shoot(tester, '147-downloading-concurrency-picker-ours');

    final sheet = rect(tester, 'offline-concurrency-sheet');
    expect(sheet.top, closeTo(725.67, 0.5));
    expect(rect(tester, 'offline-concurrency-1').top, closeTo(744.67, 0.5));
  });

  testWidgets('148: everything paused, 3 at once', (tester) async {
    final library = _ShotLibrary(
      items: _season4(first: 27.5, second: 1.2, lead: OfflineState.paused, rest: OfflineState.paused),
      used: 96.4,
      freeGb: 74.0,
    )..setConcurrency(3);
    await show(tester, library, DownloadingPage(skin: _green));
    await shoot(tester, '148-downloading-all-paused-ours');

    expect(find.text('全部开始'), findsOneWidget);
    expect(find.text('同时缓存数量：3'), findsOneWidget);
  });

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('offline-edit')));
    await settle(tester);
  }

  testWidgets('149: edit mode', (tester) async {
    await show(
      tester,
      _ShotLibrary(
        items: _season4(first: 27.5, second: 1.2, lead: OfflineState.paused, rest: OfflineState.paused),
        used: 96.4,
        freeGb: 74.0,
      ),
      DownloadingPage(skin: _green),
    );
    await edit(tester);
    await shoot(tester, '149-downloading-edit-ours');

    expect(rect(tester, 'offline-row-11'), const Rect.fromLTRB(0, 106, 440, 208));
    expect(tester.getCenter(find.byKey(const ValueKey('offline-circle-11'))), const Offset(24, 157));
    expect(find.byKey(const ValueKey('offline-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-back')), findsNothing);
  });

  testWidgets('150: 确定要删除吗?', (tester) async {
    await show(
      tester,
      _ShotLibrary(
        items: _season4(first: 27.5, second: 1.2, lead: OfflineState.paused, rest: OfflineState.paused),
        used: 96.4,
        freeGb: 74.0,
      ),
      DownloadingPage(skin: _green),
    );
    await edit(tester);
    for (final cid in [12, 13, 14]) {
      await tester.tap(find.byKey(ValueKey('offline-row-$cid')));
    }
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-delete')));
    await settle(tester);
    await shoot(tester, '150-downloading-delete-confirm-ours');

    final alert = rect(tester, 'offline-confirm');
    expect(alert.width, 280);
    expect(alert.center.dy, closeTo(492, 0.5));
  });

  testWidgets('151: search open', (tester) async {
    await show(tester, _ShotLibrary(items: [_shenqiang()], used: 78.6, freeGb: 75.2), OfflineListPage(skin: _green));
    await tester.tap(find.byKey(const ValueKey('offline-search')));
    await settle(tester);
    await shoot(tester, '151-offline-search-ours');

    expect(rect(tester, 'offline-search-field-box'), const Rect.fromLTRB(12, 70, 388, 98));
  });

  testWidgets('155: a 合集 on 离线缓存', (tester) async {
    await show(
      tester,
      _ShotLibrary(
        items: [
          _shenqiang(position: 21),
          _item(2, '师姐的脸软乎乎的~', owner: '我要当老祖-开宗立派', duration: 19, mb: 2.2, position: 1, minute: 5),
          ..._xingtie3(),
        ],
        used: 174.6,
        freeGb: 74.8,
      ),
      OfflineListPage(skin: _green),
    );
    await shoot(tester, '155-offline-list-collection-group-ours');

    expect(rect(tester, 'offline-row-c88'), const Rect.fromLTRB(0, 149, 440, 251));
    expect(find.text('92.7MB'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('156: the 合集 page', (tester) async {
    await show(
      tester,
      _ShotLibrary(items: _xingtie3(), used: 174.6, freeGb: 74.8),
      OfflineGroupPage(group: const ShelfGroup.collection(88), title: '星铁', skin: _green),
    );
    await shoot(tester, '156-offline-collection-folder-ours');

    expect(rect(tester, 'offline-row-21'), const Rect.fromLTRB(0, 106, 440, 208));
    expect(find.text('大会员专享 · 75.0MB'), findsOneWidget);
    expect(find.text('06:51'), findsOneWidget);
    expect(find.text('00:03 / 03:39'), findsOneWidget);
  });

  testWidgets('157: one part done', (tester) async {
    await show(tester, _ShotLibrary(items: [_shenqiang()], used: 78.6, freeGb: 75.2), OfflineListPage(skin: _green));
    await shoot(tester, '157-offline-list-one-done-ours');

    expect(rect(tester, 'offline-row-1'), const Rect.fromLTRB(0, 149, 440, 251));
  });
}
