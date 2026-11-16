import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../dynamic/card/dynamic_open.dart' show DynamicArt;
import '../dynamic/follow_tab/follow_parts.dart';
import '../home/feed_model.dart' show requestFailureMessage;
import '../home/home_tab_bar.dart' show TabCount;
import '../home/tab_bar_icons.dart' show SkinDecodeGate;
import '../shared/loading_tv.dart';
import '../shared/release_refresh.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../skin/skin.dart';
import 'message_model.dart';
import 'message_routes.dart';
import 'message_sheets.dart';
import 'session_row.dart';

/// The bottom bar's 消息 (196): the header with 一键已读 and ⋮, the three entries, and the session list.
class MessagePage extends StatefulWidget {
  const MessagePage({super.key, required this.active, this.skin, this.reloads, @visibleForTesting this.clock});

  /// The place is shown.
  final bool active;

  /// The equipped 装扮, dressing the header as 关注's.
  final Skin? skin;

  /// 消息 tapped again while shown.
  final Listenable? reloads;

  /// The time the dates are told from and the list's age is measured by; the wall clock unless a test sets one.
  final DateTime Function()? clock;

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> with SkinRefreshRoom {
  /// A list older than this is asked again when 消息 shows.
  static const _stale = Duration(minutes: 1);

  late AppServices _services;
  late AppEnvironment _environment;
  MessageModel? _model;
  bool _signedOut = false;

  /// 消息 has shown logged in; until then the list draws nothing, so no TV is built out of sight.
  bool _started = false;

  /// When the list last loaded without a failure, as [MessagePage.clock] tells it.
  DateTime? _loadedAt;

  final _scroll = ScrollController();
  late final _paging = FollowPaging(
    canAsk: () {
      final model = _model!;
      return model.hasMore && model.error == null && !model.loading && model.sessions.isNotEmpty;
    },
    ask: () => _model!.loadMore(),
  );

  /// The refresh running, from a pull, a tap on 消息 or the page showing; another waits on it.
  Future<void>? _refreshing;

  /// 消息's tap holds the TV open at the top until its refresh is done; [_reloadRoom] keeps it built while closing.
  bool _reloadHeader = false;
  bool _reloadRoom = false;
  bool _still = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.reloads?.addListener(_reload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    _services = AppScope.of(context);
    _environment = _services.environment..addListener(_accountChanged);
    _signedOut = _loggedOut;
    _model = _services.messages..addListener(_modelChanged);
    if (widget.active) _activateAfterBuild();
  }

  @override
  void didUpdateWidget(MessagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reloads, widget.reloads)) {
      oldWidget.reloads?.removeListener(_reload);
      widget.reloads?.addListener(_reload);
    }
    if (widget.active && !oldWidget.active) _activateAfterBuild();
  }

  /// The model tells its listeners as a refresh starts, which mustn't happen while the shell is building.
  void _activateAfterBuild() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.active) _activate();
  });

  @override
  void dispose() {
    widget.reloads?.removeListener(_reload);
    _environment.removeListener(_accountChanged);
    _model?.removeListener(_modelChanged);
    _paging.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _loggedOut => switch (_environment.account) {
    LoggedOut() || LoginExpired() => true,
    LoggedIn() || AccountUnknown() => false,
  };

  /// A -101 with nothing shown asks for the login too: the app may still think it is logged in.
  bool get _needsLogin {
    final model = _model!;
    final error = model.error;
    return _loggedOut || (error is BiliError && error.needsLogin && model.sessions.isEmpty);
  }

  /// 消息 shown: the counts asked at once, the list when it was never loaded or is over a minute old.
  void _activate() {
    if (_loggedOut) return;
    _started = true;
    unawaited(_model!.refreshUnread(force: true));
    final loaded = _loadedAt;
    if (loaded == null || _now.difference(loaded) > _stale) unawaited(_refresh());
  }

  void _accountChanged() {
    final out = _loggedOut;
    if (out == _signedOut) return;
    _signedOut = out;
    _loadedAt = null;
    _started = false;
    if (!out && widget.active) _activate();
    setState(() {});
  }

  void _modelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() {
    if (_refreshing case final running?) return running;
    late final Future<void> refresh;
    refresh = _load().whenComplete(() {
      if (identical(_refreshing, refresh)) _refreshing = null;
    });
    return _refreshing = refresh;
  }

  Future<void> _load() async {
    final model = _model!;
    await model.refresh();
    if (model.error == null) _loadedAt = _now;
  }

  /// A pull that failed over rows already shown says why; with none, the page's own state does.
  Future<void> _pull() async {
    await _refresh();
    final model = _model!;
    final error = model.error;
    if (error != null && model.sessions.isNotEmpty && mounted) showToast(context, requestFailureMessage(error));
  }

  /// 消息 tapped while shown, as 关注's: back to the top, then the TV held open there until the refresh is done.
  /// With no session shown the list's own state stands for it.
  Future<void> _reload() async {
    if (_refreshing != null || _loggedOut) return;
    if (_model!.sessions.isEmpty) {
      unawaited(_refresh());
      return;
    }
    final refresh = _refresh();
    if (_scroll.hasClients) {
      if (_still) {
        _scroll.jumpTo(0);
      } else {
        await _scroll.animateTo(0, duration: MessageTabTheme.reloadScroll, curve: Curves.easeOut);
      }
    }
    if (!mounted || !identical(_refreshing, refresh)) return;
    setState(() => _reloadHeader = _reloadRoom = true);
    await refresh;
    if (!mounted) return;
    setState(() => _reloadHeader = false);
  }

  Future<void> _login() async {
    final loggedIn = await _services.loginGate.request(context);
    // A login that changed the account has started the page already (_accountChanged); one after a -101 under an
    // account the app still held changes nothing there.
    if (!loggedIn || !mounted || !widget.active || _refreshing != null) return;
    if (_loadedAt != null && _model!.error == null) return;
    _loadedAt = null;
    _activate();
  }

  Future<void> _readAll() async {
    if (_loggedOut) {
      unawaited(_login());
      return;
    }
    if (!await confirmReadAll(context) || !mounted) return;
    try {
      await _model!.readAll();
    } on Exception catch (error) {
      Logger.shared.warn(LogCategory.api, 'message read all failed', {'error': '${error.runtimeType}'});
      if (mounted) showToast(context, requestFailureMessage(error));
    }
  }

  void _more() => unawaited(showMessageMoreSheet(context, sessions: _model!.sessions, now: _now));

  /// The pages clear their own counts as they open (a notification opens them too).
  void _openFeed(NoticeFeed feed) {
    unawaited(feed == NoticeFeed.like ? openLikes(context) : openReplies(context));
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.skin?.headBg != null ? widget.skin : null;
    return SkinDecodeGate(
      pictures: [?head?.headBg],
      builder: (context, decoded) => _page(context, decoded ? head : null),
    );
  }

  /// [head] dresses the header once its picture has decoded. The header is 首页's top row's height, so the status bar
  /// goes by 首页's measure where the skin cuts it the same way (with a tab picture), else by 关注's.
  Widget _page(BuildContext context, Skin? head) {
    _still = MediaQuery.disableAnimationsOf(context);
    final light = head != null && (head.headTabBg != null ? head.lightStatusHome : head.lightStatusFollow);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Material(
        color: MessageTabTheme.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(skin: head, onReadAll: () => unawaited(_readAll()), onMore: _more),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_needsLogin) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: MessageTabTheme.stateTop),
          child: Column(
            key: const ValueKey('message-logged-out'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/friends/page_status_empty.png',
                width: MessageTabTheme.emptyPicture,
                height: MessageTabTheme.emptyPicture,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: MessageTabTheme.emptyGap),
              FollowStateMessage(
                message: '登录后查看消息',
                button: FollowPinkButton(
                  key: const ValueKey('message-login'),
                  label: '登录',
                  onTap: () => unawaited(_login()),
                  text: DynamicFeedTheme.loginText,
                  height: DynamicFeedTheme.loginHeight,
                  padX: DynamicFeedTheme.loginPadX,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_started) return const SizedBox.shrink();
    final model = _model!;
    final sessions = model.sessions;
    final counts = model.badgeOn;
    final unread = model.unread;
    final now = _now;
    final room = refreshRoom;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return _paging.listen(
      _scroll,
      CustomScrollView(
        key: const ValueKey('message-list'),
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
              duration: _still
                  ? Duration.zero
                  : _reloadHeader
                  ? MessageTabTheme.reloadHeader
                  : MessageTabTheme.reloadCollapse,
              curve: Curves.easeInOut,
              height: _reloadHeader ? room : 0,
              onEnd: () {
                if (!_reloadHeader && mounted) setState(() => _reloadRoom = false);
              },
              child: _reloadRoom
                  ? ClipRect(
                      child: OverflowBox(
                        key: const ValueKey('message-reload'),
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
            child: _Entries(
              replies: counts ? unread.reply + unread.at : 0,
              likes: counts ? unread.like : 0,
              onReplies: () => _openFeed(NoticeFeed.reply),
              onLikes: () => _openFeed(NoticeFeed.like),
              onFans: () => unawaited(openNewFans(context)),
            ),
          ),
          if (sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(top: MessageTabTheme.stateTop, bottom: bottom),
                child: Align(alignment: Alignment.topCenter, child: _state(model)),
              ),
            )
          else ...[
            SliverList.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return SessionRow(
                  session: session,
                  now: now,
                  counts: counts,
                  onTap: () => unawaited(openMessageChat(context, session)),
                );
              },
            ),
            SliverToBoxAdapter(
              child: FollowFooter(
                keyPrefix: 'message',
                loading: model.hasMore && model.error == null,
                error: model.error == null ? null : requestFailureMessage(model.error!),
                isEnd: false,
                onRetry: () => unawaited(model.loadMore()),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        ],
      ),
    );
  }

  /// No session to show: the TV while the first page is out, why it failed with 重试, or the empty picture.
  Widget _state(MessageModel model) {
    final error = model.error;
    if (error != null && !model.loading) {
      return FollowStateMessage(
        key: const ValueKey('message-failed'),
        message: requestFailureMessage(error),
        button: FollowPinkButton(
          key: const ValueKey('message-retry'),
          label: '重试',
          onTap: () => unawaited(_refresh()),
          text: DynamicFeedTheme.retryText,
          height: DynamicFeedTheme.retryHeight,
          padX: DynamicFeedTheme.retryPadX,
        ),
      );
    }
    if (model.loading || _loadedAt == null) return const LoadingTvState(key: ValueKey('message-loading'));
    return Column(
      key: const ValueKey('message-empty'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/friends/page_status_empty.png',
          width: MessageTabTheme.emptyPicture,
          height: MessageTabTheme.emptyPicture,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: MessageTabTheme.emptyGap),
        const FollowStateMessage(message: '这里还什么都没有呢～'),
      ],
    );
  }
}

