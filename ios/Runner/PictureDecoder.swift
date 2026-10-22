import Flutter
import ImageIO
import UIKit

/// Apple's decoder for the pictures Flutter's engine can't read (lib/shared/ios/picture_api.g.dart): Pigeon's
/// PictureHostApi (PictureApi.g.swift).
enum PictureDecoder {
  static func register(with messenger: FlutterBinaryMessenger) {
    PictureHostApiSetup.setUp(binaryMessenger: messenger, api: PictureHostApiImpl())
  }

  struct Pixels: Sendable {
    let bytes: Data
    let width: Int
    let height: Int
    let rowBytes: Int
    let ms: Double
  }

  /// ImageIO's thumbnail path decodes straight to the target size, so a 1920×1080 cover is never held whole.
  static func decodeCover(_ encoded: Data, boxWidth: Int, boxHeight: Int) -> Pixels? {
    let start = DispatchTime.now().uptimeNanoseconds
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(encoded as CFData, sourceOptions as CFDictionary),
          CGImageSourceGetCount(source) > 0,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
          let pixelWidth = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
          let pixelHeight = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
          pixelWidth > 0, pixelHeight > 0 else {
      return nil
    }
    let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
    let turned = (5...8).contains(orientation)
    let width = Double(turned ? pixelHeight : pixelWidth)
    let height = Double(turned ? pixelWidth : pixelHeight)

    var scale = 1.0
    if boxWidth > 0, boxHeight > 0 {
      scale = min(1, max(Double(boxWidth) / width, Double(boxHeight) / height))
    }
    let maxPixelSize = max(1, Int((max(width, height) * scale).rounded(.up)))

    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
      return nil
    }
    let outWidth = image.width
    let outHeight = image.height
    guard outWidth > 0, outHeight > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
          ) else {
      return nil
    }
    // Copy, not source-over: the context's memory isn't promised to start clear, and a cover may have alpha.
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

    let rowBytes = context.bytesPerRow
    let bytes: Data? = withExtendedLifetime(context) {
      guard let base = context.data else { return nil }
      return Data(bytes: base, count: rowBytes * outHeight)
    }
    guard let bytes else { return nil }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    return Pixels(bytes: bytes, width: outWidth, height: outHeight, rowBytes: rowBytes, ms: ms)
  }
}

final class PictureHostApiImpl: PictureHostApi {
  func decodeCover(data: FlutterStandardTypedData, boxWidth: Int64, boxHeight: Int64) async throws -> DecodedPicture? {
    let encoded = data.data
    let width = Int(boxWidth)
    let height = Int(boxHeight)
    // Pigeon calls in on the main actor; several covers decode at once on GCD's pool instead.
    let pixels = await withCheckedContinuation { (continuation: CheckedContinuation<PictureDecoder.Pixels?, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: PictureDecoder.decodeCover(encoded, boxWidth: width, boxHeight: height))
      }
    }
    guard let pixels else { return nil }
    return DecodedPicture(
      pixels: FlutterStandardTypedData(bytes: pixels.bytes),
      width: Int64(pixels.width),
      height: Int64(pixels.height),
      rowBytes: Int64(pixels.rowBytes),
      decodeMs: pixels.ms
    )
  }
}
