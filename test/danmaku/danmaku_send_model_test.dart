import 'dart:async';
import 'dart:io';

import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<(String, DanmakuStyle)> posted;
  late PlayerPrefs prefs;

  setUp(() {
    posted = [];
    prefs = PlayerPrefs.memory();
  });

  DanmakuSendModel model({Future<String?> Function(String, DanmakuStyle)? post}) => DanmakuSendModel(
    post ??
        (text, style) async {
          posted.add((text, style));
          return null;
        },
    prefs: prefs,
  );

  test('the text is cut to 100 characters, counting an emoji as one', () {
    final draft = model();
    draft.text = 'a' * 150;
    expect(draft.text, 'a' * 100);

    draft.text = '😀' * 101;
    expect(draft.text, '😀' * 100);

    draft.text = '刚好';
    expect(draft.text, '刚好');
  });

  test('nothing but spaces cannot be sent', () async {
    final draft = model()..text = '   ';
    expect(draft.canSend, isFalse);
    expect(await draft.send(), isNull);
    expect(posted, isEmpty);
  });

  test('a sent danmaku goes out trimmed in the chosen style, and the text clears', () async {
    const style = DanmakuStyle(size: DanmakuSize.small, position: DanmakuPosition.top, color: 0xE70012);
    final draft = model()
      ..text = '  前方高能  '
      ..style = style;

    expect(await draft.send(), isNull);

    expect(posted, [('前方高能', style)]);
    expect(draft.text, isEmpty);
    expect(draft.style, style, reason: 'the style lasts for the page');
    expect(draft.sending, isFalse);
  });

  test('a refusal comes back as the message to show, and the draft stays', () async {
    final draft = model(post: (text, style) async => '弹幕发送过于频繁')..text = '再来一条';
    expect(await draft.send(), '弹幕发送过于频繁');
    expect(draft.text, '再来一条');
    expect(draft.canSend, isTrue);
  });

  test('no second post while one is out', () async {
    final answer = Completer<String?>();
    var calls = 0;
    final draft = model(
      post: (text, style) {
        calls++;
        return answer.future;
      },
    )..text = '一条';

    final first = draft.send();
    expect(draft.sending, isTrue);
    expect(draft.canSend, isFalse);
    expect(await draft.send(), isNull);
    expect(calls, 1);

    answer.complete(null);
    expect(await first, isNull);
    expect(draft.sending, isFalse);
  });

  test("A's red dot is seen once for the app, and saved", () async {
    final folder = await Directory.systemTemp.createTemp('send_prefs');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}${Platform.pathSeparator}player_prefs.json';
    prefs = await PlayerPrefs.load(path);
    final draft = model();
    var notified = 0;
    draft.addListener(() => notified++);

    expect(draft.styleHintSeen, isFalse);
    draft.sawStyleHint();
    draft.sawStyleHint();
    expect(draft.styleHintSeen, isTrue);
    expect(notified, 1);

    await prefs.settle();
    expect((await PlayerPrefs.load(path)).danmakuStyleHintSeen, isTrue);
  });
}
