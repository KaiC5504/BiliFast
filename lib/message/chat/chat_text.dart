import 'package:flutter/widgets.dart';

import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import 'chat_glyphs.dart';

/// A run of a message's text: words, an emote drawn as its picture, or a web address drawn as 网页链接.
sealed class ChatPiece {
  const ChatPiece();
}

final class ChatWords extends ChatPiece {
  const ChatWords(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is ChatWords && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ChatWords($text)';
}

final class ChatEmote extends ChatPiece {
  const ChatEmote(this.token, this.url);

  final String token;
  final String url;

  @override
  bool operator ==(Object other) => other is ChatEmote && other.token == token && other.url == url;

  @override
  int get hashCode => Object.hash(token, url);

  @override
  String toString() => 'ChatEmote($token)';
}

final class ChatLink extends ChatPiece {
  const ChatLink(this.url);

  final String url;

  @override
  bool operator ==(Object other) => other is ChatLink && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'ChatLink($url)';
}

// Addresses stop at the first character outside a URL's ASCII set, so 200's 【…】 around one stay text.
final _pieces = RegExp(r"\[[^\[\]\n]{1,24}\]|https?://[A-Za-z0-9\-._~:/?#@!$&'*+,;=%]+");
final _trailing = RegExp(r"[.,;:!?']+$");

/// [text] cut into words, emotes ([emotes] names their pictures; a code it doesn't name stays words) and addresses.
List<ChatPiece> chatPieces(String text, Map<String, String> emotes) {
  final pieces = <ChatPiece>[];
  final words = StringBuffer();
  void flush() {
    if (words.isEmpty) return;
    pieces.add(ChatWords(words.toString()));
    words.clear();
  }

  var at = 0;
  for (final match in _pieces.allMatches(text)) {
    words.write(text.substring(at, match.start));
    at = match.end;
    final found = match.group(0)!;
    if (found.startsWith('[')) {
      final url = emotes[found];
      if (url == null || url.isEmpty) {
        words.write(found);
      } else {
        flush();
        pieces.add(ChatEmote(found, url));
      }
      continue;
    }
    final address = found.replaceFirst(_trailing, '');
    flush();
    pieces.add(ChatLink(address));
    words.write(found.substring(address.length));
  }
  words.write(text.substring(at));
  flush();
  return pieces;
}

/// A bubble's text: emotes inline at 4/3 of the text's size, each address as the chain and 网页链接 in the link blue.
class ChatText extends StatelessWidget {
  const ChatText({super.key, required this.text, required this.emotes, required this.style, required this.onLink});

  final String text;
  final Map<String, String> emotes;
  final TextStyle style;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final pieces = chatPieces(text, emotes);
    final plain = pieces.every((piece) => piece is ChatWords);
    return Text.rich(
      TextSpan(
        children: [
          for (final piece in pieces)
            switch (piece) {
              ChatWords(:final text) => TextSpan(text: text),
              ChatEmote(:final token, :final url) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Semantics(
                  label: token,
                  image: true,
                  child: SizedBox.square(
                    dimension: MessageChatTheme.emote,
                    child: RemoteImage(
                      url,
                      size: const Size.square(MessageChatTheme.emote),
                      fit: BoxFit.contain,
                      placeholder: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              ChatLink(:final url) => WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _WebLink(style: style, onTap: () => onLink(url)),
              ),
            },
        ],
      ),
      style: style,
      // A forced strut would keep an emote's line from growing.
      strutStyle: plain ? BiliFonts.strutOf(context, style) : null,
    );
  }
}

class _WebLink extends StatelessWidget {
  const _WebLink({required this.style, required this.onTap});

  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    link: true,
    label: '网页链接',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('chat-web-link'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Without a baseline of its own the chain sits at the row's top.
          Padding(
            padding: const EdgeInsets.only(
              left: MessageChatTheme.linkGlyphGap,
              right: MessageChatTheme.linkGlyphGap,
              top: MessageChatTheme.linkGlyphDrop,
            ),
            child: ChatGlyph(
              ChatArt.link,
              width: MessageChatTheme.linkGlyph,
              height: MessageChatTheme.linkGlyph,
              color: MessageChatTheme.link,
            ),
          ),
          Text('网页链接', style: style.copyWith(color: MessageChatTheme.link)),
        ],
      ),
    ),
  );
}
