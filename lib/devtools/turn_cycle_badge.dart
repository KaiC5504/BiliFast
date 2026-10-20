import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'turn_cycle.dart';

/// 轮换测试's label over the whole app while it runs, so the screen recording says which style is on screen: top left
/// inside the safe area, below the status bar upright and clear of the Dynamic Island sideways. Taps go through.
class TurnCycleBadge extends StatelessWidget {
  const TurnCycleBadge({super.key, required this.cycle, required this.child});

  final TurnCycle cycle;
  final Widget child;

  static String text(TurnCycle cycle) =>
      '轮换 ${cycle.position}/${TurnCycle.styles.length} · ${cycle.style.label} · '
      '${cycle.roundTrips + 1}/${TurnCycle.roundTripsPerStyle}';

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: cycle,
                builder: (context, _) => cycle.on ? _badge(context) : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      );

  Widget _badge(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(left: safe.left + BiliMetrics.rowGap, top: safe.top + BiliMetrics.rowGap),
        child: DecoratedBox(
          key: const ValueKey('turn-cycle-badge'),
          decoration: BoxDecoration(
            color: BiliColors.statsFill,
            border: Border.all(color: BiliColors.statsBorder),
            borderRadius: BorderRadius.circular(BiliMetrics.statsRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BiliMetrics.statsPadding,
              vertical: BiliMetrics.statsLineGap,
            ),
            // Above the navigator there is no Material, whose text style would otherwise be inherited.
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: BiliFonts.family,
                fontSize: BiliMetrics.smallText,
                fontWeight: FontWeight.w600,
                color: BiliColors.onVideo,
              ),
              maxLines: 1,
              softWrap: false,
              child: Text(text(cycle)),
            ),
          ),
        ),
      ),
    );
  }
}
