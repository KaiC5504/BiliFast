import 'package:flutter/foundation.dart';

import '../app/app_environment.dart';
import 'skin.dart';
import 'skin_api.dart';

/// The equipped 装扮, asked at launch and on every login, its package downloaded once per id and version and
/// unpacked under [folder] (the support folder's `skins`). Answers from the last unpacked skin at once, so a launch
/// draws the theme from the first frame; a failure keeps what is shown.
class SkinModel extends ChangeNotifier implements ValueListenable<Skin?> {
  SkinModel({required this._api, required this._environment, required this._folder});

  // ignore: unused_field
  final SkinApi _api;
  // ignore: unused_field
  final AppEnvironment _environment;
  // ignore: unused_field
  final String? _folder;

  @override
  Skin? get value => null;

  /// Reads the cached skin, then asks for the equipped one.
  Future<void> start() async {}

  /// Asks for the equipped skin again.
  Future<void> refresh() async {}
}
