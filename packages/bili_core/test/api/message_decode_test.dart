import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:test/test.dart';

/// A raw message as fetch_session_msgs gives it, [content] serialised as the answer does.
Map<String, Object?> _message({
  required int seqno,
  int type = 1,
  Object? content = const {'content': '测试'},
  int sender = 20000921,
  int status = 0,
  int? source,
}) => {
  'sender_uid': sender,
  'msg_type': type,
  'content': content is String ? content : jsonEncode(content),
  'msg_seqno': seqno,
  'timestamp': 1760000000,
  'msg_key': seqno * 10,
  'msg_status': status,
  'msg_source': ?source,
};

ChatMessage _one(Map<String, Object?> message) => MessageDecode.messages({
  'messages': [message],
}).messages.single;

void main() {
  group('counts', () {
    test('missing counts read as 0; like falls back to recv_like', () {
      expect(MessageDecode.feedUnread(<String, Object?>{}), (reply: 0, at: 0, like: 0, system: 0));
      expect(MessageDecode.feedUnread({'recv_like': 4}).like, 4);
      expect(MessageDecode.chatUnread(<String, Object?>{}), 0);
      expect(MessageDecode.chatUnread({'follow_unread': 2, 'custom_unread': 9, 'biz_msg_follow_unread': 9}), 2);
    });
  });

  group('msgfeed pages', () {
    test('no cursor, is_end, an empty page or a cursor without an id end the list', () {
      final row = {'id': 1, 'item': <String, Object?>{}};
      expect(
        MessageDecode.replies({
          'items': [row],
        }, NoticeFeed.reply).next,
        isNull,
      );
      expect(
        MessageDecode.replies({
          'items': [row],
          'cursor': {'is_end': true, 'id': 1, 'time': 2},
        }, NoticeFeed.reply).next,
        isNull,
      );
      expect(
        MessageDecode.replies({
          'items': <Object?>[],
          'cursor': {'is_end': false, 'id': 1, 'time': 2},
        }, NoticeFeed.reply).next,
        isNull,
      );
      expect(
        MessageDecode.replies({
          'items': [row],
          'cursor': {'is_end': false, 'time': 2},
        }, NoticeFeed.reply).next,
        isNull,
      );
    });

    test('a row without user or item still decodes, empty', () {
      final notice = MessageDecode.replies({
        'items': [
          {'id': 7, 'reply_time': 1760000000},
        ],
      }, NoticeFeed.reply).items.single;
      expect((notice.user.mid, notice.user.name, notice.text, notice.targetText), (0, '', '', ''));
      expect((notice.canReply, notice.canLike, notice.liked), (true, true, false));
    });

    test('items that are not a list, and likes with no total, are empty pages', () {
      expect(MessageDecode.replies({'items': 'nope'}, NoticeFeed.at).items, isEmpty);
      final likes = MessageDecode.likes(<String, Object?>{}, firstPage: true);
      expect((likes.items.isEmpty, likes.next), (true, null));
    });

    test('a like row with no counts counts its likers; notice_state absent still notifies', () {
      final like = MessageDecode.likes({
        'total': {
          'items': [
            {
              'id': 1,
              'users': [
                {'mid': 1, 'nickname': '测试一'},
                'not a user',
                {'mid': 2, 'nickname': '测试二'},
              ],
            },
          ],
        },
      }, firstPage: false).items.single;
      expect((like.count, like.users.length, like.notifying), (2, 2, true));
    });
  });

  group('sessions', () {
    test('no sessions (null list) is an empty last page', () {
      final page = MessageDecode.sessions({'session_list': null, 'has_more': 0});
      expect((page.sessions.isEmpty, page.next), (true, null));
    });

    test('has_more with nothing decodable gives no next page', () {
      final page = MessageDecode.sessions({
        'session_list': [
          {'session_type': 1},
        ],
        'has_more': 1,
      });
      expect((page.sessions.isEmpty, page.next), (true, null));
    });

    ChatSession session(Map<String, Object?> lastMsg, {Map<String, Object?> extra = const {}}) =>
        MessageDecode.sessions({
          'session_list': [
            {'talker_id': 20000921, 'session_type': 1, 'session_ts': 1760000000000000, 'last_msg': lastMsg, ...extra},
          ],
        }).sessions.single;

    test('the last line as the website words it, per type', () {
      String last(int type, Object? content, {int sender = 20000921, int status = 0, int? source}) =>
          session(_message(seqno: 1, type: type, content: content, sender: sender, status: status, source: source))
              .lastText;
      expect(last(1, {'content': '你好'}), '你好');
      expect(last(1, {'content': '你好'}, source: 9), '[自动回复] 你好');
      expect(last(1, {'content': '你好'}, sender: 12345, status: 1), '你撤回了一条消息');
      expect(last(5, '7300000000000000001'), '对方撤回了一条消息');
      expect(last(2, {'url': 'x'}), '[图片]');
      expect(last(6, {'url': 'x'}), '[自定义表情]');
      expect(last(7, {'title': '测试分享', 'headline': ''}), '[分享]测试分享');
      expect(last(7, {'title': '测试转发', 'headline': '测试标题'}), '[转发]测试转发');
      expect(last(10, {'title': '测试通知'}), '测试通知');
      expect(last(11, {'title': '测试视频'}), '[视频]测试视频');
      expect(last(12, {'title': '测试文章'}), '[文章]测试文章');
      expect(last(13, {'title': '测试图卡'}), '测试图卡');
      expect(last(14, {'title': '测试直播'}), '[分享]测试直播');
      expect(last(16, {'reply_content': '测试\n\n回复'}), '测试 回复');
      expect(last(18, {'content': '[]'}), '');
      expect(last(306, {'content': '欢迎测试入群'}), '欢迎测试入群');
      expect(last(999, 'not json'), '');
    });

    test('no last message is an empty line, timed by the session; a missing session_ts falls back to it', () {
      final bare = MessageDecode.sessions({
        'session_list': [
          {'talker_id': 1, 'session_ts': 1760000000000000},
        ],
      }).sessions.single;
      expect((bare.lastText, bare.time.microsecondsSinceEpoch), ('', 1760000000000000));
      final untimed = MessageDecode.sessions({
        'session_list': [
          {'talker_id': 1, 'last_msg': _message(seqno: 1)},
        ],
      }).sessions.single;
      expect(untimed.time.millisecondsSinceEpoch, 1760000000000);
    });

    test('official boxes by name, else by system_msg_type; a person named like one stays a person', () {
      NoticeBox? box(Map<String, Object?> extra) => session(_message(seqno: 1), extra: extra).box;
      expect(
        box({
          'account_info': {'name': '社区中心', 'pic_url': ''},
        }),
        NoticeBox.community,
      );
      expect(
        box({
          'account_info': {'name': '创作助手', 'pic_url': ''},
        }),
        NoticeBox.creator,
      );
      expect(
        box({
          'account_info': {'name': '测试小助手'},
          'system_msg_type': 5,
        }),
        NoticeBox.system,
      );
      expect(
        box({
          'account_info': {'name': '主播小助手'},
          'system_msg_type': 1,
        }),
        isNull,
      );
      expect(box({'system_msg_type': 0, 'group_name': '服务通知'}), isNull);
    });
  });

  group('messages', () {
    test('an empty session reads 2⁶⁴−1 and 0 as no seqnos', () {
      final page = MessageDecode.messages(
        jsonDecode('{"messages":null,"has_more":0,"min_seqno":18446744073709551615,"max_seqno":0}'),
      );
      expect((page.messages.isEmpty, page.hasMore, page.minSeqno, page.maxSeqno), (true, false, 0, 0));
    });

    test('a page of take-backs alone still pages on from the answer\'s min_seqno', () {
      final page = MessageDecode.messages({
        'messages': [_message(seqno: 50, type: 5, content: '1')],
        'has_more': 1,
        'min_seqno': 50,
        'max_seqno': 50,
      });
      expect((page.messages.isEmpty, page.hasMore, page.minSeqno), (true, true, 50));
    });

    test('without min and max the messages\' own seqnos stand in', () {
      final page = MessageDecode.messages({
        'messages': [_message(seqno: 9), _message(seqno: 7)],
      });
      expect((page.minSeqno, page.maxSeqno), (7, 9));
    });

    test('a withdrawn message never carries its text, whatever its type', () {
      final withdrawn = _one(_message(seqno: 1, type: 2, content: {'url': 'https://example.invalid/p.jpg'}, status: 1));
      expect((withdrawn.kind, withdrawn.text, withdrawn.picture), (ChatMessageKind.withdrawn, '', ''));
    });

    test('a custom emote draws as a picture; a size with a fraction rounds', () {
      final emote = _one(_message(seqno: 1, type: 6, content: {'url': 'u', 'width': 120.6, 'height': '80'}));
      expect(
        (emote.kind, emote.picture, emote.pictureWidth, emote.pictureHeight),
        (ChatMessageKind.picture, 'u', 121, 0),
      );
    });

    test('grey lines: 18\'s JSON lines, 53\'s paragraph, a group\'s line and a line from no one', () {
      final tip = _one(
        _message(
          seqno: 1,
          type: 18,
          content: {
            'content': jsonEncode([
              {'text': '测试提示一'},
              {'text': '，二', 'jump_url': 'https://www.bilibili.com/'},
              {'color_day': '#000000'},
            ]),
          },
        ),
      );
      expect((tip.kind, tip.text), (ChatMessageKind.tip, '测试提示一，二'));
      expect(_one(_message(seqno: 1, type: 18, content: {'content': '不是 JSON'})).text, '不是 JSON');

      final subscribe = _one(
        _message(
          seqno: 1,
          type: 53,
          content: {
            'paragraph': {
              'text': {
                'nodes': [
                  {
                    'node_type': 1,
                    'word': {'words': '你已订阅'},
                  },
                  {
                    'node_type': 2,
                    'link': {
                      'link': 'https://www.bilibili.com/',
                      'show_text': {'words': '测试'},
                    },
                  },
                  {'node_type': 9, 'raw_text': '更新'},
                ],
              },
            },
          },
        ),
      );
      expect((subscribe.kind, subscribe.text), (ChatMessageKind.tip, '你已订阅测试更新'));

      expect(_one(_message(seqno: 1, type: 301, content: {'content': '测试离开'}, sender: 0)).kind, ChatMessageKind.tip);
      final bare = _one(_message(seqno: 1, type: 400, content: {'content': '测试系统行'}, sender: 0));
      expect((bare.kind, bare.text), (ChatMessageKind.tip, '测试系统行'));
    });

    test('anything unknown from a person is other, with what text it has', () {
      final other = _one(_message(seqno: 1, type: 400, content: {'content': '测试未知'}));
      expect((other.kind, other.text), (ChatMessageKind.other, '测试未知'));
      final shapeless = _one(_message(seqno: 1, type: 1, content: 'not json'));
      expect((shapeless.kind, shapeless.text), (ChatMessageKind.text, ''));
    });

    test('auto replies are marked from msg_source 8 to 11 only', () {
      expect(
        [
          for (final source in [6, 7, 8, 9, 10, 11, 12]) _one(_message(seqno: 1, source: source)).autoReply,
        ],
        [false, false, true, true, true, true, false],
      );
    });

    test('a notice card without buttons or modules has none', () {
      final card = _one(_message(seqno: 1, type: 10, content: {'title': '测试', 'text': '正文', 'modules': null}));
      expect((card.kind, card.fields.isEmpty, card.links.isEmpty), (ChatMessageKind.notice, true, true));
    });

    test('e_infos that are not a list, or entries without a picture, give no emotes', () {
      expect(
        MessageDecode.messages({
          'messages': [
            _message(seqno: 1, content: {'content': '[doge]'}),
          ],
          'e_infos': 'nope',
        }).messages.single.emotes,
        isEmpty,
      );
      expect(
        MessageDecode.messages({
          'messages': [
            _message(seqno: 1, content: {'content': '[doge]'}),
          ],
          'e_infos': [
            {'text': '[doge]', 'url': ''},
          ],
        }).messages.single.emotes,
        isEmpty,
      );
    });

    test('a sent message without e_infos has no emotes and no key', () {
      final sent = MessageDecode.sent(
        <String, Object?>{},
        senderMid: 1,
        text: '测试[doge]',
        time: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect((sent.key, sent.seqno, sent.emotes.isEmpty), (0, 0, true));
    });
  });

  group('系统通知', () {
    test('data that is not a list is no notices', () {
      final page = MessageDecode.systemNotices({'list': <Object?>[]}, pageSize: 20);
      expect((page.messages.isEmpty, page.hasMore), (true, false));
    });

    test('a full page may have more', () {
      final page = MessageDecode.systemNotices([
        for (var i = 1; i <= 3; i++) {'id': i, 'cursor': i * 1000, 'title': '测试$i', 'content': '正文'},
      ], pageSize: 3);
      expect((page.hasMore, page.minSeqno, page.maxSeqno), (true, 1000, 3000));
    });

    test('several links lift out; a time with no zone is Beijing\'s', () {
      final notice = MessageDecode.systemNotices([
        {
          'id': 1,
          'cursor': 5,
          'title': '测试',
          'content': '看#{一}{"https://www.bilibili.com/a"}和#{二}{https://www.bilibili.com/b}',
          'time_at': '2026-01-01 08:00:00',
        },
      ], pageSize: 20).messages.single;
      expect(notice.text, '看一和二');
      expect(notice.links.map((link) => (link.text, link.uri)), [
        ('一', 'https://www.bilibili.com/a'),
        ('二', 'https://www.bilibili.com/b'),
      ]);
      expect(notice.time.toUtc(), DateTime.utc(2026, 1, 1));
    });
  });

  group('settings', () {
    test('an unknown value is 不接收; a missing field is missing', () {
      expect(MessageDecode.noticeSettings({'set_recv_like': 5}), {NoticeSettingKind.likes: NoticeAudience.off});
      expect(MessageDecode.noticeSettings(<String, Object?>{}), isEmpty);
    });

    test('the chat bar: 拉黑 isn\'t following, show_push_setting 0 hides the switch, nothing reads as defaults', () {
      final blocked = MessageDecode.chatSettings({'follow_status': 128, 'push_setting': 0, 'show_push_setting': 0});
      expect((blocked.following, blocked.pushOn, blocked.showPush), (false, true, false));
      final whisper = MessageDecode.chatSettings({'follow_status': 1});
      expect(whisper.following, isTrue);
      final bare = MessageDecode.chatSettings(<String, Object?>{});
      expect((bare.following, bare.pushOn, bare.showPush), (false, true, true));
    });

    test('the wire values', () {
      expect(NoticeSettingKind.values.map(MessageDecode.settingField), [
        'set_recv_reply',
        'set_recv_like',
        'set_new_follow',
      ]);
      expect(NoticeAudience.values.map(MessageDecode.audienceValue), ['0', '1', '2']);
    });
  });

  group('user cards', () {
    test('a map of cards by mid reads as a list; anything else is none', () {
      final cards = MessageDecode.userCards({
        '20000921': {'mid': 20000921, 'name': '测试一', 'face': ''},
        '20000922': {'mid': 20000922, 'uname': '测试二'},
      });
      expect(cards.map((card) => (card.mid, card.name)), [(20000921, '测试一'), (20000922, '测试二')]);
      expect(MessageDecode.userCards('nope'), isEmpty);
      expect(MessageDecode.userCards(null), isEmpty);
    });
  });
}
