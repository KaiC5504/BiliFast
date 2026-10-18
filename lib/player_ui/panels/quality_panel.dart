import 'package:bili_core/api.dart' show QualityOption, VideoCodec;
import 'package:bili_core/logic.dart' show QualityNames, QualityRules;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../../video/player_session.dart';
import 'panel_parts.dart';

/// 清晰度 (05): 自动 and every quality the playurl offered, best first (port of BiliNative `QualityPanel.swift`).
class QualityPanel extends StatelessWidget {
  const QualityPanel({
    super.key,
    required this.session,
    required this.openCodec,
    required this.toast,
    required this.close,
  });

  final PlayerSession session;
  final VoidCallback openCodec;
  final ValueChanged<String> toast;
  final VoidCallback close;

  static String title(QualityOption option) => QualityNames.full(qn: option.id, serverText: option.name);

  static String? subtitle(QualityOption option) => option.id == 125 ? '绚丽色彩，沉浸体验' : null;

  @override
  Widget build(BuildContext context) {
    final options = [...session.qualities]..sort((a, b) => b.id.compareTo(a.id));
    return PanelPage(
      header: PanelHeader(
        title: '清晰度',
        trailing: Semantics(
          button: true,
          child: GestureDetector(
            key: const ValueKey('quality-advanced'),
            behavior: HitTestBehavior.opaque,
            onTap: openCodec,
            child: const SizedBox(
              height: BiliMetrics.panelHitBox,
              child: Center(child: PanelDisclosure(text: '高级设置')),
            ),
          ),
        ),
      ),
      children: [
        PanelReveal(
          order: 0,
          child: PanelCardRow(title: '自动', onTap: () => _chooseAuto(options)),
        ),
        for (final (index, option) in options.indexed)
          PanelReveal(
            order: index + 1,
            child: PanelCardRow(
              title: title(option),
              subtitle: subtitle(option),
              badge: QualityRules.needsVip(option.id) ? '大会员' : null,
              trailing: subtitle(option) == null
                  ? null
                  : Transform.translate(
                      offset: const Offset(BiliMetrics.panelCardPadX - BiliMetrics.panelInfoInset, 0),
                      child: const Icon(
                        Icons.info_outline,
                        size: BiliMetrics.panelInfoIcon,
                        color: BiliColors.panelSecondary,
                      ),
                    ),
              selected: option.id == session.playingQuality,
              onTap: () => _choose(option),
            ),
          ),
      ],
    );
  }

  void _chooseAuto(List<QualityOption> options) {
    final best = QualityRules.auto(offered: [for (final option in options) option.id], isVip: session.isVip);
    if (best == null) return;
    _apply(best);
  }

  void _choose(QualityOption option) {
    if (QualityRules.needsVip(option.id) && !session.isVip) {
      toast('开通大会员后可观看');
      return;
    }
    _apply(option.id);
  }

  void _apply(int qn) {
    toastFailure(session.setQuality(qn), toast);
    close();
  }
}

/// 高级设置 > from 清晰度: which codec the engine asks Bilibili for.
class CodecPanel extends StatelessWidget {
  const CodecPanel({super.key, required this.session, required this.back, required this.toast, required this.close});

  final PlayerSession session;
  final VoidCallback back;
  final ValueChanged<String> toast;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => PanelPage(
    header: PanelHeader(title: '高级设置', back: back),
    children: [
      for (final (index, codec) in VideoCodec.values.indexed)
        PanelReveal(
          order: index,
          child: PanelCardRow(
            title: codec.label,
            selected: codec == session.codec,
            onTap: () {
              toastFailure(session.setCodec(codec), toast);
              close();
            },
          ),
        ),
    ],
  );
}
