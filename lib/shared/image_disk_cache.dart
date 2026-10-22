import 'dart:async';
import 'dart:typed_data';

/// Downloads a picture's bytes; throws `NetworkImageLoadException` for a status other than 200.
typedef ImageFetch = Future<Uint8List> Function(Uri url, Map<String, String>? headers);

/// Every network picture kept on the phone, so a picture asked for again (iOS emptied the memory cache, a page came
/// back, the app relaunched) comes from storage instead of the network. Files are named by a hash of the address, in
/// the caches folder iOS may empty when storage runs short; past [capBytes] the oldest go first.
class ImageDiskCache {
  ImageDiskCache({required this.folder, this.capBytes = defaultCapBytes, this._fetch});

  static const defaultCapBytes = 500 * 1024 * 1024;

  /// The app's, set at launch; null in tests, where pictures come straight from the network as before.
  static ImageDiskCache? shared;

  final String folder;
  final int capBytes;
  // ignore: unused_field
  final ImageFetch? _fetch;

  /// Trims to the cap, oldest first, and logs `image cache`. Never throws.
  Future<void> start() async {}

  /// The picture at [url] from storage, or downloaded (with [headers]) and stored.
  Future<Uint8List> bytes(String url, {Map<String, String>? headers}) =>
      throw UnimplementedError('ImageDiskCache.bytes');

  /// What the stored pictures take, in bytes.
  Future<int> sizeBytes() async => 0;

  /// Deletes every stored picture.
  Future<void> clear() async {}
}
