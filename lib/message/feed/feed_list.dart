import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../comments/comments_tab.dart' show NearEndPaging;
import '../../friends/friends_rows.dart' show FriendsMessage;
import '../../shared/loading_tv.dart';
import '../../shared/release_refresh.dart';
import '../../shared/theme.dart';
import 'feed_lane.dart';
import 'feed_parts.dart';

/// One list of the page: the TV while its first page loads, its failure with 重试, [empty] once it answers with
/// nothing, else the rows with the footer's spinner or 加载失败，点击重试. Pulled, it refreshes; near its end, it asks
/// for the next page.
class FeedList<T> extends StatefulWidget {
  const FeedList({
    super.key,
    required this.name,
    required this.lane,
    required this.scroll,
    required this.row,
    required this.empty,
    required this.refreshRoom,
    required this.refreshTrigger,
    required this.onRefreshFailed,
  });

  /// Names its keys: `feed-<name>-…`.
  final String name;
  final FeedLane<T> lane;
  final ScrollController scroll;

  /// A row; [last] is the list's very last, with nothing more to load (198 draws no rule under it).
  final Widget Function(BuildContext context, T item, bool last) row;
  final Widget empty;
  final double refreshRoom;
  final double refreshTrigger;
  final ValueChanged<String> onRefreshFailed;

  @override
  State<FeedList<T>> createState() => _FeedListState<T>();
}

class _FeedListState<T> extends State<FeedList<T>> {
  late final _paging = NearEndPaging(canAsk: () => widget.lane.canLoadMore, ask: () => widget.lane.loadMore());

  @override
  void dispose() {
    _paging.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final failure = await widget.lane.refresh();
    if (failure != null && mounted) widget.onRefreshFailed(failure);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.lane, builder: (context, _) => _body());

  Widget _body() {
    final lane = widget.lane;
    final name = widget.name;
    if (!lane.loaded) {
      final error = lane.error;
      if (error == null) return Center(key: ValueKey('feed-$name-loading'), child: const LoadingTvState());
      return FriendsMessage(
        key: ValueKey('feed-$name-failed'),
        message: error,
        action: '重试',
        actionKey: ValueKey('feed-$name-retry'),
        onAction: () => unawaited(lane.retry()),
      );
    }
    final items = lane.items;
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewInsets.bottom, media.padding.bottom);
    return _paging.listen(
      CustomScrollView(
        key: ValueKey('feed-$name-list'),
        controller: widget.scroll,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          ReleaseRefreshControl(
            refreshTriggerPullDistance: widget.refreshTrigger,
            refreshIndicatorExtent: widget.refreshRoom,
            onRefresh: _refresh,
          ),
          if (items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: widget.empty)
          else ...[
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  widget.row(context, items[index], index == items.length - 1 && !lane.hasMore),
            ),
            SliverToBoxAdapter(
              child: _Footer(
                name: name,
                loading: lane.loadingMore,
                error: lane.error,
                onRetry: () => unawaited(lane.retry()),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        ],
      ),
    );
  }
}

/// Under the rows: the small spinner while the next page loads, or 加载失败，点击重试.
class _Footer extends StatelessWidget {
  const _Footer({required this.name, required this.loading, required this.error, required this.onRetry});

  final String name;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(vertical: MessageFeedTheme.footerPad);
    if (loading) {
      return Padding(
        padding: padding,
        child: CupertinoActivityIndicator(key: ValueKey('feed-$name-more'), radius: MessageFeedTheme.spinnerRadius),
      );
    }
    if (error == null) return const SizedBox.shrink();
    final style = feedStyle(MessageFeedTheme.footerText, MessageFeedTheme.footerInk);
    return FeedTap(
      key: ValueKey('feed-$name-footer-retry'),
      label: '加载失败，点击重试',
      onTap: onRetry,
      child: Padding(
        padding: padding,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '加载失败，', style: style),
              TextSpan(
                text: '点击重试',
                style: style.copyWith(color: BiliColors.link),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
