import 'package:bili_core/api.dart';
import 'package:test/test.dart';

void main() {
  test('accepts bilibili and subdomains', () {
    for (final host in ['.bilibili.com', 'bilibili.com', 'www.bilibili.com', 'BILIBILI.COM', '.Passport.Bilibili.com']) {
      expect(BiliHosts.isBilibili(host), isTrue, reason: host);
    }
  });

  test('rejects lookalikes', () {
    for (final host in ['evilbilibili.com', 'bilibili.com.evil.com', 'notbilibili.com', '', '.', 'bilibili.co']) {
      expect(BiliHosts.isBilibili(host), isFalse, reason: host);
    }
  });
}
