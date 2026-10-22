import 'dart:io';
import 'dart:typed_data';

import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1×1 GIF of two frames, 100 ms each, looping forever: a red pixel, then a blue one.
final animatedGif = Uint8List.fromList([
  ...'GIF89a'.codeUnits,
  0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // 1×1, a global table of two colours
  0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF,
  0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 0x03, 0x01, 0x00, 0x00, 0x00, // loop forever
  for (final pixel in [0x44, 0x4C]) ...[
    0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // 100 ms
    0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0x02, 0x02, pixel, 0x01, 0x00, // colour 0, then colour 1
  ],
  0x3B,
]);

/// Pictures kept as the app keeps them, through [ImageDiskCache.shared] in a temporary folder; every download is
/// answered with [animatedGif] and its address recorded in [downloads]. Nothing reaches the network.
final class StoredPictures {
  StoredPictures._(this._folder, this._cache, this.downloads);

  final Directory _folder;
  final ImageDiskCache _cache;
  final List<String> downloads;

  static Future<StoredPictures> keep(WidgetTester tester) async {
    final downloads = <String>[];
    final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('stored_pictures')))!;
    final cache = ImageDiskCache(
      folder: folder.path,
      fetch: (url, _) async {
        downloads.add('$url');
        return animatedGif;
      },
    );
    ImageDiskCache.shared = cache;
    addTearDown(() => ImageDiskCache.shared = null);
    return StoredPictures._(folder, cache, downloads);
  }

  /// Lets the reads, downloads and decodes run, then any fade.
  static Future<void> arrive(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      // Storage and decoding run on the engine's real clock.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Empties the image cache, puts [ImageDiskCache.shared] back and deletes the folder.
  Future<void> drop(WidgetTester tester) async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    ImageDiskCache.shared = null;
    await tester.runAsync(() async {
      await _cache.settle();
      await _folder.delete(recursive: true);
    });
  }
}
