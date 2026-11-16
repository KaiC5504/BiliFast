import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// The chat's glyphs from the official app's icon font, drawn white for tinting (`assets/README.md`).
abstract final class ChatArt {
  static const settings = 'assets/images/message/chat_settings.png';
  static const pushOff = 'assets/images/message/chat_push_off.png';
  static const pushOn = 'assets/images/message/chat_push_on.png';
  static const follow = 'assets/images/message/chat_follow.png';
  static const following = 'assets/images/message/chat_following.png';
  static const picture = 'assets/images/message/chat_picture.png';
  static const emote = 'assets/images/message/chat_emote.png';
  static const keyboard = 'assets/images/message/chat_keyboard.png';
  static const link = 'assets/images/message/chat_link.png';
}

/// [asset] tinted [color] in a [width] × [height] box.
class ChatGlyph extends StatelessWidget {
  const ChatGlyph(this.asset, {super.key, required this.width, required this.height, required this.color});

  final String asset;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Image.asset(asset, width: width, height: height, color: color, fit: BoxFit.contain, excludeFromSemantics: true);
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// The title row's ‹, its tip [MessageChatTheme.backTipX] from the box's left, on the box's middle.
class ChatBackPainter extends CustomPainter {
  const ChatBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    canvas.drawPath(
      Path()
        ..moveTo(MessageChatTheme.backEndX, middle - MessageChatTheme.backHalfHeight)
        ..lineTo(MessageChatTheme.backTipX, middle)
        ..lineTo(MessageChatTheme.backEndX, middle + MessageChatTheme.backHalfHeight),
      _stroke(MessageChatTheme.dim, MessageChatTheme.backStroke),
    );
  }

  @override
  bool shouldRepaint(ChatBackPainter oldDelegate) => false;
}

/// A card's link row ›, filling its box.
class ChatChevronPainter extends CustomPainter {
  const ChatChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = MessageChatTheme.chevronStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset)
        ..lineTo(size.width - inset, size.height / 2)
        ..lineTo(inset, size.height - inset),
      _stroke(MessageChatTheme.grey, MessageChatTheme.chevronStroke),
    );
  }

  @override
  bool shouldRepaint(ChatChevronPainter oldDelegate) => false;
}