/// 196's header: the 装扮's `head_bg` or white, 消息 on the row under the status bar, the broom and ⋮ at its right.
class _Header extends StatelessWidget {
  const _Header({required this.skin, required this.onReadAll, required this.onMore});

  /// A skin with a `head_bg`, its picture decoded, or null.
  final Skin? skin;
  final VoidCallback onReadAll;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final head = skin?.headBg;
    final ink = skin?.color ?? MessageTabTheme.titleInk;
    Widget button(String key, String label, double centreRight, String asset, VoidCallback onTap) => Positioned(
      right: centreRight - MessageTabTheme.buttonTarget / 2,
      bottom: 0,
      width: MessageTabTheme.buttonTarget,
      height: MessageTabTheme.barRow,
      child: FollowTap(
        key: ValueKey(key),
        label: label,
        onTap: onTap,
        child: Center(child: Image.asset(asset, scale: 3, color: ink, excludeFromSemantics: true)),
      ),
    );
    return SizedBox(
      key: const ValueKey('message-header'),
      height: MediaQuery.paddingOf(context).top + MessageTabTheme.barRow,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (head != null)
            SkinDecodeGate.image(head, key: const ValueKey('message-head-art'))
          else
            const ColoredBox(color: MessageTabTheme.bar),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MessageTabTheme.barRow,
            child: Padding(
              padding: const EdgeInsets.only(top: MessageTabTheme.titleDrop * 2),
              child: Center(
                child: Semantics(
                  header: true,
                  child: Text(
                    '消息',
                    key: const ValueKey('message-title'),
                    style: messageStyle(MessageTabTheme.titleText, ink, weight: MessageTabTheme.titleWeight),
                  ),
                ),
              ),
            ),
          ),
          button(
            'message-read-all-button',
            '一键已读',
            MessageTabTheme.broomCentreRight,
            'assets/images/message/tab_broom.png',
            onReadAll,
          ),
          button('message-more-button', '更多', MessageTabTheme.moreCentreRight, DynamicArt.more, onMore),
        ],
      ),
    );
  }
}

