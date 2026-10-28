import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/app/phone_frame.dart';
import 'package:bilifast/skin/skin_status_bar.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';

void main() {
  testWidgets("on the iPad the headers are measured at the screen's width, under its 24 pt bar", (tester) async {
    showAsPad(tester, landscape: true);
    final home = StatusBarPlacement.home(tabPicture: false);
    expect(home.box.width, PhoneFrame.padLandscape.width);
    expect(StatusBarPlacement.me(card: true).box.width, PhoneFrame.padLandscape.width);
    expect(StatusBarPlacement.follow().box.width, PhoneFrame.padLandscape.width);
    expect(home.areas, [const Rect.fromLTRB(24, 0, 140, 24), const Rect.fromLTRB(1054, 0, 1170, 24)]);

    tester.view.physicalSize = PhoneFrame.padPortrait * 2;
    expect(StatusBarPlacement.home(tabPicture: false).box.width, PhoneFrame.padPortrait.width);
  });

  testWidgets('the iPhone stays at its upright width, sideways too', (tester) async {
    expect(FormFactor.device, FormFactor.phone);
    showAsPhone(tester, landscape: true);
    final home = StatusBarPlacement.home(tabPicture: true);
    expect(home.box.width, 440);
    expect(home.areas, [const Rect.fromLTRB(24, 0, 140, 62), const Rect.fromLTRB(300, 0, 416, 62)]);
  });
}
