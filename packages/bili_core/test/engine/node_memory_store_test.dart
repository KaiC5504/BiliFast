import 'dart:io';

import 'package:bili_core/engine.dart';
import 'package:bili_core/src/engine/node_memory_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('node_memory'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a saved memory loads again in the next launch', () {
    final store = NodeMemoryStore('${dir.path}/nested/node_memory.json');
    final memory = NodeMemory()
      ..signature = 'lan:abc'
      ..record('upos-sz-mirroraliov.bilivideo.com', ttfbMs: 30, bps: 17.5e6);
    store.save(memory);
    expect(File('${store.path}.tmp').existsSync(), isFalse);
    final loaded = store.load()..signature = 'lan:abc';
    expect(loaded.prior('upos-sz-mirroraliov.bilivideo.com')?.ttfbMs, 30);
  });

  test('a missing or broken file starts an empty memory', () {
    final store = NodeMemoryStore('${dir.path}/node_memory.json');
    expect((store.load()..signature = 'lan:abc').prior('upos-sz-mirroraliov.bilivideo.com'), isNull);
    File(store.path).writeAsStringSync('{not json');
    expect((store.load()..signature = 'lan:abc').prior('upos-sz-mirroraliov.bilivideo.com'), isNull);
  });

  test('the network signature never holds an address', () async {
    final signature = await NodeMemoryStore.networkSignature();
    expect(signature, anyOf('', 'cellular', matches(RegExp(r'^lan:[0-9a-f]{12}$'))));
  });
}
