import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 收到喜欢 (198).
class LikesPage extends StatefulWidget {
  const LikesPage({super.key});

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageFeedTheme.page);
}
