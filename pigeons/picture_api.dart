// Regenerate after any change, from the repo root:
//   fvm dart run pigeon --input pigeons/picture_api.dart
// and commit both outputs (lib/shared/ios/picture_api.g.dart, ios/Runner/PictureApi.g.swift).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/shared/ios/picture_api.g.dart',
    swiftOut: 'ios/Runner/PictureApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'PictureApiError'),
  ),
)
/// A picture decoded by ImageIO: [pixels] are RGBA, 8 bits each, alpha premultiplied, [rowBytes] per row.
class DecodedPicture {
  DecodedPicture({
    required this.pixels,
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.decodeMs,
  });

  Uint8List pixels;
  int width;
  int height;
  int rowBytes;

  /// How long ImageIO took, for the log.
  double decodeMs;
}

/// Apple's own decoder (PictureDecoder.swift), for the formats Flutter's engine can't read (AVIF).
@HostApi()
abstract class PictureHostApi {
  /// Decodes [data] small enough to cover a [boxWidth] × [boxHeight] px box, never larger than the picture itself;
  /// null when ImageIO can't read it.
  @async
  DecodedPicture? decodeCover(Uint8List data, int boxWidth, int boxHeight);
}
