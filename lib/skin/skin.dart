import 'dart:io';
import 'dart:ui' show Color;

import 'package:bili_core/api.dart';

/// One of the themed bottom bar's icons: a still picture, or an svga animation.
final class SkinIcon {
  const SkinIcon(this.file, {this.animated = false});

  final File file;

  /// An `.svga` file, drawn by `SvgaView`.
  final bool animated;
}

/// The equipped 装扮, unpacked on the device: its pictures by role (each null when the package has none) and its
/// colours. Pages read it from `AppServices.skin.value`; null there means the stock look.
final class Skin {
  const Skin({
    required this.equip,
    this.headBg,
    this.headTabBg,
    this.headMyself,
    this.headMyselfVideo,
    this.tailBg,
    this.tailIcons = const [],
    this.tailIconsSelected = const [],
    this.pubButton,
    this.pubButtonSelected,
    this.files = const {},
    this.statusBar,
  });

  final SkinEquip equip;

  /// 首页's top: avatar, search field and tab row (110).
  final File? headBg;
  final File? headTabBg;

  /// 我的's header (109): `head_myself_squared_bg`, else `head_myself_bg`.
  final File? headMyself;

  /// `head_myself_mp4_bg`, muted, over [headMyself].
  final File? headMyselfVideo;

  /// The bottom bar's picture (109, 110).
  final File? tailBg;

  /// The bar's icons in the package's order (main, channel, dynamic, shop, myself), normal and selected. Each set is
  /// whole or empty (resolveSkin).
  final List<SkinIcon> tailIcons;
  final List<SkinIcon> tailIconsSelected;
  final SkinIcon? pubButton;
  final SkinIcon? pubButtonSelected;

  /// Every file the package unpacked, by its name without the extension (the official app's key), roles above
  /// included.
  final Map<String, File> files;

  /// What the headers' pictures are like behind the status bar, measured on the device; null until then.
  final SkinStatusBar? statusBar;

  Color? get color => _color(equip.colors.color);
  Color? get tailColor => _color(equip.colors.tailColor);
  Color? get tailColorSelected => _color(equip.colors.tailColorSelected);

  /// Light text and icons over the themed headers.
  bool get lightText => equip.colors.lightText;

  /// White status bar icons over 首页's dressed top, as the official iPhone app judges `head_bg`; the skin's
  /// `color_mode` until it is measured or when it can't be read.
  bool get lightStatusHome => switch (statusBar?.home) {
    final luminance? => SkinStatusBar.whiteOver(luminance),
    null => lightText,
  };

  /// White status bar icons over 我的's dressed header: by its picture, or for a header video by the header's text
  /// colour, light text meaning a dark header.
  bool get lightStatusMe {
    if (headMyselfVideo != null) {
      final text = color;
      return text == null ? lightText : !SkinStatusBar.whiteOverColor(text);
    }
    return switch (statusBar?.me) {
      final luminance? => SkinStatusBar.whiteOver(luminance),
      null => lightText,
    };
  }

  Skin withStatusBar(SkinStatusBar statusBar) => Skin(
    equip: equip,
    headBg: headBg,
    headTabBg: headTabBg,
    headMyself: headMyself,
    headMyselfVideo: headMyselfVideo,
    tailBg: tailBg,
    tailIcons: tailIcons,
    tailIconsSelected: tailIconsSelected,
    pubButton: pubButton,
    pubButtonSelected: pubButtonSelected,
    files: files,
    statusBar: statusBar,
  );

  /// Whether the bottom bar takes the skin: its picture, all five icons each way and both label colours are there.
  bool get themesBar =>
      tailBg != null &&
      tailIcons.length >= 5 &&
      tailIconsSelected.length >= 5 &&
      tailColor != null &&
      tailColorSelected != null;

  static Color? _color(int? argb) => argb == null ? null : Color(argb);
}

/// The relative luminance (WCAG, linear light) behind the status bar's clock and icons in each dressed header, as a
/// geometric mean: contrast is a ratio, so a picture of fine dark lines on a lighter ground reads by its share of each
/// rather than by its highlights. 109's header, a beige and black ornament, has a plain mean of 0.26 and a geometric
/// one of 0.16, and the official app draws white over it. Null where there is no picture or it couldn't be read.
final class SkinStatusBar {
  const SkinStatusBar({this.home, this.me});

  final double? home;
  final double? me;

  /// Where white's contrast ratio with the backdrop and black's are equal: (L + 0.05)² = 1.05 × 0.05.
  static const crossover = 0.1791;

  /// White icons over [luminance] contrast more than black ones.
  static bool whiteOver(double luminance) => luminance < crossover;

  static bool whiteOverColor(Color color) => whiteOver(color.computeLuminance());
}
