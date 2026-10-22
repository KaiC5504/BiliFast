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

  Color? get color => _color(equip.colors.color);
  Color? get tailColor => _color(equip.colors.tailColor);
  Color? get tailColorSelected => _color(equip.colors.tailColorSelected);

  /// Light text and icons over the themed headers.
  bool get lightText => equip.colors.lightText;

  /// Whether the bottom bar takes the skin: its picture, all five icons each way and both label colours are there.
  bool get themesBar =>
      tailBg != null &&
      tailIcons.length >= 5 &&
      tailIconsSelected.length >= 5 &&
      tailColor != null &&
      tailColorSelected != null;

  static Color? _color(int? argb) => argb == null ? null : Color(argb);
}
