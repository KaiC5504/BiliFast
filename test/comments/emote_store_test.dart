import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/comments/emote_store.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

Emote emote(int index) => Emote(token: '[e$index]', url: 'https://example.invalid/$index.png', large: false);

List<String> tokens(RecentEmotes recent) => [for (final emote in recent.list) emote.token];

void main() {
  group('最近使用', () {
    late Directory folder;
    late String path;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('emotes');
      path = '${folder.path}${Platform.pathSeparator}emotes_recent.json';
    });
    tearDown(() => folder.delete(recursive: true));

    test('most recent first, one entry per token, and at most 14', () async {
      final recent = await RecentEmotes.load(null, logger: Logger(session: 'test'));
      expect(recent.list, isEmpty);
      for (var index = 0; index < 20; index++) {
        recent.record(emote(index));
      }
      recent.record(emote(10));

      expect(recent.list, hasLength(RecentEmotes.limit));
      expect(tokens(recent), [
        '[e10]',
        '[e19]',
        '[e18]',
        '[e17]',
        '[e16]',
        '[e15]',
        '[e14]',
        '[e13]',
        '[e12]',
        '[e11]',
        '[e9]',
        '[e8]',
        '[e7]',
        '[e6]',
      ]);
      expect(recent.list.first.url, 'https://example.invalid/10.png');
    });

    test('kept across launches as JSON at the path it was loaded from', () async {
      final nested = '${folder.path}${Platform.pathSeparator}sub${Platform.pathSeparator}emotes_recent.json';
      final recent = await RecentEmotes.load(nested, logger: Logger(session: 'test'));
      recent
        ..record(emote(1))
        ..record(const Emote(token: '(⌒▽⌒)', url: '', large: false))
        ..record(const Emote(token: '[tv_doge]', url: 'https://example.invalid/tv.png', large: true));
      await recent.settle();

      final again = await RecentEmotes.load(nested, logger: Logger(session: 'test'));
      expect(again.list, recent.list);
      expect(again.list.first.large, isTrue);
      expect(jsonDecode(await File(nested).readAsString()), [
        {'token': '[tv_doge]', 'url': 'https://example.invalid/tv.png', 'large': true},
        {'token': '(⌒▽⌒)', 'url': '', 'large': false},
        {'token': '[e1]', 'url': 'https://example.invalid/1.png', 'large': false},
      ]);
    });

    test('with no file yet the list starts empty', () async {
      final recent = await RecentEmotes.load(path, logger: Logger(session: 'test'));
      expect(recent.list, isEmpty);
      expect(File(path).existsSync(), isFalse, reason: 'nothing is written until an emote is used');
    });

    test('a file that is not a JSON list is set aside as .bad and the list starts empty', () async {
      await File(path).writeAsString('{not json');
      final logs = MemorySink();
      final recent = await RecentEmotes.load(path, logger: Logger(session: 'test')..add(logs));
      expect(recent.list, isEmpty);
      expect(await File('$path.bad').readAsString(), '{not json');
      expect(logs.events.single.msg, 'recent emotes unreadable, starting empty');

      recent.record(emote(1));
      await recent.settle();
      expect(tokens(await RecentEmotes.load(path, logger: Logger(session: 'test'))), ['[e1]']);
    });

    test('entries that don\'t read are dropped one by one', () async {
      await File(path).writeAsString(
        jsonEncode([
          {'token': '[e1]', 'url': 'u', 'large': false},
          {'token': '[e2]', 'url': 'u'},
          {'token': '', 'url': 'u', 'large': false},
          'not an entry',
          {'token': '[e3]', 'url': 'u', 'large': true},
        ]),
      );
      final logs = MemorySink();
      final recent = await RecentEmotes.load(path, logger: Logger(session: 'test')..add(logs));
      expect(tokens(recent), ['[e1]', '[e3]']);
      expect(logs.events.single.f['skipped']?.toJson(), 3);
    });

    test('a write that fails is logged and the list in memory stays', () async {
      final blocked = '${folder.path}${Platform.pathSeparator}taken';
      await File(blocked).writeAsString('a file where the folder should be');
      final logs = MemorySink();
      final recent = await RecentEmotes.load(
        '$blocked${Platform.pathSeparator}emotes_recent.json',
        logger: Logger(session: 'test')..add(logs),
      );
      recent.record(emote(1));
      await recent.settle();
      expect(tokens(recent), ['[e1]']);
      expect(logs.events.single.msg, 'recent emotes not saved');
    });
  });

  group('the emote catalog', () {
    const packages = [
      EmotePackage(
        id: 1,
        name: '小黄脸',
        icon: '',
        isText: false,
        emotes: [Emote(token: '[doge]', url: 'u', large: false)],
      ),
    ];

    test('composers asking at once share one call, and later ones get the same packages', () async {
      final api = FakePageApi()..emotes = packages;
      final catalog = EmoteCatalog(logger: Logger(session: 'test'));
      final answers = await Future.wait([catalog.load(api), catalog.load(api)]);
      expect(answers, [packages, packages]);
      expect(await catalog.load(api), packages);
      expect(api.calls, ['emotePackages']);
    });

    test('a failure reaches the caller and is forgotten, so the next composer asks again', () async {
      final api = FakePageApi()..failures['emotePackages'] = const BiliError.http(500);
      final catalog = EmoteCatalog(logger: Logger(session: 'test'));
      await expectLater(catalog.load(api), throwsA(isA<BiliHTTPError>()));

      api
        ..failures.clear()
        ..emotes = packages;
      expect(await catalog.load(api), packages);
      expect(api.calls, ['emotePackages', 'emotePackages']);
    });

    test('an empty answer is asked again next time, as Swift did', () async {
      final api = FakePageApi();
      final catalog = EmoteCatalog(logger: Logger(session: 'test'));
      expect(await catalog.load(api), isEmpty);
      api.emotes = packages;
      expect(await catalog.load(api), packages);
      expect(api.calls, hasLength(2));
    });

    test('another api asks its own', () async {
      final catalog = EmoteCatalog(logger: Logger(session: 'test'));
      final first = FakePageApi()..emotes = packages;
      final second = FakePageApi()..emotes = const [];
      await catalog.load(first);
      expect(await catalog.load(second), isEmpty);
      expect(second.calls, ['emotePackages']);
    });

    test('a call held at the server is shared until it answers', () async {
      final api = FakePageApi()..emotes = packages;
      final hold = api.holds['emotePackages'] = Completer<void>();
      final catalog = EmoteCatalog(logger: Logger(session: 'test'));
      final first = catalog.load(api);
      final second = catalog.load(api);
      hold.complete();
      expect(await first, packages);
      expect(await second, packages);
      expect(api.calls, hasLength(1));
    });
  });
}
