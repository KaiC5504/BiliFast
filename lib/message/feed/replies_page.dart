import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../comments/comment_callbacks.dart';
import '../../comments/comment_overlays.dart';
import '../../comments/comments_model.dart';
import '../../dynamic/following/following_page.dart' show FollowingBarLook;
import '../../shared/loading_tv.dart';
import '../../shared/theme.dart';
import '../../skin/skin.dart';
import '../../space/uploader_tap.dart';
import 'feed_bar.dart';
import 'feed_lane.dart';
import 'feed_list.dart';
import 'feed_page_state.dart';
import 'feed_parts.dart';
import 'feed_sheet.dart';
import 'feed_targets.dart';
import 'reply_row.dart';

/// 回复与@ (197, 213): 全部 and @我. A row's 回复 opens the comment composer on that reply, 点赞 likes it at once (back
/// with a toast if Bilibili refuses), ⋮ the sheet (214); a tap opens the video or post at the reply.
class RepliesPage extends StatefulWidget {
  const RepliesPage({
    super.key,
    this.mentions = false,
    this.skin,
    @visibleForTesting this.opens = const FeedOpeners(),
    @visibleForTesting this.now,
  });

  /// Opens on @我.
  final bool mentions;

  /// [AppScope]'s by default.
  final ValueListenable<Skin?>? skin;
  final FeedOpeners opens;
  final DateTime Function()? now;

  @override
  State<RepliesPage> createState() => _RepliesPageState();
}

class _RepliesPageState extends State<RepliesPage> with SkinRefreshRoom, FeedPageState {
  final _calls = FeedCalls();
  late final _all = FeedLane<ReplyNotice>(
    name: 'replies',
    calls: _calls,
    idOf: (notice) => notice.id,
    fetch: (after) async {
      final page = await services.messageApi.replies(cursor: after as NoticeCursor?);
      return FeedChunk(page.items, next: page.next);
    },
  );
  late final _at = FeedLane<ReplyNotice>(
    name: 'mentions',
    calls: _calls,
    idOf: (notice) => notice.id,
    fetch: (after) async {
      final page = await services.messageApi.mentions(cursor: after as NoticeCursor?);
      return FeedChunk(page.items, next: page.next);
    },
  );
  final _allScroll = ScrollController();
  final _atScroll = ScrollController();
  late bool _mentions = widget.mentions;

  /// The chips shown so far (@我 as true): a list is built only once its chip has been chosen.
  late final _shownOnce = {widget.mentions};
  final _sheet = ValueNotifier<FeedSheetTarget?>(null);
  final _overlays = CommentOverlayController();
  final _drafts = CommentDrafts();
  final _models = <CommentsModel>[];
  CommentsModel? _comments;
  final _liking = <int>{};

  late final _callbacks = CommentCallbacks(
    reply: (_, _) {},
    openThread: (_) {},
    viewPictures: _overlays.viewPictures,
    confirmDelete: (_) {},
    seek: (_) {},
    openVideo: (_) {},
  );

  @override
  List<FeedLane<Object?>> get lanes => [_all, _at];

  @override
  FeedOpeners get opens => widget.opens;

