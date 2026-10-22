import 'dart:async';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Bilibili's JSON hands out `//host/path` and `http://` addresses; iOS wants https.
String secureImageUrl(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring('http://'.length)}';
  return url;
}

/// [url] from Bilibili's image CDN scaled and cropped there to [width]×[height] px (`@…w_…h_1c.webp`), so a feed card
/// downloads tens of KB instead of the full-size cover.
String sizedImageUrl(String url, {required int width, required int height}) {
  final secure = secureImageUrl(url);
  final uri = Uri.tryParse(secure);
  if (uri == null || !uri.host.endsWith('hdslb.com') || uri.hasQuery || uri.path.contains('@')) return secure;
  return '$secure@${width}w_${height}h_1c.webp';
}

/// Fills the box it is given with the image, grey (or [placeholder]) until it arrives and then faded in. Sizes are
/// rounded up to steps, so cards of nearly the same width share one cached download.
///
/// Only emotes and 装扮 pictures move; anything else shows its first frame (see [StillNetworkImage]).
class RemoteImage extends StatelessWidget {
  const RemoteImage(this.url, {super.key, this.fit = BoxFit.cover, this.size, this.placeholder, this.fallback});

  /// An avatar: Bilibili's default face while it loads, if it fails and when there is none.
  const RemoteImage.avatar(this.url, {super.key, this.size})
    : fit = BoxFit.cover,
      placeholder = null,
      fallback = const DefaultAvatar();

  final String? url;
  final BoxFit fit;

  /// Asks for the image at this size instead of the box's, so a box that changes size every frame (a Hero flight)
  /// keeps one download.
  final Size? size;

  /// Shown instead of the grey until the image arrives, and if it fails.
  final Widget? placeholder;

  /// Shown in place of the image while it loads, if it fails and for an empty [url]. Unlike [placeholder] it is gone
  /// once the image is in, so it never shows through a transparent one.
  final Widget? fallback;

  static const _step = 60;

  /// A failure is logged once per host and status: enough to see a CDN refusing the size suffix.
  static final _loggedFailures = <String>{};

  static int _bucket(double pixels) => pixels.isFinite && pixels > 0 ? ((pixels / _step).ceil() * _step) : 480;

  @override
  Widget build(BuildContext context) {
    final source = url;
    final fixed = size;
    final instead = fallback;
    final Widget image;
    if (source == null || source.isEmpty) {
      image = instead ?? const SizedBox.expand();
    } else if (fixed != null) {
      image = _image(context, source, fixed);
    } else {
      image = LayoutBuilder(builder: (context, constraints) => _image(context, source, constraints.biggest));
    }
    final under = placeholder;
    if (under == null) return instead != null ? image : ColoredBox(color: BiliColors.pageGrey, child: image);
    return Stack(fit: StackFit.expand, children: [under, image]);
  }

  /// Fetches and decodes [url] as a RemoteImage of [logical] size shows it, so that box shows it at once. True once
  /// it is ready, false if it failed or there is none; never throws.
  static Future<bool> precache(BuildContext context, String? url, Size logical) async {
    if (url == null || url.isEmpty) return false;
    var ok = true;
    await precacheImage(_provider(_address(context, url, logical), url), context, onError: (_, _) => ok = false);
    return ok;
  }

