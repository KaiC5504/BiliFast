import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 回复与@ (197, 213): 全部 and @我.
class RepliesPage extends StatefulWidget {
  const RepliesPage({super.key, this.mentions = false});

  /// Opens on @我.
  final bool mentions;

  @override
  State<RepliesPage> createState() => _RepliesPageState();
}

class _RepliesPageState extends State<RepliesPage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageFeedTheme.page);
}
