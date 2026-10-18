import 'dart:async';

import 'package:bilifast/video/actions/action_overlays.dart';
import 'package:bilifast/video/actions/coin_dialog.dart';
import 'package:bilifast/video/actions/favourite_sheet.dart';
import 'package:bilifast/video/actions/unfollow_confirm.dart';
import 'package:bilifast/video/actions/video_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';

final link = Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD');

class Rig {
  Rig(this.controller, this.below, this.shared);

  final ActionOverlayController controller;

  /// Taps that went through to the page under the overlays.
  final List<Offset> below;

  /// The links handed to the share sheet.
  final List<Uri> shared;
}

class Host extends StatelessWidget {
  const Host({
    super.key,
    required this.actions,
    required this.controller,
    required this.below,
    this.landscape = false,
    this.shareLink,
    this.share,
    this.still = false,
  });

  final VideoActions? actions;
  final ActionOverlayController controller;
  final List<Offset> below;
  final bool landscape;
  final Uri? shareLink;
  final Future<bool> Function(Uri)? share;
  final bool still;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: landscape ? const Size(956, 440) : const Size(440, 956), disableAnimations: still),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: '页面',
                child: GestureDetector(
                  key: const ValueKey('page'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => below.add(details.globalPosition),
                ),
              ),
            ),
            Positioned.fill(
              child: ActionOverlays(
                actions: actions,
                controller: controller,
                landscape: landscape,
                shareLink: shareLink,
                share: share ?? (_) async => true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<Rig> pumpOverlays(
  WidgetTester tester,
  VideoActions? actions, {
  bool landscape = false,
  Uri? shareLink,
  Future<bool> Function(Uri)? share,
  bool still = false,
}) async {
  tester.view.physicalSize = landscape ? const Size(956, 440) : const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = ActionOverlayController();
  addTearDown(controller.dispose);
  final below = <Offset>[];
  final shared = <Uri>[];
  await tester.pumpWidget(
    Host(
      actions: actions,
      controller: controller,
      below: below,
      landscape: landscape,
      shareLink: shareLink,
      share:
          share ??
          (uri) async {
            shared.add(uri);
            return true;
          },
      still: still,
    ),
  );
  await tester.pumpAndSettle();
  return Rig(controller, below, shared);
}

FakeVideoActions fakeActions({int maxCoins = 2}) {
  final actions = FakeVideoActions(maxCoins: maxCoins);
  addTearDown(actions.dispose);
  return actions;
}

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> clearToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing up, every touch reaches the page and it adds nothing to semantics', (tester) async {
    final actions = fakeActions();
    final rig = await pumpOverlays(tester, actions);
    await tester.tapAt(const Offset(220, 700));
    expect(rig.below, hasLength(1));
    expect(find.descendant(of: find.byType(ActionOverlays), matching: find.byType(Semantics)), findsNothing);
    expect(rig.controller.value, isNull);
  });

  testWidgets('without actions it shows nothing', (tester) async {
    final rig = await pumpOverlays(tester, null);
    await tester.tapAt(const Offset(220, 700));
    expect(rig.below, hasLength(1));
  });

  group('coin', () {
    testWidgets('puts up the coin dialog and takes the prompt', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.coin);
      await tester.pumpAndSettle();
      expect(find.byType(CoinDialog), findsOneWidget);
      expect(tester.widget<CoinDialog>(find.byType(CoinDialog)).actions, same(actions));
      expect(rig.controller.value, ActionPrompt.coin);
      expect(actions.prompt, isNull);
      expect(actions.calls, ['ask coin', 'clearPrompt']);
      tester.widget<CoinDialog>(find.byType(CoinDialog)).onClose();
      await tester.pumpAndSettle();
      expect(rig.controller.value, isNull);
      expect(find.byType(CoinDialog), findsNothing);
    });

    testWidgets('at the limit there is no dialog: coin() says it is full', (tester) async {
      final actions = fakeActions(maxCoins: 0);
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.coin);
      await tester.pumpAndSettle();
      expect(find.byType(CoinDialog), findsNothing);
      expect(rig.controller.value, isNull);
      expect(actions.calls, ['ask coin', 'clearPrompt', 'coin 1 alsoLike=false']);
    });
  });

  group('favourites', () {
    testWidgets('puts up the light sheet in portrait, and disposes its folders once it has closed', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.favourites);
      await tester.pumpAndSettle();
      final sheet = tester.widget<FavouriteSheet>(find.byType(FavouriteSheet));
      expect(sheet.dark, isFalse);
      expect(sheet.folders, same(actions.folders));
      expect(rig.controller.value, ActionPrompt.favourites);
      expect(actions.calls, ['ask favourites', 'openFolders', 'clearPrompt']);
      await tester.tap(find.byKey(const ValueKey('sheet-close')));
      await tester.pump();
      expect(rig.controller.value, isNull);
      expect(actions.folders.disposed, isFalse);
      await tester.pumpAndSettle();
      expect(find.byType(FavouriteSheet), findsNothing);
      expect(actions.folders.disposed, isTrue);
    });

    testWidgets('完成 commits and closes', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.favourites);
      await tester.pumpAndSettle();
      await tester.tap(find.text('二乃'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(actions.folders.calls, ['toggle 12', 'commit']);
      expect(rig.controller.value, isNull);
      expect(find.byType(FavouriteSheet), findsNothing);
    });

    testWidgets('in landscape it is the dark panel', (tester) async {
      final actions = fakeActions();
      await pumpOverlays(tester, actions, landscape: true);
      actions.ask(ActionPrompt.favourites);
      await tester.pumpAndSettle();
      expect(tester.widget<FavouriteSheet>(find.byType(FavouriteSheet)).dark, isTrue);
      expect(find.byKey(const ValueKey('favourite-panel')), findsOneWidget);
    });

    testWidgets('taken again while it closes, it turns around with fresh folders', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.favourites);
      await tester.pumpAndSettle();
      final first = actions.folders;
      rig.controller.close();
      await tester.pump(const Duration(milliseconds: 100));
      final second = actions.folders = FakeFavouriteFolders();
      addTearDown(() {
        if (!second.disposed) second.dispose();
      });
      actions.ask(ActionPrompt.favourites);
      await tester.pumpAndSettle();
      expect(rig.controller.value, ActionPrompt.favourites);
      expect(tester.widget<FavouriteSheet>(find.byType(FavouriteSheet)).folders, same(second));
      expect(first.disposed, isTrue);
      expect(second.disposed, isFalse);
    });
  });

  group('unfollow', () {
    testWidgets('确定 unfollows, then closes', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.unfollow);
      await tester.pumpAndSettle();
      expect(find.byType(UnfollowConfirm), findsOneWidget);
      expect(rig.controller.value, ActionPrompt.unfollow);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(actions.calls, ['ask unfollow', 'clearPrompt', 'toggleFollow']);
      expect(rig.controller.value, isNull);
      expect(find.byType(UnfollowConfirm), findsNothing);
    });

    testWidgets('取消 closes without unfollowing', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.unfollow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(actions.calls, ['ask unfollow', 'clearPrompt']);
      expect(rig.controller.value, isNull);
      expect(find.byType(UnfollowConfirm), findsNothing);
    });
  });

  testWidgets('while up, the page under it gets no touches and drops out of semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final actions = fakeActions();
    final rig = await pumpOverlays(tester, actions);
    expect(find.semantics.byLabel('页面'), findsOne);
    actions.ask(ActionPrompt.unfollow);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(220, 100));
    await tester.pumpAndSettle();
    expect(rig.below, isEmpty);
    actions.ask(ActionPrompt.unfollow);
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('页面'), findsNothing);
    handle.dispose();
  });

  testWidgets('controller.close() from outside closes what is up, animated, letting touches through at once', (
    tester,
  ) async {
    final actions = fakeActions();
    final rig = await pumpOverlays(tester, actions);
    actions.ask(ActionPrompt.unfollow);
    await tester.pumpAndSettle();
    rig.controller.close();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(UnfollowConfirm), findsOneWidget);
    await tester.tapAt(const Offset(220, 100));
    expect(rig.below, hasLength(1));
    await tester.pumpAndSettle();
    expect(find.byType(UnfollowConfirm), findsNothing);
  });

  testWidgets('with reduced motion it closes in a frame', (tester) async {
    final actions = fakeActions();
    final rig = await pumpOverlays(tester, actions, still: true);
    actions.ask(ActionPrompt.favourites);
    await tester.pump();
    expect(find.byType(FavouriteSheet), findsOneWidget);
    rig.controller.close();
    await tester.pump();
    await tester.pump();
    expect(find.byType(FavouriteSheet), findsNothing);
  });

  group('share', () {
    testWidgets('hands the link to the share sheet, counts the share once it closes, then clears', (tester) async {
      final actions = fakeActions();
      final sheet = Completer<bool>();
      final links = <Uri>[];
      final rig = await pumpOverlays(
        tester,
        actions,
        shareLink: link,
        share: (uri) {
          links.add(uri);
          return sheet.future;
        },
      );
      actions.ask(ActionPrompt.share);
      await tester.pump();
      expect(links, [link]);
      expect(rig.controller.value, ActionPrompt.share);
      expect(actions.calls, ['ask share', 'clearPrompt']);
      expect(find.byType(FavouriteSheet), findsNothing);
      sheet.complete(true);
      await tester.pumpAndSettle();
      expect(actions.calls, ['ask share', 'clearPrompt', 'shared']);
      expect(rig.controller.value, isNull);
    });

    testWidgets('a share sheet dismissed without sharing counts nothing', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions, shareLink: link, share: (_) async => false);
      actions.ask(ActionPrompt.share);
      await tester.pumpAndSettle();
      expect(actions.calls, ['ask share', 'clearPrompt']);
      expect(rig.controller.value, isNull);
    });

    testWidgets('before the link is known it says so and shares nothing', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions);
      actions.ask(ActionPrompt.share);
      await tester.pump();
      await tester.pump();
      expect(find.text('视频还没有加载完'), findsOneWidget);
      expect(rig.shared, isEmpty);
      expect(actions.calls, ['ask share', 'clearPrompt']);
      expect(rig.controller.value, isNull);
      await clearToast(tester);
    });

    testWidgets('a share sheet that fails says 分享失败 and counts nothing', (tester) async {
      final actions = fakeActions();
      final rig = await pumpOverlays(tester, actions, shareLink: link, share: (_) async => throw StateError('no'));
      actions.ask(ActionPrompt.share);
      await tester.pump();
      await tester.pump();
      expect(find.text('分享失败'), findsOneWidget);
      expect(actions.calls, ['ask share', 'clearPrompt']);
      expect(rig.controller.value, isNull);
      await clearToast(tester);
    });
  });

  testWidgets('a new actions object is followed, and closes what the one before put up', (tester) async {
    final first = fakeActions();
    final second = fakeActions();
    final rig = await pumpOverlays(tester, first);
    first.ask(ActionPrompt.unfollow);
    await tester.pumpAndSettle();
    await tester.pumpWidget(Host(actions: second, controller: rig.controller, below: rig.below));
    await tester.pumpAndSettle();
    expect(find.byType(UnfollowConfirm), findsNothing);
    expect(rig.controller.value, isNull);
    first.ask(ActionPrompt.coin);
    await tester.pumpAndSettle();
    expect(find.byType(CoinDialog), findsNothing);
    second.ask(ActionPrompt.coin);
    await tester.pumpAndSettle();
    expect(tester.widget<CoinDialog>(find.byType(CoinDialog)).actions, same(second));
  });

  testWidgets('a prompt already waiting when the actions arrive is taken', (tester) async {
    final actions = fakeActions()..prompt = ActionPrompt.unfollow;
    final rig = await pumpOverlays(tester, actions);
    expect(find.byType(UnfollowConfirm), findsOneWidget);
    expect(rig.controller.value, ActionPrompt.unfollow);
    expect(actions.prompt, isNull);
  });
}
