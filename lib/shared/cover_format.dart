import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'cover_preset.dart';
import 'image_disk_cache.dart' show PictureDownload;
import 'ios/picture_api.g.dart';
import 'remote_image.dart' show suffixedImageUrl;

/// Decodes [data] small enough to cover a [boxWidth] × [boxHeight] px box, as [PictureHostApi.decodeCover] does.
typedef CoverDecode = Future<DecodedPicture?> Function(Uint8List data, int boxWidth, int boxHeight);

/// Whether a video's cover is asked by its [CoverPreset]. Most presets are AVIF, which Flutter's engine can't read, so
/// they are asked only where Apple's ImageIO decodes them ([PictureHostApi]). Elsewhere, for an address whose AVIF
/// failed, and for the rest of the session once [failuresToTurnOff] decodes in a row have failed, the cover is asked
/// at its box's exact size as JPEG instead. Also times the covers' downloads per preset (`cover downloads`).
final class CoverFormat {
  CoverFormat({this._decode, this._logger});

  /// The iPhone decodes AVIF through ImageIO; the PC and tests ask for JPEG and never reach the channel.
  static CoverFormat shared = CoverFormat.platform();

  static CoverFormat platform() => Platform.isIOS ? CoverFormat(decode: PictureHostApi().decodeCover) : CoverFormat();

  static const failuresToTurnOff = 3;

  /// Network downloads of one preset and format per `cover downloads` line.
  static const downloadsPerLine = 10;

  final CoverDecode? _decode;
  final Logger? _logger;

  int _failuresInARow = 0;
  bool _off = false;
  bool _announced = false;
  final _reasons = <String>{};

  /// AVIF addresses that didn't draw this session: their covers are asked at their exact size from then on.
  final _failed = <String>{};

  /// Per preset and format, the downloads since the last line, and how many there were in all.
  final _downloads = <String, List<(PictureDownload, double?)>>{};
  final _downloadCounts = <String, int>{};

  Logger get _log => _logger ?? Logger.shared;

  bool get avif => _decode != null && !_off;

  /// How AVIF presets' covers are asked now: `avif`, or `jpg` at their exact size.
  String get name => avif ? 'avif' : 'jpg';

  /// [cover]'s address by [preset], through [suffixedImageUrl]; null when it is to be asked at its exact size:
  /// [CoverPreset.exact], an AVIF preset without ImageIO, or an address that takes no suffix. An address whose AVIF
  /// failed keeps it, so its provider (a precache's and its draw's) stays one; its load goes straight to the JPEG
  /// ([failed]).
  String? address(String cover, CoverPreset preset) {
    if (!_announced) {
      _announced = true;
      _log.info(LogCategory.ui, 'cover format', {'format': name});
    }
    if (preset == CoverPreset.exact) return null;
    if (!preset.avif) return suffixedImageUrl(cover, preset.suffix);
    if (!avif) return null;
    final asked = suffixedImageUrl(cover, preset.suffix);
    return asked.endsWith(preset.suffix) ? asked : null;
  }

  /// Whether [address]'s AVIF was refused or didn't decode this session.
  bool failed(String address) => _failed.contains(address);

  /// One cover whichever suffix it is asked with.
  static String sameCover(String address) {
    final at = address.lastIndexOf('@');
    return at < 0 || address.contains('?') ? address : address.substring(0, at);
  }

  /// [data], an AVIF, as one frame decoded by ImageIO to cover a [boxWidth] × [boxHeight] px box, with ImageIO's ms.
  /// Null when it can't be drawn: [address] is then asked at its exact size, and the failure counts toward turning
  /// AVIF off. Never throws.
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

  /// The CDN answered [status] for an AVIF: its cover is asked at its exact size, without counting against the
  /// decoder.
  void refused(String address, int status) {
    _failed.add(address);
    if (_reasons.add('status $status')) _log.warn(LogCategory.ui, 'avif refused', {'status': status});
  }

  /// A cover of [preset] downloaded as [format] (`avif`, `webp` or `jpg`), with ImageIO's [decodeMs] for an AVIF that
  /// decoded. Every [downloadsPerLine]th of a preset and format logs `cover downloads`: the medians and slowest of
  /// those downloads, so the phone shows which presets the CDN has ready.
  void downloaded(CoverPreset preset, String format, PictureDownload download, {double? decodeMs}) {
    final key = '${preset.name} $format';
    final batch = _downloads.putIfAbsent(key, () => [])..add((download, decodeMs));
    final n = _downloadCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (batch.length < downloadsPerLine) return;
    _downloads.remove(key);
    final firstBytes = [for (final (download, _) in batch) download.firstByteMs];
    final decodes = [for (final (_, ms) in batch) ?ms];
    _log.info(LogCategory.ui, 'cover downloads', {
      'preset': preset.name,
      'format': format,
      'n': n,
      'firstByteMs': _median(firstBytes),
      'firstByteMaxMs': firstBytes.reduce(math.max),
      'kb': (_median([for (final (download, _) in batch) download.bytes]) / 1024).round(),
      if (decodes.isNotEmpty) 'decodeMsMax': decodes.reduce(math.max).round(),
    });
  }

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2).round();
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
      // The codec reads the descriptor as it makes frames, so the descriptor is left to its finalizer.
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
