import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../friends/friends_route.dart';
import '../../friends/friends_rows.dart' show FriendsRow, RelationPillKind;
import '../../shared/loading_tv.dart';
import '../../shared/theme.dart';
import '../../space/uploader_tap.dart';
import '../message_routes.dart';
import 'feed_bar.dart';
import 'feed_lane.dart';
import 'feed_list.dart';
import 'feed_page_state.dart';
import 'feed_parts.dart';
import 'feed_targets.dart';

/// 新增粉丝 (199): the account's fans, newest first, as 我的好友's 粉丝 rows (no screenshot of a row yet); 回关 follows
/// back. Empty, the APK's picture under the plain bar.
class NewFansPage extends StatefulWidget {
  const NewFansPage({super.key, @visibleForTesting this.opens = const FeedOpeners()});

  final FeedOpeners opens;

  @override
  State<NewFansPage> createState() => _NewFansPageState();
}

class _NewFansPageState extends State<NewFansPage> with SkinRefreshRoom, FeedPageState {
  late final _lane = FeedLane<RelationUser>(
    name: 'fans',
    calls: FeedCalls(),
    idOf: (user) => user.mid,
    fetch: (after) async {
      final page = (after as int?) ?? 1;
      final answer = await services.messageApi.newFans(environment.mid ?? 0, page: page);
      return FeedChunk(answer.users, next: answer.hasMore ? page + 1 : null);
    },
  );
  final _scroll = ScrollController();

  /// 回关 still out, by mid.
  final _pending = <int, bool>{};

  @override
  List<FeedLane<Object?>> get lanes => [_lane];

  @override
  FeedOpeners get opens => widget.opens;

  @override
  void servicesReady() => services.follows.addListener(_followsChanged);

  /// The fans need the account's mid, which a cold start's check may not have yet.
  @override
  void startLists() {
    if (environment.mid != null) unawaited(_lane.start());
  }

  @override
  void dispose() {
    services.follows.removeListener(_followsChanged);
    _lane.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followsChanged() {
    if (mounted) setState(() {});
  }

  bool _following(RelationUser user) => _pending[user.mid] ?? services.follows.following(user.mid) ?? user.following;

  Future<void> _followBack(RelationUser user) async {
    final mid = user.mid;
    if (_following(user) || _pending.containsKey(mid)) return;
    setState(() => _pending[mid] = true);
    try {
      await services.messageApi.follow(mid, on: true);
      services.follows.changed(mid, following: true);
      toast('关注成功');
    } catch (error) {
      Logger.shared.warn(LogCategory.api, 'new fans follow failed', {'error': feedLogReason(error)});
      if (error is BiliError && error.needsLogin) {
        unawaited(login());
      } else {
        toast(FeedPageState.failureMessage(error));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(mid));
    }
  }

  void _open(RelationUser user) {
    final person = user.user;
    unawaited(opens.openSpace(context, UploaderRef(mid: person.mid, name: person.name, face: person.face)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MessageFeedTheme.page,
    resizeToAvoidBottomInset: false,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeedPlainBar(
          title: '新增粉丝',
          onBack: () => unawaited(Navigator.of(context).maybePop()),
          onGear: () => unawaited(openNoticePicker(context, NoticeSettingKind.fans)),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: ListenableBuilder(
              listenable: _lane,
              builder: (context, _) =>
                  accountState(_lane) ??
                  FeedList<RelationUser>(
                    name: _lane.name,
                    lane: _lane,
                    scroll: _scroll,
                    refreshRoom: refreshRoom,
                    refreshTrigger: refreshTrigger,
                    onRefreshFailed: toast,
                    empty: const FeedEmpty(
                      top: MessageFeedTheme.fansEmptyTop,
                      textCentre: MessageFeedTheme.fansEmptyTextCentre,
                    ),
                    row: (context, user, _) => FriendsRow(
                      key: ValueKey('feed-fan-${user.mid}'),
                      user: user,
                      pill: RelationPillKind.of(user, tab: FriendsTab.fans, following: _following(user)),
                      busy: _pending.containsKey(user.mid),
                      onTap: () => _open(user),
                      onPill: () => unawaited(_followBack(user)),
                    ),
                  ),
            ),
          ),
        ),
      ],
    ),
  );
}
