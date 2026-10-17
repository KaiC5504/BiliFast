import 'dart:async';

import 'package:bilifast/account/cookie_persistence.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKeychain implements KeychainStore {
  FakeKeychain(this.next);

  CookieLoad next;
  final saved = <Map<String, String>>[];
  Completer<void>? gate;

  @override
  Future<CookieLoad> loadCookies() async => next;

  @override
  Future<bool> saveCookies(Map<String, String> cookies) async {
    saved.add(cookies);
    await gate?.future;
    return true;
  }

  @override
  Future<void> deleteCookies() async {}
  @override
  Future<String?> loadAppToken() async => null;
  @override
  Future<bool> saveAppToken(String token) async => true;
  @override
  Future<void> deleteAppToken() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stored cookies start the jar and later changes are written', () async {
    final keychain = FakeKeychain(const StoredCookies({'SESSDATA': 's', 'bili_jct': 'j'}));
    final persistence = CookiePersistence(keychain);
    expect(await persistence.load(), {'SESSDATA': 's', 'bili_jct': 'j'});
    await persistence.save({'SESSDATA': 's', 'bili_jct': 'j', 'buvid3': 'b'});
    expect(keychain.saved.single['buvid3'], 'b');
  });

  test('after a failed read nothing is written until login or logout', () async {
    final keychain = FakeKeychain(const CookieLoadFailed(-25308));
    final persistence = CookiePersistence(keychain);
    expect(await persistence.load(), isEmpty);
    expect(persistence.blocked, isTrue);
    await persistence.save({'buvid3': 'b'});
    expect(keychain.saved, isEmpty);
    persistence.unblock();
    await persistence.save({'SESSDATA': 'new'});
    expect(keychain.saved.single, {'SESSDATA': 'new'});
  });

  test('a later successful read lifts the block', () async {
    final keychain = FakeKeychain(const CookieLoadFailed(-25308));
    final persistence = CookiePersistence(keychain);
    await persistence.load();
    keychain.next = const NoStoredCookies();
    await persistence.load();
    await persistence.save({'buvid3': 'b'});
    expect(keychain.saved, hasLength(1));
  });

  test('changes during a write collapse into one write of the latest state', () async {
    final keychain = FakeKeychain(const NoStoredCookies())..gate = Completer<void>();
    final persistence = CookiePersistence(keychain);
    await persistence.load();
    final first = persistence.save({'a': '1'});
    unawaited(persistence.save({'a': '2'}));
    unawaited(persistence.save({'a': '3'}));
    keychain.gate!.complete();
    await first;
    expect(keychain.saved, [
      {'a': '1'},
      {'a': '3'},
    ]);
  });

  group('channel format', () {
    const channel = MethodChannel('bilifast/keychain');
    final calls = <MethodCall>[];
    Object? Function(MethodCall) reply = (_) => null;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
    });

    test('reads the three load outcomes', () async {
      final store = ChannelKeychainStore();
      reply = (_) => {
        'status': 'cookies',
        'cookies': {'SESSDATA': 's'},
      };
      expect(await store.loadCookies(), isA<StoredCookies>().having((c) => c.cookies, 'cookies', {'SESSDATA': 's'}));
      reply = (_) => {'status': 'notFound'};
      expect(await store.loadCookies(), isA<NoStoredCookies>());
      reply = (_) => {'status': 'failed', 'code': -25308};
      expect(await store.loadCookies(), isA<CookieLoadFailed>().having((f) => f.status, 'status', -25308));
    });

    test('sends cookies as a name to value map', () async {
      reply = (_) => {'ok': true};
      expect(await ChannelKeychainStore().saveCookies({'SESSDATA': 's'}), isTrue);
      expect(calls.single.method, 'saveCookies');
      expect(calls.single.arguments, {
        'cookies': {'SESSDATA': 's'},
      });
    });

    test('an empty token reads as none', () async {
      reply = (_) => <String, Object?>{};
      expect(await ChannelKeychainStore().loadAppToken(), isNull);
      reply = (_) => {'token': 't'};
      expect(await ChannelKeychainStore().loadAppToken(), 't');
    });
  });
}
