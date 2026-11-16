import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/message/chat/chat_model.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 11, 12, 15, 34);

ChatMessage _text(int seqno, {int sender = 7}) =>
    ChatMessage(seqno: seqno, senderMid: sender, kind: ChatMessageKind.text, text: '演示$seqno', time: _at);

ChatSession _person({NoticeBox? box, int sessionType = 1}) =>
    ChatSession(talkerId: 7, name: '演示', face: '', lastText: '', time: _at, box: box, sessionType: sessionType);

ChatModel _model(FakeMessageApi api, {ChatSession? session}) {
  final model = ChatModel(
    api: api,
    session: session ?? _person(),
    selfMid: () => 1,
    logger: Logger(session: 'test'),
  );
  addTearDown(model.dispose);
  return model;
}

void main() {
  test('the first page, then older pages before the oldest shown, until none are left', () async {
    final api = FakeMessageApi(
      pageSize: 4,
      chats: {
        7: [for (var seqno = 1; seqno <= 10; seqno++) _text(seqno)],
      },
    );
    final model = _model(api);

    final page = await model.start();
    expect(page!.maxSeqno, 10);
    expect(model.messages.map((message) => message.seqno), [7, 8, 9, 10]);
    expect(model.hasMore, isTrue);

    await model.loadOlder();
    expect(model.messages.map((message) => message.seqno), [3, 4, 5, 6, 7, 8, 9, 10]);
    await model.loadOlder();
    expect(model.messages.first.seqno, 1);
    expect(model.hasMore, isFalse);
    await model.loadOlder();
    expect(api.calls, ['messages 7 0', 'messages 7 7', 'messages 7 3']);
  });

  test('older pages are asked one at a time; a failure stops them until a retry', () async {
    final api = FakeMessageApi(
      pageSize: 2,
      chats: {
        7: [for (var seqno = 1; seqno <= 6; seqno++) _text(seqno)],
      },
    );
    final model = _model(api);
    await model.start();

    final hold = api.holds['messages'] = Completer<void>();
    final first = model.loadOlder();
    unawaited(model.loadOlder());
    expect(api.calls, ['messages 7 0', 'messages 7 5']);
    api.holds.clear();
    hold.complete();
    await first;

    api.failures['messages'] = const BiliError.http(502);
    await model.loadOlder();
    expect(model.olderFailed, isTrue);
    await model.loadOlder();
    expect(api.calls.where((call) => call == 'messages 7 3'), hasLength(1));

    api.failures.clear();
    model.retryOlder();
    await Future<void>.delayed(Duration.zero);
    expect(model.olderFailed, isFalse);
    expect(model.messages.first.seqno, 1);
  });

  test('a sent message shows at once and is replaced by the answer; a failure takes it away', () async {
    final api = FakeMessageApi(
      selfMid: 1,
      chats: {
        7: [_text(1)],
      },
    );
    final model = _model(api);
    await model.start();

    final hold = api.holds['send'] = Completer<void>();
    final sending = model.send('你好');
    expect(model.messages.last.text, '你好');
    expect(model.isPending(model.messages.last), isTrue);
    expect(model.isOwn(model.messages.last), isTrue);
    api.holds.clear();
    hold.complete();
    await sending;
    expect(model.messages.last.seqno, 2);
    expect(model.isPending(model.messages.last), isFalse);

    api.failures['send'] = const BiliError.api(code: 21046, message: '发送过于频繁');
    await expectLater(model.send('再来'), throwsA(isA<BiliAPIError>()));
    expect(model.messages.map((message) => message.text), ['演示1', '你好']);
  });

  test('the bar is a person\'s, shown unless they were followed when the chat opened', () async {
    final api = FakeMessageApi(chatSettingsOf: {7: const ChatSettings(pushOn: false)});
    final model = _model(api);
    await model.loadSettings();
    expect(model.showsBar, isTrue);
    expect(model.following, isFalse);

    await model.follow();
    expect(model.following, isTrue);
    expect(model.showsBar, isTrue);
    await model.togglePush();
    expect(model.settings!.pushOn, isTrue);
    expect(api.pushes, [(talkerId: 7, on: true)]);

    model.followChanged(false);
    expect(model.following, isFalse);
  });

  test('notice boxes and groups have no bar, and nothing of theirs is the account\'s', () async {
    final api = FakeMessageApi(selfMid: 1);
    final box = _model(api, session: _person(box: NoticeBox.service));
    await box.loadSettings();
    expect(box.isPerson, isFalse);
    expect(box.showsBar, isFalse);
    expect(box.isOwn(_text(1, sender: 1)), isFalse);
    expect(_model(api, session: _person(sessionType: 2)).isPerson, isFalse);
    expect(api.calls.where((call) => call.startsWith('chatSettings')), isEmpty);
  });
}
