import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../app/app_environment.dart';
import 'skin.dart';
import 'skin_api.dart';
import 'skin_package.dart';

/// The equipped 装扮, asked at launch and on every login, its package downloaded once per id and version and
/// unpacked under [folder] (the support folder's `skins`). Answers from the last unpacked skin at once, so a launch
/// draws the theme from the first frame; a failure keeps what is shown.
///
/// On disk: `current.json` names the skin last equipped (or none), and each package is unpacked into
/// `<id>/<ver>-<md5>`, whole once its `.skin.json` is there (the unpack goes to a `.partial` folder and is renamed into
/// place). A package changed under the same version gets a folder of its own, so files on screen are never replaced in
/// place. Logging out shows the stock look and the next launch starts stock, but the files stay for the next login.
class SkinModel extends ChangeNotifier implements ValueListenable<Skin?> {
  SkinModel({required this._api, required this._environment, required this._folder, Logger? logger})
    : _logger = logger ?? Logger.shared;

  final SkinApi _api;
  final AppEnvironment _environment;
  final String? _folder;
  final Logger _logger;

  static const _currentName = 'current.json';
  static const _manifestName = '.skin.json';

  Skin? _value;
  Future<void>? _started;
  Future<void> _cacheRead = Future.value();
  Future<void>? _refreshing;

  /// Unpacking, writing `current.json` and deleting versions run one after another.
  Future<void> _disk = Future.value();

  /// Where versions are unpacked without [_folder]: a temporary folder, made on first use.
  Future<String>? _scratch;

  /// The account as it last settled; unknown only until the launch's check answers.
  Account _account = const AccountUnknown();

  /// The turn to logged in has refreshed already, so the login count that follows asks nothing more.
  bool _loginRefreshed = false;

  /// Bumped by every login and logout, so an answer for the account before never shows.
  int _generation = 0;
  bool _toldNoToken = false;
  String? _logged;
  bool _disposed = false;

  @override
  Skin? get value => _value;

  bool get _signedIn => switch (_environment.account) {
    LoggedOut() || LoginExpired() => false,
    LoggedIn() || AccountUnknown() => true,
  };

