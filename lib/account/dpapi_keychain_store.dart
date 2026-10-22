import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'keychain_store.dart';

/// CRYPTPROTECT_UI_FORBIDDEN, which win32 6.4.0 doesn't export.
const _uiForbidden = 0x1;

/// The Windows build's login store: the cookies in one file in the app's support folder, encrypted with DPAPI
/// (`CryptProtectData`, this Windows user only), so a copy of the file is useless elsewhere. The app token is never
/// kept on the PC: its loads answer null and its saves are refused.
class DpapiKeychainStore implements KeychainStore {
  DpapiKeychainStore(this.path, {Logger? logger}) : _logger = logger ?? Logger.shared;

  /// The encrypted file.
  final String path;
  final Logger _logger;

  /// The [CookieLoadFailed.status] of a file that decrypts to something other than a cookie map. Win32 codes are
  /// never negative, and -1 is the app's own for a read that threw.
  static const badContentsStatus = -2;

  String get _tempPath => '$path.tmp';

  @override
  Future<CookieLoad> loadCookies() async {
    if (!Platform.isWindows) return const NoStoredCookies();
    final Uint8List sealed;
    try {
      sealed = File(path).readAsBytesSync();
    } on PathNotFoundException {
      return const NoStoredCookies();
    } on FileSystemException catch (error) {
      return _loadFailed('read', error.osError?.errorCode ?? 0);
    }
    final (:bytes, :error) = _crypt(sealed, protect: false);
    if (bytes == null) return _loadFailed('decrypt', error);
    // A FormatException's message quotes the decrypted text, so it goes no further than here.
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return _loadFailed('decode', badContentsStatus);
    }
    if (decoded is! Map<String, Object?> || decoded.values.any((value) => value is! String)) {
      return _loadFailed('decode', badContentsStatus);
    }
    return StoredCookies({for (final MapEntry(:key, :value) in decoded.entries) key: value as String});
  }

  @override
  Future<bool> saveCookies(Map<String, String> cookies) async {
    if (!Platform.isWindows) return false;
    if (cookies.isEmpty) {
      try {
        _deleteFiles();
        return true;
      } catch (error) {
        _logWriteFailed('delete', error);
        return false;
      }
    }
    final (:bytes, :error) = _crypt(utf8.encode(jsonEncode(cookies)), protect: true);
    if (bytes == null) {
      _logger.error(LogCategory.app, 'login file write failed', {'step': 'encrypt', 'status': error});
      return false;
    }
    // Synchronous, as DPAPI is, so two saves never interleave on the one temporary file.
    final temp = File(_tempPath);
    try {
      temp.parent.createSync(recursive: true);
      temp.writeAsBytesSync(bytes, flush: true);
      temp.renameSync(path);
      return true;
    } catch (error) {
      _logWriteFailed('write', error);
      try {
        temp.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<void> deleteCookies() async {
    if (!Platform.isWindows) return;
    _deleteFiles();
  }

  @override
  Future<String?> loadAppToken() async => null;

  @override
  Future<bool> saveAppToken(String token) async => false;

  @override
  Future<void> deleteAppToken() async {}

  /// A temporary file left by a save that died before its rename holds a login too.
  void _deleteFiles() {
    for (final file in [File(path), File(_tempPath)]) {
      try {
        file.deleteSync();
      } on PathNotFoundException catch (_) {}
    }
  }

  CookieLoadFailed _loadFailed(String step, int status) {
    _logger.error(LogCategory.app, 'login file read failed', {'step': step, 'status': status});
    return CookieLoadFailed(status);
  }

  void _logWriteFailed(String step, Object error) {
    _logger.error(LogCategory.app, 'login file write failed', {
      'step': step,
      'error': error.runtimeType.toString(),
      'status': error is FileSystemException ? error.osError?.errorCode ?? 0 : 0,
    });
  }
}

/// [CryptProtectData] or [CryptUnprotectData] on [input]: the output, or null and the Win32 error code.
({Uint8List? bytes, int error}) _crypt(Uint8List input, {required bool protect}) {
  final inData = calloc<Uint8>(math.max(input.length, 1));
  final inBlob = calloc<CRYPT_INTEGER_BLOB>();
  final outBlob = calloc<CRYPT_INTEGER_BLOB>();
  try {
    inData.asTypedList(input.length).setAll(0, input);
    inBlob.ref
      ..cbData = input.length
      ..pbData = inData;
    final Win32Result(:value, :error) = protect
        ? CryptProtectData(inBlob, null, null, null, _uiForbidden, outBlob)
        : CryptUnprotectData(inBlob, null, null, null, _uiForbidden, outBlob);
    if (!value) return (bytes: null, error: error);
    final out = outBlob.ref;
    return (bytes: Uint8List.fromList(out.pbData.asTypedList(out.cbData)), error: 0);
  } finally {
    final produced = outBlob.ref.pbData;
    if (produced != nullptr) LocalFree(HLOCAL(produced));
    calloc.free(outBlob);
    calloc.free(inBlob);
    calloc.free(inData);
  }
}
