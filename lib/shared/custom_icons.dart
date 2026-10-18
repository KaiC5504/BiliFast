import 'package:flutter/widgets.dart';

/// Glyphs in the borrowed `custom_icon` font (assets/fonts/custom_icon.ttf, from PiliPlus): the 弹 toggles and the
/// danmaku settings mark.
abstract final class CustomIcons {
  static const _family = 'custom_icon';

  static const danmakuOff = IconData(0xe801, fontFamily: _family);
  static const danmakuOn = IconData(0xe802, fontFamily: _family);
  static const danmakuSettings = IconData(0xe803, fontFamily: _family);
}
