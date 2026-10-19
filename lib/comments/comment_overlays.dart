import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import 'comment_callbacks.dart';
import 'comments_model.dart';

sealed class CommentOverlay {
  const CommentOverlay();
}

final class ComposeOverlay extends CommentOverlay {
  const ComposeOverlay(this.target, {this.emotes = false});

  final ReplyTarget target;

  /// Opens on the emote panel rather than the keyboard.
  final bool emotes;
}

final class PicturesOverlay extends CommentOverlay {
  const PicturesOverlay(this.pictures, this.index);

  final List<CommentPicture> pictures;
  final int index;
}

final class DeleteOverlay extends CommentOverlay {
  const DeleteOverlay(this.comment);

  final Comment comment;
}

/// What [CommentOverlays] has up besides the thread, so the page's back closes it first.
class CommentOverlayController extends ValueNotifier<CommentOverlay?> {
  CommentOverlayController() : super(null);

  void compose(ReplyTarget target, {bool emotes = false}) => value = ComposeOverlay(target, emotes: emotes);

  void viewPictures(List<CommentPicture> pictures, int index) => value = PicturesOverlay(pictures, index);

  void confirmDelete(Comment comment) => value = DeleteOverlay(comment);

  void close() => value = null;
}

/// The comments' in-page overlays, in the page's Stack: 评论详情 rising from the bottom over the tab row and the list,
/// up to [threadTop] (an edge swipe lowers it with the finger and closes it), and over the whole page the composer,
/// the picture viewer and the delete confirm. Lets touches through when nothing is up.
class CommentOverlays extends StatefulWidget {
  const CommentOverlays({
    super.key,
    required this.model,
    required this.controller,
    required this.callbacks,
    required this.threadTop,
  });

  /// Null until the video's aid is known.
  final CommentsModel? model;
  final CommentOverlayController controller;
  final CommentCallbacks callbacks;

  /// The small player's bottom edge: the thread covers everything below it.
  final double threadTop;

  @override
  State<CommentOverlays> createState() => _CommentOverlaysState();
}

class _CommentOverlaysState extends State<CommentOverlays> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
