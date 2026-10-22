/// The colours a 装扮 sets, 0xAARRGGBB; null where the skin leaves the stock colour.
final class SkinColors {
  const SkinColors({
    this.color,
    this.colorSecondPage,
    this.lightText = false,
    this.tailColor,
    this.tailColorSelected,
    this.tailIconTinted = false,
    this.tailIconColor,
    this.tailIconColorSelected,
    this.tailIconAnimated = false,
    this.tailIconCycle = false,
    this.headMyselfVideoLoop = true,
  });

  /// The text and icons over the themed headers: 首页's tabs and indicator, 我的's top icons.
  final int? color;
  final int? colorSecondPage;

  /// `color_mode` "light": light text over a dark picture.
  final bool lightText;

  /// The bottom bar's labels.
  final int? tailColor;
  final int? tailColorSelected;

  /// `tail_icon_mode` "color": the stock icons tinted with [tailIconColor] and [tailIconColorSelected] instead of
  /// the package's pictures.
  final bool tailIconTinted;
  final int? tailIconColor;
  final int? tailIconColorSelected;

  /// `tail_icon_ani`: the selected icons are animations.
  final bool tailIconAnimated;

  /// `tail_icon_ani_mode` "cycle": the selected icon's animation loops; otherwise it plays once.
  final bool tailIconCycle;

  /// `head_myself_mp4_play` "loop"; otherwise it plays once.
  final bool headMyselfVideoLoop;
}

/// The account's equipped 装扮, from the official app's `/x/resource/show/skin`. Its pictures are in the zip at
/// [packageUrl], a public file on Bilibili's CDN.
final class SkinEquip {
  const SkinEquip({
    required this.id,
    required this.name,
    required this.ver,
    required this.packageUrl,
    required this.packageMd5,
    this.colors = const SkinColors(),
    this.primaryOnly = false,
  });

  final int id;
  final String name;
  final int ver;
  final String packageUrl;
  final String packageMd5;
  final SkinColors colors;

  /// `conf.attribute` bit 2: the skin dresses only the main pages.
  final bool primaryOnly;

  /// The skin `data` names; null when nothing with a package is equipped (a plain colour theme, or none).
  static SkinEquip? fromJson(Object? json) => throw UnimplementedError('core builder');
}
