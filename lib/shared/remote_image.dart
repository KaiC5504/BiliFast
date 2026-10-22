import 'dart:async';
import 'dart:io' show IOException;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'cover_format.dart';
import 'image_disk_cache.dart';
import 'theme.dart';

/// Bilibili's JSON hands out `//host/path` and `http://` addresses; iOS wants https. Pictures on i1 and i2 are asked
/// from i0 ([PictureSession.host]), which serves the same paths, so one connection carries them all.
String secureImageUrl(String url) {
  final secure = url.startsWith('//')
      ? 'https:$url'
      : url.startsWith('http://')
      ? 'https://${url.substring('http://'.length)}'
      : url;
  for (final mirror in _pictureMirrors) {
    if (secure.startsWith(mirror)) return 'https://${PictureSession.host}/${secure.substring(mirror.length)}';
  }
  return secure;
}

const _pictureMirrors = ['https://i1.hdslb.com/', 'https://i2.hdslb.com/'];

/// [url] from Bilibili's image CDN scaled and cropped there to [width]×[height] px (`@…w_…h_1c.webp`). Covers are
/// asked for at full size instead ([RemoteImage.cover]).
String sizedImageUrl(String url, {required int width, required int height}) =>
    suffixedImageUrl(url, '@${width}w_${height}h_1c.webp');

/// [url] with the CDN's processing [suffix] (`@…`), on Bilibili's image hosts and only where the address has none yet.
String suffixedImageUrl(String url, String suffix) {
  final secure = secureImageUrl(url);
  final uri = Uri.tryParse(secure);
  if (uri == null || !uri.host.endsWith('hdslb.com') || uri.hasQuery || uri.path.contains('@')) return secure;
  return '$secure$suffix';
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
    this.cdnSuffix,
    this.cover = false,
  });

  /// An avatar: Bilibili's default face while it loads, if it fails and when there is none.
  const RemoteImage.avatar(this.url, {super.key, this.size})
    : fit = BoxFit.cover,
      placeholder = null,
      fallback = const DefaultAvatar(),
      fadeIn = true,
      overlay = null,
      cdnSuffix = null,
      cover = false;

  final String? url;
  final BoxFit fit;

  /// Asks for the image at this size instead of the box's, so a box that changes size every frame (a Hero flight)
  /// keeps one download.
  final Size? size;

  /// The CDN's suffix (`@…`) asked for in place of the box's size rounded up, whatever the box: a size the CDN keeps
  /// pre-made answers sooner.
  final String? cdnSuffix;

  /// A video's cover: the full-size picture ([CoverFormat]), which the CDN has ready where a box-sized one is made on
  /// demand, decoded only as large as the box (rounded up) needs. One download serves every box it is drawn in.
  final bool cover;

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
    } else if (fixed != null || (cdnSuffix != null && !cover)) {
      image = _image(context, source, fixed);
    } else {
      image = LayoutBuilder(builder: (context, constraints) => _image(context, source, constraints.biggest));
    }
    final under = placeholder;
    if (under == null) return instead != null ? image : ColoredBox(color: BiliColors.pageGrey, child: image);
    return Stack(fit: StackFit.expand, children: [under, image]);
  }

  /// Fetches and decodes [url] as a RemoteImage of [size] or [cdnSuffix] (or a [cover] of [size]) shows it, so that
  /// box shows it at once. True once it is ready, false if it failed or there is none; never throws. [onDecoded] gets
  /// ImageIO's ms for a cover this decoded from AVIF.
  static Future<bool> precache(
    BuildContext context,
    String? url, {
    Size? size,
    String? cdnSuffix,
    bool cover = false,
    ValueChanged<double>? onDecoded,
  }) async {
    if (url == null || url.isEmpty) return false;
    final provider = _provider(context, url, size, cdnSuffix: cdnSuffix, cover: cover);
    var ok = true;
    // Without an onError, precacheImage hands the failure to FlutterError, and CrashLog would log the signed address.
    await precacheImage(
      provider,
      context,
      onError: (error, _) {
        ok = false;
        _logFailure(provider.url, error);
      },
    );
    if (ok && onDecoded != null) {
      if (StoredNetworkImage._avifDecodeMs[provider] case final ms?) onDecoded(ms);
    }
    return ok;
  }

  /// A cover's box is the same rounded-up size in device pixels as a sized address's, so a precache and its draw
  /// share one decode.
  static StoredNetworkImage _provider(
    BuildContext context,
    String source,
    Size? logical, {
    String? cdnSuffix,
    bool cover = false,
  }) {
    final suffix = cover ? null : cdnSuffix;
    if (suffix != null) {
      return StoredNetworkImage(
        suffixedImageUrl(source, suffix),
        headers: BiliClient.mediaHeaders,
        still: !animates(source),
      );
    }
    final pixels = (logical ?? Size.infinite) * MediaQuery.devicePixelRatioOf(context);
    final width = _bucket(pixels.width);
    final height = _bucket(pixels.height);
    if (cover) {
      return StoredNetworkImage(
        CoverFormat.shared.address(source),
        headers: BiliClient.mediaHeaders,
        box: Size(width.toDouble(), height.toDouble()),
      );
    }
    return StoredNetworkImage(
      sizedImageUrl(source, width: width, height: height),
      headers: BiliClient.mediaHeaders,
      still: !animates(source),
    );
  }

  Widget _image(BuildContext context, String source, Size? logical) => _Picture(
    image: _provider(context, source, logical, cdnSuffix: cdnSuffix, cover: cover),
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
    final kind = status != null
        ? '$status'
        : error is PictureDownloadException
        ? error.reason
        : '${error.runtimeType}';
    if (!_loggedFailures.add('$host $kind')) return;
    Logger.shared.warn(LogCategory.ui, 'image failed', {
      'host': host,
      'path': uri?.path ?? '',
      if (status != null) 'status': status else 'error': kind,
    });
  }
}

