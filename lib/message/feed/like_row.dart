import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../message_dates.dart';
import 'feed_parts.dart';

/// 我的评论, 我的弹幕, …: what was liked, by its business.
String likedThing(LikeNotice notice) => switch (notice.business) {
  '评论' => '我的评论',
  '弹幕' => '我的弹幕',
  '视频' => '我的视频',
  '动态' => '我的动态',
  '专栏' => '我的专栏',
  final other when other.isNotEmpty => '我的$other',
  _ => '我的内容',
};

/// One row of 收到喜欢 (198): the latest likers' faces, "A、B 等总计N人赞了我的评论" or "A 点赞了我的评论", the date and
/// ⋮; at the right what was liked. A tap opens it where the app can, the faces the newest liker's space.
class LikeRow extends StatelessWidget {
  const LikeRow({
    super.key,
    required this.notice,
    required this.now,
    required this.onOpen,
    required this.onFace,
    required this.onMore,
    this.rule = true,
  });

  final LikeNotice notice;
  final DateTime now;

  /// The rule under it; not under the list's last.
  final bool rule;
  final VoidCallback onOpen;
  final VoidCallback onFace;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final id = notice.id;
    final name = feedStyle(
      MessageFeedTheme.nameText,
      MessageFeedTheme.name,
      line: MessageFeedTheme.nameLine,
      weight: MessageFeedTheme.nameWeight,
    );
    final grey = feedStyle(MessageFeedTheme.nameText, MessageFeedTheme.actionInk, line: MessageFeedTheme.nameLine);
    final date = feedStyle(MessageFeedTheme.dateText, MessageFeedTheme.dateInk, line: MessageFeedTheme.dateLine);
    final users = notice.users.take(2).toList();
    final line = likeLine(notice);
    const nameTop = MessageFeedTheme.likeNameCentre - MessageFeedTheme.nameLine / 2;
    const dateTop = MessageFeedTheme.likeDateCentre - MessageFeedTheme.dateBox / 2;
    const bottom = MessageFeedTheme.rowBottom - MessageFeedTheme.dateBox / 2;
    return FeedRowTap(
      key: ValueKey('feed-like-$id'),
      label: '${line.names.join('、')}${line.rest}，${noticeDate(notice.time, now: now)}',
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Positioned(
                left: MessageFeedTheme.faceLeft,
                top: users.length > 1 ? MessageFeedTheme.pairTop : MessageFeedTheme.likeFaceTop,
                child: FeedTap(
                  key: ValueKey('feed-like-face-$id'),
                  label: users.isEmpty ? '' : users.first.name,
                  onTap: users.isEmpty ? null : onFace,
                  child: users.length > 1 ? _Pair(users: users) : _Single(face: users.isEmpty ? '' : users.first.face),
                ),
              ),
              Positioned(
                right: MessageFeedTheme.sideRight,
                top: 0,
                bottom: 0,
                width: MessageFeedTheme.sideWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: FeedSide(
                      key: ValueKey('feed-like-side-$id'),
                      text: notice.title.isNotEmpty || notice.image.isEmpty ? notice.title : '',
                      picture: notice.image,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: MessageFeedTheme.textLeft),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: nameTop),
                    Padding(
                      padding: const EdgeInsets.only(right: MessageFeedTheme.textRight),
                      child: SizedBox(
                        height: MessageFeedTheme.nameLine,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ExcludeSemantics(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  for (final (index, who) in line.names.indexed) ...[
                                    // iOS squeezes the 、 to about half its width.
                                    if (index > 0)
                                      TextSpan(
                                        text: ' 、',
                                        style: grey.copyWith(letterSpacing: -MessageFeedTheme.likeCommaSqueeze),
                                      ),
                                    TextSpan(text: who, style: name),
                                  ],
                                  const WidgetSpan(child: SizedBox(width: MessageFeedTheme.nameGap)),
                                  TextSpan(text: line.rest, style: grey),
                                ],
                              ),
                              key: ValueKey('feed-like-line-$id'),
                              strutStyle: BiliFonts.strut(grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: dateTop - nameTop - MessageFeedTheme.nameLine),
                    SizedBox(
                      height: MessageFeedTheme.dateBox,
                      child: Row(
                        children: [
                          feedDateWords(noticeDate(notice.time, now: now), date),
                          const Spacer(),
                          FeedMoreButton(key: ValueKey('feed-like-more-$id'), onTap: onMore),
                          const SizedBox(width: MessageFeedTheme.moreRight - MessageFeedTheme.moreTarget / 2),
                        ],
                      ),
                    ),
                    const SizedBox(height: bottom),
                  ],
                ),
              ),
            ],
          ),
          FeedRowRule(shown: rule),
        ],
      ),
    );
  }
}

/// The first line's runs (198): the names bold with a grey 、 between, then what happened, grey.
({List<String> names, String rest}) likeLine(LikeNotice notice) {
  final users = notice.users.take(2).toList();
  final thing = likedThing(notice);
  final count = notice.count > users.length ? notice.count : users.length;
  return (
    names: [for (final user in users) user.name],
    rest: users.length > 1 || count > 1 ? '等总计$count人赞了$thing' : '点赞了$thing',
  );
}

class _Single extends StatelessWidget {
  const _Single({required this.face});

  final String face;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: MessageFeedTheme.face, child: FeedFace(face));
}

/// Two likers (198): the older face behind at the top left, the newer over it lower right in a white ring.
class _Pair extends StatelessWidget {
  const _Pair({required this.users});

  /// Newest first.
  final List<NoticeUser> users;

  @override
  Widget build(BuildContext context) {
    const face = MessageFeedTheme.pairFace;
    const shift = MessageFeedTheme.pairShift;
    const ring = MessageFeedTheme.pairRing;
    return SizedBox.square(
      dimension: face + shift,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, width: face, height: face, child: FeedFace(users[1].face)),
          Positioned(
            left: shift - ring,
            top: shift - ring,
            width: face + ring * 2,
            height: face + ring * 2,
            child: Container(
              padding: const EdgeInsets.all(ring),
              decoration: const BoxDecoration(color: MessageFeedTheme.page, shape: BoxShape.circle),
              child: FeedFace(users[0].face),
            ),
          ),
        ],
      ),
    );
  }
}
