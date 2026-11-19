import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../app/form_factor.dart';
import '../../home/feed_inline_player.dart';
import '../../home/tab_bar_icons.dart' show SkinDecodeGate;
import '../../shared/loading_tv.dart';
import '../../shared/release_refresh.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../skin/skin.dart';
import '../../space/follow_book.dart';
import '../../space/space_route.dart';
import '../../space/uploader_tap.dart';
import '../following/following_route.dart';
import 'face_sheet.dart';
import 'follow_feed_model.dart';
import 'follow_header.dart';
import 'follow_parts.dart';
import 'follow_top.dart';

/// The bottom bar's 关注 (127, 128): the header, 全部 / 视频, 最常访问 and, on 视频, 我的追番 · 追剧 over the posts,
/// paged, pulled to refresh. It loads the first time it is shown. A face opens the face sheet ([faceSheet], drawn by
/// `MainShell` over the bar too); video cards play muted where they settle while 关注 is shown with nothing over it.
/// An unfollow made anywhere takes that account's posts off both lists at once.
class FollowTabPage extends StatefulWidget {
  const FollowTabPage({
    super.key,
    required this.active,
    required this.faceSheet,
    this.reloads,
    this.countReloads,
    this.skin,
  });

  /// 关注 is the tab shown.
  final bool active;
  final FaceSheetController faceSheet;

  /// Notifies for each tap on the bar's 关注 while 关注 shows: the list goes back to the top and refreshes.
  final Listenable? reloads;

  /// Notifies as 关注 is opened over its count: as [reloads], and 全部 is asked again under 视频 too, since the count
  /// goes from 全部's newest post.
  final Listenable? countReloads;

  /// The equipped 装扮: with a `head_bg` it dresses the header.
  final Skin? skin;

  @override
  State<FollowTabPage> createState() => _FollowTabPageState();
}

class _FollowTabPageState extends State<FollowTabPage> with SkinRefreshRoom, TickerProviderStateMixin {
  static const _soon = '暂未开放';

  late AppServices _services;
  late AppEnvironment _environment;
  late FollowBook _follows;
  FollowTabModel? _model;

  /// Each post's card, so a leaving one can be lifted out of the list and fade over it.
  final _cardKeys = <String, GlobalKey>{};

  /// Posts of an unfollowed account still drawn where they were, by id.
  final _leaving = <String, _Leaving>{};

  /// Each post's height as the list last laid it out, which the list's offsets still count once it is no longer built.
  final _heights = <String, double>{};
  final _postsKey = GlobalKey();
  bool _started = false;
  bool _signedOut = false;

  /// Counts the first loads, so 登录 can tell the login already started one.
  int _starts = 0;

  final _scroll = ScrollController();
  final _faces = ScrollController();
  final _facesKey = GlobalKey();
  final _listKey = GlobalKey();
  late final _paging = FollowPaging(
    canAsk: () => _model?.current.canLoadMore ?? false,
    ask: () => _model!.current.loadMore(),
  );
  FeedInlineHost? _inline;

  /// The refresh running, from a pull or a tap on 关注; another waits on it.
  Future<String?>? _refreshing;

  /// 关注's tap holds the TV open at the top until its refresh is done; [_reloadRoom] keeps it built while closing.
  bool _reloadHeader = false;
  bool _reloadRoom = false;

  /// Reduce Motion and the inset under the list (the home indicator, or a dressed bar), as the last build saw them.
  bool _still = false;
  double _inset = 0;

  @override
  void initState() {
    super.initState();
    widget.reloads?.addListener(_reload);
    widget.countReloads?.addListener(_reloadOverCount);
    widget.faceSheet.addListener(_sheetChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    _services = AppScope.of(context);
    _environment = _services.environment..addListener(_accountChanged);
    _follows = _services.follows..addListener(_followsChanged);
    _signedOut = _loggedOut;
    _model = FollowTabModel(
      api: _services.dynamicApi,
      mid: () => _environment.mid,
      // The iPad's bar draws no count on 动态, so its 全部 hands nothing on.
      onBaseline: FormFactor.of(context).isPad ? null : _services.followBadge.seen,
    )..addListener(_modelChanged);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(FollowTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reloads, widget.reloads)) {
      oldWidget.reloads?.removeListener(_reload);
      widget.reloads?.addListener(_reload);
    }
    if (!identical(oldWidget.countReloads, widget.countReloads)) {
      oldWidget.countReloads?.removeListener(_reloadOverCount);
      widget.countReloads?.addListener(_reloadOverCount);
    }
    if (!identical(oldWidget.faceSheet, widget.faceSheet)) {
      oldWidget.faceSheet.removeListener(_sheetChanged);
      widget.faceSheet.addListener(_sheetChanged);
    }
    if (widget.active && !oldWidget.active) _start();
  }

