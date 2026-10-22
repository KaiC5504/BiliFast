import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/me/me_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = MeProfile(
    mid: 2233,
    name: '保存的名字',
    face: 'https://i0.hdslb.com/bfs/face/saved.jpg',
    pendant: 'https://i0.hdslb.com/bfs/garb/item/frame.png',
    level: 5,
    coins: 878.5,
    bcoin: 2,
    vip: true,
    vipLabel: '年度大会员',
    vipBadge: true,
  );
  const counts = MeCounts(dynamics: 3, following: 13, followers: 12000);

  late Directory folder;
  late String path;
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('me_profile');
    path = '${folder.path}${Platform.pathSeparator}me.json';
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  String logged() => sink.events.map((event) => '${event.toJson()}').join();

  test('what is saved comes back on the next launch, field for field', () async {
    final store = await MeProfileStore.load(path, logger: logger);
    expect(store.kept, isNull);
    store.save(2233, const MeShown(profile, counts));
    await store.settle();
    expect(File('$path.tmp').existsSync(), isFalse, reason: 'written beside it, then renamed over it');

    final again = await MeProfileStore.load(path, logger: logger);
    expect(again.kept, (mid: 2233, view: const MeShown(profile, counts)));
  });

  test('a profile without mid, pendant or counts comes back as it was', () async {
    const bare = MeShown(MeProfile(name: '无号', face: '', level: 0, coins: 0, bcoin: 0), null);
    final store = await MeProfileStore.load(path, logger: logger);
    store.save(7, bare);
    await store.settle();
    expect((await MeProfileStore.load(path, logger: logger)).kept, (mid: 7, view: bare));
  });

  test('the newest save lands last', () async {
    final store = await MeProfileStore.load(path, logger: logger);
    for (var level = 1; level <= 5; level++) {
      store.save(1, MeShown(MeProfile(mid: 1, name: 'n', face: '', level: level, coins: 0, bcoin: 0), null));
    }
    await store.settle();
    expect((await MeProfileStore.load(path, logger: logger)).kept?.view.profile.level, 5);
  });

  test('delete removes the file', () async {
    final store = await MeProfileStore.load(path, logger: logger);
    store.save(2233, const MeShown(profile, counts));
    store.delete();
    expect(store.kept, isNull);
    await store.settle();
    expect(File(path).existsSync(), isFalse);
    expect((await MeProfileStore.load(path, logger: logger)).kept, isNull);
  });

  for (final (name, text) in [
    ('not JSON', '{"mid": 2233, "profile": {"name": "保存的名'),
    ('not an object', '["保存的名字"]'),
    ('no mid', '{"profile": {"name": "保存的名字"}}'),
    ('a field of the wrong type', '{"mid": 2233, "profile": {"name": "保存的名字", "face": 1, "level": 5}}'),
  ]) {
    test('a file $name starts empty, logs why without its contents, and is deleted', () async {
      File(path).writeAsStringSync(text);
      final store = await MeProfileStore.load(path, logger: logger);
      expect(store.kept, isNull);
      await store.settle();
      expect(File(path).existsSync(), isFalse);
      final warning = sink.events.singleWhere((event) => event.msg == 'me profile unreadable, starting empty');
      expect(warning.level, LogLevel.warn);
      expect(warning.f['file']?.toJson(), 'me.json');
      expect(logged(), isNot(contains('保存的名')));
    });
  }

  test('in memory it keeps the account for the run only', () {
    final store = MeProfileStore.memory(logger: logger)..save(1, const MeShown(profile, null));
    expect(store.kept?.mid, 1);
    store.delete();
    expect(store.kept, isNull);
    expect(sink.events, isEmpty);
  });

  test('nothing of the account reaches the log', () async {
    final store = await MeProfileStore.load(path, logger: logger);
    store.save(2233, const MeShown(profile, counts));
    await store.settle();
    await MeProfileStore.load(path, logger: logger);
    store.delete();
    await store.settle();
    for (final secret in ['保存的名字', 'hdslb', '2233']) {
      expect(logged(), isNot(contains(secret)));
    }
  });
}
