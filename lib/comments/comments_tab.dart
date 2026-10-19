import 'dart:async';

import 'package:bili_core/api.dart' show Comment, CommentSort;
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../video/collapsing_player.dart';
import 'comment_callbacks.dart';
import 'comment_row.dart';
import 'comments_model.dart';

/// 评论 (10-12): 热门评论 / 最新评论 with ≡ 按热度 / 按时间, the pinned comment, the list paging as it nears the end,
/// its footer, and the 哎呦，不错哦，发条评论吧 bar fixed at the bottom. Asks [model] for its first page when it first
/// shows. Its list scrolls with the page's primary scroll controller and starts `PlayerReserve` below its top.
class CommentsTab extends StatefulWidget {
  const CommentsTab({super.key, required this.model, required this.callbacks});

  final CommentsModel model;
  final CommentCallbacks callbacks;

  @override
  State<CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends State<CommentsTab> {
  late NearEndPaging _paging = _pagingFor(widget.model);

  @override
  void initState() {
    super.initState();
    // The first build reads the model as it is, so a change ensureLoaded makes before the listener is on is not lost.
    unawaited(widget.model.ensureLoaded());
    widget.model.addListener(_changed);
  }

  @override
  void didUpdateWidget(CommentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.model, widget.model)) return;
    oldWidget.model.removeListener(_changed);
    _paging.dispose();
    _paging = _pagingFor(widget.model);
    unawaited(widget.model.ensureLoaded());
    widget.model.addListener(_changed);
  }

  @override
  void dispose() {
    widget.model.removeListener(_changed);
    _paging.dispose();
    super.dispose();
  }

  NearEndPaging _pagingFor(CommentsModel model) => NearEndPaging(
    canAsk: () =>
        model.hasLoaded && !model.loading && !model.isEnd && model.error == null && model.closedMessage == null,
    ask: model.loadMore,
  );

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final callbacks = widget.callbacks;
    final closed = model.closedMessage;
    final pinned = model.pinned;
    final comments = model.comments;
    return ColoredBox(
      color: CommentListTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _paging.listen(
              CustomScrollView(
                primary: true,
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(key: const ValueKey('comments-reserve'), height: PlayerReserve.of(context)),
                  ),
                  if (closed != null)
                    SliverToBoxAdapter(child: _ClosedNotice(message: closed))
                  else ...[
                    SliverToBoxAdapter(
                      child: CommentSortHeader(
                        title: model.sort == CommentSort.hot ? '热门评论' : '最新评论',
                        sort: model.sort,
                        onChange: (sort) => unawaited(model.setSort(sort)),
                      ),
                    ),
                    if (pinned != null)
                      SliverToBoxAdapter(
                        child: CommentRow(
                          key: ValueKey('pinned-${pinned.rpid}'),
                          comment: pinned,
                          model: model,
                          callbacks: callbacks,
                        ),
                      ),
                    commentRows(
                      comments,
                      (comment) =>
                          CommentRow(key: ValueKey(comment.rpid), comment: comment, model: model, callbacks: callbacks),
                    ),
                    SliverToBoxAdapter(
                      child: CommentListFooter(
                        loading: model.loading || !model.hasLoaded,
                        error: model.error,
                        isEnd: model.isEnd,
                        isEmpty: comments.isEmpty && pinned == null,
                        onRetry: () => unawaited(model.loadMore()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          CommentWriteBar(onWrite: (emotes) => callbacks.reply(const ReplyToVideo(), emotes)),
        ],
      ),
    );
  }
}

/// [comments] as rows keyed by rpid, so a row posted at the top moves the others down rather than rebuilding them in
/// place.
SliverList commentRows(List<Comment> comments, Widget Function(Comment comment) row) {
  final indexes = {for (final (index, comment) in comments.indexed) comment.rpid: index};
  return SliverList.builder(
    itemCount: comments.length,
    itemBuilder: (context, index) => row(comments[index]),
    findChildIndexCallback: (key) => key is ValueKey<int> ? indexes[key.value] : null,
  );
}

/// Asks for the next page once the end of a list is within a screen: one ask at a time, and only while [canAsk],
/// which a list makes false while loading, at its end and after a failure, so a failed page waits for 点击重试.
class NearEndPaging {
  NearEndPaging({required this.canAsk, required this.ask});

  final bool Function() canAsk;
  final Future<void> Function() ask;

  bool _asking = false;
  bool _disposed = false;

  /// Watches [scrollView]: scrolling, and its content growing or shrinking without a scroll, as when a page arrives
  /// that still leaves the end on screen.
  Widget listen(Widget scrollView) => NotificationListener<ScrollMetricsNotification>(
    onNotification: (notification) {
      if (notification.depth == 0) _check(notification.metrics);
      return false;
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _check(notification.metrics);
        return false;
      },
      child: scrollView,
    ),
  );

  void _check(ScrollMetrics metrics) {
    if (_asking || _disposed || !metrics.hasContentDimensions || !canAsk()) return;
    if (metrics.extentAfter > metrics.viewportDimension) return;
    _asking = true;
    // A scroll notification can come mid-layout, where the model's change must not rebuild anything yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && canAsk()) {
          _ask();
        } else {
          _asking = false;
        }
      });
    } else {
      _ask();
    }
  }

  void _ask() => unawaited(ask().whenComplete(() => _asking = false));

  void dispose() => _disposed = true;
}