/// A network picture through [ImageDiskCache.shared] (straight from the network without one, as [NetworkImage]).
/// [still] shows only its first frame: the CDN serves a GIF original (a cover, a face) as an animated webp through
/// the size suffix, and a moving picture decodes a frame every few tens of ms for as long as it is on screen. A still
/// one is cached under its own key, so it never shares an entry with the moving one.
class StoredNetworkImage extends ImageProvider<NetworkImage> implements NetworkImage {
  const StoredNetworkImage(this.url, {this.headers, this.still = true, this.box});

  @override
  final String url;

  @override
  final Map<String, String>? headers;

  final bool still;

  /// A full-size cover's box in device pixels: it is decoded only as large as covering the box needs (never the whole
  /// original), and is a cache entry of its own per box. An AVIF ([CoverFormat]) that doesn't decode is shown from
  /// its webp instead. Always still.
  final Size? box;

  /// ImageIO's ms for the AVIF cover a provider decoded, read by [RemoteImage.precache].
  static final _avifDecodeMs = Expando<double>();

  @override
  double get scale => 1;

  @override
  WebHtmlElementStrategy get webHtmlElementStrategy => WebHtmlElementStrategy.never;

  /// What the image cache holds this picture under.
  NetworkImage get cacheKey => still || box != null ? this : NetworkImage(url, headers: headers);

  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<NetworkImage>(cacheKey);

  @override
  ImageStreamCompleter loadImage(NetworkImage key, ImageDecoderCallback decode) {
    final completer = MultiFrameImageStreamCompleter(codec: _load(decode), scale: scale);
    completer.addEphemeralErrorListener((error, _) {
      // A failed picture must not stay failed in the cache, nor a stored copy that didn't decode be read again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      if (!_network(error)) unawaited(ImageDiskCache.shared?.forget(url));
    });
    return completer;
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final box = this.box;
    if (box == null) {
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(await _bytes(url)));
      return still ? _FirstFrame(codec) : codec;
    }
    if (CoverFormat.isAvif(url)) {
      final avif = await _avif(box);
      if (avif != null) return avif;
      final webp = CoverFormat.webpOf(url);
      try {
        return await _covering(await _bytes(webp), box, decode);
      } catch (error) {
        if (!_network(error)) unawaited(ImageDiskCache.shared?.forget(webp));
        rethrow;
      }
    }
    return _covering(await _bytes(url), box, decode);
  }

  /// Null when the AVIF can't be shown and its webp is to be asked for; a stored copy that didn't decode is deleted.
  Future<ui.Codec?> _avif(Size box) async {
    final Uint8List bytes;
    try {
      bytes = await _bytes(url);
    } on NetworkImageLoadException catch (error) {
      CoverFormat.shared.refused(url, error.statusCode);
      return null;
    }
    final decoded = await CoverFormat.shared.decodeAvif(url, bytes, box.width.round(), box.height.round());
    if (decoded == null) {
      unawaited(ImageDiskCache.shared?.forget(url));
      return null;
    }
    _avifDecodeMs[this] = decoded.decodeMs;
    return decoded.codec;
  }

  Future<Uint8List> _bytes(String address) async {
    final stored = ImageDiskCache.shared;
    final bytes = stored != null
        ? await stored.bytes(address, headers: headers)
        : await ImageDiskCache.download(Uri.base.resolve(address), headers);
    if (bytes.isEmpty) throw StateError('empty picture');
    return bytes;
  }

  static bool _network(Object error) =>
      error is NetworkImageLoadException || error is TimeoutException || error is IOException;

  static Future<ui.Codec> _covering(Uint8List bytes, Size box, ImageDecoderCallback decode) async {
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: (width, height) => covering(width, height, box),
    );
    return _FirstFrame(codec);
  }

  /// The size a [width] × [height] picture decodes at to cover [box], keeping its shape; its own size when it is no
  /// larger. Only the side that binds is given, so the engine keeps the aspect.
  @visibleForTesting
  static ui.TargetImageSize covering(int width, int height, Size box) {
    if (width <= 0 || height <= 0) return const ui.TargetImageSize();
    final across = box.width / width;
    final down = box.height / height;
    if (math.max(across, down) >= 1) return const ui.TargetImageSize();
    return across >= down
        ? ui.TargetImageSize(width: math.max(box.width.round(), 1))
        : ui.TargetImageSize(height: math.max(box.height.round(), 1));
  }

  @override
  bool operator ==(Object other) =>
      other is StoredNetworkImage &&
      other.url == url &&
      other.still == still &&
      other.box == box &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(StoredNetworkImage, url, still, box);

  /// Host and path only: a query can carry a signature.
  @override
  String toString() {
    final uri = Uri.tryParse(url);
    final cover = box;
    return 'StoredNetworkImage("${uri?.host}${uri?.path}", still: $still'
        '${cover == null ? '' : ', box: ${cover.width.round()}×${cover.height.round()}'})';
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
    final image = widget.image;
    // A cover asked for as webp after its AVIF failed (or AVIF went off) is still the picture already shown.
    final address = image.box == null ? image.url : CoverFormat.sameCover(image.url);
    final instead = widget.fallback;
    return Image(
      image: image,
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
        RemoteImage._logFailure(image.url, error);
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
  void didUpdateWidget(_FadeOver oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new address: [under] shows again until it has a frame.
    if (!widget.loaded) _covered = false;
  }

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
