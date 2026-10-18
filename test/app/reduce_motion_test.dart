import 'package:bilifast/app/reduce_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("iOS's Reduce Motion reaches disableAnimationsOf and follows the setting, keeping the tree below",
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final key = GlobalKey();
    late bool still;
    await tester.pumpWidget(
      ReduceMotion(
        child: Builder(
          key: key,
          builder: (context) {
            still = MediaQuery.disableAnimationsOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    final element = key.currentContext;
    expect(still, isFalse);

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(still, isTrue);
    expect(key.currentContext, same(element));

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(still, isFalse);

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expect(still, isTrue, reason: "Android's Remove animations still counts");
  });
}
