import 'dart:ui' show CheckedState;

import 'package:bili_core/api.dart' show FavFolder;
import 'package:bilifast/video/actions/favourite_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';
import '../../support/system_font.dart';

const portrait = Size(440, 956);
const landscape = Size(956, 440);

class Rig {
  Rig(this.folders);

  final FakeFavouriteFolders folders;

  /// Calls to the folders, and 'close' for each call to the sheet's onClose, in order.
  List<String> get calls => folders.calls;
}

Future<Rig> pumpSheet(
  WidgetTester tester, {
  FakeFavouriteFolders? folders,
  bool dark = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool settle = true,
  bool resize = false,
}) async {
  final size = dark ? landscape : portrait;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = folders ?? FakeFavouriteFolders();
  addTearDown(() {
    if (!fake.disposed) fake.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, viewInsets: viewInsets),
        child: Scaffold(
          resizeToAvoidBottomInset: resize,
          body: FavouriteSheet(folders: fake, dark: dark, onClose: () => fake.calls.add('close')),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return Rig(fake);
}

SemanticsNode node(WidgetTester tester, int id) => tester.getSemantics(find.byKey(ValueKey('favourite-$id')));

bool ticked(WidgetTester tester, int id) =>
    node(tester, id).getSemanticsData().flagsCollection.isChecked == CheckedState.isTrue;

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> clearToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  group('portrait', () {
    testWidgets('lists the folders under 选择收藏夹: title, count, a lock when private', (tester) async {
      await pumpSheet(tester);
      expect(find.text('选择收藏夹'), findsOneWidget);
      expect(find.text('默认收藏夹'), findsOneWidget);
      expect(find.text('0个内容'), findsOneWidget);
      expect(find.text('二乃'), findsOneWidget);
      expect(find.text('8个内容'), findsOneWidget);
      expect(find.byKey(const ValueKey('favourite-lock-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('favourite-lock-11')), findsNothing);
      expect(find.byKey(const ValueKey('sheet-close')), findsOneWidget);
    });

    testWidgets('a white sheet whose top meets the small player, up from the bottom', (tester) async {
      await pumpSheet(tester);
      final sheet = tester.getRect(find.byKey(const ValueKey('favourite-sheet')));
      expect(sheet.bottom, portrait.height);
      expect(sheet.top, closeTo(portrait.width / (16 / 9), 0.01));
    });

    testWidgets('a tap ticks a folder, and its count follows the tick', (tester) async {
      final rig = await pumpSheet(tester);
      expect(ticked(tester, 11), isFalse);
      await tester.tap(find.text('默认收藏夹'));
      await tester.pumpAndSettle();
      expect(rig.calls, ['toggle 11']);
      expect(ticked(tester, 11), isTrue);
      expect(find.text('1个内容'), findsOneWidget);
      await tester.tap(find.text('默认收藏夹'));
      await tester.pumpAndSettle();
      expect(ticked(tester, 11), isFalse);
      expect(find.text('0个内容'), findsOneWidget);
    });

    testWidgets('a folder that held the video counts one less once unticked', (tester) async {
      await pumpSheet(
        tester,
        folders: FakeFavouriteFolders(
          folders: const [FavFolder(id: 5, title: '有它', count: 3, isPrivate: false, contains: true, isDefault: true)],
          ticked: {5},
        ),
      );
      expect(find.text('3个内容'), findsOneWidget);
      await tester.tap(find.text('有它'));
      await tester.pumpAndSettle();
      expect(find.text('2个内容'), findsOneWidget);
    });

    testWidgets('完成 commits, then closes', (tester) async {
      final rig = await pumpSheet(tester);
      await tester.tap(find.text('二乃'));
      await tester.tap(find.text('完成'));
      expect(rig.calls, ['toggle 12', 'commit', 'close']);
    });

    testWidgets('✕ and a tap above the sheet close it without committing; a tap on the sheet does not', (tester) async {
      final rig = await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('sheet-close')));
      await tester.tapAt(const Offset(220, 100));
      expect(rig.calls, ['close', 'close']);
      await tester.tap(find.text('选择收藏夹'));
      expect(rig.calls, ['close', 'close']);
    });

    testWidgets('a drag down on the grabber past its threshold closes it; a short one springs back', (tester) async {
      final rig = await pumpSheet(tester);
      final grabber = find.byKey(const ValueKey('favourite-grabber'));
      final top = tester.getTopLeft(find.byKey(const ValueKey('favourite-frame'))).dy;
      await tester.drag(grabber, const Offset(0, 20));
      await tester.pumpAndSettle();
      expect(rig.calls, isEmpty);
      expect(tester.getTopLeft(find.byKey(const ValueKey('favourite-frame'))).dy, top);
      await tester.drag(grabber, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(rig.calls, ['close']);
    });

    testWidgets('loading shows a spinner that is gone once the folders arrive', (tester) async {
      final folders = FakeFavouriteFolders(loading: true);
      await pumpSheet(tester, folders: folders, settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('默认收藏夹'), findsNothing);
      folders
        ..loading = false
        ..notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('默认收藏夹'), findsOneWidget);
    });

    testWidgets('a failure shows why and 重试 reloads', (tester) async {
      final rig = await pumpSheet(tester, folders: FakeFavouriteFolders(error: '网络连接失败，请检查网络后重试'));
      expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
      expect(find.text('默认收藏夹'), findsNothing);
      await tester.tap(find.text('重试'));
      expect(rig.calls, ['reload']);
    });

    testWidgets('新建收藏夹 opens a form whose 确定 creates the folder, which joins the list ticked', (tester) async {
      final rig = await pumpSheet(tester);
      await tester.tap(find.text('新建收藏夹'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favourite-name')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('favourite-name')), '  新的  ');
      await tester.pump();
      expect(find.text('6/20'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('favourite-private')));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(rig.calls, ['create 新的 private=true']);
      expect(find.byKey(const ValueKey('favourite-name')), findsNothing);
      expect(find.text('新的'), findsOneWidget);
      expect(ticked(tester, 102), isTrue);
    });

    testWidgets('the name stops at 20 characters, and 确定 does nothing while it is blank', (tester) async {
      final rig = await pumpSheet(tester);
      await tester.tap(find.text('新建收藏夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('favourite-name')), '   ');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pump();
      expect(rig.calls, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('favourite-name')), '一二三四五六七八九十一二三四五六七八九十多出来');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('favourite-name'))).controller!.text.length, 20);
    });

    testWidgets('a failed create toasts why and keeps the form', (tester) async {
      final folders = FakeFavouriteFolders()..createFailure = '收藏夹名称已存在';
      await pumpSheet(tester, folders: folders);
      await tester.tap(find.text('新建收藏夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('favourite-name')), '二乃');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump();
      expect(find.text('收藏夹名称已存在'), findsOneWidget);
      expect(find.byKey(const ValueKey('favourite-name')), findsOneWidget);
      await clearToast(tester);
    });

    testWidgets('取消 closes the form without creating anything', (tester) async {
      final rig = await pumpSheet(tester);
      await tester.tap(find.text('新建收藏夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('favourite-name')), '不要了');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favourite-name')), findsNothing);
      expect(find.text('新建收藏夹'), findsOneWidget);
      expect(rig.calls, isEmpty);
    });

    testWidgets('the sheet rises with the keyboard', (tester) async {
      await pumpSheet(tester, viewInsets: const EdgeInsets.only(bottom: 336));
      final sheet = tester.getRect(find.byKey(const ValueKey('favourite-sheet')));
      expect(sheet.bottom, portrait.height - 336);
      expect(sheet.top, greaterThanOrEqualTo(0));
      expect(tester.getRect(find.text('完成')).bottom, lessThan(portrait.height - 336));
    });

    testWidgets('a page that shrinks for the keyboard still gets the whole sheet above it', (tester) async {
      await pumpSheet(tester, viewInsets: const EdgeInsets.only(bottom: 336), resize: true);
      final sheet = tester.getRect(find.byKey(const ValueKey('favourite-sheet')));
      expect(sheet.bottom, portrait.height - 336);
      expect(sheet.height, portrait.height - 336);
    });

    testWidgets('every control answers accessibility presses', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await pumpSheet(tester);
      expect(
        node(tester, 12),
        matchesSemantics(label: '二乃，私密', value: '8个内容', hasCheckedState: true, hasTapAction: true, isFocusable: false),
      );
      tester.semantics.tap(find.semantics.byLabel('默认收藏夹'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('新建收藏夹'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('私密'));
      tester.semantics.tap(find.semantics.byLabel('取消'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('完成'));
      expect(rig.calls, ['toggle 11', 'commit', 'close']);
      handle.dispose();
    });
  });

  group('landscape', () {
    testWidgets('the dark panel at the right, without the sheet’s ✕', (tester) async {
      await pumpSheet(tester, dark: true);
      final panel = tester.getRect(find.byKey(const ValueKey('favourite-panel')));
      expect(panel.right, landscape.width);
      expect(find.text('选择收藏夹'), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet-close')), findsNothing);
      expect(find.byKey(const ValueKey('favourite-sheet')), findsNothing);
      expect(tester.getRect(find.text('二乃')).left, greaterThan(landscape.width * 0.5));
    });

    testWidgets('ticks, creates and commits as in portrait; a tap left of it closes it', (tester) async {
      final rig = await pumpSheet(tester, dark: true);
      await tester.tap(find.text('二乃'));
      await tester.pumpAndSettle();
      expect(ticked(tester, 12), isTrue);
      await tester.tap(find.text('新建收藏夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('favourite-name')), '横屏');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('横屏'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.tapAt(const Offset(100, 220));
      expect(rig.calls, ['toggle 12', 'create 横屏 private=false', 'commit', 'close', 'close']);
    });

    testWidgets('loading and failure show in the panel too', (tester) async {
      await pumpSheet(tester, dark: true, folders: FakeFavouriteFolders(loading: true), settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await pumpSheet(tester, dark: true, folders: FakeFavouriteFolders(error: '加载失败'));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  testWidgets('it slides in with the motion it is given', (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final motion = AnimationController(vsync: const TestVSync(), value: 0);
    addTearDown(motion.dispose);
    final folders = FakeFavouriteFolders();
    addTearDown(folders.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavouriteSheet(folders: folders, dark: false, onClose: () {}, motion: motion),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('favourite-frame'))).dy, greaterThanOrEqualTo(portrait.height));
    motion.value = 1;
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('favourite-frame'))).dy, lessThan(portrait.height / 2));
  });

  testWidgets('under the system font, sheet and side panel fall back to PingFang SC', (tester) async {
    await expectSystemFallback(tester, () => pumpSheet(tester), find.text('默认收藏夹'));
    await expectSystemFallback(tester, () => pumpSheet(tester, dark: true), find.text('默认收藏夹'));
  });
}
