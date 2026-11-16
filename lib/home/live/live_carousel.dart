import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../app/zoom_back_route.dart';
import '../../live/danmaku/live_danmaku_layer.dart';
import '../../live/live_api.dart';
import '../../live/live_entry.dart';
import '../../player_ui/landscape_chrome.dart' show DanmakuGlyph;
import '../../player_ui/player_loading.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../feed_big_card.dart' show FeedBigCardView;
import '../feed_inline_player.dart';
import 'live_cards.dart';
import 'live_inline_player.dart';

/// The carousel at 直播's top (205, 225): the big rooms side by side, the one in the middle whole and its neighbours
/// peeking smaller at both sides, swiped round and round. The middle card plays its stream muted while [host] picks it,
/// with 弹 and the speaker as 推荐's big card's. A tap opens the room, shrinking back into the card on leaving.
class LiveCarousel extends StatefulWidget {
  const LiveCarousel({
    super.key,
    required this.cards,
    required this.host,
    required this.api,
    required this.loggedIn,
    required this.scrolling,
    required this.onOpen,
  });

  final List<LiveBigCard> cards;
  final FeedInlineHost host;
  final LiveApi api;
  final bool Function() loggedIn;

  /// The page's list, which the host waits on to rest before a card starts.
  final ValueListenable<bool>? Function() scrolling;
  final void Function(LiveCard card, ZoomSource source) onOpen;

  /// The card [screen] wide gets.
  static double cardWidth(double screen) => screen - LiveTabTheme.carouselSide * 2;

  static double height(double screen) => cardWidth(screen) * 9 / 16 + LiveTabTheme.carouselBand;

  @override
  State<LiveCarousel> createState() => _LiveCarouselState();
}

class _LiveCarouselState extends State<LiveCarousel> {
  /// Laps of the list either side of the start: enough that nobody swipes to an end.
  static const _laps = 500;

  PageController? _pages;
  double? _width;
  int _centred = 0;

  bool get _loops => widget.cards.length > 1;