/// 回复与@, 收到喜欢 and 新增粉丝 (196), each a coloured glyph on its grey square with its label under it and, while
/// it has some, its red count on the square's corner.
class _Entries extends StatelessWidget {
  const _Entries({
    required this.replies,
    required this.likes,
    required this.onReplies,
    required this.onLikes,
    required this.onFans,
  });

  final int replies;
  final int likes;
  final VoidCallback onReplies;
  final VoidCallback onLikes;
  final VoidCallback onFans;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MessageTabTheme.entries,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Entry(
          name: 'replies',
          label: '回复与@',
          count: replies,
          onTap: onReplies,
          glyph: Image.asset(
            'assets/images/message/tab_entry_reply.png',
            scale: 3,
            color: MessageTabTheme.replyInk,
            excludeFromSemantics: true,
          ),
        ),
        _Entry(
          name: 'likes',
          label: '收到喜欢',
          count: likes,
          onTap: onLikes,
          glyph: Transform.translate(
            offset: const Offset(0, -MessageTabTheme.likeRise),
            child: Image.asset(
              'assets/images/message/tab_entry_like.png',
              scale: 3,
              color: MessageTabTheme.likeInk,
              excludeFromSemantics: true,
            ),
          ),
        ),
        _Entry(
          name: 'fans',
          label: '新增粉丝',
          count: 0,
          onTap: onFans,
          glyph: const CustomPaint(
            size: Size(MessageTabTheme.fansWidth, MessageTabTheme.fansHeight),
            painter: _BustPainter(),
          ),
        ),
      ],
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.name,
    required this.label,
    required this.count,
    required this.onTap,
    required this.glyph,
  });

  final String name;
  final String label;
  final int count;
  final VoidCallback onTap;
  final Widget glyph;

  @override
  Widget build(BuildContext context) {
    const square = MessageTabTheme.entrySquare;
    const labelTop =
        MessageTabTheme.entryTop + square + MessageTabTheme.entryLabelCentre - MessageTabTheme.entryLabelLine / 2;
    final style = messageStyle(
      MessageTabTheme.entryLabelText,
      MessageTabTheme.entryLabelInk,
      line: MessageTabTheme.entryLabelLine,
    );
    return SizedBox(
      width: MessageTabTheme.entryPitch,
      child: Semantics(
        button: true,
        label: label,
        value: count > 0 ? TabCount.label(count) : null,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('message-entry-$name'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: MessageTabTheme.entryTop,
                left: (MessageTabTheme.entryPitch - square) / 2,
                width: square,
                height: square,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: MessageTabTheme.entryFill,
                    borderRadius: BorderRadius.circular(MessageTabTheme.entryRadius),
                  ),
                  child: Center(child: glyph),
                ),
              ),
              if (count > 0)
                Positioned(
                  top: MessageTabTheme.entryTop,
                  left: (MessageTabTheme.entryPitch + square) / 2,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: TabCount(count, key: ValueKey('message-entry-count-$name')),
                  ),
                ),
              Positioned(
                top: labelTop,
                left: 0,
                right: 0,
                height: MessageTabTheme.entryLabelLine,
                child: messageLine(label, style, align: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新增粉丝's bust, traced on 196 in its pixels: a round head over a dome of shoulders with a flat foot.
class _BustPainter extends CustomPainter {
  const _BustPainter();

  static const _width = 64.5;
  static const _height = 74.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _width, size.height / _height);
    final ink = Paint()..color = MessageTabTheme.fansInk;
    const middle = _width / 2;
    const foot = Radius.circular(6);
    canvas
      ..drawPath(
        Path()..addArc(Rect.fromCenter(center: const Offset(middle, 67), width: _width, height: 48), math.pi, math.pi),
        ink,
      )
      ..drawRRect(RRect.fromLTRBAndCorners(0, 66, _width, _height, bottomLeft: foot, bottomRight: foot), ink)
      ..drawCircle(const Offset(middle, 25), 25, ink)
      ..restore();
  }

  @override
  bool shouldRepaint(_BustPainter oldDelegate) => false;
}
