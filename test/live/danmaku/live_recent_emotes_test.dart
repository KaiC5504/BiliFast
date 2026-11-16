import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/live/danmaku/live_recent_emotes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  final logger = Logger(session: 'test');

  setUp(() async => folder = await Directory.systemTemp.createTemp('live_recent'));
  tearDown(() => folder.delete(recursive: true));

  String path() => '${folder.path}${Platform.pathSeparator}${LiveRecentEmotes.fileName}';

  test('the emotes used are kept across launches, newest first, each once', () async {
    final store = await LiveRecentEmotes.load(path(), logger: logger);
    expect(store.list, isEmpty);
    store
      ..record(const LiveEmote(text: '[dog]', url: 'https://i0.hdslb.com/dog.png', unique: 'emoji_1'))
      ..record(const LiveEmote(text: '赞', url: 'https://i0.hdslb.com/zan.png', unique: 'room_zan', width: 162))
      ..record(const LiveEmote(text: '[dog]', url: 'https://i0.hdslb.com/dog.png', unique: 'emoji_1'));
    await store.settle();

    final again = await LiveRecentEmotes.load(path(), logger: logger);
    expect(again.list.map((emote) => emote.unique), ['emoji_1', 'room_zan']);
    expect(again.list.last.width, 162);
    expect(again.list.last.url, 'https://i0.hdslb.com/zan.png');
  });

  test('at most the limit', () async {
    final store = await LiveRecentEmotes.load(path(), logger: logger);
    for (var i = 0; i < LiveRecentEmotes.limit + 5; i++) {
      store.record(LiveEmote(text: '[$i]', url: '', unique: 'e$i'));
    }
    expect(store.list, hasLength(LiveRecentEmotes.limit));
    expect(store.list.first.unique, 'e${LiveRecentEmotes.limit + 4}');
    await store.settle();
  });

  test('an unreadable file is set aside and the list starts empty', () async {
    await File(path()).writeAsString('{not json');
    final store = await LiveRecentEmotes.load(path(), logger: logger);
    expect(store.list, isEmpty);
    expect(File('${path()}.bad').existsSync(), isTrue);
  });
}
