import AVFoundation
import CoreImage
import Photos
import UIKit

/// The screenshot button. BTR plays a local HLS playlist, which AVAssetImageGenerator cannot read, so frames
/// come from the video output PlayerHostView attaches to every item.
enum FrameCapture {
  enum SaveResult {
    case saved
    case refused(Int)
    case failed(String)
  }

  static func capture(from item: AVPlayerItem) -> UIImage? {
    guard let output = item.outputs.lazy.compactMap({ $0 as? AVPlayerItemVideoOutput }).first,
          let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil) else {
      return nil
    }
    let image = CIImage(cvPixelBuffer: buffer)
    guard let frame = CIContext().createCGImage(image, from: image.extent) else { return nil }
    return UIImage(cgImage: frame)
  }

  static func saveToPhotos(_ image: UIImage) async -> SaveResult {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { return .refused(status.rawValue) }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
      }
      return .saved
    } catch {
      return .failed(String(describing: error))
    }
  }
}
