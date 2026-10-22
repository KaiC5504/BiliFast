import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../app/zoom_back_route.dart';
import '../player_ui/player_loading.dart';
import '../search/search_glyphs.dart';
import '../search/results/video_row.dart' show searchLogReason;
import '../search/search_page.dart';
import '../shared/loading_tv.dart';
import '../shared/release_refresh.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/link_opener.dart';
import '../video/player_prefs.dart';
import '../video/video_route.dart';
import 'avatar_page.dart';
import 'feed_card.dart';
import 'feed_model.dart';

/// 首页 (01, port of HomeView.swift): the avatar and the search entry, the 推荐 tab and its feed, above the bottom bar
/// `MainShell` holds. The entry opens 搜索 with the default word; the avatar opens its page (49), with 设置, the
/// shortcuts and the last of 最近打开.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.developerPage, this.initialLink, this.reloads});

  /// Builds the developer page (dev builds), passed on to 设置 through the avatar's page; null leaves 开发者 out.
  final WidgetBuilder? developerPage;

  /// Opened as a pasted link once home is up (`--play=<BV or link>` on the PC).
  final String? initialLink;

  /// Notifies for each tap on the bar's 首页 while 首页 shows: 推荐 goes back to the top and refreshes.
  final Listenable? reloads;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late AppServices _services;
  FeedModel? _feed;
  final _grid = GlobalKey<_FeedGridState>();
  late final _opener = LinkOpener(onPushed: (pushed) => unawaited(_visit(pushed)));
  bool _opening = false;

  /// The search entry's grey word, asked for once; null until it comes, and after a failure.
  String? _searchWord;

  /// Whether the feed on screen was fetched logged in; null until the first account check has answered.
  bool? _feedSignedIn;

  /// Whether the app token was held when last heard, so a new one can bring the official 推荐 and a lost one take it
  /// away.
  bool _authorized = false;

  /// The refresh of 推荐 running, from the first load, an account change, a pull, 首页 or 重试; a pull or a tap while
  /// it runs waits on it instead of asking again.
  Future<void>? _refreshing;

  /// Counts the refreshes started, so a lost token's refresh can tell whether another came first.
  int _refreshesStarted = 0;

  AppEnvironment get _environment => _services.environment;

  @override
  void initState() {
    super.initState();
    widget.reloads?.addListener(_reload);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reloads, widget.reloads)) {
      oldWidget.reloads?.removeListener(_reload);
      widget.reloads?.addListener(_reload);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_feed != null) return;
    _services = AppScope.of(context);
    _opener.busy.addListener(_busyChanged);
    _feed = FeedModel(client: _environment.client);
    unawaited(LoadingTv.precache(context));
    unawaited(PlayerLoading.precache());
    unawaited(_refreshFeed());
    _environment.addListener(_accountChanged);
    _accountChanged();
    _authorized = _services.appAuth.authorized;
    _services.appAuth.addListener(_authChanged);
    unawaited(_loadSearchWord());
    final link = widget.initialLink;
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_opener.open(context, link));
      });
    }
  }

  @override
  void dispose() {
    widget.reloads?.removeListener(_reload);
    _opener.dispose();
    _environment.removeListener(_accountChanged);
    _services.appAuth.removeListener(_authChanged);
    _feed?.dispose();
    super.dispose();
  }

  void _busyChanged() => setState(() => _opening = _opener.busy.value);

  Future<void> _loadSearchWord() async {
    try {
      final word = await _services.searchApi.defaultWord();
      if (mounted) setState(() => _searchWord = word);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'default search word failed', {'error': searchLogReason(error)});
    }
  }

  /// Logging in or out changes what 推荐 recommends; the first check at launch does not.
  void _accountChanged() {
    final bool signedIn;
    switch (_environment.account) {
      case AccountUnknown():
        return;
      case LoggedIn():
        signedIn = true;
      case LoggedOut() || LoginExpired():
        signedIn = false;
    }
    final previous = _feedSignedIn;
    _feedSignedIn = signedIn;
    if (previous != null && previous != signedIn) unawaited(_refreshFeed(restart: true));
  }

  /// A token that arrives after 推荐 came from the website (at launch the stored one may land after the first load,
  /// or the confirm was just given) brings the official feed in its place. One lost (rejected, another account's,
  /// 退出登录) takes the official cards away, as they were that token's.
  void _authChanged() {
    final authorized = _services.appAuth.authorized;
    final gained = authorized && !_authorized;
    final lost = !authorized && _authorized;
    _authorized = authorized;
    if (gained && PlayerPrefs.shared.officialFeed && _feed?.source != FeedSource.official) {
      unawaited(_refreshFeed(restart: true));
    } else if (lost && _feed?.source == FeedSource.official) {
      // 退出登录 drops the token just before the account hears of it, and the account's refresh is the one wanted:
      // waiting out this turn keeps that to one call.
      final started = _refreshesStarted;
      scheduleMicrotask(() {
        if (mounted && _refreshesStarted == started) unawaited(_refreshFeed(restart: true));
      });
    }
  }

  /// The running refresh, or a new one. [restart] starts one even while another runs (whose answer the feed then
  /// drops), as a refresh asked for before the account changed would bring the old account's 推荐.
  Future<void> _refreshFeed({bool restart = false}) {
    final running = _refreshing;
    if (running != null && !restart) return running;
    _refreshesStarted += 1;
    late final Future<void> refresh;
    refresh = _fetchFeed().whenComplete(() {
      if (identical(_refreshing, refresh)) _refreshing = null;
    });
    return _refreshing = refresh;
  }

  /// A refresh that fails with cards on screen keeps them and says why in a toast.
  Future<void> _fetchFeed() async {
    final failure = await _feed?.refresh();
    if (failure != null && mounted) showToast(context, failure);
  }

  /// Back on home from a pushed page, an account check that failed is tried again, as Swift's HomeView.task did on
  /// every return; one still running is left to answer.
  Future<void> _visit(Future<void> pushed) async {
    await pushed;
    if (mounted && _environment.account is AccountUnknown && _environment.accountCheckFailed) {
      await _environment.refreshAccount();
    }
  }

  void _openAvatarPage() {
    final page = SwipeBackPageRoute<void>(builder: (_) => AvatarPage(developerPage: widget.developerPage));
    unawaited(_visit(Navigator.of(context).push(page)));
  }

  void _openSearch() => unawaited(_visit(openSearchPage(context, placeholder: _searchWord)));

  void _reload() => unawaited(_grid.currentState?.reload());

  void _openCard(FeedCard card, ZoomSource source) => unawaited(
    _visit(
      openVideoPage(context, VideoRoute(bvid: card.bvid, title: card.title, cover: card.cover, zoomSource: source)),
    ),
  );

  /// Logged out it goes to the login page and sends nothing; an account still being checked tries, and goes there
  /// only if Bilibili answers that it needs a login.
  Future<void> _watchLater(FeedCard card) async {
    if (_environment.account case LoggedOut() || LoginExpired()) {
      await _services.loginGate.request(context);
      return;
    }
    try {
      await _environment.client.addToWatchLater(aid: card.aid);
      if (mounted) showToast(context, '已添加至稍后再看');
    } catch (error) {
      if (error is BiliError && error.needsLogin) {
        if (mounted) await _services.loginGate.request(context);
        return;
      }
      Logger.shared.warn(LogCategory.ui, 'watch later failed', feedLogFields(error));
      if (mounted) showToast(context, requestFailureMessage(error));
    }
  }

  /// Without the app token the confirm is asked first; the card turns over only once it is given.
  Future<bool> _authorize() async {
    final auth = _services.appAuth;
    return auth.authorized || await auth.request(context);
  }

  Future<void> _dislike(FeedCard card, FeedReason reason) async {
    if (!await _authorize() || !mounted) return;
    _dislikeFailed(await _feed!.dislike(card, reason));
  }

  Future<void> _undoDislike(FeedCard card) async {
    if (!await _authorize() || !mounted) return;
    _dislikeFailed(await _feed!.undo(card));
  }

  /// The official app says nothing after a reason is picked, so neither does this, unless it fails.
  Future<void> _dislikeReason(FeedCard card, FeedReason reason) async {
    if (!await _authorize() || !mounted) return;
    _dislikeFailed(await _feed!.sendReason(card, reason));
  }

  /// A refused token asks for the confirm again, as the video page's 不喜欢 does; the tap isn't replayed.
  void _dislikeFailed(DislikeFailure? failure) {
    if (failure == null || !mounted) return;
    switch (failure) {
      case DislikeTokenRefused():
        unawaited(_services.appAuth.request(context));
      case DislikeError(:final message):
        showToast(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: BiliColors.pageGrey,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Column(
              children: [
                ColoredBox(
                  color: BiliColors.card,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        ListenableBuilder(
                          listenable: _environment,
                          builder: (context, _) => _TopRow(
                            face: _environment.face,
                            searchWord: _searchWord,
                            onAvatar: _openAvatarPage,
                            onSearch: _openSearch,
                          ),
                        ),
                        const _RecommendTab(),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 0.5, thickness: 0.5, color: BiliColors.divider),
                Expanded(
                  child: _FeedGrid(
                    key: _grid,
                    feed: _feed!,
                    onOpen: _openCard,
                    onWatchLater: _watchLater,
                    onDislike: _dislike,
                    onUndo: _undoDislike,
                    onReason: _dislikeReason,
                    onRefresh: _refreshFeed,
                    refreshing: () => _refreshing,
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: Center(
                child: _Presence(
                  visible: _opening,
                  duration: still ? Duration.zero : const Duration(milliseconds: 220),
                  reverseDuration: still ? Duration.zero : const Duration(milliseconds: 180),
                  builder: (context, animation) => ScaleTransition(
                    scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: Container(
                        key: const ValueKey('opening'),
                        padding: const EdgeInsets.all(BiliMetrics.openingPadding),
                        decoration: BoxDecoration(
                          color: BiliColors.toastFill,
                          borderRadius: BorderRadius.circular(BiliMetrics.toastRadius),
                        ),
                        child: const CupertinoActivityIndicator(
                          radius: BiliMetrics.openingSpinner / 2,
                          color: BiliColors.panelText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds its child only while [visible] or animating out, so nothing in it (a spinner above all) keeps ticking once
/// it has gone.
class _Presence extends StatefulWidget {
  const _Presence({
    required this.visible,
    required this.duration,
    this.reverseDuration,
    required this.builder,
  });

  final bool visible;
  final Duration duration;
  final Duration? reverseDuration;
  final Widget Function(BuildContext context, Animation<double> animation) builder;

  @override
  State<_Presence> createState() => _PresenceState();
}

class _PresenceState extends State<_Presence> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration,
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_statusChanged);
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  void _statusChanged(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_Presence oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..duration = widget.duration
      ..reverseDuration = widget.reverseDuration;
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        unawaited(_controller.forward());
      } else {
        unawaited(_controller.reverse());
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _controller.isDismissed ? const SizedBox.shrink() : widget.builder(context, _curved);
}

/// The account's avatar; a grey head until the account has a face.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.face, required this.size});

  final String? face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = face;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url != null && url.isNotEmpty
            ? RemoteImage.avatar(url)
            : ColoredBox(
                color: BiliColors.pageGrey,
                child: Icon(Icons.person, size: size * 0.55, color: BiliColors.divider),
              ),
      ),
    );
  }
}

/// The avatar and the search entry (01): a rounded bar with the magnifier and the default word, which opens 搜索.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.face, required this.searchWord, required this.onAvatar, required this.onSearch});

  final String? face;
  final String? searchWord;
  final VoidCallback onAvatar;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BiliMetrics.topRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.topRowMargin),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: '账号',
              child: GestureDetector(
                key: const ValueKey('home-avatar'),
                onTap: onAvatar,
                child: _AccountAvatar(face: face, size: BiliMetrics.homeAvatar),
              ),
            ),
            const SizedBox(width: HomeTabBarTheme.fieldGap),
            _SearchField(word: searchWord, onTap: onSearch),
          ],
        ),
      ),
    );
  }
}

