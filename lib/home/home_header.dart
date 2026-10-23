import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../search/search_glyphs.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../skin/skin.dart';
import 'tab_bar_icons.dart' show SkinDecodeGate;

/// 首页's top (01, 110): the avatar and the search entry over the 推荐 tab, on white or the 装扮's pictures, and the
/// hairline under it. Once [feedOffset], how far 推荐 is scrolled, passes [HomeHeaderTheme.trigger], it folds the top
/// row away (121): everything moves up under the status bar, the top row fading out and a magnifier riding in at
/// the tab row's end, which opens 搜索 in its place. Back under the trigger it opens again.
class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.skin,
    required this.face,
    required this.searchWord,
    required this.feedOffset,
    required this.onAvatar,
    required this.onSearch,
  });

  /// A skin with a `head_bg`, its pictures decoded, or null.
  final Skin? skin;
  final String? face;
  final String? searchWord;
  final ValueListenable<double> feedOffset;
  final VoidCallback onAvatar;
  final VoidCallback onSearch;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader>
    with SingleTickerProviderStateMixin {
  late bool _folded = _shouldFold;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: HomeHeaderTheme.duration,
    value: _folded ? 1 : 0,
  )..addStatusListener(_statusChanged);
  late final CurvedAnimation _fold = CurvedAnimation(
    parent: _controller,
    curve: HomeHeaderTheme.curve,
  );
  late final Animation<double> _shown = ReverseAnimation(_fold);
  bool _still = false;

  bool get _shouldFold => widget.feedOffset.value >= HomeHeaderTheme.trigger;

  @override
  void initState() {
    super.initState();
    widget.feedOffset.addListener(_offsetChanged);
  }

  @override
  void didUpdateWidget(HomeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.feedOffset, widget.feedOffset)) {
      oldWidget.feedOffset.removeListener(_offsetChanged);
      widget.feedOffset.addListener(_offsetChanged);
      _offsetChanged();
    }
  }

  @override
  void dispose() {
    widget.feedOffset.removeListener(_offsetChanged);
    _fold.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _offsetChanged() {
    final fold = _shouldFold;
    if (fold == _folded) return;
    // The feed's notifications can come mid-layout, and the fold itself resizes the feed.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _offsetChanged();
      });
      return;
    }
    setState(() => _folded = fold);
    if (_still) {
      _controller.value = fold ? 1 : 0;
    } else if (fold) {
      unawaited(_controller.forward());
    } else {
      unawaited(_controller.reverse());
    }
  }

  /// The magnifier is built only while the header is folded or folding.
  void _statusChanged(AnimationStatus status) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.disableAnimationsOf(context);
    final head = widget.skin;
    final colour = head?.color;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Head(
          skin: head,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                FadeTransition(
                  opacity: _shown,
                  child: IgnorePointer(
                    ignoring: _folded,
                    child: ExcludeSemantics(
                      excluding: _folded,
                      child: _TopRow(
                        face: widget.face,
                        searchWord: widget.searchWord,
                        filled: head != null,
                        onAvatar: widget.onAvatar,
                        onSearch: widget.onSearch,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      _RecommendTab(colour: colour ?? BiliColors.pink),
                      if (!_controller.isDismissed)
                        Positioned(
                          top: 0,
                          right: 0,
                          bottom: 0,
                          child: _TabSearch(
                            fold: _fold,
                            enabled: _folded,
                            colour:
                                colour?.withValues(
                                  alpha: HomeHeaderTheme.skinSearchOpacity,
                                ) ??
                                HomeHeaderTheme.searchInk,
                            onTap: widget.onSearch,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: HomeTabBarTheme.hairlineWidth,
          thickness: HomeTabBarTheme.hairlineWidth,
          color: head != null
              ? HomeTabBarTheme.headDivider
              : BiliColors.divider,
        ),
      ],
    );
    return AnimatedBuilder(
      animation: _fold,
      builder: (context, child) =>
          _Fold(by: HomeHeaderTheme.fold * _fold.value, child: child),
      child: content,
    );
  }
}

/// The tab row's magnifier (121), riding in from the right as the header folds; it takes taps only while folded.
class _TabSearch extends StatelessWidget {
  const _TabSearch({
    required this.fold,
    required this.enabled,
    required this.colour,
    required this.onTap,
  });

  final Animation<double> fold;
  final bool enabled;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const lead =
        HomeHeaderTheme.searchTarget -
        HomeHeaderTheme.searchSize -
        HomeHeaderTheme.searchRight;
    return AnimatedBuilder(
      animation: fold,
      builder: (context, child) => Transform.translate(
        offset: Offset(HomeHeaderTheme.searchSlide * (1 - fold.value), 0),
        child: child,
      ),
      child: IgnorePointer(
        ignoring: !enabled,
        child: ExcludeSemantics(
          excluding: !enabled,
          child: Semantics(
            button: true,
            label: '搜索',
            child: GestureDetector(
              key: const ValueKey('home-header-search'),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: SizedBox(
                width: HomeHeaderTheme.searchTarget,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: lead,
                      top: HomeHeaderTheme.searchTop,
                    ),
                    child: SearchGlyphIcon(
                      SearchGlyph.magnifier,
                      size: HomeHeaderTheme.searchSize,
                      color: colour,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Its child [by] pt shorter: laid out whole, drawn moved up by [by] and cut at its own top, so what is below
/// follows the child's bottom.
class _Fold extends SingleChildRenderObjectWidget {
  const _Fold({required this.by, super.child});

  final double by;

  @override
  _RenderFold createRenderObject(BuildContext context) => _RenderFold(by);

  @override
  void updateRenderObject(BuildContext context, _RenderFold renderObject) =>
      renderObject.by = by;
}

class _RenderFold extends RenderShiftedBox {
  _RenderFold(this._by) : super(null);

  double _by;

  set by(double value) {
    if (value == _by) return;
    _by = value;
    markNeedsLayout();
  }

  final _clip = LayerHandle<ClipRectLayer>();

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width) - _by, 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width) - _by, 0);

  Size _sizeFor(BoxConstraints constraints, Size child) =>
      constraints.constrain(Size(child.width, math.max(child.height - _by, 0)));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _sizeFor(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = _sizeFor(constraints, child.size);
    (child.parentData! as BoxParentData).offset = Offset(
      0,
      size.height - child.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      size.contains(position) &&
      super.hitTestChildren(result, position: position);

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

/// The account's avatar; a grey head until the account has a face.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.face, required this.size});

  final String? face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = face;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url != null && url.isNotEmpty
            ? RemoteImage.avatar(url)
            : ColoredBox(
                color: BiliColors.pageGrey,
                child: Icon(
                  Icons.person,
                  size: size * 0.55,
                  color: BiliColors.divider,
                ),
              ),
      ),
    );
  }
}

/// The status bar, the top row and the tab row on white (01), or over the 装扮's pictures (110): [skin]'s `head_bg`
/// down to the top row's bottom and `head_tab_bg` behind the tab row, or `head_bg` behind all of it when the package
/// has no tab picture. Both are cropped to their boxes about the centre.
class _Head extends StatelessWidget {
  const _Head({required this.skin, required this.child});

  /// A skin with a `head_bg`, its pictures decoded, or null.
  final Skin? skin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final head = skin?.headBg;
    if (head == null) return ColoredBox(color: BiliColors.card, child: child);
    final tab = skin?.headTabBg;
    final rowBottom =
        MediaQuery.paddingOf(context).top + BiliMetrics.topRowHeight;
    return Stack(
      children: [
        Positioned(
          key: const ValueKey('home-head-art'),
          top: 0,
          left: 0,
          right: 0,
          height: tab == null ? null : rowBottom,
          bottom: tab == null ? 0 : null,
          child: _picture(head),
        ),
        if (tab != null)
          Positioned(
            key: const ValueKey('home-head-tab-art'),
            top: rowBottom,
            left: 0,
            right: 0,
            bottom: 0,
            child: _picture(tab),
          ),
        child,
      ],
    );
  }

  static Widget _picture(File file) => SkinDecodeGate.image(file);
}

/// The avatar and the search entry (01): a rounded bar with the magnifier and the default word, which opens 搜索.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.face,
    required this.searchWord,
    required this.filled,
    required this.onAvatar,
    required this.onSearch,
  });

  final String? face;
  final String? searchWord;

  /// The entry filled white without its rim, over the 装扮's picture (110).
  final bool filled;
  final VoidCallback onAvatar;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BiliMetrics.topRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BiliMetrics.topRowMargin,
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: '账号',
              child: GestureDetector(
                key: const ValueKey('home-avatar'),
                onTap: onAvatar,
                child: _AccountAvatar(face: face, size: BiliMetrics.homeAvatar),
              ),
            ),
            const SizedBox(width: HomeTabBarTheme.fieldGap),
            _SearchField(word: searchWord, filled: filled, onTap: onSearch),
          ],
        ),
      ),
    );
  }
}

