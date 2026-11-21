import 'dart:math' as math;

import 'package:bili_core/logic.dart' show CountFormat;
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../collapsing_player.dart' show PlayerReserve;
import '../page_details.dart' show PageTab;
import 'story_sheet.dart';

/// 竖屏's 简介/评论 sheet, placed over the whole page and drawn from [controller]'s position: the grabber, the tab
/// row with 评论's count and the expand / collapse button, then [intro] or [comments].
///
/// The header strip drags the sheet both ways. A tab's list, pulled down at its top, hands the drag to the sheet,
/// which follows the finger and snaps on release; pushed up, the list only scrolls. Each tab scrolls with its own
/// primary scroll controller under a [PlayerReserve] of its own. Once opened the sheet stays built, offstage while
/// closed, so the tabs keep their places.
class StorySheetView extends StatefulWidget {
  const StorySheetView({
    super.key,
    required this.controller,
    required this.intro,
    required this.comments,
    required this.replies,
  });

  final StorySheetController controller;
  final Widget intro;
  final Widget comments;

  /// 评论's count beside its tab; null until known.
  final ValueListenable<int?> replies;

  @override
  State<StorySheetView> createState() => _StorySheetViewState();
}

class _StorySheetViewState extends State<StorySheetView> {
  final _introScroll = ScrollController();
  final _commentsScroll = ScrollController();
  final _pull = _ListPull();
  late ScrollBehavior _lists;
  double _height = 0;
  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final behavior = ScrollConfiguration.of(context);
    // No glow or stretch either: a pull at the top is the sheet's.
    _lists = behavior.copyWith(
      physics: _SheetListPhysics(pull: _pull, parent: behavior.getScrollPhysics(context)),
      overscroll: false,
    );
  }

  @override
  void dispose() {
    _introScroll.dispose();
    _commentsScroll.dispose();
    super.dispose();
  }

  StorySheetController get _controller => widget.controller;

  /// A list's drag: once it pulls down from the list's top, the sheet follows, and the list holds still until the
  /// sheet is back where the drag found it.
  bool _scrolled(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
    final controller = _controller;
    switch (notification) {
      case OverscrollNotification(:final overscroll, dragDetails: _?):
        if (!_pull.holding) {
          if (overscroll >= 0) break;
          if (!_pull.pulled) {
            _pull.pulled = true;
            controller.dragStart(raises: false);
            _pull.from = controller.stop.index.toDouble();
          }
          _pull.holding = true;
        }
        controller.dragUpdate(-overscroll, _height);
        if (controller.position.value >= _pull.from) _pull.holding = false;
      case ScrollEndNotification(:final dragDetails):
        if (_pull.pulled) controller.dragEnd(dragDetails?.primaryVelocity ?? 0, _height);
        _pull
          ..pulled = false
          ..holding = false;
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    controller.still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        _height = height;
        controller.screenHeight = height;
        return ListenableBuilder(
          listenable: Listenable.merge([controller, controller.position]),
          builder: (context, card) {
            final position = controller.position.value;
            final shown = position > 0 || controller.isOpen;
            if (!shown && !_built) return const SizedBox.shrink();
            _built = true;
            final top = StorySheetController.topFor(position, height);
            return Stack(
              children: [
                Positioned(
                  key: const ValueKey('story-sheet'),
                  left: 0,
                  right: 0,
                  top: top,
                  // Above half the sheet reaches the screen's bottom; below it keeps half's height and slides away,
                  // the 发条评论 bar with it (268).
                  height: height - math.min(top, StorySheetTheme.halfTop),
                  child: Offstage(
                    offstage: !shown,
                    child: TickerMode(enabled: shown, child: card!),
                  ),
                ),
              ],
            );
          },
          child: _card(context),
        );
      },
    );
  }

  Widget _card(BuildContext context) => Listener(
    // Touches on the card stay off the page under it.
    behavior: HitTestBehavior.opaque,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: StorySheetTheme.fill,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(StorySheetTheme.radius)),
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final controller = _controller;
          final full = controller.stop == SheetStop.full;
          return Semantics(
            key: const ValueKey('story-sheet-card'),
            container: true,
            explicitChildNodes: true,
            customSemanticsActions: {
              if (full)
                const CustomSemanticsAction(label: '收起'): controller.collapse
              else
                const CustomSemanticsAction(label: '展开'): controller.expand,
              const CustomSemanticsAction(label: '关闭'): controller.close,
            },
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: StorySheetTheme.headerHeight,
                  bottom: 0,
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _body(PageTab.intro, _introScroll, 0, widget.intro),
                        _body(PageTab.comments, _commentsScroll, StorySheetTheme.commentsGap, widget.comments),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: StorySheetTheme.headerHeight,
                  child: _SheetHeader(
                    controller: controller,
                    replies: widget.replies,
                    onDragStart: controller.dragStart,
                    onDrag: (delta) => controller.dragUpdate(delta, _height),
                    onDragEnd: (velocity) => controller.dragEnd(velocity, _height),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  /// A tab's content, kept built beside the other: out of sight it stops its tickers, so 评论 asks for its first page
  /// only once it shows.
  Widget _body(PageTab tab, ScrollController scroll, double reserve, Widget child) {
    final shown = _controller.tab == tab;
    return Offstage(
      key: ValueKey('story-sheet-${tab.name}'),
      offstage: !shown,
      child: TickerMode(
        enabled: shown,
        // Every platform, so a list that doesn't say `primary` takes it on Windows as it does on the phone.
        child: PrimaryScrollController(
          controller: scroll,
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: PlayerReserve(
            height: reserve,
            child: ScrollConfiguration(
              behavior: _lists,
              child: NotificationListener<ScrollNotification>(onNotification: _scrolled, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a list's drag stands with the sheet.
class _ListPull {
  /// The drag has moved the sheet: its end lets the sheet go.
  bool pulled = false;

  /// The sheet is below where the drag found it, so the list holds still and every move is the sheet's.
  bool holding = false;

  /// The stop the drag found the sheet at, as a position.
  double from = 0;
}

/// The tab lists' physics: a vertical list never bounces at its top, so a pull there reaches the sheet as overscroll,
/// it holds still while the sheet follows the finger, and it doesn't fling after a drag that moved the sheet. Always
/// scrollable, so a short list still hands its pulls over. The rest is the platform's.
class _SheetListPhysics extends ScrollPhysics {
  const _SheetListPhysics({required this.pull, super.parent});

  final _ListPull pull;

  @override
  _SheetListPhysics applyTo(ScrollPhysics? ancestor) => _SheetListPhysics(pull: pull, parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      position.axis == Axis.vertical || super.shouldAcceptUserOffset(position);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position.axis != Axis.vertical) return super.applyBoundaryConditions(position, value);
    if (pull.holding) return value - position.pixels;
    if (value < position.pixels && position.pixels <= position.minScrollExtent) return value - position.pixels;
    if (value < position.minScrollExtent && position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (position.axis == Axis.vertical && pull.pulled) return null;
    return super.createBallisticSimulation(position, velocity);
  }
}

/// The strip over the tabs (264, 266): the grabber, 简介 and 评论 (N) with the pink bar under the chosen one, and the
/// round expand / collapse button. A vertical drag anywhere on it moves the sheet.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.controller,
    required this.replies,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
  });

  final StorySheetController controller;
  final ValueListenable<int?> replies;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final full = controller.stop == SheetStop.full;
    return GestureDetector(
      key: const ValueKey('story-sheet-header'),
      behavior: HitTestBehavior.opaque,
      // The sheet's own 展开, 收起 and 关闭 serve VoiceOver; a drag's scroll actions would move nothing.
      excludeFromSemantics: true,
      onVerticalDragStart: (_) => onDragStart(),
      onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
      onVerticalDragEnd: (details) => onDragEnd(details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => onDragEnd(0),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: StorySheetTheme.grabberBoxHeight,
            // A finger here drags; VoiceOver and the test driver close the sheet through it.
            child: Semantics(
              key: const ValueKey('story-sheet-close'),
              button: true,
              label: '关闭',
              onTap: controller.close,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: StorySheetTheme.grabberTop),
                  child: Container(
                    width: StorySheetTheme.grabberWidth,
                    height: StorySheetTheme.grabberHeight,
                    decoration: BoxDecoration(
                      color: StorySheetTheme.grabber,
                      borderRadius: BorderRadius.circular(StorySheetTheme.grabberHeight / 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: StorySheetTheme.introLeft - StorySheetTheme.tabTouchPad,
            top: StorySheetTheme.grabberBoxHeight,
            bottom: 0,
            child: _SheetTab(
              key: const ValueKey('story-sheet-tab-intro'),
              label: '简介',
              count: null,
              chosen: controller.tab == PageTab.intro,
              onTap: () => controller.selectTab(PageTab.intro),
            ),
          ),
          Positioned(
            left: StorySheetTheme.commentsLeft - StorySheetTheme.tabTouchPad,
            top: StorySheetTheme.grabberBoxHeight,
            bottom: 0,
            child: ValueListenableBuilder<int?>(
              valueListenable: replies,
              builder: (context, count, _) => _SheetTab(
                key: const ValueKey('story-sheet-tab-comments'),
                label: '评论',
                count: count == null ? null : CountFormat.short(count),
                chosen: controller.tab == PageTab.comments,
                onTap: () => controller.selectTab(PageTab.comments),
              ),
            ),
          ),
          Positioned(
            right: StorySheetTheme.buttonRight - (StorySheetTheme.buttonTouch - StorySheetTheme.button) / 2,
            top: StorySheetTheme.buttonCentre - StorySheetTheme.buttonTouch / 2,
            width: StorySheetTheme.buttonTouch,
            height: StorySheetTheme.buttonTouch,
            child: Semantics(
              key: const ValueKey('story-sheet-button'),
              button: true,
              label: full ? '收起' : '展开',
              onTap: controller.toggle,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.toggle,
                child: Center(
                  child: Container(
                    width: StorySheetTheme.button,
                    height: StorySheetTheme.button,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(color: StorySheetTheme.buttonFill, shape: const CircleBorder()),
                    child: Image.asset(
                      full ? StorySheetTheme.collapseAsset : StorySheetTheme.expandAsset,
                      width: full ? StorySheetTheme.collapseWidth : StorySheetTheme.expandWidth,
                      fit: BoxFit.contain,
                      color: StorySheetTheme.buttonInk,
                      colorBlendMode: BlendMode.srcIn,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
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

/// One tab: its words, 评论's count after them, and the pink bar centred under both while chosen.
class _SheetTab extends StatelessWidget {
  const _SheetTab({super.key, required this.label, required this.count, required this.chosen, required this.onTap});

  final String label;
  final String? count;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    final labelStyle = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: StorySheetTheme.tabText,
      fontWeight: StorySheetTheme.tabWeight,
      color: chosen ? StorySheetTheme.tabChosen : StorySheetTheme.tabOther,
      letterSpacing: 0,
    );
    final countStyle = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: StorySheetTheme.countText,
      color: StorySheetTheme.countInk,
      letterSpacing: 0,
    );
    return Semantics(
      button: true,
      selected: chosen,
      label: count == null ? label : '$label $count',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: StorySheetTheme.tabTouchPad),
              child: Baseline(
                baseline: StorySheetTheme.tabBaseline - StorySheetTheme.grabberBoxHeight,
                baselineType: TextBaseline.alphabetic,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(label, maxLines: 1, softWrap: false, style: labelStyle),
                    if (count != null) ...[
                      const SizedBox(width: StorySheetTheme.countGap),
                      Text('($count)', key: const ValueKey('story-sheet-count'), maxLines: 1, style: countStyle),
                    ],
                  ],
                ),
              ),
            ),
            if (chosen)
              Positioned(
                left: 0,
                right: 0,
                top: StorySheetTheme.underlineTop - StorySheetTheme.grabberBoxHeight,
                height: StorySheetTheme.underlineHeight,
                child: Center(
                  child: Container(
                    key: const ValueKey('story-sheet-underline'),
                    width: StorySheetTheme.underlineWidth,
                    decoration: BoxDecoration(
                      color: StorySheetTheme.underline,
                      borderRadius: BorderRadius.circular(StorySheetTheme.underlineHeight / 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
