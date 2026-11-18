import 'package:bilifast/main.dart' show DefaultStatusBar;
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SystemUiOverlayStyle? styleOf(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
      .value;

  testWidgets('pages without a region of their own get dark icons by day and light ones at night', (tester) async {
    await tester.pumpWidget(const DefaultStatusBar(child: SizedBox()));
    expect(styleOf(tester), SystemUiOverlayStyle.dark);

    BiliTheme.dark = true;
    await tester.pumpWidget(const DefaultStatusBar(key: ValueKey('night'), child: SizedBox()));
    expect(styleOf(tester), SystemUiOverlayStyle.light);
  });
}