  static String _address(BuildContext context, String source, Size logical) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return sizedImageUrl(source, width: _bucket(logical.width * ratio), height: _bucket(logical.height * ratio));
  }

  static ImageProvider _provider(String address, String source) => animates(source)
      ? NetworkImage(address, headers: BiliClient.mediaHeaders)
      : StillNetworkImage(address, headers: BiliClient.mediaHeaders);

  Widget _image(BuildContext context, String source, Size logical) {
    final address = _address(context, source, logical);
    final instead = fallback;
    return Image(
      image: _provider(address, source),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        if (synchronous) return child;
        if (instead != null) return _FadeOver(loaded: frame != null, under: instead, child: child);
        return AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: _fade, curve: Curves.easeOut, child: child);
      },
      errorBuilder: (context, error, stack) {
        _logFailure(address, error);
        return instead ?? const SizedBox.expand();
      },
    );
  }

  static const _fade = Duration(milliseconds: 150);

  /// The comments' emotes and 装扮 stickers are drawn moving, as in the official app.
  @visibleForTesting
  static bool animates(String url) {
    final path = Uri.tryParse(secureImageUrl(url))?.path ?? '';
    return path.startsWith('/bfs/emote/') || path.startsWith('/bfs/garb/');
  }

  /// The path shows the size suffix; the query, which can carry a signature, never goes in the log.
  static void _logFailure(String address, Object error) {
    final uri = Uri.tryParse(address);
    final host = uri?.host ?? '';
    final status = error is NetworkImageLoadException ? error.statusCode : null;
    final kind = status == null ? '${error.runtimeType}' : '$status';
    if (!_loggedFailures.add('$host $kind')) return;
    Logger.shared.warn(LogCategory.ui, 'image failed', {
      'host': host,
      'path': uri?.path ?? '',
      if (status != null) 'status': status else 'error': kind,
    });
  }
}

/// A network picture's first frame only. The CDN serves a GIF original (a cover, a face) as an animated webp through
/// the size suffix, and a moving picture decodes a frame every few tens of ms for as long as it is on screen. It is a
/// [NetworkImage] of its own type, so it never shares a cache entry with the moving one.
class StillNetworkImage extends ImageProvider<NetworkImage> implements NetworkImage {
  StillNetworkImage(String url, {Map<String, String>? headers}) : _network = NetworkImage(url, headers: headers);

  final NetworkImage _network;

  @override
  String get url => _network.url;

  @override
  double get scale => _network.scale;

  @override
  Map<String, String>? get headers => _network.headers;

  @override
  WebHtmlElementStrategy get webHtmlElementStrategy => _network.webHtmlElementStrategy;

  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<NetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(NetworkImage key, ImageDecoderCallback decode) {
    Future<ui.Codec> firstFrame(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) async =>
        _FirstFrame(await decode(buffer, getTargetSize: getTargetSize));
    final completer = _network.loadImage(_network, firstFrame);
    // NetworkImage evicts its own key when the download fails, not this one; without this a failed picture would
    // stay failed in the cache.
    completer.addEphemeralErrorListener((_, _) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) => other is StillNetworkImage && other._network == _network;

  @override
  int get hashCode => Object.hash(StillNetworkImage, _network);

  @override
  String toString() => 'StillNetworkImage("$url")';
}

/// One frame, played once, so the image stream never asks for the next.
final class _FirstFrame implements ui.Codec {
  _FirstFrame(this._codec);

  final ui.Codec _codec;

  @override
  int get frameCount => 1;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() => _codec.getNextFrame();

  @override
  void dispose() => _codec.dispose();
}

/// The image fading in over [under], which goes once the fade is done.
class _FadeOver extends StatefulWidget {
  const _FadeOver({required this.loaded, required this.under, required this.child});

  final bool loaded;
  final Widget under;
  final Widget child;

  @override
  State<_FadeOver> createState() => _FadeOverState();
}

class _FadeOverState extends State<_FadeOver> {
  bool _covered = false;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (!_covered) widget.under,
      AnimatedOpacity(
        opacity: widget.loaded ? 1 : 0,
        duration: RemoteImage._fade,
        curve: Curves.easeOut,
        onEnd: () {
          if (widget.loaded && mounted) setState(() => _covered = true);
        },
        child: widget.child,
      ),
    ],
  );
}

/// Bilibili's default face (PiliPlus's `noface.jpeg`), for an avatar that is loading, failed or missing.
class DefaultAvatar extends StatelessWidget {
  const DefaultAvatar({super.key});

  static const asset = 'assets/images/noface.jpeg';

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    key: const ValueKey('default-avatar'),
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    excludeFromSemantics: true,
  );
}
