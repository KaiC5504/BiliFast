import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/device/launch_form_factor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FormFactor.device = FormFactor.phone);

  void sized(WidgetTester tester, {required Size view, required Size screen}) {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = view;
    tester.view.display
      ..devicePixelRatio = 2
      ..size = screen;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
  }

  testWidgets('a laid-out view decides', (tester) async {
    sized(tester, view: const Size(1194, 834) * 2, screen: Size.zero);
    expect(await launchFormFactor(tester.binding), FormFactor.pad);
    sized(tester, view: const Size(440, 956) * 2, screen: const Size(834, 1194) * 2);
    expect(await launchFormFactor(tester.binding), FormFactor.phone);
  });

  testWidgets('a view with no size yet goes by the screen', (tester) async {
    sized(tester, view: Size.zero, screen: const Size(834, 1194) * 2);
    expect(await launchFormFactor(tester.binding), FormFactor.pad);
    sized(tester, view: Size.zero, screen: const Size(956, 440) * 2);
    expect(await launchFormFactor(tester.binding), FormFactor.phone);
  });

  testWidgets('with neither, the first metrics with a size decide', (tester) async {
    sized(tester, view: Size.zero, screen: Size.zero);
    FormFactor? found;
    launchFormFactor(tester.binding).then((value) => found = value);
    await tester.pump();
    expect(found, isNull);
    tester.view.physicalSize = const Size(834, 1194) * 2;
    await tester.pump();
    expect(found, FormFactor.pad);
  });

  testWidgets('with no size at all it stays the phone after the wait', (tester) async {
    sized(tester, view: Size.zero, screen: Size.zero);
    FormFactor? found;
    launchFormFactor(tester.binding, wait: const Duration(milliseconds: 200)).then((value) => found = value);
    await tester.pump(const Duration(milliseconds: 250));
    expect(found, FormFactor.phone);
  });
}
