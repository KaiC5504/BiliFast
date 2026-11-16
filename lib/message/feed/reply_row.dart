import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../message_dates.dart';
import 'feed_parts.dart';

/// The grey words after the name (197): what kind of reply or mention this is.
String replyAction(ReplyNotice notice) {
  final at = notice.feed == NoticeFeed.at;
  return switch (notice.business) {
    'reply' => at ? '在评论中@了我' : '回复了我的评论',
    'video' => at ? '在视频中@了我' : '评论了我的视频',
    'dynamic' || 'album' || 'text' => at ? '在动态中@了我' : '评论了我的动态',
    'article' => at ? '在专栏中@了我' : '评论了我的专栏',
    _ => at ? '@了我' : '回复了我',
  };
}

/// One row of 回复与@ (197): the face, the name with its UP tag and what they did, what they wrote, then the date,
/// 回复, 点赞 and ⋮; at the right what it answered. A tap on the row opens what it was on, on the face the space.
class ReplyRow extends StatelessWidget {
  const ReplyRow({
    super.key,
    required this.notice,
    required this.now,
    required this.onOpen,
    required this.onFace,
    required this.onReply,
    required this.onLike,
    required this.onMore,
    this.rule = true,
  });

  final ReplyNotice notice;
  final DateTime now;

