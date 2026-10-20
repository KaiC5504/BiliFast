import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'turn_cycle.dart';

/// 轮换测试's label over the whole app while it runs, so the screen recording says which style is on screen: top centre,
/// just below the status bar upright and at the top edge sideways, clear of the back chevron and the Dynamic Island.
/// Taps go through. Accessibility reads it as its own small node, so it never becomes the label of the app around it.
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
    final label = text(cycle);
    return Padding(
      padding: EdgeInsets.only(
        left: safe.left + BiliMetrics.rowGap,
        top: safe.top + BiliMetrics.rowGap / 2,
        right: safe.right + BiliMetrics.rowGap,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Semantics(
          container: true,
          label: label,
          child: ExcludeSemantics(
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
                  overflow: TextOverflow.ellipsis,
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
