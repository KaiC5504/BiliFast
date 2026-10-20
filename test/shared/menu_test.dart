import 'package:bilifast/shared/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'text_lines.dart';

void main() {
  testWidgets('under the system font, a row mixing Latin and Chinese sits on a Chinese row\'s line', (tester) async {
    await useSystemFont(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Material(
          child: Column(
            children: [
              MenuRow(key: const ValueKey('chinese'), title: '稍后再看', icon: Icons.schedule, onTap: () {}, note: '暂不支持'),
              MenuRow(key: const ValueKey('mixed'), title: 'KaiC 稍后', icon: Icons.schedule, onTap: () {}, note: '2 天后'),
            ],
          ),
        ),
      ),
    );
    double han(String row, String text) =>
        linesOf(tester, find.text(text)).han.single - tester.getRect(find.byKey(ValueKey(row))).top;
    expect(han('mixed', 'KaiC 稍后'), closeTo(han('chinese', '稍后再看'), 0.01));
    expect(han('mixed', '2 天后'), closeTo(han('chinese', '暂不支持'), 0.01));
  });
}
