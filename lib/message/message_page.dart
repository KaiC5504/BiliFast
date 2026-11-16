import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../skin/skin.dart';

/// The bottom bar's 消息 (196): the header with 一键已读 and ⋮, the three entries, and the session list.
class MessagePage extends StatefulWidget {
  const MessagePage({super.key, required this.active, this.skin, this.reloads});

  /// The place is shown.
  final bool active;

  /// The equipped 装扮, dressing the header as 关注's.
  final Skin? skin;

  /// 消息 tapped again while shown.
  final Listenable? reloads;

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageTabTheme.page);
}
