import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../live_badges.dart';
import 'live_rank_model.dart';
import 'rank_parts.dart';

/// 房间观众 (230, 232): the 在线榜 pill, the 贡献值 line, the rows, and the viewer's own row pinned under them when
/// logged in.
class RankAudiencePage extends StatefulWidget {
  const RankAudiencePage({
    super.key,
    required this.feed,
    required this.loggedIn,
    required this.ownFace,
    required this.bottomInset,
    required this.onUnavailable,
  });

  final RankFeed<LiveRankPage> feed;
  final bool loggedIn;
  final String ownFace;
  final double bottomInset;

  /// ⓘ, 贡献值 ⇌ and 去投喂: 暂未开放.
  final VoidCallback onUnavailable;

  @override
  State<RankAudiencePage> createState() => _RankAudiencePageState();
}

class _RankAudiencePageState extends State<RankAudiencePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final inset = widget.bottomInset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: LiveRankTheme.audienceListTop,
          child: Stack(
            children: [
              const Positioned(left: LiveRankTheme.pillLeft, top: 0, child: _OnlinePill()),
              Positioned(
                left: 0,
                right: 0,
                top: LiveRankTheme.infoTop,
                height: LiveRankTheme.infoHeight,
                child: _InfoLine(onUnavailable: widget.onUnavailable),
              ),
            ],
          ),
        ),
        Expanded(
          child: RankList(
            key: const ValueKey('rank-audience-list'),
            feed: widget.feed,
            bottom: widget.loggedIn ? 0 : inset,
            row: (entry) => AudienceRow(key: ValueKey('rank-audience-${entry.user.uid}-${entry.rank}'), entry: entry),
          ),
        ),
        if (widget.loggedIn)
          ListenableBuilder(
            listenable: widget.feed,
            builder: (context, _) => OwnRow(
              own: widget.feed.first?.own,
              face: widget.ownFace,
              bottomInset: inset,
              onFeed: widget.onUnavailable,
            ),
          ),
      ],
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill();

  @override
  Widget build(BuildContext context) => Container(
    height: LiveRankTheme.pillHeight,
    padding: const EdgeInsets.symmetric(horizontal: LiveRankTheme.pillPadX),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: LiveRankTheme.pillFill,
      borderRadius: BorderRadius.circular(LiveRankTheme.pillRadius),
    ),
    child: RankText('在线榜', rankStyle(LiveRankTheme.pillText, LiveRankTheme.pillInk)),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.onUnavailable});

  final VoidCallback onUnavailable;

  @override
  Widget build(BuildContext context) {
    final style = rankStyle(LiveRankTheme.infoText, LiveRankTheme.audienceInfoInk);
    return Row(
      children: [
        const SizedBox(width: LiveRankTheme.audienceInfoLeft),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: RankTap(
              label: '贡献值说明',
              onTap: onUnavailable,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: RankText('投喂、点赞、发弹幕均可获得贡献值', style)),
                  const SizedBox(width: LiveRankTheme.helpGap),
                  RankGlyph(RankArt.help, size: LiveRankTheme.helpSize, color: LiveRankTheme.audienceInfoInk),
                ],
              ),
            ),
          ),
        ),
        RankTap(
          label: '贡献值排序',
          onTap: onUnavailable,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RankText('贡献值', style),
              const SizedBox(width: LiveRankTheme.exchangeGap),
              RankGlyph(RankArt.exchange, size: LiveRankTheme.exchangeSize, color: LiveRankTheme.audienceInfoInk),
            ],
          ),
        ),
        const SizedBox(width: LiveRankTheme.edgeRight),
      ],
    );
  }
}

/// A 在线榜 row (230).
class AudienceRow extends StatelessWidget {
  const AudienceRow({super.key, required this.entry});

