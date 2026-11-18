import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import 'chat_glyphs.dart';
import 'chat_rows.dart' show chatStyle;

/// An official notice card (200, 201): the title, the body, the labelled fields (有效期 永久有效), and a row with ›
/// for each link under a rule.
class ChatNoticeCard extends StatelessWidget {
  const ChatNoticeCard({super.key, required this.message, required this.onLink});

  final ChatMessage message;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final body = chatStyle(MessageChatTheme.cardBody, MessageChatTheme.dim, line: MessageChatTheme.cardBodyLine);
    final label = chatStyle(MessageChatTheme.cardBody, MessageChatTheme.grey, line: MessageChatTheme.fieldLine);
    final value = chatStyle(MessageChatTheme.cardBody, MessageChatTheme.dim, line: MessageChatTheme.fieldLine);
    final fields = message.fields;
    final links = message.links;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MessageChatTheme.cardMargin),
      child: DecoratedBox(
        key: ValueKey('chat-card-${message.seqno}'),
        decoration: BoxDecoration(
          color: MessageChatTheme.card,
          borderRadius: BorderRadius.circular(MessageChatTheme.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MessageChatTheme.cardInset,
                MessageChatTheme.cardTop,
                MessageChatTheme.cardInset,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message.title.isNotEmpty)
                    Text(
                      message.title,
                      style: chatStyle(
                        MessageChatTheme.cardTitle,
                        MessageChatTheme.text,
                        line: MessageChatTheme.cardTitleLine,
                        weight: MessageChatTheme.cardTitleWeight,
                      ),
                    ),
                  if (message.text.isNotEmpty) ...[
                    if (message.title.isNotEmpty) const SizedBox(height: MessageChatTheme.cardBodyGap),
                    Text(message.text, style: body, strutStyle: BiliFonts.strutOf(context, body)),
                  ],
                  for (final (index, field) in fields.indexed) ...[
                    SizedBox(
                      height: index == 0
                          ? MessageChatTheme.cardFieldGap
                          : MessageChatTheme.fieldPitch - MessageChatTheme.fieldLine,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: MessageChatTheme.fieldLabelWidth),
                          child: Text(field.title, style: label, strutStyle: BiliFonts.strutOf(context, label)),
                        ),
                        const SizedBox(width: MessageChatTheme.fieldValueGap),
                        Expanded(
                          child: Text(field.detail, style: value, strutStyle: BiliFonts.strutOf(context, value)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (links.isEmpty)
              const SizedBox(height: MessageChatTheme.cardBottom)
            else ...[
              const SizedBox(height: MessageChatTheme.cardRuleGap),
              for (final (index, link) in links.indexed)
                _LinkRow(index: index, link: link, onTap: () => onLink(link.uri)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.index, required this.link, required this.onTap});

  final int index;
  final ({String text, String uri}) link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: link.text,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('chat-card-link-$index'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MessageChatTheme.cardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: MessageChatTheme.cardRule,
              child: ColoredBox(color: MessageChatTheme.hairline),
            ),
            SizedBox(
              height: MessageChatTheme.linkRow - MessageChatTheme.cardRule,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      link.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chatStyle(MessageChatTheme.linkText, MessageChatTheme.text),
                    ),
                  ),
                  const SizedBox(
                    width: MessageChatTheme.chevronWidth,
                    height: MessageChatTheme.chevronHeight,
                    child: CustomPaint(painter: ChatChevronPainter()),
                  ),
                  const SizedBox(width: MessageChatTheme.chevronRight),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
