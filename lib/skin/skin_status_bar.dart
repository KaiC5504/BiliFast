import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../app/phone_frame.dart';
import '../shared/theme.dart';
import 'skin.dart';

/// How a header's picture lies on KaiC's iPhone: cover-fit in [box] from the screen's top-left, cropped about
/// [alignment], over [backdrop].
final class StatusBarPlacement {
  const StatusBarPlacement({required this.box, required this.alignment, required this.backdrop});

  /// 首页's top: `head_bg` down to the top row's bottom, or to 01's hairline when the package has no tab picture,
  /// over the page's grey.
  factory StatusBarPlacement.home({required bool tabPicture}) => StatusBarPlacement(
    box: Size(PhoneFrame.portrait.width, tabPicture ? _statusBar + BiliMetrics.topRowHeight : _homeHairline),
    alignment: Alignment.center,
    backdrop: BiliColors.pageGrey,
  );

  /// 我的's header: from the screen's top to the list's under a 大会员's card (109), cut at the bottom.
  static final me = StatusBarPlacement(
    box: Size(PhoneFrame.portrait.width, _statusBar + MeTheme.cardTop + MeTheme.cardHeight + MeTheme.listCut),
    alignment: Alignment.topCenter,
    backdrop: MeTheme.background,
  );

  static final _statusBar = PhoneFrame.portraitPadding.top;
  static const _homeHairline = 141 + 2 / 3;

  /// Behind the clock and behind signal, Wi-Fi and battery, the status bar's height.
  static final areas = [Rect.fromLTRB(24, 0, 140, _statusBar), Rect.fromLTRB(300, 0, 416, _statusBar)];

  final Size box;
  final Alignment alignment;
  final Color backdrop;
}

/// [skin]'s headers measured behind the status bar: 首页's `head_bg`, and 我的's picture unless a video plays over it
/// (that one goes by the skin's colour). A file that can't be read throws, so a passing failure is never kept as the
/// picture's.
Future<SkinStatusBar> measureSkinStatusBar(Skin skin) async {
  final home = skin.headBg;
  final me = skin.headMyselfVideo == null ? skin.headMyself : null;
  return SkinStatusBar(
    home: home == null
        ? null
        : await statusBarLuminance(home, StatusBarPlacement.home(tabPicture: skin.headTabBg != null)),
    me: me == null ? null : await statusBarLuminance(me, StatusBarPlacement.me),
  );
}

/// The log-average relative luminance of [file] laid as [placement], over the status bar's areas; null when it
/// doesn't decode. Decoded at one pixel per point at most, as small as the measure needs.
Future<double?> statusBarLuminance(File file, StatusBarPlacement placement) async {
  final bytes = await file.readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    final header = descriptor = await ui.ImageDescriptor.encoded(buffer);
    final source = Size(header.width.toDouble(), header.height.toDouble());
    final scale = _coverScale(source, placement.box);
    final decoded = math.min(1.0, scale);
    codec = await header.instantiateCodec(
      targetWidth: math.max(1, (header.width * decoded).round()),
      targetHeight: math.max(1, (header.height * decoded).round()),
    );
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) return null;
      final drawn = placement.alignment.inscribe(source * scale, Offset.zero & placement.box);
      return _logAverage(data, image.width, image.height, drawn, placement.backdrop);
    } finally {
      image.dispose();
    }
  } on Exception {
    return null;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

double _coverScale(Size source, Size box) => math.max(box.width / source.width, box.height / source.height);

double? _logAverage(ByteData data, int width, int height, Rect drawn, Color backdrop) {
  final pixels = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final under = [backdrop.r * 255, backdrop.g * 255, backdrop.b * 255];
  var sum = 0.0;
  var count = 0;
  for (final area in StatusBarPlacement.areas) {
    final left = ((area.left - drawn.left) * width / drawn.width).floor().clamp(0, width);
    final right = ((area.right - drawn.left) * width / drawn.width).ceil().clamp(0, width);
    final top = ((area.top - drawn.top) * height / drawn.height).floor().clamp(0, height);
    final bottom = ((area.bottom - drawn.top) * height / drawn.height).ceil().clamp(0, height);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final at = (y * width + x) * 4;
        final alpha = pixels[at + 3] / 255;
        // Blended as the screen blends, in sRGB, then linearised.
        double channel(int index) => _linear[(pixels[at + index] * alpha + under[index] * (1 - alpha)).round()];
        sum += math.log(0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2) + 0.05);
        count++;
      }
    }
  }
  return count == 0 ? null : math.exp(sum / count) - 0.05;
}

final _linear = List<double>.generate(256, (value) {
  final c = value / 255;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}, growable: false);