  final LiveRankEntry entry;

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
          left: LiveRankTheme.audienceRankLeft,
          alignment: Alignment.center,
          child: SizedBox(
            width: LiveRankTheme.rankWidth,
            child: Center(
              child: RankNumber(
                rank: entry.rank,
                art: RankArt.tag(entry.rank),
                style: rankStyle(LiveRankTheme.audienceRankText, LiveRankTheme.audienceRankInk),
              ),
            ),
          ),
        ),
        rowLine(
          height: height,
          centre: 0,
          lineHeight: LiveRankTheme.faceSize,
          left: LiveRankTheme.audienceFaceLeft,
          child: LiveFace(
            url: user.face,
            size: LiveRankTheme.faceSize,
            guardLevel: user.guardLevel,
            frame: user.faceFrame,
          ),
        ),
        Positioned(
          left: LiveRankTheme.audienceNameLeft,
          right: LiveRankTheme.scoreRight,
          top: 0,
          bottom: 0,
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    rowLine(
                      height: height,
                      centre: LiveRankTheme.nameCentre,
                      lineHeight: LiveRankTheme.nameLine,
                      left: 0,
                      right: 0,
                      child: RankText(
                        user.name,
                        rankStyle(
                          LiveRankTheme.nameText,
                          LiveRankTheme.audienceNameInk,
                          weight: LiveRankTheme.nameWeight,
                        ),
                      ),
                    ),
                    rowLine(
                      height: height,
                      centre: LiveRankTheme.audienceChipsCentre,
                      lineHeight: LiveRankTheme.chipsHeight,
                      left: 0,
                      right: 0,
                      child: _Chips(wealth: user.wealthLevel, medal: medal),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LiveRankTheme.scoreGap),
              RankText('${entry.score}', rankStyle(LiveRankTheme.scoreText, LiveRankTheme.scoreInk)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.wealth, required this.medal});

  final int wealth;
  final LiveMedal? medal;

  @override
  Widget build(BuildContext context) {
    final medal = this.medal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (wealth > 0) LiveWealthChip(level: wealth),
        if (wealth > 0 && medal != null) const SizedBox(width: LiveRankTheme.chipGap),
        if (medal != null) LiveMedalChip(medal: medal),
      ],
    );
  }
}

/// The viewer's own row under the list (230): their rank or -, face, 贡献值 and 去投喂.
class OwnRow extends StatelessWidget {
  const OwnRow({super.key, required this.own, required this.face, required this.bottomInset, required this.onFeed});

  final LiveRankEntry? own;
  final String face;
  final double bottomInset;
  final VoidCallback onFeed;

  @override
  Widget build(BuildContext context) {
    const height = LiveRankTheme.ownHeight;
    final rank = own?.rank ?? 0;
    final small = rankStyle(LiveRankTheme.ownText, LiveRankTheme.ownInk);
    return Container(
      key: const ValueKey('rank-own'),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: LiveRankTheme.audiencePage,
        border: Border(
          top: BorderSide(color: LiveRankTheme.ownRuleInk, width: LiveRankTheme.ownRule),
        ),
      ),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            rowLine(
              height: height,
              centre: 0,
              lineHeight: height,
              left: LiveRankTheme.audienceRankLeft,
              child: SizedBox(
                width: LiveRankTheme.rankWidth,
                child: RankText(
                  rank > 0 ? '$rank' : '-',
                  rankStyle(LiveRankTheme.audienceRankText, LiveRankTheme.ownRankInk),
                  align: TextAlign.center,
                ),
              ),
            ),
            rowLine(
              height: height,
              centre: 0,
              lineHeight: LiveRankTheme.faceSize,
              left: LiveRankTheme.audienceFaceLeft,
              child: LiveFace(url: face, size: LiveRankTheme.faceSize),
            ),
            rowLine(
              height: height,
              centre: LiveRankTheme.ownTopCentre,
              lineHeight: LiveRankTheme.ownLine,
              left: LiveRankTheme.audienceNameLeft,
              right: LiveRankTheme.feedWidth + LiveRankTheme.edgeRight,
              child: RankText('贡献值 ${own?.score ?? 0}', small),
            ),
            rowLine(
              height: height,
              centre: LiveRankTheme.ownBottomCentre,
              lineHeight: LiveRankTheme.ownLine,
              left: LiveRankTheme.audienceNameLeft,
              right: LiveRankTheme.feedWidth + LiveRankTheme.edgeRight,
              child: RankText('快来投喂吧～', small),
            ),
            rowLine(
              height: height,
              centre: 0,
              lineHeight: LiveRankTheme.feedHeight,
              right: LiveRankTheme.edgeRight,
              alignment: Alignment.centerRight,
              child: RankTap(
                label: '去投喂',
                onTap: onFeed,
                child: Container(
                  width: LiveRankTheme.feedWidth,
                  height: LiveRankTheme.feedHeight,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(color: LiveRankTheme.feedFill, shape: const StadiumBorder()),
                  child: RankText('去投喂', rankStyle(LiveRankTheme.feedText, LiveRankTheme.feedInk)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
