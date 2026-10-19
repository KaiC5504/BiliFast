import 'dart:math' as math;

import 'package:bili_core/api.dart' hide RichText;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';

/// A comment's pictures over the whole page: swipe between them, pinch to zoom, tap to close.
class PictureViewer extends StatefulWidget {
  const PictureViewer({super.key, required this.pictures, required this.initialIndex, required this.onClose});

  final List<CommentPicture> pictures;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<PictureViewer> createState() => _PictureViewerState();
}

class _PictureViewerState extends State<PictureViewer> {
  late int _index = _start;
  late final _pages = PageController(initialPage: _index);

  /// A zoomed picture pans under the finger instead of paging.
  bool _zoomed = false;

  int get _start => widget.pictures.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.pictures.length - 1);

  @override
  void didUpdateWidget(PictureViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.pictures, widget.pictures) && oldWidget.initialIndex == widget.initialIndex) return;
    _index = _start;
    _zoomed = false;
    if (_pages.hasClients) _pages.jumpToPage(_index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pictures = widget.pictures;
    final top = MediaQuery.paddingOf(context).top;
    final still = MediaQuery.disableAnimationsOf(context);
    return BlockSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1 : 0, end: 1),
        duration: CommentTextTheme.viewerFadeIn,
        curve: Curves.easeOut,
        builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
        child: ColoredBox(
          color: CommentTextTheme.viewerBackground,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pages,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: pictures.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => _PicturePage(
                  key: ValueKey((index, pictures[index].url)),
                  picture: pictures[index],
                  label: '图片 ${index + 1}/${pictures.length}',
                  onClose: widget.onClose,
                  onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
                ),
              ),
              if (pictures.isEmpty)
                GestureDetector(behavior: HitTestBehavior.opaque, excludeFromSemantics: true, onTap: widget.onClose),
              if (pictures.length > 1)
                Positioned(
                  top: top + CommentTextTheme.viewerCountTop,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Text(
                        '${_index + 1}/${pictures.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: BiliFonts.family,
                          fontSize: CommentTextTheme.viewerCountText,
                          fontWeight: FontWeight.w500,
                          color: CommentTextTheme.viewerText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: top,
                left: 0,
                width: CommentTextTheme.viewerCloseTarget,
                height: CommentTextTheme.viewerCloseTarget,
                child: Semantics(
                  button: true,
                  label: '关闭',
                  onTap: widget.onClose,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: widget.onClose,
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

class _PicturePage extends StatefulWidget {
  const _PicturePage({
    super.key,
    required this.picture,
    required this.label,
    required this.onClose,
    required this.onZoomChanged,
  });

  final CommentPicture picture;
  final String label;
  final VoidCallback onClose;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_PicturePage> createState() => _PicturePageState();
}

class _PicturePageState extends State<_PicturePage> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _zoom = AnimationController(vsync: this, duration: CommentTextTheme.viewerZoomDuration);
  late final _zoomCurve = CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic);
  final _zoomTo = Matrix4Tween();
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_followZoom);
    _zoom.addListener(() => _transform.value = _zoomTo.evaluate(_zoomCurve));
  }

  @override
  void dispose() {
    _zoomCurve.dispose();
    _zoom.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _followZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  /// In around the tapped point, or back out to the whole picture.
  void _toggleZoom() {
    final scale = CommentTextTheme.viewerDoubleTapScale;
    final point = _doubleTapAt;
    final end = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-point.dx * (scale - 1), -point.dy * (scale - 1), 0, 1)
            ..scaleByDouble(scale, scale, 1, 1));
    if (MediaQuery.disableAnimationsOf(context)) {
      _transform.value = end;
      return;
    }
    _zoomTo
      ..begin = _transform.value
      ..end = end;
    _zoom.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pixels = screen * MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      image: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _transform,
          panEnabled: _zoomed,
          maxScale: CommentTextTheme.viewerMaxScale,
          onInteractionStart: (_) => _zoom.stop(),
          child: SizedBox.expand(
            child: RemoteImage(
              _viewerAddress(widget.picture, pixels),
              size: screen,
              fit: BoxFit.contain,
              placeholder: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture fitted inside the screen by Bilibili's image CDN, never above its own size. `@…w_…h` with no `c` keeps
/// the whole picture, where RemoteImage's own suffix crops it to the box; RemoteImage leaves an address that already
/// has a suffix alone.
String _viewerAddress(CommentPicture picture, Size pixels) {
  final secure = secureImageUrl(picture.url);
  final uri = Uri.tryParse(secure);
  if (pixels.isEmpty || uri == null || !uri.host.endsWith('hdslb.com') || uri.hasQuery || uri.path.contains('@')) {
    return secure;
  }
  int side(double screen, double own) => (own > 0 ? math.min(screen, own) : screen).ceil();
  return '$secure@${side(pixels.width, picture.width)}w_${side(pixels.height, picture.height)}h.webp';
}
