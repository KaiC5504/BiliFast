import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/dpapi_keychain_store.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  group('DpapiKeychainStore', skip: Platform.isWindows ? false : 'DPAPI is Windows only', () {
    const cookies = {
      'SESSDATA': 'made-up%2Csess%2Cvalue',
      'bili_jct': 'fake-csrf-0123456789',
      'DedeUserID': '10001',
      'odd': '哔哩哔哩=a;b; c==',
    };

    late Directory dir;
    late String path;
    late MemorySink memory;
    late DpapiKeychainStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dpapi_store_test');
      path = '${dir.path}\\support\\login.bin';
      final logger = Logger(session: 'test');
      memory = MemorySink();
      logger.add(memory);
      store = DpapiKeychainStore(path, logger: logger);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('a missing file, folder and all, loads as no cookies', () async {
      expect(await store.loadCookies(), isA<NoStoredCookies>());
      expect(memory.events, isEmpty);
    });

    test('a save makes the folder, and a load gives the cookies back unchanged', () async {
      expect(await store.saveCookies(cookies), isTrue);
      final loaded = await store.loadCookies();
      expect(loaded, isA<StoredCookies>());
      expect((loaded as StoredCookies).cookies, cookies);
    });

    test('a second save replaces the first', () async {
      expect(await store.saveCookies(cookies), isTrue);
      expect(await store.saveCookies({'SESSDATA': 'another-made-up'}), isTrue);
      final loaded = await store.loadCookies() as StoredCookies;
      expect(loaded.cookies, {'SESSDATA': 'another-made-up'});
    });

    test('the file holds no cookie value in UTF-8 or UTF-16', () async {
      expect(await store.saveCookies(cookies), isTrue);
      final bytes = File(path).readAsBytesSync();
      for (final value in cookies.values) {
        expect(_contains(bytes, utf8.encode(value)), isFalse, reason: 'UTF-8');
        expect(_contains(bytes, _utf16le(value)), isFalse, reason: 'UTF-16');
      }
    });

    test('no temporary file is left after a save', () async {
      expect(await store.saveCookies(cookies), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse);
      expect(Directory('${dir.path}\\support').listSync().map((e) => e.uri.pathSegments.last), ['login.bin']);
    });

    test('an empty save deletes the file', () async {
      expect(await store.saveCookies(cookies), isTrue);
      expect(await store.saveCookies(const {}), isTrue);
      expect(File(path).existsSync(), isFalse);
      expect(await store.loadCookies(), isA<NoStoredCookies>());
    });

    test('a delete removes the file and a temporary one a dead save left', () async {
      expect(await store.saveCookies(cookies), isTrue);
      File('$path.tmp').writeAsBytesSync([1, 2, 3]);
      await store.deleteCookies();
      expect(File(path).existsSync(), isFalse);
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('a delete with nothing stored completes', () async {
      await store.deleteCookies();
      Directory('${dir.path}\\support').createSync();
      await store.deleteCookies();
    });

    test('a delete that fails throws', () async {
      Directory(path).createSync(recursive: true);
      File('$path\\inside').writeAsBytesSync([0]);
      await expectLater(store.deleteCookies(), throwsA(isA<FileSystemException>()));
    });

    test('a corrupted file loads as a failure with its Win32 code, and is left alone', () async {
      expect(await store.saveCookies(cookies), isTrue);
      final bytes = File(path).readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0xff;
      File(path).writeAsBytesSync(bytes);

      final loaded = await store.loadCookies();
      expect(loaded, isA<CookieLoadFailed>());
      expect((loaded as CookieLoadFailed).status, isNot(anyOf(0, DpapiKeychainStore.badContentsStatus)));
      expect(File(path).readAsBytesSync(), bytes);
      final event = memory.events.single;
      expect(event.level, LogLevel.error);
      expect(event.f['status']?.toJson(), loaded.status);
    });

    test('a file that decrypts to no cookie map loads as a failure, and is left alone', () async {
      Directory('${dir.path}\\support').createSync();
      for (final text in ['SESSDATA=made-up', '["made-up"]', '{"SESSDATA": 7}']) {
        final sealed = _protect(utf8.encode(text));
        File(path).writeAsBytesSync(sealed);
        final loaded = await store.loadCookies();
        expect(loaded, isA<CookieLoadFailed>(), reason: text);
        expect((loaded as CookieLoadFailed).status, DpapiKeychainStore.badContentsStatus, reason: text);
        expect(File(path).readAsBytesSync(), sealed, reason: text);
      }
      for (final event in memory.events) {
        expect(event.encode(), isNot(contains('made-up')));
      }
    });

    test('a failed write answers false, keeps the old login, cleans up, and logs no value', () async {
      expect(await store.saveCookies(cookies), isTrue);
      final before = File(path).readAsBytesSync();
      // Windows won't rename over a file another handle holds open without delete sharing.
      final held = File(path).openSync(mode: FileMode.append);
      try {
        expect(await store.saveCookies({'SESSDATA': 'made-up-new'}), isFalse);
      } finally {
        held.closeSync();
      }
      expect(File(path).readAsBytesSync(), before);
      expect(File('$path.tmp').existsSync(), isFalse);
      final event = memory.events.single;
      expect(event.level, LogLevel.error);
      expect(event.f['step']?.toJson(), 'write');
      expect(event.f['status']?.toJson(), isNot(0));
      expect(event.encode(), isNot(contains('made-up')));
    });

    test('the app token is never kept', () async {
      expect(await store.loadAppToken(), isNull);
      expect(await store.saveAppToken('made-up-token'), isFalse);
      await store.deleteAppToken();
      expect(dir.listSync(), isEmpty);
    });
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}

List<int> _utf16le(String text) => [
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
];

/// Seals [plain] as the store would, for files whose contents the store itself never writes.
Uint8List _protect(List<int> plain) {
  final data = calloc<Uint8>(plain.length);
  final inBlob = calloc<CRYPT_INTEGER_BLOB>();
  final outBlob = calloc<CRYPT_INTEGER_BLOB>();
  try {
    data.asTypedList(plain.length).setAll(0, plain);
    inBlob.ref
      ..cbData = plain.length
      ..pbData = data;
    final Win32Result(:value) = CryptProtectData(inBlob, null, null, null, 0x1, outBlob);
    expect(value, isTrue);
    return Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
  } finally {
    if (outBlob.ref.pbData != nullptr) LocalFree(HLOCAL(outBlob.ref.pbData));
    calloc.free(outBlob);
    calloc.free(inBlob);
    calloc.free(data);
  }
}
