import 'dart:math' as math;

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
    if (PanelScope.padStripOf(context)) {
      return _PadStripPage(
        header: PanelHeader(title: '清晰度', trailing: _advanced()),
        rows: [
          _PadRow(title: '自动', onTap: () => _chooseAuto(options)),
          for (final option in options)
            _PadRow(
              title: title(option),
              subtitle: subtitle(option),
              badge: QualityRules.needsVip(option.id) ? '大会员' : null,
              info: subtitle(option) != null,
              selected: option.id == session.playingQuality,
              onTap: () => _choose(option),
            ),
        ],
      );
    }
    return PanelPage(
      header: PanelHeader(title: '清晰度', trailing: _advanced()),
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

  Widget _advanced() => Semantics(
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
  );

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

  void _choose(VideoCodec codec) {
    toastFailure(session.setCodec(codec), toast);
    close();
  }

  @override
  Widget build(BuildContext context) {
    final header = PanelHeader(title: '高级设置', back: back);
    if (PanelScope.padStripOf(context)) {
      return _PadStripPage(
        header: header,
        rows: [
          for (final codec in VideoCodec.values)
            _PadRow(title: codec.label, selected: codec == session.codec, onTap: () => _choose(codec)),
        ],
      );
    }
    return PanelPage(
      header: header,
      children: [
        for (final (index, codec) in VideoCodec.values.indexed)
          PanelReveal(
            order: index,
            child: PanelCardRow(title: codec.label, selected: codec == session.codec, onTap: () => _choose(codec)),
          ),
      ],
    );
  }
}

/// The iPad's full-screen 清晰度 (ipad/10): plain rows on the strip, their block centred a little above the screen's
/// middle, under the phone's header (10 has none; it keeps 高级设置 reachable).
class _PadStripPage extends StatelessWidget {
  const _PadStripPage({required this.header, required this.rows});

  final PanelHeader header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final top = MediaQuery.paddingOf(context).top;
    const headerBottom = PadPanelTheme.qualityHeaderTop + BiliMetrics.panelHitBox;
    final centred = (screen - rows.length * PadPanelTheme.qualityRow) / 2 - PadPanelTheme.qualityLift - top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: PadPanelTheme.qualityHeaderTop),
        Padding(
          padding: const EdgeInsets.only(left: PadPanelTheme.qualityLead, right: PadPanelTheme.qualityTrailing),
          child: header,
        ),
        SizedBox(height: math.max(PadPanelTheme.qualityHeaderGap, centred - headerBottom)),
        for (final (index, row) in rows.indexed) PanelReveal(order: index, child: row),
      ],
    );
  }
}

class _PadRow extends StatelessWidget {
  const _PadRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.info = false,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final String? badge;

  /// 真彩 HDR's ⓘ, after its title.
  final bool info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontSize: PadPanelTheme.qualityText,
      color: selected ? PadPanelTheme.qualitySelected : BiliColors.panelText,
    );
    return Semantics(
      button: true,
      selected: selected,
      child: PanelPressable(
        onTap: onTap,
        radius: 0,
        child: Container(
          height: PadPanelTheme.qualityRow,
          padding: const EdgeInsets.only(left: PadPanelTheme.qualityLead, right: PadPanelTheme.qualityTrailing),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: _title(style)),
                    if (info) ...[
                      const SizedBox(width: BiliMetrics.panelBadgeGap),
                      const Icon(Icons.info_outline, size: BiliMetrics.panelInfoIcon, color: BiliColors.panelSecondary),
                    ],
                  ],
                ),
              ),
              if (badge case final badge?) ...[const SizedBox(width: BiliMetrics.panelBadgeGap), _PadBadge(badge)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(TextStyle style) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 160),
        style: style,
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, strutStyle: BiliFonts.strut(style)),
      ),
      if (subtitle case final subtitle?)
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: PadPanelTheme.qualitySubtitleText, color: BiliColors.panelSecondary),
        ),
    ],
  );
}

class _PadBadge extends StatelessWidget {
  const _PadBadge(this.text);

  final String text;

  static const _style = TextStyle(
    fontSize: PadPanelTheme.badgeText,
    height: 1,
    color: BiliColors.onPink,
    fontWeight: FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) => Container(
    height: PadPanelTheme.badgeHeight,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: PadPanelTheme.badgePad),
    decoration: BoxDecoration(
      color: PadPanelTheme.badgeFill,
      borderRadius: BorderRadius.circular(PadPanelTheme.badgeHeight / 2),
    ),
    child: Text(text, style: _style, strutStyle: BiliFonts.strutOf(context, _style)),
  );
}
