import 'dart:convert';
import 'dart:io';
import 'dart:ui' show loadFontFromList;

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../shared/theme.dart';

enum FontChoice { system, miSans, imported }

/// A font file brought in through 导入字体, copied into the fonts folder beside `font.json`.
final class ImportedFont {
  const ImportedFont({required this.name, required this.family, required this.file});

  /// The file's name without its extension, as 字体 lists it.
  final String name;

  /// The family it was registered under: new for every import, since the engine can't drop a family once loaded.
  final String family;

  /// The copy's file name in the fonts folder.
  final String file;
}

enum ImportOutcome { imported, notAFont, failed }

typedef FontLoader = Future<void> Function(Uint8List bytes, String family);

/// 设置 → 字体: which font the app draws with, kept as a small JSON file, with an imported font's copy in `fonts/` beside
/// it. Every change goes to [BiliFonts.family] at once and tells the app to draw again.
class FontStore extends ChangeNotifier {
  FontStore._(this._path, this._loader, this._logger, this._choice, this._imported) {
    _apply();
  }

  /// Kept in memory only, for tests and for platforms without a support folder.
  factory FontStore.memory({FontLoader? loader, Logger? logger}) =>
      FontStore._(null, loader ?? _engineLoader, logger ?? Logger.shared, defaultChoice, null);

  /// The system's on the iPhone, as the official app draws; MiSans elsewhere, since Windows has no PingFang and its
  /// own Chinese fonts are further from it.
  static FontChoice get defaultChoice =>
      defaultTargetPlatform == TargetPlatform.iOS ? FontChoice.system : FontChoice.miSans;

  /// [path] null keeps the choice in memory. An unreadable file, or an imported font whose copy is gone, falls back
  /// to [defaultChoice], logged.
  static Future<FontStore> load(String? path, {FontLoader? loader, Logger? logger}) async {
    final log = logger ?? Logger.shared;
    final load = loader ?? _engineLoader;
    if (path == null) return FontStore._(null, load, log, defaultChoice, null);
    var choice = defaultChoice;
    ImportedFont? imported;
    final file = File(path);
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is! Map<String, Object?>) throw const FormatException('not an object');
        choice = FontChoice.values.where((value) => value.name == json['font']).firstOrNull ?? choice;
        if (json['imported'] case {'name': String name, 'family': String family, 'file': String copy}) {
          imported = ImportedFont(name: name, family: family, file: copy);
        }
      } catch (error) {
        log.warn(LogCategory.app, 'font choice unreadable, using the default', {'error': _reason(error)});
      }
    }
    if (imported != null) {
      try {
        await load(await File(_fontsFolder(path, imported.file)).readAsBytes(), imported.family);
      } catch (error) {
        log.warn(LogCategory.app, 'imported font not loaded', {'error': _reason(error)});
        imported = null;
      }
    }
    if (choice == FontChoice.imported && imported == null) choice = defaultChoice;
    return FontStore._(path, load, log, choice, imported);
  }

  final String? _path;
  final FontLoader _loader;
  final Logger _logger;
  FontChoice _choice;
  ImportedFont? _imported;
  Future<void> _writing = Future.value();

  FontChoice get choice => _choice;
  ImportedFont? get imported => _imported;

  /// The current font's name, as 设置 shows it.
  String get label => labelOf(_choice);

  String labelOf(FontChoice choice) => switch (choice) {
    FontChoice.system => '系统字体',
    FontChoice.miSans => 'MiSans',
    FontChoice.imported => _imported?.name ?? '导入的字体',
  };

  /// The family [choice] draws with.
  String? familyOf(FontChoice choice) => switch (choice) {
    FontChoice.system => BiliFonts.system,
    FontChoice.miSans => BiliFonts.miSans,
    FontChoice.imported => _imported?.family,
  };

  void select(FontChoice choice) {
    if (choice == _choice || (choice == FontChoice.imported && _imported == null)) return;
    _choice = choice;
    _changed();
  }

  /// Registers [bytes] as a font, keeps a copy and switches to it. A file that isn't a TrueType or OpenType font is
  /// refused before the engine sees it, since the engine drops bad data without a word.
  Future<ImportOutcome> importFont(String fileName, Uint8List bytes) async {
    if (!_looksLikeFont(bytes)) return ImportOutcome.notAFont;
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : 'ttf';
    final family = 'imported-${DateTime.now().microsecondsSinceEpoch}';
    final copy = '$family.$extension';
    try {
      final path = _path;
      if (path != null) {
        final target = File(_fontsFolder(path, copy));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
      }
      await _loader(bytes, family);
    } catch (error) {
      _logger.warn(LogCategory.app, 'font not imported', {'error': _reason(error)});
      return ImportOutcome.failed;
    }
    final previous = _imported;
    _imported = ImportedFont(name: name.isEmpty ? '导入的字体' : name, family: family, file: copy);
    _choice = FontChoice.imported;
    _changed();
    if (previous != null && _path != null) await _delete(_fontsFolder(_path, previous.file));
    return ImportOutcome.imported;
  }

  Map<String, Object?> toJson() => {
    'font': _choice.name,
    if (_imported case final imported?)
      'imported': {'name': imported.name, 'family': imported.family, 'file': imported.file},
  };

  void _apply() => BiliFonts.family = familyOf(_choice);

  void _changed() {
    _apply();
    notifyListeners();
    final path = _path;
    if (path == null) return;
    final text = jsonEncode(toJson());
    // One write after another, so an older choice never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'font choice not saved', {'error': _reason(error)});
    }
  }

  Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } catch (error) {
      _logger.warn(LogCategory.app, 'old imported font not deleted', {'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;

  static String _fontsFolder(String path, String file) =>
      '${File(path).parent.path}${Platform.pathSeparator}fonts${Platform.pathSeparator}$file';

  /// TrueType, OpenType (CFF), Apple's TrueType and font collections, by their first four bytes.
  static bool _looksLikeFont(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final tag = bytes.sublist(0, 4);
    return listEquals(tag, const [0, 1, 0, 0]) || const ['OTTO', 'true', 'ttcf'].contains(String.fromCharCodes(tag));
  }

  static Future<void> _engineLoader(Uint8List bytes, String family) => loadFontFromList(bytes, fontFamily: family);

  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}
