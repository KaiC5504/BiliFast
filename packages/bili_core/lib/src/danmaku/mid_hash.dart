import 'dart:convert';

/// The `midHash` on a danmaku is the CRC-32 of the sender's uid, which is how a user block rule matches.
abstract final class MidHash {
  static final List<int> _table = List<int>.generate(256, (index) {
    var c = index;
    for (var k = 0; k < 8; k++) {
      c = c & 1 == 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    return c;
  }, growable: false);

  static String of(int uid) {
    var crc = 0xFFFFFFFF;
    for (final byte in ascii.encode(uid.toString())) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF).toRadixString(16);
  }
}