/// 热门评论 … ≡ 按热度 over the list, 相关回复共N条 … ≡ 按时间 in a thread; a tap on the right switches the sort.
class CommentSortHeader extends StatelessWidget {
  const CommentSortHeader({
    super.key,
    required this.title,
    required this.sort,
    required this.onChange,
    this.height = CommentListTheme.sortHeight,
    this.centre = CommentListTheme.sortCentre,
  });

  final String title;
  final CommentSort sort;
  final ValueChanged<CommentSort> onChange;

  final double height;

  /// Where the title's and the button's line centres, down from the header's top.
  final double centre;

  TextStyle _style(double size, double spacing) => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: size,
    color: CommentListTheme.sortInk,
    height: CommentListTheme.sortLine / size,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: spacing,
  );

  @override
  Widget build(BuildContext context) {
    final label = sort == CommentSort.hot ? '按热度' : '按时间';
    void toggle() => onChange(sort == CommentSort.hot ? CommentSort.time : CommentSort.hot);
    const line = CommentListTheme.sortLine;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: CommentListTheme.gutter,
            top: centre - line / 2,
            height: line,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              style: _style(CommentListTheme.sortTitleText, CommentListTheme.sortTitleSpacing),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Semantics(
              key: const ValueKey('comment-sort'),
              button: true,
              label: label,
              hint: '切换排序',
              onTap: toggle,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: CommentListTheme.sortTouchLead,
                    right: CommentListTheme.gutter,
                    top: centre - line / 2,
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    widthFactor: 1,
                    child: SizedBox(
                      height: line,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CustomPaint(
                            size: Size(CommentListTheme.sortIconWidth, line),
                            painter: _SortGlyphPainter(),
                          ),
                          const SizedBox(width: CommentListTheme.sortIconGap),
                          Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            style: _style(CommentListTheme.sortText, CommentListTheme.sortSpacing),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortGlyphPainter extends CustomPainter {
  const _SortGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CommentListTheme.sortInk
      ..strokeWidth = CommentListTheme.sortIconBar;
    final middle = size.height / 2;
    for (final offset in const [-CommentListTheme.sortIconPitch, 0.0, CommentListTheme.sortIconPitch]) {
      canvas.drawLine(Offset(0, middle + offset), Offset(size.width, middle + offset), paint);
    }
  }

  @override
  bool shouldRepaint(_SortGlyphPainter oldDelegate) => false;
}

/// The end of a list: the spinner while a page loads, 没有更多了, 还没有评论，快来抢沙发吧, or 加载失败，点击重试. Idle with
/// more to come it keeps the spinner's room empty: the next page is asked for before the end shows, and a spinner
/// left turning in a tab kept alive off screen would keep a core busy.
class CommentListFooter extends StatelessWidget {
  const CommentListFooter({
    super.key,
    required this.loading,
    required this.error,
    required this.isEnd,
    required this.isEmpty,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool isEnd;
  final bool isEmpty;
  final VoidCallback onRetry;

  TextStyle _style(Color color) => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: CommentListTheme.footerText,
    color: color,
    height: CommentListTheme.footerLine / CommentListTheme.footerText,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: 0,
  );

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(
      vertical: isEmpty ? CommentListTheme.emptyPadding : CommentListTheme.footerPadding,
    );
    if (error != null && !loading) {
      return Semantics(
        key: const ValueKey('comments-retry'),
        button: true,
        label: '加载失败，点击重试',
        onTap: onRetry,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Padding(
            padding: padding,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '加载失败，', style: _style(CommentListTheme.retryInk)),
                  TextSpan(text: '点击重试', style: _style(CommentListTheme.retryAction)),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (isEnd && !loading) {
      return Padding(
        key: const ValueKey('comments-end'),
        padding: padding,
        child: Text(
          isEmpty ? '还没有评论，快来抢沙发吧' : '没有更多了',
          textAlign: TextAlign.center,
          style: _style(CommentListTheme.footerInk),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: SizedBox(
        height: CommentListTheme.spinnerRadius * 2,
        child: loading
            ? const CupertinoActivityIndicator(
                key: ValueKey('comments-loading'),
                radius: CommentListTheme.spinnerRadius,
              )
            : null,
      ),
    );
  }
}

class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('comments-closed'),
    padding: const EdgeInsets.only(
      top: CommentListTheme.closedTop,
      left: CommentListTheme.gutter,
      right: CommentListTheme.gutter,
    ),
    child: Column(
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.chat_bubble_outline, size: CommentListTheme.closedIcon, color: CommentListTheme.closedInk),
        ),
        const SizedBox(height: CommentListTheme.closedGap),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: BiliFonts.family,
            fontSize: CommentListTheme.closedText,
            color: CommentListTheme.closedInk,
            letterSpacing: 0,
          ),
        ),
      ],
    ),
  );
}