/// The search entry: the magnifier and the grey word in a stadium, greyed while pressed.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.word, required this.onTap});

  final String? word;
  final VoidCallback onTap;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    const word = TextStyle(fontSize: HomeTabBarTheme.fieldText, color: HomeTabBarTheme.fieldInk);
    const glyphLead = HomeTabBarTheme.fieldGlyphCentre - HomeTabBarTheme.fieldGlyph / 2;
    return Semantics(
      button: true,
      label: '搜索',
      value: widget.word,
      child: GestureDetector(
        key: const ValueKey('home-search'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: ExcludeSemantics(
          // The rim is drawn over the contents: as the decoration, its width would inset them (01 measures from the
          // rim's outer edge).
          child: Container(
            key: const ValueKey('home-search-field'),
            width: HomeTabBarTheme.fieldWidth,
            height: BiliMetrics.linkFieldHeight,
            foregroundDecoration: ShapeDecoration(
              color: _pressed ? BiliColors.pressedFill : null,
              shape: const StadiumBorder(
                side: BorderSide(color: HomeTabBarTheme.fieldOutline, width: HomeTabBarTheme.fieldOutlineWidth),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: glyphLead),
                Transform.translate(
                  offset: const Offset(0, -HomeTabBarTheme.fieldGlyphRise),
                  child: const SearchGlyphIcon(
                    SearchGlyph.magnifier,
                    size: HomeTabBarTheme.fieldGlyph,
                    color: HomeTabBarTheme.fieldInk,
                  ),
                ),
                const SizedBox(width: HomeTabBarTheme.fieldTextStart - glyphLead - HomeTabBarTheme.fieldGlyph),
                Expanded(
                  child: Text(
                    widget.word ?? '',
                    key: const ValueKey('home-search-word'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: word,
                    strutStyle: BiliFonts.strutOf(context, word),
                  ),
                ),
                const SizedBox(width: HomeTabBarTheme.fieldTextEnd),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 01's tab row, with only 推荐 and that one selected.
class _RecommendTab extends StatelessWidget {
  const _RecommendTab();

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    selected: true,
    child: Padding(
      padding: const EdgeInsets.only(top: BiliMetrics.tabRowTop, bottom: BiliMetrics.tabRowBottom),
      child: Column(
        children: [
          const Text(
            '推荐',
            style: TextStyle(fontSize: BiliMetrics.tabText, fontWeight: FontWeight.w600, color: BiliColors.pink),
          ),
          const SizedBox(height: BiliMetrics.tabIndicatorGap),
          Container(
            width: BiliMetrics.tabIndicatorWidth,
            height: BiliMetrics.tabIndicatorHeight,
            decoration: BoxDecoration(color: BiliColors.pink, borderRadius: BorderRadius.circular(2)),
          ),
        ],
      ),
    ),
  );
}

class _FeedGrid extends StatefulWidget {
  const _FeedGrid({
    super.key,
    required this.feed,
    required this.onOpen,
    required this.onWatchLater,
    required this.onDislike,
    required this.onUndo,
    required this.onReason,
    required this.onRefresh,
    required this.refreshing,
  });

  final FeedModel feed;
  final void Function(FeedCard card, ZoomSource source) onOpen;
  final void Function(FeedCard card) onWatchLater;
  final void Function(FeedCard card, FeedReason reason) onDislike;
  final void Function(FeedCard card) onUndo;
  final void Function(FeedCard card, FeedReason reason) onReason;

  /// The page's refresh: the one running, or a new one.
  final Future<void> Function() onRefresh;

  /// The refresh running, if any.
  final Future<void>? Function() refreshing;

  @override
  State<_FeedGrid> createState() => _FeedGridState();
}

class _FeedGridState extends State<_FeedGrid> {
  static const _skeletons = 6;

  /// The next page is asked for once fewer than this many rows of cards are left below the screen.
  static const _rowsAhead = 2;

  /// Cards appearing in the same frame come in this far apart, the later ones all at the last step.
  static const _staggerStep = Duration(milliseconds: 45);
  static const _staggerSteps = 6;

  final _scroll = ScrollController();

  /// Cards that have made their entrance; one rebuilt or scrolled back into view just shows.
  final _entered = <String>{};
  int _batch = 0;
  double _rowExtent = 0;

  /// Whether 首页's refresh shows the pull-to-refresh TV at the top.
  bool _reloadHeader = false;

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_feedChanged);
  }

  @override
  void didUpdateWidget(_FeedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.feed, widget.feed)) {
      oldWidget.feed.removeListener(_feedChanged);
      widget.feed.addListener(_feedChanged);
    }
  }

  @override
  void dispose() {
    widget.feed.removeListener(_feedChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _feedChanged() {
    setState(() {});
    // A page too short to scroll leaves the end on screen with no scrolling to notice it; look once it is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _loadMoreNearEnd(_scroll.position);
    });
  }

  /// 首页's tap, as the official app's: back to the top and 推荐 refreshed at once, whether scrolled or already at the
  /// top, with the pull-to-refresh TV held at the top until the new cards come. Nothing more while a refresh
  /// (or the first load) runs.
  Future<void> reload() async {
    final feed = widget.feed;
    if (widget.refreshing() case final running?) return running;
    if (feed.cards.isEmpty && feed.loading) return;
    final refresh = widget.onRefresh();
    if (!_scroll.hasClients) return refresh;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      await _scroll.animateTo(0, duration: HomeTabBarTheme.reloadScroll, curve: Curves.easeOut);
    }
    if (!mounted || !identical(widget.refreshing(), refresh)) return;
    setState(() => _reloadHeader = true);
    await refresh;
    if (mounted) setState(() => _reloadHeader = false);
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth == 0) _loadMoreNearEnd(notification.metrics);
    return false;
  }

  void _loadMoreNearEnd(ScrollMetrics metrics) {
    if (!widget.feed.canLoadMore || !metrics.hasContentDimensions) return;
    if (metrics.extentAfter >= _rowExtent * _rowsAhead) return;
    // A scroll notification can come mid-layout, where the feed's change must not rebuild anything yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.feed.canLoadMore) unawaited(widget.feed.loadMore());
      });
    } else {
      unawaited(widget.feed.loadMore());
    }
  }

  Duration _nextStagger() {
    if (_batch == 0) WidgetsBinding.instance.addPostFrameCallback((_) => _batch = 0);
    return _staggerStep * math.min(_batch++, _staggerSteps);
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final scaler = MediaQuery.textScalerOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = BiliMetrics.feedSpacing;
        final width = (constraints.maxWidth - spacing * 3) / 2;
        final extent = FeedCardSize.height(width, scaler);
        _rowExtent = extent + spacing;
        final grid = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: extent,
        );
        final cards = feed.cards;
        final loadingFirst = cards.isEmpty && (feed.loading || feed.error == null);
        final pull = ReleaseRefreshControl(
          refreshIndicatorExtent: LoadingTvTheme.size,
          builder: loadingTvRefreshIndicator,
          onRefresh: widget.onRefresh,
        );
        return AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 320),
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: loadingFirst
              ? CustomScrollView(
                  key: const ValueKey('feed-skeleton'),
                  physics: const NeverScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(spacing),
                      sliver: SliverGrid(
                        gridDelegate: grid,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => const FeedCardSkeleton(),
                          childCount: _skeletons,
                        ),
                      ),
                    ),
                  ],
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _scrolled,
                  child: CustomScrollView(
                    key: const ValueKey('feed'),
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      pull,
                      SliverToBoxAdapter(
                        child: _Presence(
                          visible: _reloadHeader,
                          duration: still ? Duration.zero : HomeTabBarTheme.reloadHeader,
                          builder: (context, animation) => SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              key: const ValueKey('feed-reload'),
                              height: pull.refreshIndicatorExtent,
                              child: const Center(child: LoadingTv()),
                            ),
                          ),
                        ),
                      ),
                      if (cards.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: _RetryMessage(
                              message: feed.error ?? FeedModel.emptyMessage,
                              messageKey: const ValueKey('feed-error'),
                              onRetry: widget.onRefresh,
                            ),
                          ),
                        )
                      else ...[
                        SliverPadding(
                          padding: const EdgeInsets.all(spacing),
                          sliver: SliverGrid(
                            gridDelegate: grid,
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final card = cards[index];
                                final enter = !still && _entered.add(card.bvid);
                                return _Entrance(
                                  key: ValueKey('feed-card-${card.bvid}'),
                                  delay: enter ? _nextStagger() : null,
                                  child: FeedCardView(
                                    card: card,
                                    onOpen: (source) => widget.onOpen(card, source),
                                    onWatchLater: () => widget.onWatchLater(card),
                                    dislike: feed.dislikeOf(card),
                                    onDislike: (reason) => widget.onDislike(card, reason),
                                    onUndo: () => widget.onUndo(card),
                                    onReason: (reason) => widget.onReason(card, reason),
                                  ),
                                );
                              },
                              childCount: cards.length,
                              findChildIndexCallback: (key) {
                                if (key is! ValueKey<String>) return null;
                                final index = cards.indexWhere((card) => 'feed-card-${card.bvid}' == key.value);
                                return index < 0 ? null : index;
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _Footer(feed: feed)),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// A card's first appearance: after [delay] it fades in and rises into place. Without a delay it just shows, as it
/// does when rebuilt or scrolled back into view.
class _Entrance extends StatefulWidget {
  const _Entrance({super.key, required this.delay, required this.child});

  final Duration? delay;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  static const _rise = Duration(milliseconds: 380);

  AnimationController? _controller;
  CurvedAnimation? _curve;
  Animation<Offset>? _offset;

  @override
  void initState() {
    super.initState();
    final delay = widget.delay;
    if (delay == null) return;
    final total = delay + _rise;
    final controller = AnimationController(vsync: this, duration: total);
    final curve = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOutCubic),
    );
    _controller = controller;
    _curve = curve;
    _offset = Tween(begin: const Offset(0, BiliMetrics.cardRise), end: Offset.zero).animate(curve);
    unawaited(controller.forward());
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    final offset = _offset;
    if (curve == null || offset == null) return widget.child;
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(position: offset, child: widget.child),
    );
  }
}

