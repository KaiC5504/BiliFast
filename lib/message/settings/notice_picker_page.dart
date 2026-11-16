import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// A 消息提醒 picker: 回复与@ (215), 收到喜欢 (216), 新增粉丝 (195).
class NoticePickerPage extends StatefulWidget {
  const NoticePickerPage({super.key, required this.kind});

  final NoticeSettingKind kind;

  @override
  State<NoticePickerPage> createState() => _NoticePickerPageState();
}

class _NoticePickerPageState extends State<NoticePickerPage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageSettingsTheme.page);
}
