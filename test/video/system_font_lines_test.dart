import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/video/actions/coin_dialog.dart';
import 'package:bilifast/video/actions/favourite_sheet.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_video_actions.dart';
import 'mixed_lines.dart';

void main() {
  group('under the system font a line mixing Latin and Chinese sits on the Chinese line', () {
    testWidgets('the danmaku field\'s UP主已关闭弹幕, where 点我发弹幕 sits', (tester) async {
      await useSystemFont(tester);
      final tabs = PageTabsController();
      addTearDown(tabs.dispose);
      await expectMixedOnChineseLines(
        tester,
        chinese: '点我发弹幕',
        mixed: 'UP主已关闭弹幕',
        show: (text) => tester.pumpWidget(
          appHost(
            Align(
              alignment: Alignment.topCenter,
              child: PageTabRow(
                controller: tabs,
                replyCount: 1835,
                danmakuOn: true,
                onToggleDanmaku: () {},
                onSendDanmaku: () {},
                danmakuClosed: text != '点我发弹幕',
              ),
            ),
          ),
        ),
      );
    });

    testWidgets('the player\'s failure message', (tester) async {
      await useSystemFont(tester);
      await expectMixedOnChineseLines(
        tester,
        chinese: '播放失败，请稍后重试',
        mixed: '播放失败 (HTTP 403)',
        show: (message) => tester.pumpWidget(
          appHost(
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 440,
                height: 248,
                child: VideoPlayerArea(
                  presentation: Presentation.inline,
                  onBack: () {},
                  failure: message,
                  onRetry: () {},
                ),
              ),
            ),
          ),
        ),
      );
    });

    testWidgets('the coin dialog\'s balance and hint', (tester) async {
      await useSystemFont(tester);
      CoinDialog.alsoLike = true;
      Future<void> show({required bool fails}) async {
        final actions = FakeVideoActions(balance: 873);
        addTearDown(actions.dispose);
        if (fails) actions.balanceFailure = Exception('offline');
        await tester.pumpWidget(
          appHost(CoinDialog(key: UniqueKey(), actions: actions, onClose: () {}, openLink: (_) async => true)),
        );
        // A failed balance is asked twice more before the dialog gives up on it.
        for (final wait in [1, 2, 10]) {
          await tester.pump(Duration(seconds: wait));
        }
        await tester.pumpAndSettle();
      }

      await show(fails: true);
      final chinese = baselinesOf(tester, find.text('硬币余额获取失败'), strut: false);
      await show(fails: false);
      expectOnChineseLines(tester, find.text('硬币余额：873.0'), chinese);
      expectOnChineseLine(tester, find.text('上滑或点击22娘投硬币'));
    });

    testWidgets('a new favourites folder\'s name as it is typed', (tester) async {
      await useSystemFont(tester);
      final folders = FakeFavouriteFolders();
      addTearDown(folders.dispose);
      // Its AnimatedSize can't run at zero length, so not under appHost's reduced motion.
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(body: FavouriteSheet(folders: folders, dark: false, onClose: () {})),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建收藏夹'));
      await tester.pumpAndSettle();

      final field = find.byType(EditableText);
      await tester.enterText(field, chineseLine);
      await tester.pump();
      final chinese = baselinesOf(tester, field, strut: false);
      await tester.enterText(field, mixedLine);
      await tester.pump();
      expectOnChineseLines(tester, field, chinese);
    });
  });
}
