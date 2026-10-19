import 'package:flutter/widgets.dart';

import 'comment_callbacks.dart';
import 'comments_model.dart';

/// 评论详情 (13): the 评论详情 header with ✕, the root comment in full, a grey band, 相关回复共N条 with its sort, the
/// replies paging as they near the end, and the 发条评论 bar.
class ThreadView extends StatelessWidget {
  const ThreadView({super.key, required this.model, required this.thread, required this.callbacks});

  final CommentsModel model;
  final ThreadState thread;
  final CommentCallbacks callbacks;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
