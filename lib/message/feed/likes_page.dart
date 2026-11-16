import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../dynamic/following/following_page.dart' show FollowingBarLook;
import '../../shared/loading_tv.dart';
import '../../shared/theme.dart';
import '../../skin/skin.dart';
import '../../space/uploader_tap.dart';
import '../message_routes.dart';
import 'feed_bar.dart';
import 'feed_lane.dart';
import 'feed_list.dart';
import 'feed_page_state.dart';
import 'feed_parts.dart';
import 'feed_sheet.dart';
import 'feed_targets.dart';
import 'like_row.dart';

/// 收到喜欢 (198): who liked what, newest first; ⋮ brings up 214's sheet, a tap opens what was liked.
class LikesPage extends StatefulWidget {
  const LikesPage({
    super.key,
    this.skin,
    @visibleForTesting this.opens = const FeedOpeners(),
    @visibleForTesting this.now,
  });

  /// [AppScope]'s by default.
  final ValueListenable<Skin?>? skin;
  final FeedOpeners opens;
  final DateTime Function()? now;

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> with SkinRefreshRoom, FeedPageState {
  late final _lane = FeedLane<LikeNotice>(
    name: 'likes',
    calls: FeedCalls(),
    idOf: (notice) => notice.id,
    fetch: (after) async {
      final page = await services.messageApi.likes(cursor: after as NoticeCursor?);
      return FeedChunk(page.items, next: page.next);
    },
  );
  final _scroll = ScrollController();
  final _sheet = ValueNotifier<FeedSheetTarget?>(null);

  /// Rows muted this visit, whose sheet no longer offers 不再通知.
  final _muted = <int>{};

  @override
  List<FeedLane<Object?>> get lanes => [_lane];

  @override
  FeedOpeners get opens => widget.opens;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_sheetChanged);
  }

  @override
  void servicesReady() => services.messages.feedOpened(NoticeFeed.like);

  @override
  void startLists() => unawaited(_lane.start());

  @override
  void muted(FeedSheetTarget target) => _muted.add(target.id);

  @override
  void dispose() {
    _sheet
      ..removeListener(_sheetChanged)
      ..dispose();
    _lane.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sheetChanged() {
    if (mounted) setState(() {});
  }

  void _face(LikeNotice notice) {
    if (notice.users.isEmpty) return;
    final user = notice.users.first;
    unawaited(opens.openSpace(context, UploaderRef(mid: user.mid, name: user.name, face: user.face)));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Skin?>(
    valueListenable: widget.skin ?? services.skin,
    builder: (context, skin, _) => _page(FollowingBarLook.of(skin)),
  );

  Widget _page(FollowingBarLook look) {
    final sheetUp = _sheet.value != null;
    final now = (widget.now ?? DateTime.now)();
    return PopScope<Object?>(
      canPop: !sheetUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _sheet.value = null;
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
                  title: '收到喜欢',
                  look: look,
                  onBack: () => unawaited(Navigator.of(context).maybePop()),
                  onGear: () => unawaited(openNoticePicker(context, NoticeSettingKind.likes)),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: ListenableBuilder(
                      listenable: _lane,
                      builder: (context, _) =>
                          accountState(_lane) ??
                          FeedList<LikeNotice>(
                            name: _lane.name,
                            lane: _lane,
                            scroll: _scroll,
                            refreshRoom: refreshRoom,
                            refreshTrigger: refreshTrigger,
                            onRefreshFailed: toast,
                            empty: const ColoredBox(
                              color: MessageFeedTheme.emptyFill,
                              child: FeedEmpty(
                                top: MessageFeedTheme.emptyTop,
                                textCentre: MessageFeedTheme.emptyTextCentre,
                              ),
                            ),
                            row: (context, notice, last) => LikeRow(
                              key: ValueKey('feed-row-${notice.id}'),
                              notice: notice,
                              now: now,
                              rule: !last,
                              onOpen: () => open(likeTarget(notice)),
                              onFace: () => _face(notice),
                              onMore: () => _sheet.value = FeedSheetTarget(
                                feed: NoticeFeed.like,
                                id: notice.id,
                                canMute: notice.notifying && !_muted.contains(notice.id),
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: FeedSheetLayer(
                open: _sheet,
                onMute: (target) => unawaited(mute(target)),
                onDelete: (target) => unawaited(delete(target, _lane)),
              ),
            ),
            if (sheetUp)
              Positioned(
                key: const ValueKey('feed-layer-edge'),
                left: 0,
                top: 0,
                bottom: 0,
                width: math.max(BiliMetrics.swipeBackEdge, MediaQuery.paddingOf(context).left),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) >= 0) _sheet.value = null;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
