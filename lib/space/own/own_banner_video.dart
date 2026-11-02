import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart' show BiliClient;
import 'package:bili_core/devlog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../shared/image_disk_cache.dart';
import '../../shared/remote_image.dart' show secureImageUrl;
import '../../skin/skin_video.dart';

/// The 空间头图's video as a file, which SkinVideo plays: kept in the caches beside the pictures, named by its
/// address's hash, downloaded once; storing one deletes the others, so only the equipped one stays.
final class OwnBannerVideos {
  OwnBannerVideos({required this.folder, Future<Uint8List> Function(Uri url)? fetch})
    : _fetch = fetch ?? ((url) => ImageDiskCache.download(url, BiliClient.mediaHeaders, timeout: _timeout));

  /// The app's: a `space_banner` folder beside [ImageDiskCache.shared]'s, on the phone only (elsewhere SkinVideo
  /// draws its placeholder, so nothing is fetched); null without either.
  static OwnBannerVideos? shared = _platform();

  static OwnBannerVideos? _platform() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    final pictures = ImageDiskCache.shared?.folder;
    if (pictures == null) return null;
    return OwnBannerVideos(folder: '${File(pictures).parent.path}${Platform.pathSeparator}space_banner');
  }

  static const _timeout = Duration(seconds: 60);

  final String folder;
  final Future<Uint8List> Function(Uri url) _fetch;
  final _loads = <String, Future<File?>>{};

  File fileOf(String url) => File('$folder${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}.mp4');

  /// [url]'s file, downloaded the first time; null when it can't be had. The address is never logged.
  Future<File?> file(String url) => _loads[url] ??= _load(url).whenComplete(() {
    // A block body: returning the removed future would have this one wait on itself.
    _loads.remove(url);
  });

  Future<File?> _load(String url) async {
    final file = fileOf(url);
    try {
      if (await file.exists() && await file.length() > 0) return file;
      final address = Uri.tryParse(secureImageUrl(url));
      if (address == null) return null;
      final bytes = await _fetch(address);
      if (bytes.isEmpty) return null;
      await Directory(folder).create(recursive: true);
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      await _keepOnly(file);
      return file;
    } on Object catch (error) {
      Logger.shared.warn(LogCategory.ui, 'own space banner video failed', {'error': _reason(error)});
      return null;
    }
  }

  Future<void> _keepOnly(File kept) async {
    await for (final entry in Directory(folder).list(followLinks: false)) {
      if (entry is File && entry.path != kept.path) await entry.delete();
    }
  }

  static String _reason(Object error) => switch (error) {
    final NetworkImageLoadException failure => 'status ${failure.statusCode}',
    final PictureDownloadException failure => failure.reason,
    _ => '${error.runtimeType}',
  };
}

/// The animated 空间头图: its video, looped and without sound, cover-fit about [alignY] as the still under it is, so
/// the still shows until the video draws and wherever it can't (the PC, a failed download).
class OwnBannerVideo extends StatefulWidget {
  const OwnBannerVideo({
    super.key,
    required this.url,
    required this.size,
    required this.alignY,
    required this.still,
    this.videos,
  });

  final String url;

  /// The video's own width and height; without them it fills the box about its middle, as SkinVideo lays it.
  final ({int width, int height})? size;
  final double alignY;
  final Widget still;

  /// Where the file comes from; [OwnBannerVideos.shared] when null.
  final OwnBannerVideos? videos;

  @override
  State<OwnBannerVideo> createState() => _OwnBannerVideoState();
}

class _OwnBannerVideoState extends State<OwnBannerVideo> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(OwnBannerVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _file = null;
      _fetch();
    }
  }

  void _fetch() {
    final videos = widget.videos ?? OwnBannerVideos.shared;
    if (videos == null) return;
    final url = widget.url;
    unawaited(
      videos.file(url).then((file) {
        if (mounted && file != null && widget.url == url) setState(() => _file = file);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.still,
        if (file != null)
          LayoutBuilder(
            builder: (context, constraints) {
              final box = constraints.biggest;
              final video = _drawn(box);
              return ClipRect(
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: video,
                      child: SkinVideo(
                        key: const ValueKey('own-space-banner-video'),
                        file: file,
                        loop: true,
                        placeholder: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  /// Where the video lies in [box]: covering it, cut about [OwnBannerVideo.alignY].
  Rect _drawn(Size box) {
    final size = widget.size;
    if (size == null) return Offset.zero & box;
    final source = Size(size.width.toDouble(), size.height.toDouble());
    final scale = box.width / source.width > box.height / source.height
        ? box.width / source.width
        : box.height / source.height;
    return Alignment(0, widget.alignY).inscribe(source * scale, Offset.zero & box);
  }
}
