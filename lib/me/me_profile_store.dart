import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';

import 'me_model.dart';

/// The account 我的 last showed and the uid it belongs to.
typedef KeptMe = ({int mid, MeShown view});

/// 我的's last account and counts, kept on the phone so the next launch draws them at once (the official app never
/// shows 我的 without them), in a JSON file in the support folder: `{"mid": …, "profile": {…}, "counts": {…}}`. It
/// holds the account's name and face, so none of it ever reaches the log.
class MeProfileStore {
  MeProfileStore.memory({Logger? logger}) : this._(null, null, false, logger ?? Logger.shared);

  MeProfileStore._(this._path, this._kept, this._onDisk, this._logger);

  /// [path] null keeps it in memory only. An unreadable file starts empty and is deleted.
  static Future<MeProfileStore> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return MeProfileStore._(null, null, false, log);
    final file = File(path);
    try {
      if (!await file.exists()) return MeProfileStore._(path, null, await File('$path.tmp').exists(), log);
      return MeProfileStore._(path, _decode(await file.readAsString()), true, log);
    } catch (error) {
      log.warn(LogCategory.app, 'me profile unreadable, starting empty', {
        'file': _name(file),
        'error': _reason(error),
      });
    }
    return MeProfileStore._(path, null, true, log)..delete();
  }

  final String? _path;
  KeptMe? _kept;

  /// Whether the file may be there, so a delete with nothing written asks nothing of storage.
  bool _onDisk;
  final Logger _logger;
  Future<void> _writing = Future.value();

  KeptMe? get kept => _kept;

  /// Keeps [view] as [mid]'s; the same again writes nothing.
  void save(int mid, MeShown view) {
    final kept = (mid: mid, view: view);
    if (kept == _kept) return;
    _kept = kept;
    final path = _path;
    if (path == null) return;
    _onDisk = true;
    final text = jsonEncode(_encode(kept));
    // One write after another, so an older account never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  void delete() {
    _kept = null;
    final path = _path;
    if (path == null || !_onDisk) return;
    _onDisk = false;
    _writing = _writing.then((_) => _remove(path));
  }

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;

  Future<void> _write(String path, String text) async {
    final file = File(path);
    final temporary = File('$path.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'me profile not saved', {'file': _name(file), 'error': _reason(error)});
      // It holds the account too.
      await _deleteFile(temporary);
    }
  }

  /// A write killed before its rename leaves the account in the temporary file, so that goes as well.
  Future<void> _remove(String path) async {
    await _deleteFile(File(path));
    await _deleteFile(File('$path.tmp'));
  }

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      _logger.warn(LogCategory.app, 'me profile not deleted', {'file': _name(file), 'error': _reason(error)});
    }
  }

  static Map<String, Object?> _encode(KeptMe kept) {
    final profile = kept.view.profile;
    final counts = kept.view.counts;
    return {
      'mid': kept.mid,
      'profile': {
        'mid': ?profile.mid,
        'name': profile.name,
        'face': profile.face,
        'pendant': ?profile.pendant,
        'level': profile.level,
        'coins': profile.coins,
        'bcoin': profile.bcoin,
        'vip': profile.vip,
        'vipLabel': profile.vipLabel,
        'vipBadge': profile.vipBadge,
      },
      if (counts != null)
        'counts': {'dynamics': counts.dynamics, 'following': counts.following, 'followers': counts.followers},
    };
  }

  /// Throws when [text] isn't a kept account.
  static KeptMe _decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) throw const FormatException('not an object');
    final mid = json['mid'];
    if (mid is! int || mid <= 0) throw const FormatException('no mid');
    final profile = json['profile'];
    if (profile is! Map<String, Object?>) throw const FormatException('no profile');
    final counts = json['counts'];
    if (counts != null && counts is! Map<String, Object?>) throw const FormatException('counts not an object');
    return (
      mid: mid,
      view: MeShown(
        MeProfile(
          mid: profile['mid'] as int?,
          name: profile['name']! as String,
          face: profile['face']! as String,
          pendant: profile['pendant'] as String?,
          level: profile['level']! as int,
          coins: (profile['coins']! as num).toDouble(),
          bcoin: (profile['bcoin']! as num).toDouble(),
          vip: profile['vip'] as bool? ?? false,
          vipLabel: profile['vipLabel'] as String? ?? '',
          vipBadge: profile['vipBadge'] as bool? ?? false,
        ),
        counts is Map<String, Object?>
            ? MeCounts(
                dynamics: counts['dynamics']! as int,
                following: counts['following']! as int,
                followers: counts['followers']! as int,
              )
            : null,
      ),
    );
  }

  static String _name(File file) => file.uri.pathSegments.last;

  /// The error without the text that failed, which holds the account: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    TypeError() => 'a field missing or of the wrong type',
    _ => '${error.runtimeType}',
  };
}
