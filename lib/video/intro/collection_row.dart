import 'package:flutter/widgets.dart';

import '../player_session.dart' show Episode;

/// 合集 · name, with the playing episode's place (⫴ 221/221 >) (03). Opens the 选集 sheet.
class CollectionRow extends StatelessWidget {
  const CollectionRow({super.key, required this.title, required this.episodes, required this.onOpen});

  final String title;
  final List<Episode> episodes;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
