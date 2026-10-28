import 'package:flutter/widgets.dart';

/// The iPhone or the iPad. Every iPad layout reads this, never the screen's width alone, so the iPhone's screens stay
/// exactly as they are whatever its size.
enum FormFactor {
  phone,
  pad;

  /// The iPhone 17 Pro Max's short side is 440 pt, the smallest iPad's 744; flutter_test's default 800×600 view
  /// stays a phone.
  static const padShortestSide = 700.0;

  /// The device's, set once at launch from UIKit's idiom (Windows: `--pad`), for code with no [BuildContext] (the
  /// orientation rules). Tests set it.
  static FormFactor device = phone;

  bool get isPad => this == pad;

  /// The screen's, read from [MediaQuery]: a look-alike test at the iPad's size gets the iPad layouts.
  static FormFactor of(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= padShortestSide ? pad : phone;
}
