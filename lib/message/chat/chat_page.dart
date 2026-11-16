import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// A 私信 session (202, 203), or a notice box's cards and bubbles (200, 201).
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.session});

  final ChatSession session;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageChatTheme.page);
}
