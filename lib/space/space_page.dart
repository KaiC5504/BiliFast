import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'uploader_tap.dart';

/// UP主空间 (63, 69-75, 77).
class SpacePage extends StatefulWidget {
  const SpacePage({super.key, required this.uploader});

  final UploaderRef uploader;

  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: BiliColors.card);
}
