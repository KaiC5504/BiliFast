import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 消息设置 (188).
class MessageSettingsPage extends StatefulWidget {
  const MessageSettingsPage({super.key});

  @override
  State<MessageSettingsPage> createState() => _MessageSettingsPageState();
}

class _MessageSettingsPageState extends State<MessageSettingsPage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageSettingsTheme.page);
}