  /// Reads the cached skin and shows it unless the account is logged out, then asks for the equipped one when logged
  /// in (not awaited). Completes once the cache is read, so `main` can draw the first frame with it.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    _account = _environment.account;
    _environment.addListener(_accountChanged);
    _environment.logins.addListener(_loginCompleted);
    final read = _readCache();
    _cacheRead = read;
    final cached = await read;
    if (cached != null && _signedIn && _value == null) _show(cached, from: 'cache');
    if (_environment.account is LoggedIn) unawaited(refresh());
  }

  /// Asks for the equipped skin again; a call while one is out joins it. Never throws: pages fire it unawaited.
  Future<void> refresh() {
    if (_refreshing case final running?) return running;
    late final Future<void> run;
    run = _refresh(_generation)
        .catchError((Object error) {
          _logger.warn(LogCategory.ui, 'skin refresh failed, keeping what is shown', {'error': _describe(error)});
        })
        .whenComplete(() {
          if (identical(_refreshing, run)) _refreshing = null;
        });
    return _refreshing = run;
  }

  Future<void> _refresh(int generation) async {
    await _cacheRead;
    if (!_current(generation) || !_signedIn) return;
    final SkinEquip? equip;
    try {
      equip = await _api.equipped();
    } catch (error) {
      if (error is BiliNoAppTokenError) {
        if (!_toldNoToken) {
          _logger.info(LogCategory.ui, 'skin waits for the app token, keeping what is shown', {
            'shown': _value != null,
          });
        }
        _toldNoToken = true;
      } else {
        _logger.warn(LogCategory.ui, 'skin check failed, keeping what is shown', {'error': _describe(error)});
      }
      return;
    }
    _toldNoToken = false;
    if (!_current(generation)) return;
    if (equip == null) {
      _logger.info(LogCategory.ui, 'skin stays stock', {'reason': 'none equipped'});
      _show(null);
      await _exclusive(() async {
        await _writeCurrent(null);
        await _deleteVersions(keep: null);
      });
      return;
    }
    final SkinEquip next = equip;
    if (_value case final shown? when _cacheText(shown.equip) == _cacheText(next)) return;
    try {
      final (skin, from) = await _exclusive(() => _install(next));
      if (!_current(generation)) return;
      _show(skin, from: from);
      await _exclusive(() async {
        await _writeCurrent(next);
        await _deleteVersions(keep: next);
      });
    } catch (error) {
      _logger.warn(LogCategory.ui, 'skin not installed, keeping what is shown', {
        'id': equip.id,
        'ver': equip.ver,
        'error': _describe(error),
      });
    }
  }

  /// The version's files, unpacked already or downloaded, checked and unpacked now.
  Future<(Skin, String)> _install(SkinEquip equip) async {
    final target = Directory(_versionPath(await _root(), equip));
    if (await _wholeVersion(target, equip) case final files?) return (resolveSkin(equip, files), 'unpacked');
    final url = Uri.tryParse(equip.packageUrl);
    if (url == null || !isSkinPackageUrl(url)) throw const SkinPackageError('package host not allowed');
    final download = await _api.download(url);
    if (download.length > SkinLimits.packageBytes) throw const SkinPackageError('package too large');
    final bytes = download is Uint8List ? download : Uint8List.fromList(download);
    final partial = Directory('${target.path}.partial');
    if (await partial.exists()) await partial.delete(recursive: true);
    final unpacked = await unpackSkinPackage(bytes, md5: equip.packageMd5, folder: partial.path);
    if (unpacked.skipped.isNotEmpty) {
      _logger.warn(LogCategory.ui, 'skin package entries skipped', {
        'id': equip.id,
        'ver': equip.ver,
        'skipped': unpacked.skipped.join(', '),
      });
    }
    await File('${partial.path}/$_manifestName')
        .writeAsString(jsonEncode({'md5': equip.packageMd5.trim().toLowerCase()}), flush: true);
    if (await target.exists()) await _retried(() => target.delete(recursive: true));
    await _retried(() => partial.rename(target.path));
    return (resolveSkin(equip, await listSkinFiles(target)), 'package');
  }

  /// The files of [folder] when it holds [equip]'s package whole; null otherwise, so it is unpacked again.
  Future<List<SkinFile>?> _wholeVersion(Directory folder, SkinEquip equip) async {
    try {
      final manifest = File('${folder.path}/$_manifestName');
      if (!await manifest.exists()) return null;
      final json = jsonDecode(await manifest.readAsString());
      if (json is! Map<String, Object?> || json['md5'] != equip.packageMd5.trim().toLowerCase()) return null;
      return await listSkinFiles(folder);
    } on Exception catch (error) {
      _logger.warn(LogCategory.ui, 'unpacked skin unreadable', {'id': equip.id, 'error': _describe(error)});
      return null;
    }
  }

  Future<Skin?> _readCache() async {
    final folder = _folder;
    if (folder == null) return null;
    try {
      final file = File('$folder/$_currentName');
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      final equip = _equipFromCache(json['equip']);
      if (equip == null) {
        _logger.info(LogCategory.ui, 'skin stays stock', {'reason': 'none at the last check'});
        return null;
      }
      final files = await _wholeVersion(Directory(_versionPath(folder, equip)), equip);
      if (files == null) {
        _logger.warn(LogCategory.ui, 'skin stays stock', {'reason': 'cached version incomplete', 'id': equip.id});
        return null;
      }
      return resolveSkin(equip, files);
    } catch (error) {
      _logger.warn(LogCategory.ui, 'skin stays stock', {'reason': 'cache unreadable', 'error': _describe(error)});
      return null;
    }
  }

  Future<void> _writeCurrent(SkinEquip? equip) async {
    final folder = _folder;
    if (folder == null) return;
    try {
      await Directory(folder).create(recursive: true);
      final temporary = File('$folder/$_currentName.tmp');
      await temporary.writeAsString(jsonEncode({'equip': equip == null ? null : _cacheJson(equip)}), flush: true);
      await _retried(() => temporary.rename('$folder/$_currentName'));
    } catch (error) {
      _logger.warn(LogCategory.ui, 'skin choice not saved', {'error': _describe(error)});
    }
  }

  /// Every unpacked version but [keep]'s, and any unpack left half done.
  Future<void> _deleteVersions({required SkinEquip? keep}) async {
    var failed = 0;
    try {
      final root = Directory(await _root());
      if (!await root.exists()) return;
      await for (final skin in root.list(followLinks: false)) {
        if (skin is! Directory) continue;
        final id = _nameOf(skin.path);
        await for (final version in skin.list(followLinks: false)) {
          if (keep != null && id == '${keep.id}' && _nameOf(version.path) == _versionName(keep)) continue;
          try {
            await version.delete(recursive: true);
          } on FileSystemException {
            failed++;
          }
        }
        if (await skin.list().isEmpty) await skin.delete();
      }
    } on FileSystemException {
      failed++;
    }
    // A file still open (the old header's video on Windows) can't go; the next refresh tries again.
    if (failed > 0) _logger.warn(LogCategory.ui, 'old skin files not deleted', {'count': failed});
  }

  Future<String> _root() async {
    if (_folder case final folder?) return folder;
    return _scratch ??= Directory.systemTemp.createTemp('bilifast_skin_').then((folder) => folder.path);
  }

  static String _versionPath(String root, SkinEquip equip) => '$root/${equip.id}/${_versionName(equip)}';

  /// The md5 comes from an answer, so only its hex digits reach the path.
  static String _versionName(SkinEquip equip) {
    final digits = equip.packageMd5.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');
    return '${equip.ver}-${digits.length > 8 ? digits.substring(0, 8) : digits}';
  }

  static String _nameOf(String path) => path.split(RegExp(r'[\\/]')).last;

  /// Windows' virus scan holds a file it has just seen written for a moment, and a rename or delete then fails.
  static Future<T> _retried<T>(Future<T> Function() step) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await step();
      } on FileSystemException {
        if (attempt == 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 40 * attempt));
      }
    }
  }

  /// Waits for the disk work so far; for tests.
  Future<void> settle() => _disk;

  Future<T> _exclusive<T>(Future<T> Function() task) {
    final run = _disk.then((_) => task());
    _disk = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void _accountChanged() {
    final now = _environment.account;
    if (now is AccountUnknown) {
      // didLogin passes through here on its way to logged in; the login count after it then knows whether the turn
      // to logged in has refreshed.
      _loginRefreshed = false;
      return;
    }
    final was = _account;
    _account = now;
    if (now is! LoggedIn) {
      _signedOut(was);
    } else if (was is! LoggedIn) {
      _loginRefreshed = true;
      _restart();
    }
  }

  /// A login over an account that already read logged in leaves the account where it was, and may be another one.
  void _loginCompleted() {
    if (_loginRefreshed) {
      _loginRefreshed = false;
    } else if (_account is LoggedIn) {
      _restart();
    }
  }

  void _restart() {
    _generation++;
    _refreshing = null;
    unawaited(refresh());
  }

  void _signedOut(Account was) {
    _generation++;
    _refreshing = null;
    _loginRefreshed = false;
    if (was is LoggedOut || was is LoginExpired) return;
    _logger.info(LogCategory.ui, 'skin stays stock', {'reason': 'logged out', 'shown': _value != null});
    _show(null);
    unawaited(_exclusive(() => _writeCurrent(null)));
  }

  bool _current(int generation) => generation == _generation && !_disposed;

  void _show(Skin? skin, {String? from}) {
    if (_disposed || identical(skin, _value)) return;
    _value = skin;
    if (skin != null && from != null) _log(skin, from);
    notifyListeners();
  }

  /// Once per skin as it changes: never the package's URL.
  void _log(Skin skin, String from) {
    final key = _cacheText(skin.equip);
    if (key == _logged) return;
    _logged = key;
    final equip = skin.equip;
    final colors = equip.colors;
    final gaps = skinBarGaps(skin);
    _logger.info(LogCategory.ui, 'skin', {
      'from': from,
      'id': equip.id,
      'ver': equip.ver,
      'name': equip.name,
      'primaryOnly': equip.primaryOnly,
      'lightText': colors.lightText,
      'color': _hex(colors.color),
      'colorSecondPage': _hex(colors.colorSecondPage),
      'tailColor': _hex(colors.tailColor),
      'tailColorSelected': _hex(colors.tailColorSelected),
      'tailIconTinted': colors.tailIconTinted,
      'tailIconAnimated': colors.tailIconAnimated,
      'bar': gaps.isEmpty ? 'themed' : 'stock, without ${gaps.join(', ')}',
      'files': [
        for (final MapEntry(key: stem, value: file) in skin.files.entries) '$stem ${_extension(file)} ${_size(file)}',
      ].join(', '),
    });
  }

  static String _hex(int? argb) => argb == null ? 'none' : '#${argb.toRadixString(16).padLeft(8, '0')}';

  static String _extension(File file) {
    final name = _nameOf(file.path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '-' : name.substring(dot + 1);
  }

  static int _size(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return -1;
    }
  }

  /// A transport's own words carry the request's URL, and a file error the container's path.
  static String _describe(Object error) => switch (error) {
    SkinPackageError(:final reason) => reason,
    BiliError() => '$error',
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: ${osError.message}',
    FormatException(:final message) => message,
    _ => '${error.runtimeType}',
  };

  @override
  void dispose() {
    _disposed = true;
    if (_started != null) {
      _environment.removeListener(_accountChanged);
      _environment.logins.removeListener(_loginCompleted);
    }
    super.dispose();
  }
}

