import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

/// 荣耀等级's chip (the V and its number, 207's chat and 230's rows); nothing for level 0.
class LiveWealthChip extends StatelessWidget {
  const LiveWealthChip({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A fan medal's chip (莲宝 p21), its guard anchor before the name when [LiveMedal.guardLevel] is set.
class LiveMedalChip extends StatelessWidget {
  const LiveMedalChip({super.key, required this.medal});

  final LiveMedal medal;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A face [size] across, in its guard frame (总督 / 提督 / 舰长) when [guardLevel] is set, or [frame]'s picture.
class LiveFace extends StatelessWidget {
  const LiveFace({super.key, required this.url, required this.size, this.guardLevel = 0, this.frame = ''});

  final String url;
  final double size;
  final int guardLevel;
  final String frame;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size);
}
