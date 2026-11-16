import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 新增粉丝 (199).
class NewFansPage extends StatefulWidget {
  const NewFansPage({super.key});

  @override
  State<NewFansPage> createState() => _NewFansPageState();
}

class _NewFansPageState extends State<NewFansPage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: MessageFeedTheme.page);
}
