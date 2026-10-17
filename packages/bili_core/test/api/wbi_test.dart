import 'package:bili_core/api.dart';
import 'package:bili_core/src/api/md5.dart';
import 'package:test/test.dart';

void main() {
  // MD5 now comes from package:crypto; the vectors stay to prove the wrapper.
  test('MD5 vectors', () {
    expect(MD5.hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(MD5.hex('a'), '0cc175b9c0f1b6a831c399e269772661');
    expect(MD5.hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
    expect(MD5.hex('message digest'), 'f96b697d7cb7938d525a2f31aaf161d0');
    expect(MD5.hex('The quick brown fox jumps over the lazy dog'), '9e107d9d372bb6826bd81d3542a419d6');
    expect(MD5.hex('x' * 1000).length, 32);
  });

  test('mixin key', () {
    expect(WBI.mixinKey(imgKey: '7cd084941338484aae1ad9425b84077c', subKey: '4932caff0ff746eab6f01bf08b70ac45'),
        'ea1db124af3c7062474693fa704f4ff8');
  });

  test('key from URL', () {
    expect(WBI.keyFromURL('https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png'),
        '7cd084941338484aae1ad9425b84077c');
  });

  test('signed query reference vector', () {
    final query = WBI.signedQuery({'foo': '114', 'bar': '514', 'zab': '1919810'},
        mixinKey: 'ea1db124af3c7062474693fa704f4ff8', wts: 1702204169);
    expect(query, 'bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4');
  });

  test('signed query filters and encodes', () {
    final query =
        WBI.signedQuery({'keyword': '中文 a+b!(x)'}, mixinKey: 'ea1db124af3c7062474693fa704f4ff8', wts: 1700000000);
    expect(query, 'keyword=%E4%B8%AD%E6%96%87%20a%2Bbx&wts=1700000000&w_rid=391f961efc403664b08d417a32bbba8b');
  });
}
