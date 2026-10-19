import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/cookie_persistence.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySink memory;

  CookiePersistence persistenceOver(FakeKeychain keychain) {
    final logger = Logger(session: 'test');
    memory = MemorySink();
    logger.add(memory);
    return CookiePersistence(keychain, logger: logger);
  }

  Iterable<String> errors() => [
    for (final event in memory.events)
      if (event.level == LogLevel.error) event.msg,
  ];

  group('a read that started before a login or logout', () {
    test('failing, it doesn\'t block the writes again', () async {
      final keychain = FakeKeychain(const CookieLoadFailed(-25308));
      final persistence = persistenceOver(keychain);
      await persistence.load();
      keychain.loadGate = Completer<void>();
      final reread = persistence.reload();
      persistence.unblock();
      keychain.loadGate!.complete();
      expect(await reread, isNull);
      expect(persistence.blocked, isFalse);
      expect(await persistence.save({'SESSDATA': 'new'}), isTrue);
      expect(keychain.saved.single, {'SESSDATA': 'new'});
    });

    test('succeeding, its cookies are not handed out', () async {
      final keychain = FakeKeychain(const CookieLoadFailed(-25308));
      final persistence = persistenceOver(keychain);
      await persistence.load();
      keychain
        ..next = const StoredCookies({'SESSDATA': 'old'})
        ..loadGate = Completer<void>();
      final reread = persistence.reload();
      persistence.unblock();
      keychain.loadGate!.complete();
      expect(await reread, isNull);
    });

    test('a read that started after it counts as usual', () async {
      final keychain = FakeKeychain(const CookieLoadFailed(-25308));
      final persistence = persistenceOver(keychain);
      persistence.unblock();
      expect(await persistence.reload(), isEmpty);
      expect(persistence.blocked, isTrue);
    });
  });

  group('a write the keychain refuses', () {
    test(
      'is logged as an error with no values, and save and flush answer false',
      () async {
        final keychain = FakeKeychain(const NoStoredCookies())..saveOk = false;
        final persistence = persistenceOver(keychain);
        await persistence.load();
        final saving = persistence.save({'SESSDATA': 'secret-sess'});
        expect(await persistence.flush(), isFalse);
        expect(await saving, isFalse);
        expect(errors(), ['cookie save refused']);
        expect(
          memory.events.map((event) => event.encode()).join(),
          isNot(contains('secret-sess')),
        );

        keychain.saveOk = true;
        expect(await persistence.save({'SESSDATA': 'x'}), isTrue);
        expect(await persistence.flush(), isTrue);
      },
    );

    test(
      'that throws is logged too, and the writes after it still go out',
      () async {
        final keychain = _ThrowingOnce(const NoStoredCookies());
        final persistence = persistenceOver(keychain);
        expect(await persistence.save({'a': '1'}), isFalse);
        expect(errors(), ['cookie save threw']);
        expect(await persistence.save({'a': '2'}), isTrue);
        expect(keychain.saved.last, {'a': '2'});
      },
    );
  });

  test('held back after a failed read, save answers false', () async {
    final persistence = persistenceOver(
      FakeKeychain(const CookieLoadFailed(-25308)),
    );
    await persistence.load();
    expect(await persistence.save({'a': '1'}), isFalse);
  });
}

class _ThrowingOnce extends FakeKeychain {
  _ThrowingOnce(super.next);

  var _threw = false;

  @override
  Future<bool> saveCookies(Map<String, String> cookies) async {
    if (!_threw) {
      _threw = true;
      throw PlatformException(code: 'keychain');
    }
    return super.saveCookies(cookies);
  }
}