/// The search entry: the magnifier and the grey word in a stadium, greyed while pressed.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.word,
    required this.filled,
    required this.onTap,
  });

  final String? word;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    const word = TextStyle(
      fontSize: HomeTabBarTheme.fieldText,
      color: HomeTabBarTheme.fieldInk,
    );
    const glyphLead =
        HomeTabBarTheme.fieldGlyphCentre - HomeTabBarTheme.fieldGlyph / 2;
    return Semantics(
      button: true,
      label: '搜索',
      value: widget.word,
      child: GestureDetector(
        key: const ValueKey('home-search'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: ExcludeSemantics(
          // The rim is drawn over the contents: as the decoration, its width would inset them (01 measures from the
          // rim's outer edge).
          child: Container(
            key: const ValueKey('home-search-field'),
            width: HomeTabBarTheme.fieldWidth,
            height: BiliMetrics.linkFieldHeight,
            decoration: widget.filled
                ? const ShapeDecoration(
                    color: HomeTabBarTheme.headField,
                    shape: StadiumBorder(),
                  )
                : null,
            foregroundDecoration: ShapeDecoration(
              color: _pressed ? BiliColors.pressedFill : null,
              shape: widget.filled
                  ? const StadiumBorder()
                  : const StadiumBorder(
                      side: BorderSide(
                        color: HomeTabBarTheme.fieldOutline,
                        width: HomeTabBarTheme.fieldOutlineWidth,
                      ),
                    ),
            ),
            child: Row(
              children: [
                const SizedBox(width: glyphLead),
                Transform.translate(
                  offset: const Offset(0, -HomeTabBarTheme.fieldGlyphRise),
                  child: const SearchGlyphIcon(
                    SearchGlyph.magnifier,
                    size: HomeTabBarTheme.fieldGlyph,
                    color: HomeTabBarTheme.fieldInk,
                  ),
                ),
                const SizedBox(
                  width:
                      HomeTabBarTheme.fieldTextStart -
                      glyphLead -
                      HomeTabBarTheme.fieldGlyph,
                ),
                Expanded(
                  child: Text(
                    widget.word ?? '',
                    key: const ValueKey('home-search-word'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: word,
                    strutStyle: BiliFonts.strutOf(context, word),
                  ),
                ),
                const SizedBox(width: HomeTabBarTheme.fieldTextEnd),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 01's tab row, with only 推荐 and that one selected: pink, or the 装扮's colour over its picture (110).
class _RecommendTab extends StatelessWidget {
  const _RecommendTab({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    selected: true,
    child: Padding(
      padding: const EdgeInsets.only(
        top: BiliMetrics.tabRowTop,
        bottom: BiliMetrics.tabRowBottom,
      ),
      child: Column(
        children: [
          Text(
            '推荐',
            key: const ValueKey('home-tab-recommend'),
            style: TextStyle(
              fontSize: BiliMetrics.tabText,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
          const SizedBox(height: BiliMetrics.tabIndicatorGap),
          Container(
            key: const ValueKey('home-tab-indicator'),
            width: BiliMetrics.tabIndicatorWidth,
            height: BiliMetrics.tabIndicatorHeight,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    ),
  );
}