  FeedLane<ReplyNotice> get _shown => _mentions ? _at : _all;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_layersChanged);
    _overlays.addListener(_layersChanged);
  }

  @override
  NoticeFeed get openedFeed => NoticeFeed.reply;

  /// 全部 asks only 回复我的, but opening 回复与@ clears the @ count too (MessageModel.feedOpened), and Bilibili clears
  /// it only once @我 is read: so its first page is asked as well while there are unread mentions.
  @override
  void startLists() {
    unawaited(_shown.start());
    if (!_mentions && services.messages.unread.at > 0) unawaited(_at.start());
  }

  @override
  void dispose() {
    _sheet
      ..removeListener(_layersChanged)
      ..dispose();
    _overlays
      ..removeListener(_layersChanged)
      ..dispose();
    for (final model in _models) {
      model.dispose();
    }
    _all.dispose();
    _at.dispose();
    _allScroll.dispose();
    _atScroll.dispose();
    super.dispose();
  }

  void _layersChanged() {
    if (mounted) setState(() {});
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  void _choose(bool mentions) {
    if (mentions == _mentions) return;
    setState(() {
      _mentions = mentions;
      _shownOnce.add(mentions);
    });
    if (!loggedOut) startLists();
  }

  FeedLane<ReplyNotice> _laneOf(NoticeFeed feed) => feed == NoticeFeed.at ? _at : _all;

  bool get _loggedIn => environment.account is LoggedIn;

  /// 回复: the composer answers the reply in its thread, as the comment section's 回复 does.
  void _reply(ReplyNotice notice) {
    if (!canAct()) return;
    final comments = _commentsFor(notice);
    final member = CommentMember(mid: notice.user.mid, name: notice.user.name, face: notice.user.face);
    final reply = Comment(
      rpid: notice.sourceId,
      oid: notice.subjectId,
      mid: notice.user.mid,
      root: notice.rootId,
      parent: notice.targetId,
      member: member,
      message: notice.text,
    );
    final ReplyTarget target = notice.rootId == 0
        ? ReplyToComment(reply)
        : ReplyInThread(
            root: Comment(rpid: notice.rootId, oid: notice.subjectId, member: const CommentMember(mid: 0), message: ''),
            reply: reply,
          );
    setState(() => _comments = comments);
    _overlays.compose(target);
  }

  /// One comment section per subject, kept for the page so a draft outlives the composer.
  CommentsModel _commentsFor(ReplyNotice notice) {
    for (final model in _models) {
      if (model.aid == notice.subjectId && model.type == notice.businessId) return model;
    }
    final model = CommentsModel(
      aid: notice.subjectId,
      type: notice.businessId,
      upMid: 0,
      api: services.pageApi,
      drafts: _drafts,
      isLoggedIn: () => _loggedIn,
      accountMid: () => environment.mid,
      requestLogin: () {
        if (_overlays.value is ComposeOverlay && !_drafts.anyPosting) _overlays.close();
        unawaited(login());
      },
      toast: toast,
    );
    // The section is never loaded, so its count grows only by what is posted here.
    var posted = 0;
    model.addListener(() {
      if (model.total <= posted) return;
      posted = model.total;
      toast('发送成功');
    });
    _models.add(model);
    return model;
  }

  /// 点赞: pink at once; back as it was, with Bilibili's reason, if refused.
  Future<void> _like(ReplyNotice notice) async {
    if (!canAct()) return;
    if (!_liking.add(notice.id)) return;
    final lane = _laneOf(notice.feed);
    final on = !notice.liked;
    lane.update(notice.id, (each) => each.copyWith(liked: on));
    try {
      await services.pageApi.likeComment(aid: notice.subjectId, rpid: notice.sourceId, on: on, type: notice.businessId);
    } catch (error) {
      lane.update(notice.id, (each) => each.copyWith(liked: !on));
      if (error is BiliError && error.needsLogin) {
        unawaited(login());
      } else {
        toast(FeedPageState.failureMessage(error));
      }
    } finally {
      _liking.remove(notice.id);
    }
  }

  void _face(ReplyNotice notice) {
    final user = notice.user;
    unawaited(opens.openSpace(context, UploaderRef(mid: user.mid, name: user.name, face: user.face)));
  }

  bool get _layerUp => _sheet.value != null || _overlays.value != null;

  /// Back closes the composer (unless it is posting) or the sheet first.
  void _closeLayers() {
    if (_overlays.value case final overlay?) {
      if (overlay is! ComposeOverlay || !_drafts.anyPosting) _overlays.close();
      return;
    }
    _sheet.value = null;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Skin?>(
    valueListenable: widget.skin ?? services.skin,
    builder: (context, skin, _) => _page(FollowingBarLook.of(skin)),
  );

  Widget _page(FollowingBarLook look) {
    final barHeight = FeedBar.heightOf(context);
    return PopScope<Object?>(
      canPop: !_layerUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeLayers();
      },
      child: Scaffold(
        backgroundColor: MessageFeedTheme.page,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FeedBar(
                  title: '回复与@',
                  look: look,
                  onBack: () => unawaited(Navigator.of(context).maybePop()),
                  onGear: () => openSettings(NoticeSettingKind.replies),
                ),
                _Chips(mentions: _mentions, onChoose: _choose),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: ListenableBuilder(
                      listenable: _shown,
                      builder: (context, _) =>
                          accountState(_shown) ??
                          IndexedStack(
                            index: _mentions ? 1 : 0,
                            sizing: StackFit.expand,
                            children: [
                              if (_shownOnce.contains(false)) _list(_all, _allScroll) else const SizedBox.shrink(),
                              if (_shownOnce.contains(true)) _list(_at, _atScroll) else const SizedBox.shrink(),
                            ],
                          ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: CommentOverlays(
                model: _comments,
                controller: _overlays,
                callbacks: _callbacks,
                threadTop: barHeight,
              ),
            ),
            Positioned.fill(
              child: FeedSheetLayer(
                open: _sheet,
                onMute: (target) => unawaited(mute(target)),
                onDelete: (target) => unawaited(delete(target, _laneOf(target.feed))),
              ),
            ),
            // The PopScope holds while a layer is up, which turns the route's edge swipe off: this takes the same edge
            // and puts the layer away instead.
            if (_layerUp)
              Positioned(
                key: const ValueKey('feed-layer-edge'),
                left: 0,
                top: 0,
                bottom: 0,
                width: math.max(BiliMetrics.swipeBackEdge, MediaQuery.paddingOf(context).left),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) >= 0) _closeLayers();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list(FeedLane<ReplyNotice> lane, ScrollController scroll) => FeedList<ReplyNotice>(
    name: lane.name,
    lane: lane,
    scroll: scroll,
    refreshRoom: refreshRoom,
    refreshTrigger: refreshTrigger,
    onRefreshFailed: toast,
    empty: ColoredBox(
      color: MessageFeedTheme.emptyFill,
      child: const FeedEmpty(top: MessageFeedTheme.emptyTop, textCentre: MessageFeedTheme.emptyTextCentre),
    ),
    row: (context, notice, last) => ReplyRow(
      key: ValueKey('feed-row-${notice.id}'),
      notice: notice,
      now: _now,
      rule: !last,
      onOpen: () => open(replyTarget(notice)),
      onFace: () => _face(notice),
      onReply: () => _reply(notice),
      onLike: () => unawaited(_like(notice)),
      onMore: () => _sheet.value = FeedSheetTarget(feed: notice.feed, id: notice.id),
    ),
  );
}

/// 全部 and @我 (197, 213): the chosen pink on a pale pink chip.
class _Chips extends StatelessWidget {
  const _Chips({required this.mentions, required this.onChoose});

  final bool mentions;
  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MessageFeedTheme.chipRow + MessageFeedTheme.chipRule,
    child: Stack(
      children: [
        Positioned(
          left: MessageFeedTheme.chipLeft,
          top: MessageFeedTheme.chipTop,
          height: MessageFeedTheme.chipHeight,
          child: Row(
            children: [
              _Chip(
                key: const ValueKey('feed-chip-all'),
                label: '全部',
                width: MessageFeedTheme.chipAllWidth,
                chosen: !mentions,
                onTap: () => onChoose(false),
              ),
              const SizedBox(width: MessageFeedTheme.chipGap),
              _Chip(
                key: const ValueKey('feed-chip-at'),
                label: '@我',
                width: MessageFeedTheme.chipAtWidth,
                chosen: mentions,
                onTap: () => onChoose(true),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: MessageFeedTheme.chipRule,
          child: ColoredBox(color: MessageFeedTheme.hairline),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.width, required this.chosen, required this.onTap});

  final String label;
  final double width;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FeedTap(
    label: label,
    selected: chosen,
    onTap: onTap,
    child: Container(
      width: width,
      height: MessageFeedTheme.chipHeight,
      alignment: Alignment.center,
      decoration: chosen
          ? BoxDecoration(
              color: MessageFeedTheme.chipChosenFill,
              borderRadius: const BorderRadius.all(Radius.circular(MessageFeedTheme.chipRadius)),
            )
          : null,
      child: feedLine(
        label,
        feedStyle(
          MessageFeedTheme.chipText,
          chosen ? MessageFeedTheme.chipChosenInk : MessageFeedTheme.chipInk,
          line: MessageFeedTheme.chipLine,
        ),
        align: TextAlign.center,
      ),
    ),
  );
}
