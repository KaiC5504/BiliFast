import 'package:bili_core/api.dart';
import 'package:bilifast/message/message_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final time = DateTime(2026, 11, 16, 12);

  ChatSession session(int talker, {String name = '', int type = 1, String face = '', bool vipPink = false}) =>
      ChatSession(
        talkerId: talker,
        sessionType: type,
        name: name,
        face: face,
        lastText: '演示消息',
        time: time,
        unread: 2,
        ackSeqno: 3,
        maxSeqno: 5,
        vipPink: vipPink,
      );

  test('the two counts make one: msgfeed\'s four and 私信\'s', () {
    final counts = ClientMessageApi.combineUnread((reply: 2, at: 1, like: 4, system: 3), 5);
    expect(counts, const MessageUnread(reply: 2, at: 1, like: 4, system: 3, chat: 5));
    expect(counts.total, 15);
  });

  test('cards are asked for the bare people only, each once; groups and named sessions are left out', () {
    final sessions = [
      session(11),
      session(12, name: '演示有名字'),
      session(13),
      session(11),
      session(14, type: 2),
      session(0),
    ];
    expect(ClientMessageApi.unnamedTalkers(sessions), [11, 13]);
    expect(ClientMessageApi.unnamedTalkers([session(12, name: '演示有名字')]), isEmpty);
  });

  test('a card names its session and brings its face, badges, verify and frame', () {
    final named = ClientMessageApi.namedSessions(
      [session(11), session(12, name: '演示有名字'), session(13)],
      const [
        ChatUserCard(
          mid: 11,
          name: '演示卡片',
          face: 'face-11',
          vipPink: true,
          bigVip: true,
          verify: DynamicVerify.organisation,
          pendant: 'frame-11',
        ),
        ChatUserCard(mid: 12, name: '演示另一个名字', face: 'face-12'),
      ],
    );
    final first = named[0];
    expect(first.name, '演示卡片');
    expect(first.face, 'face-11');
    expect(first.vipPink, isTrue);
    expect(first.bigVip, isTrue);
    expect(first.verify, DynamicVerify.organisation);
    expect(first.pendant, 'frame-11');
    expect(
      (first.talkerId, first.unread, first.ackSeqno, first.maxSeqno, first.lastText, first.time),
      (11, 2, 3, 5, '演示消息', time),
      reason: 'the session\'s own fields stay',
    );
    expect(named[1].name, '演示有名字', reason: 'a session with a name keeps it');
    expect(named[1].face, '');
    expect(named[2].name, '', reason: 'no card, still bare');
  });

  test('a chat already acked that far, or 系统通知 with no cursor, asks nothing', () async {
    final transport = _NoNetwork();
    final api = ClientMessageApi(
      BiliClient(transport: transport, cookies: CookieJar()),
      mid: () => 1,
    );
    await api.read(session(11), seqno: 3);
    await api.read(session(11), seqno: 2);
    final system = ChatSession(talkerId: 0, name: '系统通知', face: '', lastText: '', time: time, box: NoticeBox.system);
    await api.read(system, seqno: 0);
    expect(transport.asked, 0);
  });

  test('what a bare session has of its own wins over the card', () {
    final named = ClientMessageApi.namedSessions(
      [session(11, face: 'own-face', vipPink: true)],
      const [ChatUserCard(mid: 11, name: '演示卡片', face: 'card-face')],
    );
    expect(named.single.face, 'own-face');
    expect(named.single.vipPink, isTrue);
    expect(named.single.name, '演示卡片');
  });
}

/// Counts what would have gone out, and answers nothing.
class _NoNetwork implements HTTPTransport {
  int asked = 0;

  @override
  Future<HTTPResponse> send(HTTPRequest request) {
    asked++;
    throw StateError('no network in tests');
  }
}
