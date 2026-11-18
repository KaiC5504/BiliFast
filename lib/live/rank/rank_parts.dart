import 'package:bili_core/api.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../shared/loading_tv.dart';
import '../../shared/theme.dart';
import 'live_rank_model.dart';

TextStyle rankStyle(double size, Color color, {FontWeight? weight, double? height}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// One line of [text], never wrapped.
class RankText extends StatelessWidget {
  const RankText(this.text, this.style, {super.key, this.align});

  final String text;
  final TextStyle style;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, textAlign: align);
}

/// A press target VoiceOver and ghosthand can press too.
class RankTap extends StatelessWidget {
  const RankTap({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
  );
}

/// One of the APK's grey glyphs (ⓘ, ⇌), drawn [size] square in [color].
class RankGlyph extends StatelessWidget {
  const RankGlyph(this.asset, {super.key, required this.size, required this.color});

  final String asset;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: size,
    height: size,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

abstract final class RankArt {
  static const help = 'assets/images/live/rank_question.png';
  static const exchange = 'assets/images/live/rank_exchange.png';
  static const anchor = 'assets/images/live/rank_anchor.png';

  /// 房间观众's 榜1-3.
  static String? tag(int rank) => rank >= 1 && rank <= 3 ? 'assets/images/live/rank_tag_$rank.png' : null;

  /// 大航海's italic 1-3.
  static String? guardNumeral(int rank) => rank >= 1 && rank <= 3 ? 'assets/images/live/rank_guard_$rank.png' : null;
}

/// [child] with its middle [centre] below the middle of a [height] tall row, [left] in.
Widget rowLine({
  required double height,
  required double centre,
  required double lineHeight,
  required Widget child,
  double? left,
  double? right,
  AlignmentGeometry alignment = Alignment.centerLeft,
}) => Positioned(
  left: left,
  right: right,
  top: height / 2 + centre - lineHeight / 2,
  height: lineHeight,
  child: Align(alignment: alignment, child: child),
);

/// A rank column's entry: [art] for 1-3, else the number.
class RankNumber extends StatelessWidget {
  const RankNumber({super.key, required this.rank, required this.art, required this.style});

  final int rank;
  final String? art;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final asset = art;
    if (asset != null) {
      return Image.asset(
        asset,
        width: LiveRankTheme.rankWidth,
        height: LiveRankTheme.rankHeight,
        filterQuality: FilterQuality.medium,
        semanticLabel: '第$rank名',
      );
    }
    return RankText(rank > 0 ? '$rank' : '-', style, align: TextAlign.center);
  }
}

/// A list of [feed]'s rows under [header], loading the next page as its end nears: the TV before the first page, a
/// failure with 重试, the next page's spinner under the rows.
class RankList extends StatefulWidget {
  const RankList({
    super.key,
    required this.feed,
    required this.row,
    this.header = const [],
    this.bottom = 0,
    this.emptyText = '暂无数据',
  });

  final RankFeed<Object?> feed;
  final Widget Function(LiveRankEntry entry) row;
  final List<Widget> header;

  /// Space under the last row (the home indicator's, when nothing else sits there).
  final double bottom;
  final String emptyText;

  @override
  State<RankList> createState() => _RankListState();
}

class _RankListState extends State<RankList> {
  final _scroll = ScrollController();
  bool _checkQueued = false;

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_changed);
  }

  @override
  void didUpdateWidget(RankList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.feed, widget.feed)) {
      oldWidget.feed.removeListener(_changed);
      widget.feed.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.feed.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // A page too short to scroll leaves its end on screen with no scrolling to notice it.
    _checkAfterFrame();
  }

  void _checkAfterFrame() {
    if (_checkQueued) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _loadMoreNearEnd();
    });
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth == 0) _loadMoreNearEnd();
    return false;
  }

  void _loadMoreNearEnd() {
    final feed = widget.feed;
    if (!feed.canLoadMore || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || position.extentAfter >= LiveRankTheme.loadAhead) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _checkAfterFrame();
    } else {
      feed.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final entries = feed.entries;
    return NotificationListener<ScrollNotification>(
      onNotification: _scrolled,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          for (final header in widget.header) SliverToBoxAdapter(child: header),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.bottom),
                child: Center(child: _state(feed)),
              ),
            )
          else ...[
            SliverFixedExtentList.builder(
              itemExtent: LiveRankTheme.rowHeight,
              itemCount: entries.length,
              itemBuilder: (_, index) => widget.row(entries[index]),
            ),
            SliverToBoxAdapter(child: _footer(feed)),
            SliverToBoxAdapter(child: SizedBox(height: widget.bottom)),
          ],
        ],
      ),
    );
  }

  Widget _state(RankFeed<Object?> feed) {
    if (feed.error case final error?) return RankFailure(message: error, onRetry: feed.retry);
    if (feed.exhausted) {
      return RankText(widget.emptyText, rankStyle(LiveRankTheme.stateText, LiveRankTheme.stateInk));
    }
    return const LoadingTvState();
  }

  Widget _footer(RankFeed<Object?> feed) {
    final error = feed.error;
    final Widget child;
    if (error != null) {
      child = RankFailure(message: error, onRetry: feed.retry);
    } else if (feed.loadingMore) {
      child = const SizedBox(
        height: LiveRankTheme.footerLine,
        child: CupertinoActivityIndicator(radius: LiveRankTheme.spinnerRadius),
      );
    } else {
      child = const SizedBox(height: LiveRankTheme.footerLine);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LiveRankTheme.footerPad),
      child: Center(child: child),
    );
  }
}

/// Why a list stopped, and 重试.
class RankFailure extends StatelessWidget {
  const RankFailure({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message, textAlign: TextAlign.center, style: rankStyle(LiveRankTheme.stateText, LiveRankTheme.stateInk)),
      const SizedBox(height: LiveRankTheme.stateGap),
      RankTap(
        label: '重试',
        onTap: onRetry,
        child: Container(
          height: LiveRankTheme.retryHeight,
          padding: const EdgeInsets.symmetric(horizontal: LiveRankTheme.retryPadX),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(color: LiveRankTheme.retryInk, width: LiveRankTheme.retryRim),
            ),
          ),
          child: Text('重试', style: rankStyle(LiveRankTheme.retryText, LiveRankTheme.retryInk)),
        ),
      ),
    ],
  );
}
