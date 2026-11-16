import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import 'chat_glyphs.dart';
import 'chat_rows.dart' show chatStyle;

/// 202's bar over a person's chat: 不接受推送 (通知正常接收) and 加关注, which reads 已关注 once it is taken.
class ChatSettingsBar extends StatelessWidget {
  const ChatSettingsBar({
    super.key,
    required this.pushOn,
    required this.showPush,
    required this.following,
    required this.onPush,
    required this.onFollow,
  });

  final bool pushOn;
  final bool showPush;
  final bool following;
  final VoidCallback onPush;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      MessageChatTheme.settingsMargin,
      MessageChatTheme.settingsTop,
      MessageChatTheme.settingsMargin,
      MessageChatTheme.settingsBottom,
    ),
    child: Container(
      key: const ValueKey('chat-settings-bar'),
      height: MessageChatTheme.settingsHeight,
      decoration: BoxDecoration(
        color: MessageChatTheme.card,
        borderRadius: BorderRadius.circular(MessageChatTheme.settingsRadius),
      ),
      child: Row(
        children: [
          if (showPush) ...[
            Expanded(child: _push()),
            const SizedBox(
              width: MessageChatTheme.settingsRule,
              height: MessageChatTheme.settingsRuleHeight,
              child: ColoredBox(color: MessageChatTheme.hairline),
            ),
          ],
          Expanded(child: _follow()),
        ],
      ),
    ),
  );

  Widget _push() {
    final title = pushOn ? '不接受推送' : '接受推送';
    final state = pushOn ? '通知正常接收' : '通知已关闭';
    return _Half(
      key: const ValueKey('chat-push'),
      label: '$title，$state',
      onTap: onPush,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatGlyph(
            pushOn ? ChatArt.pushOff : ChatArt.pushOn,
            width: MessageChatTheme.pushGlyphWidth,
            height: MessageChatTheme.pushGlyphHeight,
            color: MessageChatTheme.text,
          ),
          const SizedBox(width: MessageChatTheme.pushGap),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                style: chatStyle(MessageChatTheme.pushTitle, MessageChatTheme.text, line: MessageChatTheme.pushLine),
              ),
              Text(
                state,
                maxLines: 1,
                style: chatStyle(MessageChatTheme.pushSubtitle, MessageChatTheme.grey, line: MessageChatTheme.pushLine),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _follow() => _Half(
    key: const ValueKey('chat-follow'),
    label: following ? '已关注' : '加关注',
    onTap: following ? null : onFollow,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatGlyph(
          following ? ChatArt.following : ChatArt.follow,
          width: MessageChatTheme.followGlyphWidth,
          height: MessageChatTheme.followGlyphHeight,
          color: following ? MessageChatTheme.grey : MessageChatTheme.text,
        ),
        const SizedBox(width: MessageChatTheme.followGap),
        Text(
          following ? '已关注' : '加关注',
          maxLines: 1,
          style: chatStyle(MessageChatTheme.followText, following ? MessageChatTheme.grey : MessageChatTheme.text),
        ),
      ],
    ),
  );
}

class _Half extends StatelessWidget {
  const _Half({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: MessageChatTheme.settingsNudge * 2),
        child: Center(child: child),
      ),
    ),
  );
}
