import Flutter
import ImageIO
import UIKit

/// Apple's decoder for the pictures Flutter's engine can't read (lib/shared/ios/picture_api.g.dart): Pigeon's
/// PictureHostApi (PictureApi.g.swift).
enum PictureDecoder {
  static func register(with messenger: FlutterBinaryMessenger) {
    PictureHostApiSetup.setUp(binaryMessenger: messenger, api: PictureHostApiImpl())
  }
}

final class PictureHostApiImpl: PictureHostApi {
  func decodeCover(data: FlutterStandardTypedData, boxWidth: Int64, boxHeight: Int64) async throws -> DecodedPicture? {
    nil
  }
}
