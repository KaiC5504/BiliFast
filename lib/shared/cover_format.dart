import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'ios/picture_api.g.dart';
import 'remote_image.dart' show suffixedImageUrl;

/// Decodes [data] small enough to cover a [boxWidth] × [boxHeight] px box, as [PictureHostApi.decodeCover] does.
typedef CoverDecode = Future<DecodedPicture?> Function(Uint8List data, int boxWidth, int boxHeight);

/// Which full-size picture a video's cover is asked for. The CDN keeps the original stored as AVIF and webp, where a
/// box-sized one is made on demand (slower, measured from the PC); AVIF is the smaller and always ready, but Flutter's
/// engine can't read it, so it is asked for only where Apple's ImageIO decodes it ([PictureHostApi]). Elsewhere, and
/// for the rest of the session once [failuresToTurnOff] AVIF decodes in a row have failed, covers are webp.
final class CoverFormat {
  CoverFormat({this._decode, this._logger});

  /// The iPhone's decodes AVIF through ImageIO; the PC and tests ask for webp and never reach the channel.
  static CoverFormat shared = CoverFormat.platform();

  static CoverFormat platform() => Platform.isIOS ? CoverFormat(decode: PictureHostApi().decodeCover) : CoverFormat();

  static const avifSuffix = '@.avif';
  static const webpSuffix = '@.webp';
  static const failuresToTurnOff = 3;

  final CoverDecode? _decode;
  final Logger? _logger;

  int _failuresInARow = 0;
  bool _off = false;
  bool _announced = false;
  final _reasons = <String>{};

  /// AVIF addresses that didn't draw this session: their covers are asked for as webp from then on.
  final _failed = <String>{};

  Logger get _log => _logger ?? Logger.shared;

  bool get avif => _decode != null && !_off;

  String get name => avif ? 'avif' : 'webp';

  /// [cover]'s full-size address, through [suffixedImageUrl]: only Bilibili's image hosts, and only an address with
  /// no `@` or query yet, take the format.
  String address(String cover) {
    if (!_announced) {
      _announced = true;
      _log.info(LogCategory.ui, 'cover format', {'format': name});
    }
    if (avif) {
      final asked = suffixedImageUrl(cover, avifSuffix);
      if (!_failed.contains(asked)) return asked;
    }
    return suffixedImageUrl(cover, webpSuffix);
  }

  static bool isAvif(String address) => address.endsWith(avifSuffix);

  /// The webp asked for in place of an AVIF [address] that didn't draw.
  static String webpOf(String address) =>
      isAvif(address) ? '${address.substring(0, address.length - avifSuffix.length)}$webpSuffix' : address;

  /// One cover whichever format it is asked in.
  static String sameCover(String address) {
    for (final suffix in const [avifSuffix, webpSuffix]) {
      if (address.endsWith(suffix)) return address.substring(0, address.length - suffix.length);
    }
    return address;
  }

  /// [data], an AVIF, as one frame decoded by ImageIO to cover a [boxWidth] × [boxHeight] px box, with ImageIO's ms.
  /// Null when it can't be drawn: [address] is then asked for as webp, and the failure counts toward turning AVIF
  /// off. Never throws.
  Future<({ui.Codec codec, double decodeMs})?> decodeAvif(
    String address,
    Uint8List data,
    int boxWidth,
    int boxHeight,
  ) async {
    final decode = _decode;
    if (decode == null) {
      _failed.add(address);
      return null;
    }
    DecodedPicture? picture;
    String reason;
    try {
      picture = await decode(data, boxWidth, boxHeight);
      reason = picture == null ? 'null' : _malformed(picture) ?? '';
    } on PlatformException catch (error) {
      reason = 'platform ${error.code}';
    } catch (error) {
      reason = '${error.runtimeType}';
    }
    if (picture != null && reason.isEmpty) {
      try {
        final codec = await _codecOf(picture);
        _failuresInARow = 0;
        return (codec: codec, decodeMs: picture.decodeMs);
      } catch (error) {
        reason = 'pixels ${error.runtimeType}';
      }
    }
    _decodeFailed(address, reason);
    return null;
  }

  /// The CDN answered [status] for an AVIF: its cover is asked for as webp, without counting against the decoder.
  void refused(String address, int status) {
    _failed.add(address);
    if (_reasons.add('status $status')) _log.warn(LogCategory.ui, 'avif refused', {'status': status});
  }

  void _decodeFailed(String address, String reason) {
    _failed.add(address);
    if (_reasons.add(reason)) _log.warn(LogCategory.ui, 'avif decode failed', {'reason': reason});
    _failuresInARow += 1;
    if (_off || _failuresInARow < failuresToTurnOff) return;
    _off = true;
    _log.warn(LogCategory.ui, 'avif off', {'failures': _failuresInARow});
  }

  /// Why [picture]'s pixels can't be read as its size says, if they can't: the engine would read past them.
  static String? _malformed(DecodedPicture picture) {
    final DecodedPicture(:width, :height, :rowBytes, :pixels) = picture;
    if (width <= 0 || height <= 0) return 'empty';
    if (rowBytes < width * 4 || pixels.length < rowBytes * height) return 'short';
    return null;
  }

  static Future<ui.Codec> _codecOf(DecodedPicture picture) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(picture.pixels);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: picture.width,
        height: picture.height,
        rowBytes: picture.rowBytes,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      return await descriptor.instantiateCodec();
    } finally {
      buffer.dispose();
    }
  }
}
