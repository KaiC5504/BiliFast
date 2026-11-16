import 'package:bilifast/message/chat/chat_links.dart';
import 'package:bilifast/message/chat/chat_rows.dart' show sameMinute;
import 'package:bilifast/message/chat/chat_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatPieces', () {
    const emotes = {'[微笑]': 'https://i0.hdslb.com/bfs/emote/smile.png', '[空]': ''};

    test('emote codes it names become emotes, others stay words', () {
      expect(chatPieces('早[微笑]好[未知][空]', emotes), const [
        ChatWords('早'),
        ChatEmote('[微笑]', 'https://i0.hdslb.com/bfs/emote/smile.png'),
        ChatWords('好[未知][空]'),
      ]);
    });

    test('an address stops at the first character outside a URL and loses trailing punctuation', () {
      expect(chatPieces('领取>>【https://www.example.com/a?b=1】', emotes), const [
        ChatWords('领取>>【'),
        ChatLink('https://www.example.com/a?b=1'),
        ChatWords('】'),
      ]);
      expect(chatPieces('see http://example.com/x. ok', emotes), const [
        ChatWords('see '),
        ChatLink('http://example.com/x'),
        ChatWords('. ok'),
      ]);
    });

    test('plain words stay one piece, and nothing gives nothing', () {
      expect(chatPieces('你好，谢谢', emotes), const [ChatWords('你好，谢谢')]);
      expect(chatPieces('', emotes), isEmpty);
    });
  });

  group('chatLinkTarget', () {
    test('a Bilibili video address opens in the app; a short link goes to Safari', () {
      expect(
        chatLinkTarget('https://www.bilibili.com/video/BV1GJ411x7h7?p=2'),
        isA<ChatVideoTarget>().having((target) => target.link, 'link', contains('BV1GJ411x7h7')),
      );
      expect(chatLinkTarget('https://m.bilibili.com/video/av170001'), isA<ChatVideoTarget>());
      expect(chatLinkTarget('https://b23.tv/abc123'), isA<ChatWebTarget>());
    });

    test('a space address opens the space', () {
      expect(chatLinkTarget('https://space.bilibili.com/2'), isA<ChatSpaceTarget>().having((t) => t.mid, 'mid', 2));
      expect(chatLinkTarget('bilibili://space/9'), isA<ChatSpaceTarget>().having((t) => t.mid, 'mid', 9));
    });

    test('app links to a video open it; other app links and odd addresses open nothing', () {
      expect(
        chatLinkTarget('bilibili://video/170001'),
        isA<ChatVideoTarget>().having((t) => t.link, 'link', 'av170001'),
      );
      expect(
        chatLinkTarget('bilibili://video/BV1GJ411x7h7'),
        isA<ChatVideoTarget>().having((t) => t.link, 'link', 'BV1GJ411x7h7'),
      );
      expect(chatLinkTarget('bilibili://garb/demo'), isA<ChatUnknownTarget>());
      expect(chatLinkTarget('mailto:demo@example.com'), isA<ChatUnknownTarget>());
    });

    test('other web addresses go to Safari, even one naming a video off Bilibili', () {
      expect(
        chatLinkTarget('https://www.example.com/BV1GJ411x7h7'),
        isA<ChatWebTarget>().having((t) => t.uri.host, 'host', 'www.example.com'),
      );
    });
  });

  test('sameMinute', () {
    expect(sameMinute(DateTime(2025, 11, 28, 14, 30, 5), DateTime(2025, 11, 28, 14, 30, 59)), isTrue);
    expect(sameMinute(DateTime(2025, 11, 28, 14, 30), DateTime(2025, 11, 28, 14, 31)), isFalse);
    expect(sameMinute(DateTime(2025, 11, 28, 14, 30), DateTime(2025, 11, 29, 14, 30)), isFalse);
  });
}