/// Under the cards: the spinner while the next page loads, or why it didn't with 重试.
class _Footer extends StatelessWidget {
  const _Footer({required this.feed});

  final FeedModel feed;

  @override
  Widget build(BuildContext context) {
    final error = feed.error;
    return Padding(
      padding: const EdgeInsets.only(top: BiliMetrics.rowGap, bottom: BiliMetrics.sectionGap + BiliMetrics.rowGap),
      child: Center(
        child: error != null
            ? _RetryMessage(message: error, messageKey: const ValueKey('feed-error'), onRetry: feed.retry)
            : feed.exhausted
            ? _RetryMessage(message: FeedModel.endMessage, messageKey: const ValueKey('feed-end'), onRetry: feed.retry)
            : SizedBox.square(
                dimension: BiliMetrics.feedSpinnerRadius * 2,
                child: feed.loading
                    ? const CupertinoActivityIndicator(
                        key: ValueKey('feed-more'),
                        radius: BiliMetrics.feedSpinnerRadius,
                      )
                    : null,
              ),
      ),
    );
  }
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.message, required this.messageKey, required this.onRetry});

  final String message;
  final Key messageKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(BiliMetrics.sectionGap),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          key: messageKey,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.secondaryText),
          strutStyle: BiliFonts.strutOf(context, const TextStyle(fontSize: BiliMetrics.bodyText)),
        ),
        const SizedBox(height: BiliMetrics.rowGap),
        CupertinoButton(
          key: const ValueKey('feed-retry'),
          onPressed: onRetry,
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(BiliMetrics.pillHeight),
          child: Container(
            height: BiliMetrics.pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.sectionGap),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: BiliColors.pink)),
            ),
            child: const Text(
              '重试',
              style: TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.pink),
            ),
          ),
        ),
      ],
    ),
  );
}
