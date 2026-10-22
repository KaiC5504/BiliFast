import 'dart:async';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'image_disk_cache.dart';
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
/// Only emotes and 装扮 pictures move; anything else shows its first frame (see [StoredNetworkImage]).
class RemoteImage extends StatelessWidget {
  const RemoteImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.size,
    this.placeholder,
    this.fallback,
    this.fadeIn = true,
    this.overlay,
  });

  /// An avatar: Bilibili's default face while it loads, if it fails and when there is none.
  const RemoteImage.avatar(this.url, {super.key, this.size})
    : fit = BoxFit.cover,
      placeholder = null,
      fallback = const DefaultAvatar(),
      fadeIn = true,
      overlay = null;

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

  /// False shows the picture the frame it arrives, as 推荐's covers do in the official app (14).
  final bool fadeIn;

  /// Drawn over the picture once it is in, never over [placeholder] or [fallback]: a cover's shade.
  final Widget? overlay;

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

  static StoredNetworkImage _provider(String address, String source) =>
      StoredNetworkImage(address, headers: BiliClient.mediaHeaders, still: !animates(source));

  Widget _image(BuildContext context, String source, Size logical) => _Picture(
    image: _provider(_address(context, source, logical), source),
    fit: fit,
    fallback: fallback,
    fadeIn: fadeIn,
    overlay: overlay,
  );

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

/// A network picture through [ImageDiskCache.shared] (straight from the network without one, as [NetworkImage]),
/// only its first frame unless it moves. The CDN serves a GIF original (a cover, a face) as an animated webp through
/// the size suffix, and a moving picture decodes a frame every few tens of ms for as long as it is on screen. A still
/// one is cached under its own type, so it never shares an entry with the moving one; a moving one under the
/// [NetworkImage] of its address.
class StoredNetworkImage extends ImageProvider<NetworkImage> implements NetworkImage {
  const StoredNetworkImage(this.url, {this.headers, this.still = true});

  @override
  final String url;

  @override
  final Map<String, String>? headers;

  final bool still;

  @override
  double get scale => 1;

  @override
  WebHtmlElementStrategy get webHtmlElementStrategy => WebHtmlElementStrategy.never;

  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NetworkImage>(still ? this : NetworkImage(url, headers: headers));

  @override
  ImageStreamCompleter loadImage(NetworkImage key, ImageDecoderCallback decode) {
    final completer = MultiFrameImageStreamCompleter(codec: _load(decode), scale: scale);
    completer.addEphemeralErrorListener((error, _) {
      // A failed picture must not stay failed in the cache, nor a stored copy that didn't decode be read again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      if (error is! NetworkImageLoadException) unawaited(ImageDiskCache.shared?.forget(url));
    });
    return completer;
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final stored = ImageDiskCache.shared;
    final bytes = stored != null
        ? await stored.bytes(url, headers: headers)
        : await ImageDiskCache.download(Uri.base.resolve(url), headers);
    if (bytes.isEmpty) throw StateError('empty picture');
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    return still ? _FirstFrame(codec) : codec;
  }

  @override
  bool operator ==(Object other) =>
      other is StoredNetworkImage && other.url == url && other.still == still && mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(StoredNetworkImage, url, still);

  /// Host and path only: a query can carry a signature.
  @override
  String toString() {
    final uri = Uri.tryParse(url);
    return 'StoredNetworkImage("${uri?.host}${uri?.path}", still: $still)';
  }
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

/// The picture at [image]'s address, faded in the first time. Once a frame of that address has shown, a reload of it
/// (the Image re-resolving when its page comes back and the memory cache has let the picture go) keeps it at full
/// opacity: gapless playback still paints the old frame, but the new stream starts with no frame number.
class _Picture extends StatefulWidget {
  const _Picture({
    required this.image,
    required this.fit,
    required this.fallback,
    required this.fadeIn,
    required this.overlay,
  });

  final StoredNetworkImage image;
  final BoxFit fit;
  final Widget? fallback;
  final bool fadeIn;
  final Widget? overlay;

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  String? _shown;

  @override
  Widget build(BuildContext context) {
    final address = widget.image.url;
    final instead = widget.fallback;
    return Image(
      image: widget.image,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      frameBuilder: (context, picture, frame, synchronous) {
        if (frame != null) _shown = address;
        final over = widget.overlay;
        final child = over == null ? picture : Stack(fit: StackFit.expand, children: [picture, over]);
        if (synchronous) return child;
        final loaded = _shown == address;
        if (instead != null) return _FadeOver(loaded: loaded, under: instead, child: child);
        return AnimatedOpacity(
          opacity: loaded ? 1 : 0,
          duration: widget.fadeIn ? RemoteImage._fade : Duration.zero,
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (context, error, stack) {
        RemoteImage._logFailure(address, error);
        return instead ?? const SizedBox.expand();
      },
    );
  }
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
  // Made already loaded (a picture shown at once, now reloading), there is no fade to wait for.
  late bool _covered = widget.loaded;

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
