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
    this.headMyselfVideoLoop = false,
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

  /// `tail_icon_ani`: a change of place fades and raises the incoming icon.
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

  /// The skin `data` names; null when nothing is equipped: no `data`, a null, empty or zero (id 0) `user_equip`, or a
  /// plain colour theme (its id among `skin_colors`), which has no package. Any other answer without a package throws a
  /// [DecodeError] naming the problem and the keys it found, never their values, so a changed answer never reads as
  /// none. A missing `package_md5` reads as empty, and the package is then refused before it is downloaded.
  /// `common_equip` (an event's skin) and `load_equip` are not read.
  static SkinEquip? fromJson(Object? json) {
    final data = JsonObject.from(json, 'skin data');
    if (data.map.isEmpty) return null;
    if (!data.map.containsKey('user_equip')) throw DecodeError('skin: no user_equip (data keys: ${_keys(data.map)})');
    final raw = data.map['user_equip'];
    if (raw == null) return null;
    if (raw is! Map<String, Object?>) {
      throw DecodeError('skin: user_equip is ${_kind(raw)} (data keys: ${_keys(data.map)})');
    }
    if (raw.isEmpty) return null;
    final packageUrl = raw['package_url'];
    if (packageUrl != null && packageUrl is! String) {
      throw DecodeError('skin: package_url is ${_kind(packageUrl)} (user_equip keys: ${_keys(raw)})');
    }
    if (packageUrl is! String || packageUrl.trim().isEmpty) {
      final id = _number(raw['id']);
      if (id == 0 || _colourThemeIds(data).contains(id)) return null;
      throw DecodeError('skin: user_equip has no package_url (user_equip keys: ${_keys(raw)})');
    }
    final equip = JsonObject(raw);
    final attribute = _number(equip.nested('conf')?.map['attribute']) ?? 0;
    return SkinEquip(
      id: _number(raw['id']) ?? 0,
      name: equip.text('name') ?? '',
      ver: _number(raw['ver']) ?? 0,
      packageUrl: _secure(packageUrl.trim()),
      packageMd5: equip.text('package_md5') ?? '',
      colors: _colors(equip.nested('data') ?? const JsonObject({})),
      primaryOnly: (attribute & 4) != 0,
    );
  }
}

Set<int> _colourThemeIds(JsonObject data) => {
  for (final theme in data.lenientList('skin_colors', (json) => json))
    if (theme is Map<String, Object?>) ?_number(theme['id']),
};

/// The answer's own key names for a log, at most 20, each cut to 40 characters.
String _keys(Map<String, Object?> map) {
  final names = [for (final key in map.keys) key.length <= 40 ? key : key.substring(0, 40)]..sort();
  return names.length <= 20 ? names.join(', ') : '${names.take(20).join(', ')}, …';
}

String _kind(Object value) => switch (value) {
  String() => 'a string',
  num() => 'a number',
  bool() => 'a bool',
  List<Object?>() => 'a list',
  Map<String, Object?>() => 'an object',
  _ => 'of another type',
};

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
