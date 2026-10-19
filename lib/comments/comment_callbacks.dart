import 'package:bili_core/api.dart';

import 'comments_model.dart';

/// What a comment's taps ask of the page, which owns the composer, the picture viewer, the delete confirm and the
/// player: rows, lists and the thread only report the tap.
class CommentCallbacks {
  const CommentCallbacks({
    required this.reply,
    required this.openThread,
    required this.viewPictures,
    required this.confirmDelete,
    required this.seek,
    required this.openVideo,
  });

  /// 回复 on a row, or the 发条评论 bar; [emotes] opens the composer on the emote panel (the bar's face button).
  final void Function(ReplyTarget target, bool emotes) reply;

  /// 共N条回复, or a tap on a reply preview.
  final void Function(Comment root) openThread;
  final void Function(List<CommentPicture> pictures, int index) viewPictures;

  /// ⋮ → 删除 on the viewer's own comment.
  final void Function(Comment comment) confirmDelete;

  /// A timestamp in a comment.
  final void Function(int seconds) seek;

  /// A BV or av id, or a bilibili.com video link, in a comment.
  final void Function(String id) openVideo;
}
