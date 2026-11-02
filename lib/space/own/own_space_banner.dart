import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bili_core/api.dart' show BiliClient;
import 'package:flutter/widgets.dart';

import '../../comments/comment_badges.dart' show DecorImage;
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../skin/skin_status_bar.dart' show StatusBarPlacement;

/// The own space's banner picture. A sized ask has the CDN cut the picture to the box about its middle, so it is
/// asked whole at the screen's width and cut here about the answer's crop ([alignY]), as the official app shows the
/// 空间头图's face where the middle would be its body (24).
class OwnSpaceBanner extends StatelessWidget {
  const OwnSpaceBanner({super.key, required this.url, required this.alignY});

  final String url;
  final double alignY;

  /// The address [url] is asked by on a screen [pixels] device pixels wide, in 60 px steps as RemoteImage's.
  static String address(String url, double pixels) {
    final width = pixels.isFinite && pixels > 0 ? (pixels / 60).ceil() * 60 : 1320;
    return suffixedImageUrl(url, '@${width}w.webp');
  }

  /// What the banner draws for [url] on this screen; a measure resolving it shares the banner's download.
  static ImageProvider imageOf(BuildContext context, String url) => StoredNetworkImage(
    secureImageUrl(address(url, MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))),
    headers: BiliClient.mediaHeaders,
    still: false,
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: SpaceTheme.bannerDefault,
    child: DecorImage(
      address(url, MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)),
      fit: BoxFit.cover,
      alignment: Alignment(0, alignY),
    ),
  );
}

/// [image] laid as the resting banner [width] wide lays it, measured behind the clock and the icons as a 装扮
/// header is (skin_status_bar.dart's [StatusBarPlacement.areas] and the same mean); null when nothing was read.
Future<double?> ownBannerLuminance(ui.Image image, {required double width, required double alignY}) async {
  final placement = StatusBarPlacement(
    box: Size(width, OwnSpaceTheme.bannerHeight),
    alignment: Alignment(0, alignY),
    backdrop: SpaceTheme.bannerDefault,
  );
  final areas = placement.areas;
  final height = areas.map((area) => area.bottom).reduce(math.max);
  if (width <= 0 || height <= 0) return null;
  // Drawn at one pixel a point, only as far down as the status bar.
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(placement.backdrop, BlendMode.src);
  paintImage(
    canvas: canvas,
    rect: Offset.zero & placement.box,
    image: image,
    fit: BoxFit.cover,
    alignment: placement.alignment,
    filterQuality: FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final strip = await picture.toImage(width.ceil(), height.ceil());
  picture.dispose();
  try {
    final data = await strip.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    final pixels = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    var sum = 0.0;
    var count = 0;
    for (final area in areas) {
      final right = math.min(area.right.ceil(), strip.width);
      final bottom = math.min(area.bottom.ceil(), strip.height);
      for (var y = math.max(area.top.floor(), 0); y < bottom; y++) {
        for (var x = math.max(area.left.floor(), 0); x < right; x++) {
          final at = (y * strip.width + x) * 4;
          final luminance =
              0.2126 * _linear[pixels[at]] + 0.7152 * _linear[pixels[at + 1]] + 0.0722 * _linear[pixels[at + 2]];
          sum += math.log(luminance + 0.05);
          count++;
        }
      }
    }
    return count == 0 ? null : math.exp(sum / count) - 0.05;
  } finally {
    strip.dispose();
  }
}

final _linear = List<double>.generate(256, (value) {
  final c = value / 255;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}, growable: false);