  @override
  void dispose() {
    widget.reloads?.removeListener(_reload);
    widget.countReloads?.removeListener(_reloadOverCount);
    widget.faceSheet.removeListener(_sheetChanged);
    _environment.removeListener(_accountChanged);
    _follows.removeListener(_followsChanged);
    for (final leaving in _leaving.values) {
      leaving.dispose();
    }
    _paging.dispose();
    _inline?.dispose();
    _model?.dispose();
    _faces.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _loggedOut => switch (_environment.account) {
    LoggedOut() || LoginExpired() => true,
    LoggedIn() || AccountUnknown() => false,
  };

  /// The first show loads 最常访问 and the list; logged out it asks Bilibili nothing.
  void _start() {
    if (_started || _loggedOut) return;
    _started = true;
    _starts++;
    unawaited(_model!.start());
  }

  /// Logging out empties the tab (and closes the sheet); logging in loads it at once if 关注 is showing, otherwise on
  /// its next show.
  void _accountChanged() {
    final out = _loggedOut;
    if (out == _signedOut) return;
    _signedOut = out;
    if (out) {
      widget.faceSheet.close();
      for (final leaving in _leaving.values) {
        leaving.dispose();
      }
      _leaving.clear();
      _cardKeys.clear();
      _heights.clear();
      _model?.signOut();
      _started = false;
    } else if (widget.active) {
      _start();
    }
    setState(() {});
  }

  void _modelChanged() {
    if (!mounted) return;
    final model = _model!;
    // A list that started over drops what was left of the old one.
    final stale = [
      for (final each in _leaving.values)
        if (each.generation != each.feed.generation) each,
    ];
    for (final each in stale) {
      _leaving.remove(each.item.id);
      each.dispose();
    }
    final posts = model.all.items.length + model.video.items.length;
    if (_cardKeys.length > posts || _heights.length > posts) {
      final kept = {
        for (final item in [...model.all.items, ...model.video.items]) item.id,
        for (final each in _leaving.values)
          if (each.moving) each.item.id,
      };
      _cardKeys.removeWhere((id, _) => !kept.contains(id));
      _heights.removeWhere((id, _) => !kept.contains(id));
    }
    setState(() {});
    _inline?.settleSoon();
  }

  void _followsChanged() {
    if (_follows.last case (:final mid, following: false) when _model != null) _drop(mid);
  }

  /// 关注 shows with nothing over it, so a post can be seen leaving.
  bool get _showing =>
      widget.active &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      !widget.faceSheet.isOpen;

  /// [mid]'s posts leave both lists. Those on screen fade where they lie while the posts under them close the gap
  /// (263); the others close at once, the list moved up by those above the screen so what shows stays put.
  ///
  /// Each stays in the list as an empty row until the list starts over: the list hands a post that changes index the
  /// laid-out offset of the one that had it before, so taking rows out above the screen would shift what shows.
  void _drop(int mid) {
    final model = _model!;
    final feed = model.current;
    final view = _listArea();
    final moving = view != null && _showing && !MediaQuery.disableAnimationsOf(context);
    final rows = _rows(feed);
    RenderBox? built(_Shown row) {
      final box = _cardKeys[row.item.id]?.currentContext?.findRenderObject();
      return box is RenderBox && box.attached && box.hasSize ? box : null;
    }

    // The list lays out only the rows near the screen; those before them count in its offsets by their last height.
    final firstBuilt = rows.indexWhere((row) => row.leaving == null && built(row) != null);
    var lift = 0.0;
    var closed = 0.0;
    String? after;
    for (final (index, row) in rows.indexed) {
      final item = row.item;
      if (row.leaving == null && item.author.mid == mid) {
        final box = built(row);
        final rect = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
        final band = index == 0;
        final kept = band ? DynamicFeedTheme.band : 0.0;
        var onScreen = false;
        if ((rect, view) case (final rect?, final view?)) {
          final above = rect.bottom <= view.top;
          if (above) lift += rect.height - kept;
          onScreen = moving && !above && rect.top < view.bottom;
        } else if (rect == null && index < firstBuilt) {
          closed += math.max((_heights[item.id] ?? 0) - kept, 0);
        }
        final leaving = _Leaving(
          item: item,
          feed: feed,
          generation: feed.generation,
          after: after,
          height: rect?.height ?? 0,
          band: band,
          controller: onScreen ? AnimationController(vsync: this, duration: DynamicFeedTheme.leave) : null,
        );
        leaving.controller?.forward().whenComplete(() => _landed(leaving));
        _leaving[item.id] = leaving;
      }
      after = item.id;
    }
    model.removeAuthor(mid);
    if (lift > 0 && _scroll.hasClients) _scroll.jumpTo(_scroll.offset - lift);
    if (_postsKey.currentContext?.findRenderObject() case final _RenderPostsSliver posts) posts.closeAbove(closed);
  }

  /// The gap has closed: the faded card is let go.
  void _landed(_Leaving leaving) {
    if (!mounted || !identical(_leaving[leaving.item.id], leaving)) return;
    setState(() {
      leaving.land();
      _cardKeys.remove(leaving.item.id);
    });
  }

  /// [feed]'s posts as drawn: with those leaving it still in their places.
  List<_Shown> _rows(FollowFeed feed) {
    final items = feed.items;
    final leaving = [
      for (final each in _leaving.values)
        if (identical(each.feed, feed) && each.generation == feed.generation) each,
    ];
    if (leaving.isEmpty) return [for (final item in items) _Shown(item)];
    final ids = {for (final item in items) item.id};
    final byPlace = <String?, List<_Leaving>>{};
    for (final each in leaving) {
      if (!ids.contains(each.item.id)) (byPlace[each.after] ??= []).add(each);
    }
    final rows = <_Shown>[];
    void follow(String? id) {
      for (final each in byPlace[id] ?? const <_Leaving>[]) {
        rows.add(_Shown(each.item, leaving: each));
        follow(each.item.id);
      }
    }

    follow(null);
    for (final item in items) {
      rows.add(_Shown(item));
      follow(item.id);
    }
    return rows;
  }

  void _sheetChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _refresh() {
    if (_refreshing case final running?) return running;
    late final Future<String?> refresh;
    refresh = _model!.refresh().whenComplete(() {
      if (identical(_refreshing, refresh)) _refreshing = null;
    });
    return _refreshing = refresh;
  }

  Future<void> _pull() async {
    final failure = await _refresh();
    if (failure != null && mounted) showToast(context, failure);
  }

  void _reloadOverCount() {
    if (_loggedOut) return;
    if (_model!.type == DynamicFeedType.video) unawaited(_model!.all.reload());
    unawaited(_reload());
  }

  /// 关注 tapped while shown, as 首页's: back to the top, then the TV held open there until the refresh is done. With
  /// no post shown the list's own TV stands for it, and a first load still out answers for it (a double tap on the
  /// first show asks once).
  Future<void> _reload() async {
    if (_refreshing != null || _loggedOut) return;
    if (!_started) {
      _start();
      return;
    }
    if (_model!.current.items.isEmpty) {
      unawaited(_refresh());
      return;
    }
    final refresh = _refresh();
    if (_scroll.hasClients) {
      if (_still) {
        _scroll.jumpTo(0);
      } else {
        await _scroll.animateTo(0, duration: DynamicFeedTheme.reloadScroll, curve: Curves.easeOut);
      }
    }
    if (!mounted || !identical(_refreshing, refresh)) return;
    setState(() => _reloadHeader = _reloadRoom = true);
    final failure = await refresh;
    if (!mounted) return;
    setState(() => _reloadHeader = false);
    if (failure != null) showToast(context, failure);
  }

  Future<void> _login() async {
    final starts = _starts;
    final loggedIn = await _services.loginGate.request(context);
    // A login that changed the account has loaded the tab already (_accountChanged).
    if (!loggedIn || !mounted || !widget.active || _starts != starts) return;
    if (_started) {
      unawaited(_refresh());
    } else {
      _start();
    }
  }

  void _soonToast() => showToast(context, _soon);

  /// 全部 ›: the account's own space on its 追番.
  void _openOwnBangumi() {
    final mid = _environment.mid;
    if (mid == null) return;
    unawaited(openSpace(context, UploaderRef(mid: mid, face: _environment.face), ownTab: SpaceTabKind.bangumi));
  }

  void _openFace(DynamicUp up) {
    final box = _facesKey.currentContext?.findRenderObject();
    final top = box is RenderBox && box.attached ? box.localToGlobal(Offset.zero).dy : null;
    widget.faceSheet.open(up, model: _model!, rowOffset: _faces.hasClients ? _faces.offset : 0, originTop: top);
  }

  Rect? _listArea() {
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final area = box.localToGlobal(Offset.zero) & box.size;
    return Rect.fromLTRB(area.left, area.top, area.right, math.max(area.top, area.bottom - _inset));
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.skin?.headBg != null ? widget.skin : null;
    return SkinDecodeGate(
      pictures: [?head?.headBg],
      builder: (context, decoded) => _page(context, decoded ? head : null),
    );
  }

  /// [head] dresses the header once its picture has decoded.
  Widget _page(BuildContext context, Skin? head) {
    _still = MediaQuery.disableAnimationsOf(context);
    _inset = MediaQuery.paddingOf(context).bottom;
    final inline = _inline ??= FeedInlineHost(
      viewport: _listArea,
      pip: _services.pipKeeper,
      autoplay: InlineAutoplay.list,
    );
    // A route over the shell (a page, a sheet, a menu), another tab or the face sheet pauses the cards.
    inline.shown =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        !widget.faceSheet.isOpen;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (head == null ? BiliTheme.dark : head.lightStatusFollow)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Material(
        color: BiliColors.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FollowHeader(skin: head, onWrite: _soonToast),
            Expanded(
              child: KeyedSubtree(key: _listKey, child: _body(context, inline)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FeedInlineHost inline) {
    // A -101 with nothing shown asks for the login too: the app may still think it is logged in.
    if (_loggedOut || (_model!.current.needsLogin && _model!.current.items.isEmpty)) {
      return Center(
        key: const ValueKey('follow-logged-out'),
        child: FollowStateMessage(
          message: '登录后查看关注动态',
          button: FollowPinkButton(
            key: const ValueKey('follow-login'),
            label: '登录',
            onTap: () => unawaited(_login()),
            text: DynamicFeedTheme.loginText,
            height: DynamicFeedTheme.loginHeight,
            padX: DynamicFeedTheme.loginPadX,
          ),
        ),
      );
    }
    // Never shown yet: nothing to draw, and no TV ticking out of sight.
    if (!_started) return const SizedBox.shrink();
    final model = _model!;
    final feed = model.current;
    final rows = _rows(feed);
    final at = {for (final (index, row) in rows.indexed) row.item.id: index};
    final fading = [
      for (final row in rows)
        if (row.leaving case final leaving? when leaving.moving) leaving,
    ];
    final bangumi = model.bangumi;
    final bottom = _inset;
    final still = _still;
    final room = refreshRoom;
    final list = _paging.listen(
      _scroll,
      NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) inline.settleSoon();
          return false;
        },
        child: CustomScrollView(
          key: const ValueKey('follow-list'),
          controller: _scroll,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            ReleaseRefreshControl(
              refreshTriggerPullDistance: refreshTrigger,
              refreshIndicatorExtent: room,
              builder: _reloadHeader ? null : loadingTvRefreshIndicator,
              onRefresh: _reloadHeader ? null : _pull,
            ),
            SliverToBoxAdapter(
              child: AnimatedContainer(
                duration: still
                    ? Duration.zero
                    : _reloadHeader
                    ? DynamicFeedTheme.reloadHeader
                    : DynamicFeedTheme.reloadCollapse,
                curve: Curves.easeInOut,
                height: _reloadHeader ? room : 0,
                onEnd: () {
                  if (!_reloadHeader && mounted) setState(() => _reloadRoom = false);
                },
                child: _reloadRoom
                    ? ClipRect(
                        child: OverflowBox(
                          key: const ValueKey('follow-reload'),
                          alignment: Alignment.bottomCenter,
                          minHeight: room,
                          maxHeight: room,
                          child: Center(child: RefreshLoading(room: room)),
                        ),
                      )
                    : null,
              ),
            ),
            SliverToBoxAdapter(
              child: FollowTop(
                type: model.type,
                ups: model.ups,
                liveUps: model.liveUps,
                dot: model.hasUpdate,
                onSelect: model.select,
                onOpenFace: _openFace,
                onMore: () => unawaited(openFollowingList(context)),
                onNearEnd: () => unawaited(model.loadMoreUps()),
                facesController: _faces,
                facesKey: _facesKey,
              ),
            ),
            if (bangumi.isNotEmpty) ...[
              const SliverToBoxAdapter(child: _Band()),
              SliverToBoxAdapter(
                child: FollowBangumiSection(items: bangumi, onAll: _openOwnBangumi, onOpen: (_) => _soonToast()),
              ),
            ],
            // Empty once the last post of an unfollowed account has faded.
            if (feed.items.isEmpty && fading.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Band(),
                    Padding(
                      padding: EdgeInsets.only(top: DynamicFeedTheme.stateTop, bottom: bottom),
                      child: Center(child: _state(feed)),
                    ),
                  ],
                ),
              )
            else ...[
              _PostsSliver(
                key: _postsKey,
                delegate: SliverChildBuilderDelegate(
                  childCount: rows.length,
                  // Keyed by post, so a row keeps its place (and its laid-out offset) while posts around it go.
                  findChildIndexCallback: (key) => key is ValueKey<String> ? at[key.value] : null,
                  (context, index) {
                    final row = rows[index];
                    final id = row.item.id;
                    if (row.leaving case final leaving?) return _LeavingGap(key: ValueKey(id), leaving: leaving);
                    return _Measured(
                      key: ValueKey(id),
                      id: id,
                      heights: _heights,
                      child: KeyedSubtree(
                        key: _cardKeys[id] ??= GlobalKey(),
                        child: FollowPosts.row(row.item, inline, bandAbove: index == 0),
                      ),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: FollowFooter(
                  keyPrefix: 'follow',
                  loading: feed.loading && !feed.refreshing,
                  error: feed.error,
                  isEnd: feed.isEnd,
                  onRetry: () => unawaited(feed.loadMore()),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: bottom)),
            ],
          ],
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        list,
        // Over the list, as the official card fades over the posts rising under it.
        if (fading.isNotEmpty)
          IgnorePointer(
            child: ExcludeSemantics(
              child: ClipRect(
                child: Stack(
                  children: [
                    for (final leaving in fading)
                      Positioned(
                        key: ValueKey(leaving.item.id),
                        left: 0,
                        right: 0,
                        top: 0,
                        child: CompositedTransformFollower(
                          link: leaving.link,
                          showWhenUnlinked: false,
                          child: FadeTransition(
                            opacity: leaving.opacity,
                            child: KeyedSubtree(
                              key: _cardKeys[leaving.item.id] ??= GlobalKey(),
                              child: FollowPosts.row(leaving.item, inline, bandAbove: leaving.band),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _state(FollowFeed feed) {
    final error = feed.error;
    if (error != null && !feed.loading) {
      return FollowStateMessage(
        key: const ValueKey('follow-failed'),
        message: error,
        button: FollowPinkButton(
          key: const ValueKey('follow-retry'),
          label: '重试',
          onTap: () => unawaited(feed.retry()),
          text: DynamicFeedTheme.retryText,
          height: DynamicFeedTheme.retryHeight,
          padX: DynamicFeedTheme.retryPadX,
        ),
      );
    }
    if (feed.isEnd && !feed.loading) {
      return const FollowStateMessage(key: ValueKey('follow-empty'), message: '还没有动态');
    }
    return const LoadingTvState(key: ValueKey('follow-loading'));
  }
}

class _Band extends StatelessWidget {
  const _Band();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: DynamicFeedTheme.band,
    child: ColoredBox(color: DynamicFeedTheme.bandFill),
  );
}

/// The posts, which can close rows taken out above those laid out ([_RenderPostsSliver.closeAbove]).
class _PostsSliver extends SliverList {
  const _PostsSliver({super.key, required super.delegate});

  @override
  _RenderPostsSliver createRenderObject(BuildContext context) =>
      _RenderPostsSliver(childManager: context as SliverMultiBoxAdaptorElement);
}

class _RenderPostsSliver extends RenderSliverList {
  _RenderPostsSliver({required super.childManager});

  double _closing = 0;

  /// [height] of rows before the first one laid out has gone. The list would still place its rows by their old
  /// offsets and find the gap only back at its top, correcting the scroll there; so they move up now, and the scroll
  /// with them, and nothing shown moves.
  void closeAbove(double height) {
    if (height <= 0) return;
    _closing += height;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final first = firstChild;
    final offset = first == null ? null : childScrollOffset(first);
    final closing = offset == null ? 0.0 : math.min(_closing, offset);
    _closing = 0;
    if (closing > 0) {
      for (var child = first; child != null; child = childAfter(child)) {
        final data = child.parentData! as SliverMultiBoxAdaptorParentData;
        if (data.layoutOffset case final at?) data.layoutOffset = at - closing;
      }
      geometry = SliverGeometry(scrollOffsetCorrection: -closing);
      return;
    }
    super.performLayout();
  }
}

/// A post's row, noting the height it was laid out at under its [id].
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({super.key, required this.id, required this.heights, required super.child});

  final String id;
  final Map<String, double> heights;

  @override
  _RenderMeasured createRenderObject(BuildContext context) => _RenderMeasured(id, heights);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) => renderObject
    ..id = id
    ..heights = heights;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.id, this.heights);

  String id;
  Map<String, double> heights;

  @override
  void performLayout() {
    super.performLayout();
    heights[id] = size.height;
  }
}

/// A row of the list: a post, or one leaving it.
final class _Shown {
  const _Shown(this.item, {this.leaving});

  final DynamicItem item;
  final _Leaving? leaving;
}

/// A post of an unfollowed account gone from [feed], kept in its place after [after] (null: first) as an empty row
/// until the list starts over ([generation]).
final class _Leaving {
  _Leaving({
    required this.item,
    required this.feed,
    required this.generation,
    required this.after,
    required this.height,
    required this.band,
    required this.controller,
  }) : _curve = controller == null
           ? null
           : CurvedAnimation(parent: controller, curve: DynamicFeedTheme.leaveCurve);

  final DynamicItem item;
  final FollowFeed feed;
  final int generation;
  final String? after;

  /// The row's height as it left (0 when it wasn't drawn), with the band over it when it was the first post ([band]).
  final double height;
  final bool band;

  /// Runs while it fades on screen; null closes it at once.
  final AnimationController? controller;
  final CurvedAnimation? _curve;
  final link = LayerLink();
  bool _landed = false;

  /// Its card still fades over the list.
  bool get moving => controller != null && !_landed;
  Animation<double> get progress => moving ? _curve! : kAlwaysCompleteAnimation;
  Animation<double> get opacity => ReverseAnimation(progress);

  void land() => _landed = true;

  void dispose() {
    _curve?.dispose();
    controller?.dispose();
  }
}

/// Where a leaving post lay: the gap the posts under it rise into while its card fades over the list, then nothing. It
/// keeps the band above it when it was first, so the post after it needs none.
class _LeavingGap extends StatelessWidget {
  const _LeavingGap({super.key, required this.leaving});

  final _Leaving leaving;

  @override
  Widget build(BuildContext context) {
    final band = leaving.band ? DynamicFeedTheme.band : 0.0;
    return AnimatedBuilder(
      animation: leaving.progress,
      builder: (context, _) => CompositedTransformTarget(
        link: leaving.link,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (band > 0) const _Band(),
            SizedBox(height: math.max(leaving.height - band, 0) * (1 - leaving.progress.value)),
          ],
        ),
      ),
    );
  }
}
