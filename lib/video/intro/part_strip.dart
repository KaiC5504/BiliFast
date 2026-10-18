import 'package:flutter/widgets.dart';

import '../player_session.dart' show Episode;

/// A video in parts: 选集 N/M > over a row of part chips; a chip plays its part, the header opens the 选集 sheet.
class PartStrip extends StatelessWidget {
  const PartStrip({super.key, required this.parts, required this.onChoose, required this.onOpenList});

  final List<Episode> parts;
  final ValueChanged<Episode> onChoose;
  final VoidCallback onOpenList;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
