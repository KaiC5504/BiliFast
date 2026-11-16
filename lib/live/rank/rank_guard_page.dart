import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../live_badges.dart';
import 'live_rank_model.dart';
import 'rank_parts.dart';

/// 大航海 (231, 233): the panel with 周榜 / 月榜 / 陪伴榜, 上周TOP1, the line and the rows, under the 立即上船 bar.
class RankGuardPage extends StatefulWidget {
  const RankGuardPage({
    super.key,
    required this.model,
    required this.tab,
    required this.onTab,
    required this.onUnavailable,
  });

  final LiveRankModel model;
  final LiveGuardTab tab;
  final ValueChanged<LiveGuardTab> onTab;

  /// ⓘ and 立即上船: 暂未开放.
  final VoidCallback onUnavailable;

  static const tabNames = {LiveGuardTab.weekly: '周榜', LiveGuardTab.monthly: '月榜', LiveGuardTab.companion: '陪伴榜'};

  /// The line over the rows. 周榜's is 231's; the others' follow it until a screenshot shows them.
  static const notes = {
    LiveGuardTab.weekly: '榜单每周更新，统计周大航海亲密度',
    LiveGuardTab.monthly: '榜单每月更新，统计月大航海亲密度',
    LiveGuardTab.companion: '统计大航海陪伴天数',
  };

  @override
  State<RankGuardPage> createState() => _RankGuardPageState();
}

class _RankGuardPageState extends State<RankGuardPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final feed = widget.model.guards[widget.tab]!;
    const listTop = LiveRankTheme.segmentsTop + LiveRankTheme.segmentHeight;
    return Stack(
      children: [
        const Positioned(
          left: LiveRankTheme.panelInset,
          right: LiveRankTheme.panelInset,
          top: 0,
          bottom: 0,
          child: _PanelFrame(),
        ),
        Positioned(
          left: LiveRankTheme.guardContentInset,
          right: LiveRankTheme.guardContentInset,
          top: LiveRankTheme.segmentsTop,
          height: LiveRankTheme.segmentHeight,
          child: _Segments(chosen: widget.tab, onTab: widget.onTab),
        ),
        Positioned(
          left: LiveRankTheme.panelInset + LiveRankTheme.panelRimWidth,
          right: LiveRankTheme.panelInset + LiveRankTheme.panelRimWidth,
          top: listTop,
          bottom: LiveRankTheme.barHeight,
          child: ClipRect(
            child: ListenableBuilder(
              listenable: feed,
              builder: (context, _) => RankList(
                key: ValueKey('rank-guard-list-${widget.tab.name}'),
                feed: feed,
                header: [
                  if (_top(feed.first) case (final text, final user)) _TopCard(text: text, user: user),
                  _GuardInfo(note: RankGuardPage.notes[widget.tab]!, onHelp: widget.onUnavailable),
                ],
                row: (entry) =>
                    GuardRow(key: ValueKey('rank-guard-${widget.tab.name}-${entry.user.uid}'), entry: entry),
              ),
            ),
          ),
        ),
        // Its rim runs round all four sides; the bottom one is pushed off the edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: -LiveRankTheme.barRimWidth,
          height: LiveRankTheme.barHeight + LiveRankTheme.barRimWidth,
          child: ListenableBuilder(
            listenable: widget.model,
            builder: (context, _) => _BoardBar(total: widget.model.guardTotal, onBoard: widget.onUnavailable),
          ),
        ),
      ],
    );
  }

  static (String, LiveUser)? _top(LiveGuardPage? answer) {
    final user = answer?.topUser;
    if (answer == null || user == null) return null;
    return (answer.topText.isEmpty ? '上周TOP1' : answer.topText, user);
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [LiveRankTheme.panelWashTop, LiveRankTheme.panelWashBottom],
      ),
      border: Border.all(color: LiveRankTheme.panelRim, width: LiveRankTheme.panelRimWidth),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LiveRankTheme.panelRadius)),
    ),
  );
}

class _Segments extends StatelessWidget {
  const _Segments({required this.chosen, required this.onTab});

