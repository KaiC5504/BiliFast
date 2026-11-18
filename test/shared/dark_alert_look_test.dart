import 'dart:io';

import 'package:bilifast/settings/settings_confirm.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 255: 退出登录's alert at night over a 设置-like page of rows, under the system font. With BILIFAST_SHOTS naming a
/// folder outside the repo, the 3× shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets('255: the alert at night', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester, dark: true);
    const rows = ['消息设置', '防骚扰和互动人群设置', '推送设置', '其他设置', '定时关闭', '睡眠提醒', '深色设置', '反馈与建议'];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: BiliFonts.family,
          fontFamilyFallback: BiliFonts.fallback,
          textTheme: BiliFonts.untracked,
        ),
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Material(
            color: BiliColors.pageGrey,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 106,
                  child: ColoredBox(
                    color: BiliColors.card,
                    child: Column(
                      children: [
                        for (final row in rows)
                          SizedBox(
                            height: 44,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(row, style: TextStyle(fontSize: 16, color: BiliColors.text)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: SettingsConfirm(
                    title: '退出登录',
                    message: '记住账号信息，下次快捷登录',
                    action: '确定',
                    onConfirm: () {},
                    onCancel: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/255-ours.png');
  });
}