  @override
  void didUpdateWidget(LiveCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refresh's cards start again from the first.
    if (!identical(oldWidget.cards, widget.cards)) _width = null;
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// A new controller, and with it a new PageView; the old one goes once that has replaced it.
  PageController _controllerFor(double screen) {
    final existing = _pages;
    if (existing != null && _width == screen) return existing;
    if (existing != null) {
      existing.removeListener(_moved);
      WidgetsBinding.instance.addPostFrameCallback((_) => existing.dispose());
    }
    final card = LiveCarousel.cardWidth(screen);
    final pitch = card * (1 + LiveTabTheme.neighbourScale) / 2 + LiveTabTheme.carouselGap;
    final start = _loops ? widget.cards.length * _laps : 0;
    _width = screen;
    _centred = start;
    return _pages = PageController(viewportFraction: pitch / screen, initialPage: start)..addListener(_moved);
  }

  void _moved() {
    final pages = _pages;
    if (pages == null || !pages.hasClients || !pages.position.hasContentDimensions) return;
    final centred = (pages.page ?? 0).round();
    if (centred != _centred) setState(() => _centred = centred);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    return LayoutBuilder(
      builder: (context, box) {
        final screen = box.maxWidth;
        final pages = _controllerFor(screen);
        final width = LiveCarousel.cardWidth(screen);
        return SizedBox(
          key: const ValueKey('live-carousel'),
          height: LiveCarousel.height(screen),
          child: PageView.builder(
            key: ObjectKey(pages),
            controller: pages,
            itemCount: _loops ? cards.length * _laps * 2 : cards.length,
            itemBuilder: (context, index) {
              final big = cards[index % cards.length];
              return AnimatedBuilder(
                animation: pages,
                builder: (context, child) {
                  final page = pages.hasClients && pages.position.hasContentDimensions
                      ? pages.page ?? index.toDouble()
                      : _centred.toDouble();
                  final away = math.min(1.0, (page - index).abs());
                  return Transform.scale(scale: 1 - (1 - LiveTabTheme.neighbourScale) * away, child: child);
                },
                child: OverflowBox(
                  minWidth: width,
                  maxWidth: width,
                  child: _CarouselCard(
                    key: ValueKey('live-big-$index'),
                    big: big,
                    centred: index == _centred,
                    host: widget.host,
                    api: widget.api,
                    loggedIn: widget.loggedIn,
                    scrolling: widget.scrolling,
                    onOpen: (source) => widget.onOpen(big.card, source),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CarouselCard extends StatefulWidget {
  const _CarouselCard({
    super.key,
    required this.big,
    required this.centred,
    required this.host,
    required this.api,
    required this.loggedIn,
    required this.scrolling,
    required this.onOpen,
  });

  final LiveBigCard big;
  final bool centred;
  final FeedInlineHost host;
  final LiveApi api;
  final bool Function() loggedIn;
  final ValueListenable<bool>? Function() scrolling;
  final void Function(ZoomSource source) onOpen;

  @override
  State<_CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<_CarouselCard> implements FeedInlineCard {
  final _videoKey = GlobalKey();
  AppServices? _services;
  LiveInlinePlayback? _inline;
  bool _registered = false;
  Widget? _view;
  Object? _viewOf;

  @override
  void initState() {
    super.initState();
    FeedInlineChoices.sound.addListener(_changed);
    FeedInlineChoices.danmaku.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= AppScope.of(context);
    _register();
  }

  @override
  void didUpdateWidget(_CarouselCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host) && _registered) {
      oldWidget.host.unregister(this);
      _registered = false;
    }
    _register();
  }

  /// Only the middle card is the host's: its neighbours sit level with it, and would tie for the most shown.
  void _register() {
    if (widget.centred && !_registered) {
      widget.host.register(this);
      _registered = true;
    } else if (!widget.centred && _registered) {
      widget.host.unregister(this);
      _registered = false;
      _inline?.release();
    }
  }

  @override
  void dispose() {
    if (_registered) widget.host.unregister(this);
    final inline = _inline;
    _inline = null;
    inline
      ?..removeListener(_changed)
      ..dispose();
    FeedInlineChoices.sound.removeListener(_changed);
    FeedInlineChoices.danmaku.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Rect? videoRect() {
    final box = _videoKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  ValueListenable<bool>? scrolling() => widget.scrolling();

  @override
  void inlinePlay() {
    if (!mounted || !widget.centred) return;
    (_inline ??= LiveInlinePlayback(
      services: _services!,
      api: widget.api,
      entry: LiveRoomEntry.fromCard(widget.big.card),
      loggedIn: widget.loggedIn,
    )..addListener(_changed)).play();
  }

  @override
  void inlinePause() => _inline?.pause();

  @override
  void inlineRelease() => _inline?.release();

  void _soon() => showToast(context, '暂未开放');

  @override
  Widget build(BuildContext context) {
    final big = widget.big;
    return ZoomSourceBox(
      builder: (context, source) => ClipRRect(
        borderRadius: BorderRadius.circular(LiveTabTheme.radius),
        child: ColoredBox(
          color: LiveTabTheme.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(key: _videoKey, aspectRatio: 16 / 9, child: _video(context, () => widget.onOpen(source))),
              SizedBox(
                height: LiveTabTheme.carouselBand,
                child: big.rankText.isNotEmpty ? _rankBand() : _titleBand(() => widget.onOpen(source)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _video(BuildContext context, VoidCallback open) {
    final big = widget.big;
    final card = big.card;
    final inline = _inline;
    final player = inline?.player;
    final playing = inline != null && inline.wanted && inline.shown && player != null;
    if (!identical(_viewOf, player)) {
      _viewOf = player;
      _view = player?.buildView();
    }
    final room = inline?.room;
    final ranked = big.rankText.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          button: true,
          label: card.title,
          onTap: open,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('live-big-open-${card.roomId}'),
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LiveCover(card: card),
                if (playing && _view != null)
                  ColoredBox(
                    key: const ValueKey('live-big-video'),
                    color: BiliColors.videoBackground,
                    child: KeyedSubtree(key: ValueKey(player), child: _view!),
                  ),
                if (playing && room != null)
                  IgnorePointer(
                    child: LiveDanmakuLayer(
                      key: const ValueKey('live-big-danmaku'),
                      room: room,
                      on: FeedInlineChoices.danmaku.value,
                    ),
                  ),
                // A ranked room's card shows its rank under the video instead of the anchor over it (225).
                if (!ranked) ...[
                  Positioned(
                    left: LiveTabTheme.faceLeft,
                    top: LiveTabTheme.faceTop,
                    right: LiveTabTheme.anchorRight,
                    height: LiveTabTheme.face,
                    child: _Anchor(card: card),
                  ),
                  const Positioned(right: LiveTabTheme.liveTagRight, top: LiveTabTheme.liveTagTop, child: _LiveTag()),
                ],
                if (inline != null && inline.loading)
                  const Center(key: ValueKey('live-big-loading'), child: PlayerLoading()),
              ],
            ),
          ),
        ),
        if (playing) ...[
          _Button(
            key: const ValueKey('live-big-danmaku-toggle'),
            right: LiveTabTheme.danmakuRight,
            label: FeedInlineChoices.danmaku.value ? '关闭弹幕' : '开启弹幕',
            onTap: () => FeedInlineChoices.danmaku.value = !FeedInlineChoices.danmaku.value,
            child: DanmakuGlyph(on: FeedInlineChoices.danmaku.value),
          ),
          _Button(
            key: const ValueKey('live-big-sound'),
            right: LiveTabTheme.speakerRight,
            label: FeedInlineChoices.sound.value ? '静音' : '开启声音',
            onTap: () => FeedInlineChoices.sound.value = !FeedInlineChoices.sound.value,
            child: Image.asset(
              FeedInlineChoices.sound.value ? FeedBigCardView.soundAsset : FeedBigCardView.mutedAsset,
              width: LiveTabTheme.speakerSize,
              height: LiveTabTheme.speakerSize,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ],
    );
  }

  /// The title and 更多直播 (205).
  Widget _titleBand(VoidCallback open) => Row(
    children: [
      const SizedBox(width: LiveTabTheme.bandInset),
      Expanded(
        child: Semantics(
          button: true,
          onTap: open,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Align(
              alignment: Alignment.centerLeft,
              child: liveLine(
                widget.big.card.title,
                liveStyle(LiveTabTheme.titleText, LiveTabTheme.text),
                key: ValueKey('live-big-title-${widget.big.card.roomId}'),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: LiveTabTheme.bandInset),
      _BandButton(key: const ValueKey('live-big-more'), label: '更多直播', onTap: _soon),
      const SizedBox(width: LiveTabTheme.bandInset),
    ],
  );

  /// 人气榜TOP·2, 2009助力值 and 查看榜单 (225).
  Widget _rankBand() => Row(
    children: [
      const SizedBox(width: LiveTabTheme.bandInset),
      Semantics(
        button: true,
        onTap: _soon,
        child: GestureDetector(
          key: const ValueKey('live-big-rank'),
          behavior: HitTestBehavior.opaque,
          onTap: _soon,
          child: _RankChip(text: widget.big.rankText),
        ),
      ),
      const SizedBox(width: LiveTabTheme.rankValueGap),
      Expanded(child: liveLine(widget.big.rankValue, liveStyle(LiveTabTheme.rankValueText, LiveTabTheme.secondary))),
      _BandButton(key: const ValueKey('live-big-board'), label: '查看榜单', onTap: _soon),
      const SizedBox(width: LiveTabTheme.bandInset),
    ],
  );
}

/// The face in its white ring and the name, over the video's top left.
class _Anchor extends StatelessWidget {
  const _Anchor({required this.card});

  final LiveCard card;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      children: [
        Container(
          width: LiveTabTheme.face,
          height: LiveTabTheme.face,
          padding: const EdgeInsets.all(LiveTabTheme.faceRing),
          decoration: const BoxDecoration(color: LiveTabTheme.faceRingInk, shape: BoxShape.circle),
          child: ClipOval(child: RemoteImage.avatar(card.face.isEmpty ? null : card.face)),
        ),
        const SizedBox(width: LiveTabTheme.nameGap),
        Flexible(child: liveLine(card.uname, liveStyle(LiveTabTheme.nameText, LiveTabTheme.onCover))),
      ],
    ),
  );
}

/// 直播中 with its bars.
class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('live-big-tag'),
    height: LiveTabTheme.liveTagHeight,
    decoration: BoxDecoration(
      color: LiveTabTheme.liveTagFill,
      borderRadius: BorderRadius.circular(LiveTabTheme.liveTagRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: LiveTabTheme.liveTagBarsLead),
        const LiveBars(),
        const SizedBox(width: LiveTabTheme.liveTagTextLead),
        liveLine('直播中', liveStyle(LiveTabTheme.liveTagText, LiveTabTheme.onCover)),
        const SizedBox(width: LiveTabTheme.liveTagTrail),
      ],
    ),
  );
}

/// 更多直播 or 查看榜单: pink words in a pink-rimmed stadium.
class _BandButton extends StatelessWidget {
  const _BandButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: LiveTabTheme.bandButtonWidth,
        height: LiveTabTheme.bandButtonHeight,
        alignment: Alignment.center,
        decoration: const ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(color: LiveTabTheme.bandButtonInk, width: LiveTabTheme.bandButtonRim),
          ),
        ),
        child: liveLine(label, liveStyle(LiveTabTheme.bandButtonText, LiveTabTheme.bandButtonInk)),
      ),
    ),
  );
}

/// The rank's chip: its words between laurels.
class _RankChip extends StatelessWidget {
  const _RankChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: LiveTabTheme.rankChipHeight,
    padding: const EdgeInsets.symmetric(horizontal: LiveTabTheme.rankChipPad / 2),
    decoration: BoxDecoration(
      color: LiveTabTheme.rankChipFill,
      border: Border.all(color: LiveTabTheme.rankChipRim, width: 1 / 3),
      borderRadius: BorderRadius.circular(LiveTabTheme.rankChipRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: LiveTabTheme.rankLeaf,
          height: LiveTabTheme.rankChipHeight / 2,
          child: CustomPaint(painter: _LaurelPainter(mirrored: false)),
        ),
        const SizedBox(width: 2),
        liveLine(text, liveStyle(LiveTabTheme.rankChipText, LiveTabTheme.rankChipInk, weight: FontWeight.w700)),
        const SizedBox(width: 2),
        const SizedBox(
          width: LiveTabTheme.rankLeaf,
          height: LiveTabTheme.rankChipHeight / 2,
          child: CustomPaint(painter: _LaurelPainter(mirrored: true)),
        ),
      ],
    ),
  );
}

/// Three leaves up a stem curving in towards the words.
class _LaurelPainter extends CustomPainter {
  const _LaurelPainter({required this.mirrored});

  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirrored) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final paint = Paint()..color = LiveTabTheme.rankChipInk;
    final leaf = Size(size.width * 0.55, size.height * 0.28);
    for (final (index, y) in [0.2, 0.5, 0.8].indexed) {
      final x = size.width * (0.75 - index * 0.2);
      canvas
        ..save()
        ..translate(x, size.height * y)
        ..rotate(-0.6)
        ..drawOval(Rect.fromCenter(center: Offset.zero, width: leaf.width, height: leaf.height), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_LaurelPainter oldDelegate) => oldDelegate.mirrored != mirrored;
}

/// 弹 or the speaker on the playing video, centred [right] from its right.
class _Button extends StatelessWidget {
  const _Button({super.key, required this.right, required this.label, required this.onTap, required this.child});

  final double right;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    right: right - LiveTabTheme.buttonTarget / 2,
    bottom: LiveTabTheme.buttonCentre - LiveTabTheme.buttonTarget / 2,
    width: LiveTabTheme.buttonTarget,
    height: LiveTabTheme.buttonTarget,
    child: Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(child: child),
      ),
    ),
  );
}
