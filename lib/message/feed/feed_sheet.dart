import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import 'feed_parts.dart';

/// The row a ⋮ sheet is up for: its list, its id, and whether 不再通知 is offered.
@immutable
final class FeedSheetTarget {
  const FeedSheetTarget({required this.feed, required this.id, this.canMute = true});

  final NoticeFeed feed;
  final int id;
  final bool canMute;
}

/// A row's ⋮ sheet (214), in the page's Stack over everything: the dim fades in as the sheet rises from the bottom; a
/// tap on the dim puts it away.
class FeedSheetLayer extends StatefulWidget {
  const FeedSheetLayer({super.key, required this.open, required this.onMute, required this.onDelete});

  final ValueNotifier<FeedSheetTarget?> open;
  final ValueChanged<FeedSheetTarget> onMute;
  final ValueChanged<FeedSheetTarget> onDelete;

  @override
  State<FeedSheetLayer> createState() => _FeedSheetLayerState();
}

class _FeedSheetLayerState extends State<FeedSheetLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: MessageFeedTheme.sheetIn,
    reverseDuration: MessageFeedTheme.sheetOut,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 1), end: Offset.zero).animate(_curve);

  /// The sheet on screen: the open one, or the last while it goes away.
  FeedSheetTarget? _shown;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_changed);
    _motion.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && widget.open.value == null && mounted) setState(() => _shown = null);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _motion
      ..duration = still ? Duration.zero : MessageFeedTheme.sheetIn
      ..reverseDuration = still ? Duration.zero : MessageFeedTheme.sheetOut;
  }

  @override
  void didUpdateWidget(FeedSheetLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.open, widget.open)) {
      oldWidget.open.removeListener(_changed);
      widget.open.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.open.removeListener(_changed);
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _changed() {
    final target = widget.open.value;
    if (target == null) {
      if (_shown != null) unawaited(_motion.reverse());
      return;
    }
    setState(() => _shown = target);
    unawaited(_motion.forward());
  }

  void _close() => widget.open.value = null;

  void _act(FeedSheetTarget target, ValueChanged<FeedSheetTarget> action) {
    _close();
    action(target);
  }

  @override
  Widget build(BuildContext context) {
    final target = _shown;
    if (target == null) return const SizedBox.shrink();
    final open = widget.open.value != null;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return IgnorePointer(
      ignoring: !open,
      child: ExcludeSemantics(
        excluding: !open,
        child: BlockSemantics(
          blocking: open,
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: '取消',
                  onTap: _close,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('feed-sheet-dim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: FadeTransition(
                      opacity: _curve,
                      child: const ColoredBox(color: MessageFeedTheme.sheetDim),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SlideTransition(
                  position: _slide,
                  child: DecoratedBox(
                    key: const ValueKey('feed-sheet'),
                    decoration: BoxDecoration(
                      color: MessageFeedTheme.sheetFill,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(MessageFeedTheme.sheetRadius)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: MessageFeedTheme.cardBottom + bottom),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: MessageFeedTheme.grabberTop),
                          SizedBox(
                            width: MessageFeedTheme.grabberWidth,
                            height: MessageFeedTheme.grabberHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: MessageFeedTheme.grabberInk,
                                borderRadius: const BorderRadius.all(Radius.circular(MessageFeedTheme.grabberHeight / 2)),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height:
                                MessageFeedTheme.cardTop - MessageFeedTheme.grabberTop - MessageFeedTheme.grabberHeight,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: MessageFeedTheme.cardInset),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(MessageFeedTheme.cardRadius),
                              child: ColoredBox(
                                color: MessageFeedTheme.cardFill,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (target.canMute) ...[
                                      // The rule under it is part of its 52.
                                      _SheetRow(
                                        key: const ValueKey('feed-sheet-mute'),
                                        label: '不再通知',
                                        height: MessageFeedTheme.sheetRow - MessageFeedTheme.sheetRule,
                                        glyph: const SizedBox(
                                          width: MessageFeedTheme.bellWidth,
                                          height: MessageFeedTheme.bellHeight,
                                          child: CustomPaint(painter: FeedBellOffPainter()),
                                        ),
                                        onTap: () => _act(target, widget.onMute),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(left: MessageFeedTheme.sheetTextLeft),
                                        child: SizedBox(
                                          height: MessageFeedTheme.sheetRule,
                                          width: double.infinity,
                                          child: ColoredBox(color: MessageFeedTheme.sheetRuleInk),
                                        ),
                                      ),
                                    ],
                                    _SheetRow(
                                      key: const ValueKey('feed-sheet-delete'),
                                      label: '删除',
                                      glyph: Image.asset(
                                        'assets/images/message/feed_delete.png',
                                        width: MessageFeedTheme.deleteGlyph,
                                        height: MessageFeedTheme.deleteGlyph,
                                        color: MessageFeedTheme.sheetInk,
                                      ),
                                      onTap: () => _act(target, widget.onDelete),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    super.key,
    required this.label,
    required this.glyph,
    required this.onTap,
    this.height = MessageFeedTheme.sheetRow,
  });

  final String label;
  final Widget glyph;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = feedStyle(MessageFeedTheme.sheetText, MessageFeedTheme.sheetInk, line: MessageFeedTheme.sheetLine);
    return FeedTap(
      label: label,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: MessageFeedTheme.sheetGlyphCentre - MessageFeedTheme.sheetTextLeft / 2,
              width: MessageFeedTheme.sheetTextLeft,
              top: 0,
              bottom: 0,
              child: Center(child: glyph),
            ),
            Positioned(
              left: MessageFeedTheme.sheetTextLeft,
              right: 0,
              top: 0,
              bottom: 0,
              child: Align(alignment: Alignment.centerLeft, child: feedLine(label, style)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 不再通知's bell with a stroke through it (214): the bell's outline, its clapper under the rim, and the slash from
/// bottom-left to top-right, cut clear of the bell by the card's white.
class FeedBellOffPainter extends CustomPainter {
  const FeedBellOffPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const stroke = MessageFeedTheme.bellStroke;
    final ink = Paint()
      ..color = MessageFeedTheme.sheetInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rim = h * 0.8;
    final bell = Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.5, h * 0.1)
      ..moveTo(w * 0.12, rim)
      ..lineTo(w * 0.12, h * 0.42)
      ..cubicTo(w * 0.12, h * 0.2, w * 0.3, h * 0.1, w * 0.5, h * 0.1)
      ..cubicTo(w * 0.7, h * 0.1, w * 0.88, h * 0.2, w * 0.88, h * 0.42)
      ..lineTo(w * 0.88, rim)
      ..moveTo(w * 0.04, rim)
      ..lineTo(w * 0.96, rim)
      ..moveTo(w * 0.36, rim)
      ..arcToPoint(Offset(w * 0.64, rim), radius: Radius.circular(w * 0.14), clockwise: false);
    canvas.drawPath(bell, ink);
    final from = Offset(w * 0.04, h * 0.96);
    final to = Offset(w * 0.96, h * 0.1);
    canvas
      ..drawLine(
        from,
        to,
        Paint()
          ..color = MessageFeedTheme.cardFill
          ..strokeWidth = stroke * 3
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(from, to, ink);
  }

  @override
  bool shouldRepaint(FeedBellOffPainter oldDelegate) => false;
}
