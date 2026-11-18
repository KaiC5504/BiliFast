import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_rank_model.dart';
import 'rank_audience_page.dart';
import 'rank_guard_page.dart';
import 'rank_parts.dart';

/// 高能榜: 房间观众 and 大航海, a sheet from the bottom in portrait (230, 231), a panel on the right in full screen
/// (232, 233).
class LiveRankSheet extends StatefulWidget {
  const LiveRankSheet({super.key, required this.room, required this.overlays, required this.landscape});

  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  State<LiveRankSheet> createState() => _LiveRankSheetState();
}

class _LiveRankSheetState extends State<LiveRankSheet> with SingleTickerProviderStateMixin {
  late final LiveRankModel _model = LiveRankModel(room: widget.room)..open();
  final _pages = PageController();
  late final AnimationController _slide = AnimationController(vsync: this, duration: LiveRankTheme.slideIn);
  LiveGuardTab _guardTab = LiveGuardTab.weekly;

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_slide.isDismissed && !_slide.isAnimating) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _slide.value = 1;
      } else {
        _slide.forward();
      }
    }
  }

  @override
  void dispose() {
    _model
      ..removeListener(_changed)
      ..dispose();
    _pages.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _close() => widget.overlays.close();

  void _unavailable() => showToast(context, '暂未开放');

  void _showTab(int index) {
    if (!_pages.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(index, duration: LiveRankTheme.tabSwitch, curve: Curves.easeInOut);
    }
  }

  void _chooseGuardTab(LiveGuardTab tab) {
    if (tab == _guardTab) return;
    setState(() => _guardTab = tab);
    _model.show(tab);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = widget.landscape;
    final body = _body(context, media.padding.bottom);
    final curve = CurvedAnimation(parent: _slide, curve: Curves.easeOut);
    final outside = Semantics(
      button: true,
      label: '关闭高能榜',
      onTap: _close,
      excludeSemantics: true,
      child: GestureDetector(key: const ValueKey('rank-outside'), behavior: HitTestBehavior.opaque, onTap: _close),
    );
    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: outside),
          SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curve),
            child: SizedBox(width: LiveRankTheme.panelWidth, child: body),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: outside),
        SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curve),
          child: SizedBox(
            height: media.size.height * LiveRankTheme.sheetShare,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(LiveRankTheme.sheetRadius)),
              child: body,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, double bottomInset) {
    final environment = AppScope.of(context).environment;
    final loggedIn = widget.room.loggedIn();
    // Taps on the sheet stay on it, rather than reaching the room under it.
    return GestureDetector(
      key: const ValueKey('rank-sheet'),
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: AnimatedBuilder(
        animation: _pages,
        builder: (context, child) {
          final t = _pageValue().clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: LiveRankTheme.audiencePage)),
              Positioned.fill(
                child: Opacity(
                  opacity: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [LiveRankTheme.guardTop, LiveRankTheme.guardBottom],
                        stops: const [0, LiveRankTheme.guardBottomStop],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: LiveRankTheme.tabsHeight,
                child: _Tabs(t: t, guardTotal: _model.guardTotal, onTab: _showTab),
              ),
              Positioned(left: 0, right: 0, top: LiveRankTheme.tabsHeight, bottom: 0, child: child!),
            ],
          );
        },
        child: PageView(
          controller: _pages,
          children: [
            RankAudiencePage(
              feed: _model.audience,
              loggedIn: loggedIn,
              ownFace: environment.face ?? '',
              bottomInset: bottomInset,
              onUnavailable: _unavailable,
            ),
            RankGuardPage(model: _model, tab: _guardTab, onTab: _chooseGuardTab, onUnavailable: _unavailable),
          ],
        ),
      ),
    );
  }

  double _pageValue() {
    if (!_pages.hasClients || !_pages.position.hasContentDimensions) return 0;
    return _pages.page ?? 0;
  }
}

/// 房间观众 and 大航海 (N), the underline sliding and the colours turning with the pages: [t] 0 shows 房间观众, 1 大航海.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.t, required this.guardTotal, required this.onTab});

  final double t;
  final int? guardTotal;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final total = guardTotal;
    final audienceInk = Color.lerp(LiveRankTheme.audienceChosen, LiveRankTheme.guardOther, t)!;
    final guardInk = Color.lerp(LiveRankTheme.audienceOther, LiveRankTheme.guardChosen, t)!;
    final underline = Color.lerp(LiveRankTheme.audienceChosen, LiveRankTheme.guardChosen, t)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const left = LiveRankTheme.tabInset;
        final right = width - LiveRankTheme.tabInset;
        final middle = left + (right - left) * t;
        return Stack(
          children: [
            Positioned(
              left: 0,
              width: width / 2,
              top: 0,
              bottom: 0,
              child: _Tab(
                key: const ValueKey('rank-tab-audience'),
                label: '房间观众',
                centreX: left,
                ink: audienceInk,
                onTap: () => onTab(0),
              ),
            ),
            Positioned(
              left: width / 2,
              width: width / 2,
              top: 0,
              bottom: 0,
              child: _Tab(
                key: const ValueKey('rank-tab-guard'),
                label: total == null ? '大航海' : '大航海 ($total)',
                centreX: right - width / 2,
                ink: guardInk,
                onTap: () => onTab(1),
              ),
            ),
            Positioned(
              left: middle - LiveRankTheme.underlineWidth / 2,
              top: LiveRankTheme.underlineTop,
              width: LiveRankTheme.underlineWidth,
              height: LiveRankTheme.underlineHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: underline,
                  borderRadius: BorderRadius.circular(LiveRankTheme.underlineHeight / 2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({super.key, required this.label, required this.centreX, required this.ink, required this.onTap});

  final String label;

  /// The label's middle from the target's left edge.
  final double centreX;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RankTap(
    label: label,
    onTap: onTap,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: centreX - LiveRankTheme.tabInset,
          width: LiveRankTheme.tabInset * 2,
          top: 0,
          height: LiveRankTheme.tabCentre * 2,
          child: Center(child: RankText(label, rankStyle(LiveRankTheme.tabText, ink))),
        ),
      ],
    ),
  );
}
