/// The home screen icons 设置 → 应用图标 offers. [iconSet] names the asset catalog's icon set (listed in the
/// project's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES); null is the primary icon, the cat since 1.5.0.
enum AppIconChoice {
  standard(null, '默认', 'assets/app_icons/cat.png'),
  tv('AppIconTV', '小电视', 'assets/app_icons/tv.png');

  const AppIconChoice(this.iconSet, this.label, this.preview);

  final String? iconSet;
  final String label;

  /// A 180 px (60 pt at 3×) picture of the icon for the page.
  final String preview;

  /// An icon set this build doesn't offer counts as the primary icon: `AppIconCat`, chosen before the cat became the
  /// primary, is still in the bundle and looks the same.
  static AppIconChoice of(String? iconSet) =>
      values.firstWhere((choice) => choice.iconSet == iconSet, orElse: () => standard);
}

abstract interface class AppIconHost {
  Future<AppIconChoice> current();

  /// The icon set the home screen shows as iOS names it, null for the primary.
  Future<String?> iconSet();

  /// Throws when the system refuses; the icon is then unchanged.
  Future<void> choose(AppIconChoice choice);
}

/// Windows and tests: the choice is kept in memory only, since there is no home screen icon to change.
final class MemoryAppIconHost implements AppIconHost {
  MemoryAppIconHost([this._choice = AppIconChoice.standard]);

  AppIconChoice _choice;

  @override
  Future<AppIconChoice> current() async => _choice;

  @override
  Future<String?> iconSet() async => _choice.iconSet;

  @override
  Future<void> choose(AppIconChoice choice) async => _choice = choice;
}
