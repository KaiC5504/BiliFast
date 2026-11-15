/// The home screen icons 设置 → 应用图标 offers. [iconSet] names the asset catalog's icon set (listed in the
/// project's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES); null is the primary icon.
enum AppIconChoice {
  standard(null, '默认', 'assets/app_icons/default.png'),
  cat('AppIconCat', '猫猫', 'assets/app_icons/cat.png');

  const AppIconChoice(this.iconSet, this.label, this.preview);

  final String? iconSet;
  final String label;

  /// A 180 px (60 pt at 3×) picture of the icon for the page.
  final String preview;

  /// An icon set this build doesn't know (one a later build removed) counts as the primary icon.
  static AppIconChoice of(String? iconSet) =>
      values.firstWhere((choice) => choice.iconSet == iconSet, orElse: () => standard);
}

abstract interface class AppIconHost {
  Future<AppIconChoice> current();

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
  Future<void> choose(AppIconChoice choice) async => _choice = choice;
}