  /// The rule under it; not under the list's last.
  final bool rule;
  final VoidCallback onOpen;
  final VoidCallback onFace;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final id = notice.id;
    final up = notice.fromUploader ? MessageFeedTheme.upExtra : 0.0;
    final name = feedStyle(
      MessageFeedTheme.nameText,
      MessageFeedTheme.name,
      line: MessageFeedTheme.nameLine,
      weight: MessageFeedTheme.nameWeight,
    );
    final grey = feedStyle(MessageFeedTheme.nameText, MessageFeedTheme.actionInk, line: MessageFeedTheme.nameLine);
    final body = feedStyle(MessageFeedTheme.bodyText, MessageFeedTheme.bodyInk, line: MessageFeedTheme.bodyLine);
    final date = feedStyle(MessageFeedTheme.dateText, MessageFeedTheme.dateInk, line: MessageFeedTheme.dateLine);
    final action = replyAction(notice);
    const nameTop = MessageFeedTheme.nameCentre - MessageFeedTheme.nameLine / 2;
    const bodyTop = MessageFeedTheme.bodyCentre - MessageFeedTheme.bodyLine / 2;
    const dateTop = MessageFeedTheme.dateGap - MessageFeedTheme.bodyLine / 2 - MessageFeedTheme.dateBox / 2;
    const bottom = MessageFeedTheme.rowBottom - MessageFeedTheme.dateBox / 2;
    return FeedRowTap(
      key: ValueKey('feed-reply-$id'),
      label: '${notice.user.name}$action：${notice.text}，${noticeDate(notice.time, now: now)}',
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Positioned(
                left: MessageFeedTheme.faceLeft,
                top: MessageFeedTheme.replyFaceTop,
                width: MessageFeedTheme.face,
                height: MessageFeedTheme.face,
                child: FeedTap(
                  key: ValueKey('feed-reply-face-$id'),
                  label: notice.user.name,
                  onTap: onFace,
                  child: FeedFace(notice.user.face),
                ),
              ),
              Positioned(
                right: MessageFeedTheme.sideRight,
                top: MessageFeedTheme.sideTop,
                width: MessageFeedTheme.sideWidth,
                child: ExcludeSemantics(
                  child: FeedSide(
                    key: ValueKey('feed-reply-side-$id'),
                    text: notice.targetText.isNotEmpty || notice.image.isEmpty ? _sideText : '',
                    picture: notice.image,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: MessageFeedTheme.textLeft),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: nameTop + up),
                    Padding(
                      padding: const EdgeInsets.only(right: MessageFeedTheme.textRight),
                      child: SizedBox(
                        height: MessageFeedTheme.nameLine,
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              Flexible(child: feedLine(notice.user.name, name, key: ValueKey('feed-reply-name-$id'))),
                              if (notice.fromUploader) ...[
                                const SizedBox(width: MessageFeedTheme.nameGap),
                                _UpTag(key: ValueKey('feed-reply-up-$id')),
                                const SizedBox(width: MessageFeedTheme.upGap),
                              ] else
                                const SizedBox(width: MessageFeedTheme.nameGap),
                              Text(
                                action,
                                key: ValueKey('feed-reply-action-$id'),
                                style: grey,
                                strutStyle: BiliFonts.strut(grey),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: bodyTop - nameTop - MessageFeedTheme.nameLine),
                    Padding(
                      padding: const EdgeInsets.only(right: MessageFeedTheme.textRight),
                      child: ExcludeSemantics(
                        child: Text(
                          notice.text,
                          key: ValueKey('feed-reply-text-$id'),
                          style: body,
                          strutStyle: BiliFonts.strut(body),
                          maxLines: MessageFeedTheme.bodyLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: dateTop),
                    SizedBox(
                      height: MessageFeedTheme.dateBox,
                      child: Row(
                        children: [
                          feedDateWords(noticeDate(notice.time, now: now), date),
                          const SizedBox(width: MessageFeedTheme.actionsGap),
                          if (notice.canReply) ...[
                            _Action(
                              key: ValueKey('feed-reply-reply-$id'),
                              label: '回复',
                              glyph: Image.asset(
                                'assets/images/message/feed_reply.png',
                                width: MessageFeedTheme.glyph,
                                height: MessageFeedTheme.replyGlyphHeight,
                                color: MessageFeedTheme.dateInk,
                              ),
                              style: date,
                              onTap: onReply,
                            ),
                            const SizedBox(width: MessageFeedTheme.actionGap),
                          ],
                          if (notice.canLike)
                            _Action(
                              key: ValueKey('feed-reply-like-$id'),
                              label: notice.liked ? '取消点赞' : '点赞',
                              words: '点赞',
                              glyph: Image.asset(
                                notice.liked
                                    ? 'assets/images/message/feed_liked.png'
                                    : 'assets/images/message/feed_like.png',
                                key: ValueKey('feed-reply-thumb-$id-${notice.liked ? 'on' : 'off'}'),
                                width: MessageFeedTheme.glyph,
                                height: MessageFeedTheme.glyph,
                                color: notice.liked ? MessageFeedTheme.likedInk : MessageFeedTheme.dateInk,
                              ),
                              style: date,
                              onTap: onLike,
                            ),
                          const Spacer(),
                          FeedMoreButton(key: ValueKey('feed-reply-more-$id'), onTap: onMore),
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

  /// What was answered, else the subject's title.
  String get _sideText => notice.targetText.isNotEmpty ? notice.targetText : notice.title;
}

/// 回复 or 点赞 on the date's line: the glyph and its grey word.
class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.glyph,
    required this.style,
    required this.onTap,
    String? words,
  }) : words = words ?? label;

  final String label;
  final String words;
  final Widget glyph;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FeedTap(
    label: label,
    onTap: onTap,
    child: SizedBox(
      height: MessageFeedTheme.dateBox,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          const SizedBox(width: MessageFeedTheme.glyphGap),
          feedDateWords(words, style),
        ],
      ),
    ),
  );
}

/// UP, after the name of the subject's uploader (197).
class _UpTag extends StatelessWidget {
  const _UpTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: MessageFeedTheme.upWidth,
    height: MessageFeedTheme.upHeight,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: MessageFeedTheme.upFill,
      borderRadius: BorderRadius.all(Radius.circular(MessageFeedTheme.upRadius)),
    ),
    child: Text('UP', style: feedStyle(MessageFeedTheme.upText, MessageFeedTheme.upInk).copyWith(height: 1)),
  );
}
