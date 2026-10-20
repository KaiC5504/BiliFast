import 'package:bilifast/settings/settings_confirm.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';

void main() {
  testWidgets('under the system font, its words fall back to emoji, then PingFang SC', (tester) async {
    Future<void> show() => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SettingsConfirm(title: '退出登录', message: '确定退出当前账号？', action: '退出', onConfirm: () {}, onCancel: () {}),
      ),
    );
    await expectSystemFallback(tester, show, find.text('退出登录'));
    await expectSystemFallback(tester, show, find.text('确定退出当前账号？'));
    await expectSystemFallback(tester, show, find.text('退出'));
  });
}
