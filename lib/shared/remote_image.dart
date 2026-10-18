import 'package:bili_core/api.dart';
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

/// Fills the box it is given with the image, grey until it arrives and then faded in. Sizes are rounded up to steps,
/// so cards of nearly the same width share one cached download.
class RemoteImage extends StatelessWidget {
  const RemoteImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  static const _step = 60;

  static int _bucket(double pixels) => pixels.isFinite && pixels > 0 ? ((pixels / _step).ceil() * _step) : 480;

  @override
  Widget build(BuildContext context) {
    final source = url;
    return ColoredBox(
      color: BiliColors.pageGrey,
      child: source == null || source.isEmpty
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, constraints) {
                final ratio = MediaQuery.devicePixelRatioOf(context);
                return Image.network(
                  sizedImageUrl(
                    source,
                    width: _bucket(constraints.maxWidth * ratio),
                    height: _bucket(constraints.maxHeight * ratio),
                  ),
                  headers: BiliClient.mediaHeaders,
                  fit: fit,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, synchronous) => synchronous
                      ? child
                      : AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          child: child,
                        ),
                  errorBuilder: (context, error, stack) => const SizedBox.expand(),
                );
              },
            ),
    );
  }
}