/// The bar under the list and the thread (10, 13): the grey 哎呦，不错哦，发条评论吧 pill and the emote face at its right,
/// over the home indicator. [onWrite] gets true from the face, which opens the composer on its emotes.
class CommentWriteBar extends StatelessWidget {
  const CommentWriteBar({super.key, required this.onWrite});

  final ValueChanged<bool> onWrite;

  static const placeholder = '哎呦，不错哦，发条评论吧';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      key: const ValueKey('comment-bar'),
      decoration: const BoxDecoration(
        color: CommentListTheme.background,
        border: Border(
          top: BorderSide(color: CommentListTheme.rule, width: CommentListTheme.barHairline),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: CommentListTheme.gutter,
          top: CommentListTheme.barTop,
          bottom: CommentListTheme.barBottom + bottom,
        ),
        child: SizedBox(
          height: CommentListTheme.fieldHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  key: const ValueKey('comment-field'),
                  button: true,
                  label: placeholder,
                  onTap: () => onWrite(false),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onWrite(false),
                    child: DecoratedBox(
                      decoration: const ShapeDecoration(color: CommentListTheme.fieldFill, shape: StadiumBorder()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: CommentListTheme.fieldPadding),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            placeholder,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: BiliFonts.family,
                              fontSize: CommentListTheme.fieldText,
                              color: CommentListTheme.fieldInk,
                              letterSpacing: CommentListTheme.fieldSpacing,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                key: const ValueKey('comment-emotes'),
                button: true,
                label: '表情',
                onTap: () => onWrite(true),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onWrite(true),
                  child: const SizedBox(
                    width: CommentListTheme.faceBox,
                    child: Center(
                      child: CustomPaint(size: Size.square(CommentListTheme.face), painter: _EmoteFacePainter()),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 10's face: a ring, > < eyes and an ω mouth, traced at 3 px per pt as fractions of the 20 pt face.
class _EmoteFacePainter extends CustomPainter {
  const _EmoteFacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final centre = size.center(Offset.zero);
    Offset p(double x, double y) => centre + Offset(x * side, y * side);
    final paint = Paint()
      ..color = CommentListTheme.faceInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = CommentListTheme.faceStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawCircle(centre, side * 0.462, paint);
    final face = Path();
    for (final sign in const [-1.0, 1.0]) {
      final start = p(sign * 0.2385, -0.1085);
      final tip = p(sign * 0.115, -0.02);
      final end = p(sign * 0.2385, 0.0635);
      face
        ..moveTo(start.dx, start.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(end.dx, end.dy);
    }
    final left = p(-0.1285, 0.1565);
    final leftBend = p(-0.0528, 0.272);
    final middle = p(0, 0.1735);
    final rightBend = p(0.0528, 0.272);
    final right = p(0.1285, 0.1565);
    face
      ..moveTo(left.dx, left.dy)
      ..quadraticBezierTo(leftBend.dx, leftBend.dy, middle.dx, middle.dy)
      ..quadraticBezierTo(rightBend.dx, rightBend.dy, right.dx, right.dy);
    canvas.drawPath(face, paint);
  }

  @override
  bool shouldRepaint(_EmoteFacePainter oldDelegate) => false;
}

/// 评论 before the video's aid is known: the spinner where the list will start.
class CommentsSlot extends StatelessWidget {
  const CommentsSlot({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: CommentListTheme.background,
    child: CustomScrollView(
      primary: true,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: PlayerReserve.of(context))),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: CommentListTheme.emptyPadding),
            child: CupertinoActivityIndicator(
              key: ValueKey('comments-slot-loading'),
              radius: CommentListTheme.spinnerRadius,
            ),
          ),
        ),
      ],
    ),
  );
}
