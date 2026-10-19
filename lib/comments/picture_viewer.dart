import 'dart:math' as math;

import 'package:bili_core/api.dart' hide RichText;
import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'comment_row.dart' show CommentPictures;

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

  /// In around the tapped point, or back out to the whole width; a long picture stays scrolled where it was.
  void _toggleZoom(Size screen, double contentHeight) {
    final scale = CommentTextTheme.viewerDoubleTapScale;
    final point = _doubleTapAt;
    final Matrix4 end;
    if (_zoomed) {
      final top = _transform.toScene(Offset.zero).dy;
      end = Matrix4.translationValues(0, -clampDouble(top, 0, math.max(0, contentHeight - screen.height)), 0);
    } else {
      end = Matrix4.identity()
        ..translateByDouble(point.dx, point.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-point.dx, -point.dy, 0, 1)
        ..multiply(_transform.value);
    }
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
    final picture = widget.picture;
    final long = isLongPicture(picture, screen);
    final contentHeight = long ? screen.width * picture.height / picture.width : screen.height;
    final image = _LoadingPicture(
      address: viewerAddress(picture, pixels, long: long),
      thumbnail: _thumbnail,
      firstScreen: long ? screen.height : null,
    );
    return Semantics(
      image: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: () => _toggleZoom(screen, contentHeight),
        // A long picture sits full width from its top and scrolls under the finger, as the official app's.
        child: InteractiveViewer(
          transformationController: _transform,
          constrained: !long,
          panEnabled: long || _zoomed,
          minScale: 1,
          maxScale: CommentTextTheme.viewerMaxScale,
          onInteractionStart: (_) => _zoom.stop(),
          child: long
              ? SizedBox(width: screen.width, height: contentHeight, child: image)
              : SizedBox.expand(child: image),
        ),
      ),
    );
  }

  /// The largest of the list's thumbnails already in the image cache, so it shows at once while the picture loads.
  /// The rows ask in 60 px steps, as [CommentPictures] builds them.
  late final String? _thumbnail = () {
    final cache = PaintingBinding.instance.imageCache;
    for (var width = _thumbnailWidest; width > 0; width -= 60) {
      final address = CommentPictures.thumbnail(widget.picture.url, width: width);
      if (cache.statusForKey(NetworkImage(address, headers: BiliClient.mediaHeaders)).tracked) return address;
    }
    return null;
  }();

  static const _thumbnailWidest = 2400;
}

/// Taller than the screen's own shape: fitted inside it, such a picture would be a narrow strip.
@visibleForTesting
bool isLongPicture(CommentPicture picture, Size screen) =>
    picture.width > 0 &&
    picture.height > 0 &&
    !screen.isEmpty &&
    picture.height / picture.width > screen.height / screen.width;

/// The picture scaled by Bilibili's image CDN, never above its own size: fitted inside the screen (`@…w_…h` with no
/// `c` keeps the whole picture), or for a [long] one by width alone so it can be read at full width.
@visibleForTesting
String viewerAddress(CommentPicture picture, Size pixels, {required bool long}) {
  final secure = secureImageUrl(picture.url);
  final uri = Uri.tryParse(secure);
  if (pixels.isEmpty || uri == null || !uri.host.endsWith('hdslb.com') || uri.hasQuery || uri.path.contains('@')) {
    return secure;
  }
  int side(double screen, double own) => (own > 0 ? math.min(screen, own) : screen).ceil();
  if (long) return '$secure@${side(pixels.width, picture.width)}w.webp';
  return '$secure@${side(pixels.width, picture.width)}w_${side(pixels.height, picture.height)}h.webp';
}

/// The picture fading in over the list's [thumbnail] and a spinner, or a picture glyph if it fails (BiliNative
/// `PictureViewer`'s states).
class _LoadingPicture extends StatelessWidget {
  const _LoadingPicture({required this.address, required this.thumbnail, this.firstScreen});

  final String address;
  final String? thumbnail;

  /// A long picture's spinner and glyph sit in the middle of its first screenful, where the viewer opens.
  final double? firstScreen;

  Widget _centred(Widget child) {
    final height = firstScreen;
    if (height == null) return Center(child: child);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(height: height, child: Center(child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final fade = still ? Duration.zero : CommentTextTheme.viewerCrossFade;
    final under = thumbnail;
    return Image.network(
      address,
      headers: BiliClient.mediaHeaders,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        if (synchronous) return child;
        final loading = frame == null;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (under != null)
              AnimatedOpacity(
                opacity: loading ? 1 : 0,
                duration: fade,
                child: Image.network(
                  under,
                  headers: BiliClient.mediaHeaders,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
              ),
            AnimatedOpacity(opacity: loading ? 0 : 1, duration: fade, curve: Curves.easeOut, child: child),
            if (loading)
              _centred(
                const CupertinoActivityIndicator(
                  color: CommentTextTheme.viewerText,
                  radius: CommentTextTheme.viewerSpinnerRadius,
                ),
              ),
          ],
        );
      },
      errorBuilder: (context, error, stack) {
        _logFailure(error);
        return _centred(const PictureFailedGlyph());
      },
    );
  }

  /// Once per host and kind of failure, as [RemoteImage] logs; the address itself stays out of the log.
  static final _logged = <String>{};

  void _logFailure(Object error) {
    final host = Uri.tryParse(address)?.host ?? '';
    final kind = error is NetworkImageLoadException ? '${error.statusCode}' : '${error.runtimeType}';
    if (!_logged.add('$host $kind')) return;
    Logger.shared.warn(LogCategory.ui, 'comment picture failed', {'host': host, 'error': kind});
  }
}

/// A framed landscape: a picture that could not load.
class PictureFailedGlyph extends StatelessWidget {
  const PictureFailedGlyph({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox.square(
      dimension: CommentTextTheme.viewerFailedGlyph,
      child: CustomPaint(painter: _PictureGlyphPainter()),
    ),
  );
}

class _PictureGlyphPainter extends CustomPainter {
  const _PictureGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = CommentTextTheme.viewerFailedGlyphStroke;
    final paint = Paint()
      ..color = CommentTextTheme.viewerFailedGlyphColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final frame = Rect.fromLTRB(w * 0.08, w * 0.18, w * 0.92, w * 0.82);
    canvas.drawRRect(RRect.fromRectAndRadius(frame, Radius.circular(w * 0.08)), paint);
    canvas.drawCircle(Offset(w * 0.68, w * 0.36), w * 0.06, paint);
    canvas.drawPath(
      Path()
        ..moveTo(frame.left + stroke, w * 0.72)
        ..lineTo(w * 0.36, w * 0.46)
        ..lineTo(w * 0.56, w * 0.66)
        ..lineTo(w * 0.68, w * 0.56)
        ..lineTo(frame.right - stroke, w * 0.72),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PictureGlyphPainter oldDelegate) => false;
}
