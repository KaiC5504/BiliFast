import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

/// A comment's text (BiliNative `RichTextView`): emotes inline at the text's size (large ones bigger), @mentions,
/// links and video ids in the link blue, timestamps that seek. [leading] goes first, as a reply preview's "name: ".
class CommentText extends StatefulWidget {
  const CommentText({
    super.key,
    required this.runs,
    required this.style,
    this.leading,
    this.maxLines,
    this.onSeek,
    this.onOpenVideo,
  });

  final List<RichRun> runs;
  final TextStyle style;
  final InlineSpan? leading;

  /// Ends in an ellipsis when set.
  final int? maxLines;
  final ValueChanged<int>? onSeek;
  final ValueChanged<String>? onOpenVideo;

  @override
  State<CommentText> createState() => _CommentTextState();
}

class _CommentTextState extends State<CommentText> {
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        ?widget.leading,
        for (final run in widget.runs)
          if (run is TextRun) TextSpan(text: run.text),
      ],
    ),
    style: widget.style,
    maxLines: widget.maxLines,
    overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
  );
}