/// What `current.json` keeps of an equip: everything but the package's URL, which is needed only to download.
Map<String, Object?> _cacheJson(SkinEquip equip) {
  final colors = equip.colors;
  return {
    'id': equip.id,
    'name': equip.name,
    'ver': equip.ver,
    'md5': equip.packageMd5.trim().toLowerCase(),
    'primaryOnly': equip.primaryOnly,
    'colors': {
      'color': colors.color,
      'colorSecondPage': colors.colorSecondPage,
      'lightText': colors.lightText,
      'tailColor': colors.tailColor,
      'tailColorSelected': colors.tailColorSelected,
      'tailIconTinted': colors.tailIconTinted,
      'tailIconColor': colors.tailIconColor,
      'tailIconColorSelected': colors.tailIconColorSelected,
      'tailIconAnimated': colors.tailIconAnimated,
      'tailIconCycle': colors.tailIconCycle,
      'headMyselfVideoLoop': colors.headMyselfVideoLoop,
    },
  };
}

String _cacheText(SkinEquip equip) => jsonEncode(_cacheJson(equip));

SkinEquip? _equipFromCache(Object? json) {
  if (json == null) return null;
  if (json is! Map<String, Object?>) throw const FormatException('equip not an object');
  final colors = json['colors'];
  if (colors is! Map<String, Object?>) throw const FormatException('colors not an object');
  T need<T>(Map<String, Object?> map, String key) =>
      map[key] is T ? map[key] as T : throw FormatException('$key missing');
  int? color(String key) => colors[key] is int ? colors[key] as int : null;
  bool flag(String key, {bool otherwise = false}) => colors[key] is bool ? colors[key] as bool : otherwise;
  return SkinEquip(
    id: need<int>(json, 'id'),
    name: need<String>(json, 'name'),
    ver: need<int>(json, 'ver'),
    packageUrl: '',
    packageMd5: need<String>(json, 'md5'),
    primaryOnly: json['primaryOnly'] == true,
    colors: SkinColors(
      color: color('color'),
      colorSecondPage: color('colorSecondPage'),
      lightText: flag('lightText'),
      tailColor: color('tailColor'),
      tailColorSelected: color('tailColorSelected'),
      tailIconTinted: flag('tailIconTinted'),
      tailIconColor: color('tailIconColor'),
      tailIconColorSelected: color('tailIconColorSelected'),
      tailIconAnimated: flag('tailIconAnimated'),
      tailIconCycle: flag('tailIconCycle'),
      headMyselfVideoLoop: flag('headMyselfVideoLoop', otherwise: true),
    ),
  );
}
