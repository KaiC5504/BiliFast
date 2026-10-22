import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the official grey with the 小电视 tinted faint, about 39 × 37 pt, in the middle of the cover', (
    tester,
  ) async {
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
    expect(tester.getRect(find.byType(Image)), Rect.fromCenter(center: box.center, width: 39, height: 37));
    expect(tv.excludeFromSemantics, isTrue);
  });
}
