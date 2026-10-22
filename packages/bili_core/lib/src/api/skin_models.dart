import 'json.dart';

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
  /// `common_equip` (an event's skin), `skin_colors` and `load_equip` are not read.
  static SkinEquip? fromJson(Object? json) {
    final equip = JsonObject.from(json, 'skin').nested('user_equip');
    final packageUrl = equip?.text('package_url');
    if (equip == null || packageUrl == null || packageUrl.isEmpty) return null;
    final attribute = _number(equip.nested('conf')?.map['attribute']) ?? 0;
    return SkinEquip(
      id: _number(equip.map['id']) ?? 0,
      name: equip.text('name') ?? '',
      ver: _number(equip.map['ver']) ?? 0,
      packageUrl: _secure(packageUrl),
      packageMd5: equip.text('package_md5') ?? '',
      colors: _colors(equip.nested('data') ?? const JsonObject({})),
      primaryOnly: (attribute & 4) != 0,
    );
  }
}

SkinColors _colors(JsonObject data) => SkinColors(
  color: argbColour(data.map['color']),
  colorSecondPage: argbColour(data.map['color_second_page']),
  lightText: data.text('color_mode') == 'light',
  tailColor: argbColour(data.map['tail_color']),
  tailColorSelected: argbColour(data.map['tail_color_selected']),
  tailIconTinted: data.text('tail_icon_mode') == 'color',
  tailIconColor: argbColour(data.map['tail_icon_color']),
  tailIconColorSelected: argbColour(data.map['tail_icon_color_selected']),
  tailIconAnimated: data.flag('tail_icon_ani'),
  tailIconCycle: data.text('tail_icon_ani_mode') == 'cycle',
  headMyselfVideoLoop: data.text('head_myself_mp4_play') == 'loop',
);

int? _number(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value) : null);

String _secure(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

final _hex = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// A colour as Bilibili writes it, "#RRGGBB" or "#AARRGGBB", as 0xAARRGGBB; null for anything else.
int? argbColour(Object? value) {
  final match = value is String ? _hex.firstMatch(value.trim()) : null;
  if (match == null) return null;
  final digits = match.group(1)!;
  final colour = int.parse(digits, radix: 16);
  return digits.length == 6 ? 0xFF000000 | colour : colour;
}
