import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../../video/player_session.dart';
import 'panel_parts.dart';

/// 倍速 (06): a plain column of values on the dimmed video in landscape, a grid in the portrait sheet (port of
/// BiliNative `SpeedPanel.swift`).
class SpeedPanel extends StatelessWidget {
  const SpeedPanel({super.key, required this.session, required this.toast, required this.close});

  final PlayerSession session;
  final ValueChanged<String> toast;
  final VoidCallback close;

  static const choices = <(double, String)>[
    (3, '3.0X'),
    (2, '2.0X'),
    (1.5, '1.5X'),
    (1.25, '1.25X'),
    (1, '1.0X'),
    (0.75, '0.75X'),
    (0.5, '0.5X'),
  ];

  void _choose(double rate) {
    toastFailure(session.setRate(rate), toast);
    close();
  }

  Widget _label(double rate, String label) {
    final selected = session.rate == rate;
    return Semantics(
      button: true,
      selected: selected,
      child: Center(
        child: Text(label, style: TextStyle(color: selected ? BiliColors.pink : BiliColors.panelText)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PanelScope.landscapeOf(context)) {
      return Column(
        key: const ValueKey('speed-column'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, (rate, label)) in choices.indexed)
            PanelReveal(
              order: index,
              child: PanelPressable(
                onTap: () => _choose(rate),
                child: SizedBox(height: BiliMetrics.panelSpeedRow, child: _label(rate, label)),
              ),
            ),
        ],
      );
    }
    return Column(
      key: const ValueKey('speed-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PanelHeader(title: '倍速'),
        const SizedBox(height: BiliMetrics.gutter - (BiliMetrics.panelHitBox - BiliMetrics.panelHeaderHeight) / 2),
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 4;
            final cell = (constraints.maxWidth - BiliMetrics.panelGap * (columns - 1)) / columns;
            return Wrap(
              spacing: BiliMetrics.panelGap,
              runSpacing: BiliMetrics.panelGap,
              children: [
                for (final (index, (rate, label)) in choices.indexed)
                  PanelReveal(
                    order: index,
                    child: PanelPressable(
                      onTap: () => _choose(rate),
                      child: Container(
                        width: cell,
                        height: BiliMetrics.panelSpeedCell,
                        decoration: BoxDecoration(
                          color: BiliColors.panelCard,
                          borderRadius: BorderRadius.circular(BiliMetrics.panelRowRadius),
                        ),
                        child: _label(rate, label),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
