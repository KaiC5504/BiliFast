import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("the official grey with the 小电视 tinted faint, the asset's 117 × 109 px at 3×, in the middle of the "
      'cover', (tester) async {
    await tester.pumpWidget(
      const Center(child: SizedBox(width: 211, height: 158.25, child: CoverPlaceholder())),
    );
    final box = tester.getRect(find.byType(CoverPlaceholder));
    expect(tester.widget<ColoredBox>(find.byType(ColoredBox)).color, CoverPlaceholderTheme.fill);
    final tv = tester.widget<Image>(find.byType(Image));
    expect((tv.image as AssetImage).assetName, CoverPlaceholder.asset);
    expect(tv.color, CoverPlaceholderTheme.ink);
    expect(tv.colorBlendMode, BlendMode.srcIn);
    expect(tv.fit, BoxFit.contain);
    final drawn = tester.getRect(find.byType(Image));
    expect(drawn.width, moreOrLessEquals(39));
    expect(drawn.height, moreOrLessEquals(109 / 3));
    expect((drawn.center - box.center).distance, moreOrLessEquals(0));
    expect(tv.excludeFromSemantics, isTrue);
  });
}
