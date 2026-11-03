import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/sideload/provision_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// A made-up profile: binary bytes around a plist, as the CMS envelope has them. Never a real one, which names its
/// owner and devices.
List<int> profile(String plist) => [
  0x30, 0x82, 0x2b, 0x1f, 0x06, 0x09, 0x2a, 0x86, 0xff, 0x00, //
  ...utf8.encode(plist),
  0xa0, 0x82, 0x0e, 0x00, 0x30, 0xff, 0xfe,
];

String plist({String date = '<date>2026-11-11T08:30:00Z</date>'}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AppIDName</key>
	<string>Café Made Up</string>
	<key>CreationDate</key>
	<date>2026-11-04T08:30:00Z</date>
	<key>ExpirationDate</key>
	$date
	<key>TimeToLive</key>
	<integer>7</integer>
</dict>
</plist>''';

void main() {
  group('provisionExpiry', () {
    test('reads ExpirationDate from the plist inside the envelope, in UTC', () {
      final expires = provisionExpiry(profile(plist()));
      expect(expires, DateTime.utc(2026, 11, 11, 8, 30));
      expect(expires!.isUtc, isTrue);
    });

    test('takes ExpirationDate, not the first date', () {
      expect(provisionExpiry(profile(plist(date: '<date>2027-11-04T00:00:00Z</date>'))), DateTime.utc(2027, 11, 4));
    });

    test('no plist, an unclosed plist, no date or a date without its Z read as nothing', () {
      expect(provisionExpiry([0x30, 0x82, 0x01, 0x00]), isNull);
      expect(provisionExpiry(profile(plist()).sublist(0, 200)), isNull);
      expect(provisionExpiry(profile(plist(date: '<string>soon</string>'))), isNull);
      expect(provisionExpiry(profile(plist(date: '<date>2026-11-11T08:30:00</date>'))), isNull);
      expect(provisionExpiry(profile(plist(date: '<date>not a date Z</date>'))), isNull);
    });
  });

  group('ProvisionSignatureSource', () {
    late Directory bundle;
    late MemorySink logs;
    late Logger logger;

    setUp(() {
      bundle = Directory.systemTemp.createTempSync('provision_test');
      logs = MemorySink();
      logger = Logger(session: 'test')..add(logs);
    });

    tearDown(() => bundle.deleteSync(recursive: true));

    File file() => File('${bundle.path}${Platform.pathSeparator}embedded.mobileprovision');

    test('a bundle without a profile is not sideloaded, and says nothing', () async {
      expect(await ProvisionSignatureSource(bundle: bundle, logger: logger).read(), isNull);
      expect(logs.events, isEmpty);
    });

    test("the profile in the app's folder gives the signature", () async {
      file().writeAsBytesSync(profile(plist()));
      final info = await ProvisionSignatureSource(bundle: bundle, logger: logger).read();
      expect(info?.expires, DateTime.utc(2026, 11, 11, 8, 30));
    });

    test('a profile without a date is nothing, logged', () async {
      file().writeAsBytesSync(profile(plist(date: '')));
      expect(await ProvisionSignatureSource(bundle: bundle, logger: logger).read(), isNull);
      expect(logs.events.single.msg, 'sideload profile has no expiry');
    });
  });
}
