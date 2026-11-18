import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../comments/comment_badges.dart' show DecorImage;
import '../../me/me_glyphs.dart' show MeVipDisc;
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../message_dates.dart';
import '../notice_box_icon.dart';
import 'chat_text.dart';

TextStyle chatStyle(double size, Color color, {double? line, FontWeight? weight}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: line == null ? null : line / size,
  leadingDistribution: line == null ? null : TextLeadingDistribution.even,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// Two messages a minute or more apart get a time line between them (202).
bool sameMinute(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day && a.hour == b.hour && a.minute == b.minute;

/// 202's 2025年11月26日 21:51 over a group of messages.
class ChatTimeLine extends StatelessWidget {
  const ChatTimeLine({super.key, required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MessageChatTheme.timeLine,
    child: Center(
      child: Text(
        chatStamp(time),
        maxLines: 1,
        style: chatStyle(MessageChatTheme.timeText, MessageChatTheme.grey, line: MessageChatTheme.timeLine),
      ),
    ),
  );
}

/// A grey line in the middle: 202's 对方主动回复或关注你前，最多发送1条消息, or a withdrawn message.
class ChatTip extends StatelessWidget {
  const ChatTip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = chatStyle(MessageChatTheme.tipText, MessageChatTheme.grey, line: MessageChatTheme.tipLine);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MessageChatTheme.side),
      child: Text(text, textAlign: TextAlign.center, style: style, strutStyle: BiliFonts.strutOf(context, style)),
    );
  }
}

/// One message with its face: the other side's (or a notice box's) at the left on white, yours at the right on 202's
/// pale cyan. A text bubble draws emotes and addresses ([ChatText]) and 203's 此条消息为自动回复 under an auto reply;
/// a picture is drawn with the bubble's corners.
class ChatBubbleRow extends StatelessWidget {
  const ChatBubbleRow({
    super.key,
    required this.message,
    required this.own,
    required this.box,
    required this.face,
    required this.onFace,
    required this.onLink,
  });

  final ChatMessage message;
  final bool own;

  /// The other side's face (the session's).
  final String face;

  /// A notice box's chat: its pink face, no tap.
  final NoticeBox? box;

  /// A tap on the other side's face.
  final VoidCallback onFace;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final bubble = message.kind == ChatMessageKind.picture ? _picture() : _textBubble(context);
    final drawn = own ? const _OwnFace() : _theirFace();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MessageChatTheme.side),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: own ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!own) ...[drawn, const SizedBox(width: MessageChatTheme.faceGap)],
          Flexible(child: bubble),
          if (own) ...[const SizedBox(width: MessageChatTheme.faceGap), drawn],
        ],
      ),
    );
  }

  Widget _theirFace() {
    final box = this.box;
    if (box != null) return NoticeBoxIcon(box, size: MessageChatTheme.face);
    return Semantics(
      button: true,
      label: '个人空间',
      onTap: onFace,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('chat-face-${message.seqno}'),
        behavior: HitTestBehavior.opaque,
        onTap: onFace,
        child: SizedBox.square(
          dimension: MessageChatTheme.face,
          child: ClipOval(child: RemoteImage.avatar(face)),
        ),
      ),
    );
  }

  BorderRadius get _corners => own
      ? const BorderRadius.only(
          topLeft: Radius.circular(MessageChatTheme.bubbleRadius),
          topRight: Radius.circular(MessageChatTheme.bubbleNear),
          bottomLeft: Radius.circular(MessageChatTheme.bubbleRadius),
          bottomRight: Radius.circular(MessageChatTheme.bubbleRadius),
        )
      : const BorderRadius.only(
          topLeft: Radius.circular(MessageChatTheme.bubbleNear),
          topRight: Radius.circular(MessageChatTheme.bubbleRadius),
          bottomLeft: Radius.circular(MessageChatTheme.bubbleRadius),
          bottomRight: Radius.circular(MessageChatTheme.bubbleRadius),
        );

  Widget _textBubble(BuildContext context) {
    final style = chatStyle(MessageChatTheme.bubbleText, MessageChatTheme.text, line: MessageChatTheme.bubbleLine);
    Widget content = ChatText(text: message.text, emotes: message.emotes, style: style, onLink: onLink);
    if (message.autoReply) {
      content = IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            const SizedBox(height: MessageChatTheme.autoReplyGap),
            SizedBox(
              height: MessageChatTheme.autoReplyRule,
              child: ColoredBox(color: MessageChatTheme.autoReplyRuleInk),
            ),
            const SizedBox(height: MessageChatTheme.autoReplyGap),
            Text(
              '此条消息为自动回复',
              maxLines: 1,
              style: chatStyle(
                MessageChatTheme.autoReplyText,
                MessageChatTheme.grey,
                line: MessageChatTheme.autoReplyLine,
              ),
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: MessageChatTheme.bubbleMaxText + MessageChatTheme.bubblePadding * 2),
      child: DecoratedBox(
        key: ValueKey('chat-bubble-${message.seqno}'),
        decoration: BoxDecoration(
          color: own ? MessageChatTheme.yours : MessageChatTheme.theirs,
          borderRadius: _corners,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MessageChatTheme.bubblePadding,
            MessageChatTheme.bubbleTop,
            MessageChatTheme.bubblePadding,
            message.autoReply ? MessageChatTheme.autoReplyBottom : MessageChatTheme.bubbleBottom,
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _picture() {
    final width = message.pictureWidth.toDouble();
    final height = message.pictureHeight.toDouble();
    const side = MessageChatTheme.pictureSide;
    final scale = width > 0 && height > 0 ? math.min(side / width, side / height) : 0.0;
    final size = scale > 0 ? Size(width * scale, height * scale) : const Size.square(MessageChatTheme.pictureUnsized);
    return ClipRRect(
      key: ValueKey('chat-picture-${message.seqno}'),
      borderRadius: _corners,
      child: SizedBox.fromSize(
        size: size,
        child: ColoredBox(
          color: MessageChatTheme.pictureFill,
          child: RemoteImage(message.picture, size: size, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// The account's face as 我的 draws its own: its pendant when it wears one, and 大会员's 大.
class _OwnFace extends StatelessWidget {
  const _OwnFace();

  @override
  Widget build(BuildContext context) {
    final environment = AppScope.of(context).environment;
    final nav = environment.accountNav?.nav;
    final pendant = nav?.pendant;
    final face = pendant == null ? MessageChatTheme.face : MessageChatTheme.pendantFace;
    return SizedBox.square(
      key: const ValueKey('chat-own-face'),
      dimension: MessageChatTheme.face,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: face,
            child: ClipOval(child: RemoteImage.avatar(environment.face)),
          ),
          if (pendant != null)
            OverflowBox(
              maxWidth: MessageChatTheme.pendantFrame,
              maxHeight: MessageChatTheme.pendantFrame,
              child: IgnorePointer(
                child: SizedBox.square(dimension: MessageChatTheme.pendantFrame, child: DecorImage(pendant)),
              ),
            ),
          if (nav?.vipBadge ?? false)
            Positioned(
              right: MessageChatTheme.vipRight - MessageChatTheme.vipRing,
              bottom: MessageChatTheme.vipBottom - MessageChatTheme.vipRing,
              child: Container(
                key: const ValueKey('chat-own-vip'),
                padding: const EdgeInsets.all(MessageChatTheme.vipRing),
                decoration: BoxDecoration(color: MessageChatTheme.vipRingInk, shape: BoxShape.circle),
                child: const SizedBox.square(
                  dimension: MessageChatTheme.vipDisc,
                  child: FittedBox(child: MeVipDisc()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
