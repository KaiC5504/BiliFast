import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'comment_callbacks.dart';
import 'comment_row.dart';
import 'comments_model.dart';
import 'comments_tab.dart';

/// 评论详情 (13): the 评论详情 header with ✕, the root comment in full, a grey band, 相关回复共N条 with its sort, the
/// replies paging as they near the end, and the 发条评论 bar. A thread opened with a [ThreadState.focus] brings that
/// reply into view once.
class ThreadView extends StatefulWidget {
  const ThreadView({super.key, required this.model, required this.thread, required this.callbacks});

  final CommentsModel model;

  /// The thread as the overlay last saw it; while [model]'s open thread has the same root, that one shows instead,
  /// and once the thread closes this one stays on screen as it lowers.
  final ThreadState thread;
  final CommentCallbacks callbacks;

  @override
  State<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<ThreadView> {
  late NearEndPaging _paging = _pagingFor(widget.model);
  final _scroll = ScrollController();
  final _focusKey = GlobalKey();

  /// The root whose focus has been brought into view.
  int? _focusedRoot;

  /// Screens stepped down at most while looking for the focus's row, which the list builds only near the viewport.
  static const _focusSteps = 20;

  @override
  void didUpdateWidget(ThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.model, widget.model)) return;
    _paging.dispose();
    _paging = _pagingFor(widget.model);
  }

  @override
  void dispose() {
    _paging.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A row already in sight stays where it is; otherwise it goes to the top.
  Future<void> _bringFocus() async {
    for (var step = 0; step < _focusSteps && mounted && _scroll.hasClients; step++) {
      final position = _scroll.positions.last;
      if (_focusKey.currentContext?.findRenderObject() case final RenderBox row? when row.attached && row.hasSize) {
        final viewport = RenderAbstractViewport.of(row);
        final top = viewport.getOffsetToReveal(row, 0).offset;
        final bottom = viewport.getOffsetToReveal(row, 1).offset;
        if (position.pixels > top || position.pixels < bottom) {
          position.jumpTo(top.clamp(position.minScrollExtent, position.maxScrollExtent));
        }
        return;
      }
      if (!position.hasContentDimensions || position.pixels >= position.maxScrollExtent) return;
      position.jumpTo((position.pixels + position.viewportDimension).clamp(0.0, position.maxScrollExtent));
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  NearEndPaging _pagingFor(CommentsModel model) => NearEndPaging(
    canAsk: () {
      final thread = model.thread;
      return thread != null &&
          thread.root.rpid == widget.thread.root.rpid &&
          thread.page > 0 &&
          !thread.loading &&
          !thread.isEnd &&
          thread.error == null;
    },
    ask: model.loadMoreThread,
  );

  ThreadState get _shown => switch (widget.model.thread) {
    final live? when live.root.rpid == widget.thread.root.rpid => live,
    _ => widget.thread,
  };

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final callbacks = widget.callbacks;
    return ColoredBox(
      color: CommentListTheme.background,
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final thread = _shown;
          final root = thread.root;
          final focus = thread.focus;
          if (focus != null && _focusedRoot != root.rpid) {
            _focusedRoot = root.rpid;
            SchedulerBinding.instance.addPostFrameCallback((_) => unawaited(_bringFocus()));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onClose: model.closeThread),
              Expanded(
                child: _paging.listen(
                  CustomScrollView(
                    key: ValueKey(root.rpid),
                    controller: _scroll,
                    primary: false,
                    slivers: [
                      SliverToBoxAdapter(
                        child: CommentRow(
                          key: const ValueKey('thread-root'),
                          comment: root,
                          model: model,
                          callbacks: callbacks,
                          showsReplies: false,
                          showsDivider: false,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          key: ValueKey('thread-band'),
                          height: CommentListTheme.bandHeight,
                          child: ColoredBox(color: CommentListTheme.band),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: CommentSortHeader(
                          title: '相关回复共${thread.total}条',
                          sort: thread.sort,
                          onChange: (sort) => unawaited(model.setThreadSort(sort)),
                          height: CommentListTheme.threadSortHeight,
                          centre: CommentListTheme.threadSortCentre,
                        ),
                      ),
                      commentRows(thread.replies, (reply) {
                        final row = CommentRow(
                          key: reply.rpid == focus ? _focusKey : ValueKey(reply.rpid),
                          comment: reply,
                          model: model,
                          callbacks: callbacks,
                          thread: root,
                          showsReplies: false,
                        );
                        return reply.rpid == focus ? KeyedSubtree(key: ValueKey(reply.rpid), child: row) : row;
                      }),
                      SliverToBoxAdapter(
                        child: CommentListFooter(
                          loading: thread.loading,
                          error: thread.error,
                          isEnd: thread.isEnd,
                          isEmpty: thread.replies.isEmpty,
                          onRetry: () => unawaited(model.loadMoreThread()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              CommentWriteBar(
                prompt: thread.prompt ?? model.childPrompt,
                onWrite: (emotes) => callbacks.reply(ReplyToComment(root), emotes),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 评论详情 and ✕ over the thread, where the tab row was.
class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('thread-header'),
    height: CommentListTheme.threadHeaderHeight,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: CommentListTheme.background,
        border: Border(
          bottom: BorderSide(color: CommentListTheme.rule, width: CommentListTheme.threadHairline),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: CommentListTheme.gutter),
          Expanded(
            child: Text(
              '评论详情',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: BiliFonts.family,
                fontSize: CommentListTheme.threadTitleText,
                color: CommentListTheme.threadTitleInk,
              ),
            ),
          ),
          Semantics(
            key: const ValueKey('thread-close'),
            button: true,
            label: '关闭',
            onTap: onClose,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: const SizedBox(
                width: CommentListTheme.closeBox,
                height: CommentListTheme.threadHeaderHeight,
                child: Center(
                  child: CustomPaint(size: Size.square(CommentListTheme.close), painter: _CloseGlyphPainter()),
                ),
              ),
            ),
          ),
          const SizedBox(width: CommentListTheme.closeTrailing),
        ],
      ),
    ),
  );
}

class _CloseGlyphPainter extends CustomPainter {
  const _CloseGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CommentListTheme.closeInk
      ..strokeWidth = CommentListTheme.closeStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    // The ink spans the square, round ends included.
    final inset = CommentListTheme.closeStroke / 2;
    canvas
      ..drawLine(Offset(inset, inset), Offset(size.width - inset, size.height - inset), paint)
      ..drawLine(Offset(size.width - inset, inset), Offset(inset, size.height - inset), paint);
  }

  @override
  bool shouldRepaint(_CloseGlyphPainter oldDelegate) => false;
}