  final LiveGuardTab chosen;
  final ValueChanged<LiveGuardTab> onTab;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final tab in LiveGuardTab.values) ...[
        if (tab != LiveGuardTab.values.first) const SizedBox(width: LiveRankTheme.segmentGap),
        Expanded(
          child: _Segment(tab: tab, chosen: tab == chosen, onTap: () => onTab(tab)),
        ),
      ],
    ],
  );
}

class _Segment extends StatelessWidget {
  const _Segment({required this.tab, required this.chosen, required this.onTap});

  final LiveGuardTab tab;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = RankGuardPage.tabNames[tab]!;
    return Semantics(
      button: true,
      selected: chosen,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('rank-segment-${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: chosen ? LiveRankTheme.segmentChosenFill : LiveRankTheme.segmentFill,
            borderRadius: BorderRadius.circular(LiveRankTheme.segmentRadius),
          ),
          child: Center(
            child: RankText(
              name,
              rankStyle(
                LiveRankTheme.segmentText,
                chosen ? LiveRankTheme.segmentChosenInk : LiveRankTheme.segmentInk,
                weight: chosen ? LiveRankTheme.segmentChosenWeight : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 上周TOP1 and who (231).
class _TopCard extends StatelessWidget {
  const _TopCard({required this.text, required this.user});

  final String text;
  final LiveUser user;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: LiveRankTheme.guardContentInset - LiveRankTheme.panelInset - LiveRankTheme.panelRimWidth,
      right: LiveRankTheme.guardContentInset - LiveRankTheme.panelInset - LiveRankTheme.panelRimWidth,
      top: LiveRankTheme.cardGap,
    ),
    child: Container(
      key: const ValueKey('rank-top-card'),
      height: LiveRankTheme.cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: LiveRankTheme.cardFaceGap),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LiveRankTheme.cardTop, LiveRankTheme.cardBottom],
        ),
        borderRadius: BorderRadius.circular(LiveRankTheme.cardRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LiveFace(url: user.face, size: LiveRankTheme.cardFace, guardLevel: user.guardLevel, frame: user.faceFrame),
          const SizedBox(width: LiveRankTheme.cardFaceGap),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: text,
                    style: rankStyle(
                      LiveRankTheme.cardTitleText,
                      LiveRankTheme.cardTitleInk,
                      weight: LiveRankTheme.cardTitleWeight,
                    ),
                  ),
                  TextSpan(
                    text: ' ${user.name}',
                    style: rankStyle(LiveRankTheme.cardNameText, LiveRankTheme.cardNameInk),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _GuardInfo extends StatelessWidget {
  const _GuardInfo({required this.note, required this.onHelp});

  final String note;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: LiveRankTheme.guardInfoGap,
      left: LiveRankTheme.guardContentInset - LiveRankTheme.panelInset - LiveRankTheme.panelRimWidth,
    ),
    child: SizedBox(
      height: LiveRankTheme.infoHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: RankTap(
          label: '大航海说明',
          onTap: onHelp,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: RankText(note, rankStyle(LiveRankTheme.infoText, LiveRankTheme.guardInfoInk))),
              const SizedBox(width: LiveRankTheme.helpGap),
              const RankGlyph(RankArt.help, size: LiveRankTheme.helpSize, color: LiveRankTheme.guardHelpInk),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A 大航海 row (231).
class GuardRow extends StatelessWidget {
  const GuardRow({super.key, required this.entry});

  final LiveRankEntry entry;

  /// The row sits inside the panel's rim; its places are measured from the sheet's edge.
  static const _shift = LiveRankTheme.panelInset + LiveRankTheme.panelRimWidth;

  @override
  Widget build(BuildContext context) {
    const height = LiveRankTheme.rowHeight;
    final user = entry.user;
    final medal = user.medal;
    return Stack(
      children: [
        rowLine(
          height: height,
          centre: 0,
          lineHeight: height,
          left: LiveRankTheme.guardRankLeft - _shift,
          alignment: Alignment.center,
          child: SizedBox(
            width: LiveRankTheme.rankWidth,
            child: Center(
              child: RankNumber(
                rank: entry.rank,
                art: RankArt.guardNumeral(entry.rank),
                style: rankStyle(LiveRankTheme.guardRankText, LiveRankTheme.guardRankInk),
              ),
            ),
          ),
        ),
        rowLine(
          height: height,
          centre: 0,
          lineHeight: LiveRankTheme.faceSize,
          left: LiveRankTheme.guardFaceLeft - _shift,
          child: LiveFace(
            url: user.face,
            size: LiveRankTheme.faceSize,
            guardLevel: user.guardLevel,
            frame: user.faceFrame,
          ),
        ),
        rowLine(
          height: height,
          centre: LiveRankTheme.nameCentre,
          lineHeight: LiveRankTheme.nameLine,
          left: LiveRankTheme.guardNameLeft - _shift,
          right: LiveRankTheme.guardContentInset - _shift,
          child: RankText(
            user.name,
            rankStyle(LiveRankTheme.nameText, LiveRankTheme.guardNameInk, weight: LiveRankTheme.nameWeight),
          ),
        ),
        if (medal != null)
          rowLine(
            height: height,
            centre: LiveRankTheme.guardChipsCentre,
            lineHeight: LiveRankTheme.chipsHeight,
            left: LiveRankTheme.guardNameLeft - _shift,
            child: LiveMedalChip(medal: medal),
          ),
      ],
    );
  }
}

/// 千舰 头号粉丝大航海，等你来上船 and 立即上船.
class _BoardBar extends StatelessWidget {
  const _BoardBar({required this.total, required this.onBoard});

  final int? total;
  final VoidCallback onBoard;

  /// The room's fleet badge by its count. 231 shows 千舰 at 3351; 百舰 and 万舰 are Bilibili's other two.
  static String? badge(int? total) => switch (total) {
    null => null,
    >= 10000 => '万舰',
    >= 1000 => '千舰',
    >= 100 => '百舰',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final badge = _BoardBar.badge(total);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LiveRankTheme.barFill,
        border: Border.all(color: LiveRankTheme.barRim, width: LiveRankTheme.barRimWidth),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(LiveRankTheme.barRadius)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: LiveRankTheme.barRow,
          child: Row(
            children: [
              if (badge != null) ...[
                const SizedBox(width: LiveRankTheme.badgeLeft),
                SizedBox(
                  width: LiveRankTheme.promptLeft - LiveRankTheme.badgeLeft,
                  child: Align(alignment: Alignment.centerLeft, child: _Badge(badge)),
                ),
              ] else
                const SizedBox(width: LiveRankTheme.promptLeftBare),
              Expanded(child: RankText('头号粉丝大航海，等你来上船', rankStyle(LiveRankTheme.promptText, LiveRankTheme.promptInk))),
              RankTap(label: '立即上船', onTap: onBoard, child: const _BoardButton()),
              const SizedBox(width: LiveRankTheme.edgeRight),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      Container(
        width: LiveRankTheme.badgeGlowWidth,
        height: LiveRankTheme.badgeGlowHeight,
        decoration: const BoxDecoration(gradient: RadialGradient(colors: [LiveRankTheme.badgeGlow, Color(0x00000000)])),
      ),
      ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LiveRankTheme.badgeTop, LiveRankTheme.badgeBottom],
        ).createShader(bounds),
        child: RankText(
          text,
          rankStyle(LiveRankTheme.badgeText, LiveRankTheme.badgeTop, weight: LiveRankTheme.badgeWeight),
        ),
      ),
    ],
  );
}

class _BoardButton extends StatelessWidget {
  const _BoardButton();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('rank-board'),
    height: LiveRankTheme.boardHeight,
    padding: const EdgeInsets.only(left: LiveRankTheme.boardAnchorLeft, right: LiveRankTheme.boardPadRight),
    decoration: const ShapeDecoration(
      shape: StadiumBorder(),
      gradient: LinearGradient(colors: [LiveRankTheme.boardStart, LiveRankTheme.boardEnd]),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          RankArt.anchor,
          height: LiveRankTheme.boardAnchor,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: LiveRankTheme.boardAnchorGap),
        RankText('立即上船', rankStyle(LiveRankTheme.boardText, LiveRankTheme.boardInk)),
      ],
    ),
  );
}
