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
import '../../skin/skin_package.dart' show SkinPackageError, downloadSkinPackage, isBannerVideoUrl;
import '../../skin/skin_video.dart';

/// The 空间头图's video as a file, which SkinVideo plays: kept in the caches beside the pictures, named by the hash of
/// its address's path (the query can be a signature that changes with every answer), downloaded once. Storing the
/// one asked last deletes the others; one asked before it that finishes later is kept until then, so a new 空间头图 is
/// never deleted by the old one's download.
///
/// The address comes from an answer, so it is fetched as a 装扮 package is: only from Bilibili's CDN and video hosts
/// ([isBannerVideoUrl]), each redirect held to the same rule, with the pictures' Referer, and dropped past
/// [maxBytes]. [client] is for tests.
final class OwnBannerVideos {
  OwnBannerVideos({required this.folder, Future<Uint8List> Function(Uri url)? fetch, HttpClient Function()? client})
    : _fetch =
          fetch ??
          ((url) => downloadSkinPackage(
            url,
            client: client ?? HttpClient.new,
            timeout: _timeout,
            cap: maxBytes,
            allowed: isBannerVideoUrl,
            headers: BiliClient.mediaHeaders,
            what: 'banner video',
          ));

  /// The official 空间头图 videos are a few MB.
  static const maxBytes = 30 * 1024 * 1024;

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

  /// Keyed by the destination file: two signatures of one video are one download into one `.part`.
  final _loads = <String, Future<File?>>{};
  String? _latest;

  File fileOf(String url) {
    final path = Uri.tryParse(url)?.path;
    final key = path == null || path.isEmpty ? url : path;
    return File('$folder${Platform.pathSeparator}${sha1.convert(utf8.encode(key))}.mp4');
  }

  /// [url]'s file, downloaded the first time, from [backups] in turn when [url] can't be had; null when none can.
  /// No address is ever logged.
  Future<File?> file(String url, {List<String> backups = const []}) {
    final key = fileOf(url).path;
    _latest = key;
    return _loads[key] ??= _load(url, backups).whenComplete(() {
      // A block body: returning the removed future would have this one wait on itself.
      _loads.remove(key);
    });
  }

  Future<File?> _load(String url, List<String> backups) async {
    final file = fileOf(url);
    try {
      if (await file.exists() && await file.length() > 0) return file;
    } on Object catch (error) {
      Logger.shared.warn(LogCategory.ui, 'own space banner video failed', {'error': _reason(error)});
      return null;
    }
    final sources = [url, ...backups];
    for (final (index, source) in sources.indexed) {
      try {
        final address = Uri.tryParse(secureImageUrl(source));
        if (address == null) {
          Logger.shared.warn(LogCategory.ui, 'own space banner video failed', {'source': index, 'error': 'unparsed'});
          continue;
        }
        if (!isBannerVideoUrl(address)) throw SkinPackageError.hostNotAllowed(address, what: 'banner video');
        final bytes = await _fetch(address);
        if (bytes.isEmpty) {
          Logger.shared.warn(LogCategory.ui, 'own space banner video failed', {'source': index, 'error': 'empty'});
          continue;
        }
        await Directory(folder).create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
        Logger.shared.info(LogCategory.ui, 'own space banner video', {'host': address.host, 'bytes': bytes.length});
        if (_latest == file.path) await _keepOnly(file);
        return file;
      } on Object catch (error) {
        Logger.shared.warn(LogCategory.ui, 'own space banner video failed', {'source': index, 'error': _reason(error)});
      }
    }
    Logger.shared.warn(LogCategory.ui, 'own space banner video gave up', {'tried': sources.length});
    return null;
  }

  /// Another address still downloading keeps its file and its `.part`: the page may have moved on to it.
  Future<void> _keepOnly(File kept) async {
    final loading = _loads.keys.toSet();
    await for (final entry in Directory(folder).list(followLinks: false)) {
      if (entry is! File || entry.path == kept.path) continue;
      final path = entry.path.endsWith('.part') ? entry.path.substring(0, entry.path.length - 5) : entry.path;
      if (loading.contains(path)) continue;
      await entry.delete();
    }
  }

  static String _reason(Object error) => switch (error) {
    final SkinPackageError failure => failure.reason,
    final NetworkImageLoadException failure => 'status ${failure.statusCode}',
    final PictureDownloadException failure => failure.reason,
    _ => '${error.runtimeType}',
  };
}

/// The animated 空间头图: its video, looped, cover-fit about [alignY] as the still under it is, so the still shows
/// until the video draws and wherever it can't (the PC, a failed download). With [muted] its sound is kept, heard
/// while the notifier is false; without, it plays silent.
class OwnBannerVideo extends StatefulWidget {
  const OwnBannerVideo({
    super.key,
    required this.url,
    required this.size,
    required this.alignY,
    required this.still,
    this.backups = const [],
    this.videos,
    this.muted,
    this.playing,
  });

  final String url;

  /// The video's own width and height; without them it fills the box about its middle, as SkinVideo lays it.
  final ({int width, int height})? size;
  final double alignY;
  final Widget still;

  /// Other addresses of the same video, tried in turn when [url] can't be had.
  final List<String> backups;

  /// Where the file comes from; [OwnBannerVideos.shared] when null.
  final OwnBannerVideos? videos;

  final ValueListenable<bool>? muted;

  /// Set to [url] once the video draws, and back to null if it fails; the sound button shows only then.
  final ValueNotifier<String?>? playing;

  @override
  State<OwnBannerVideo> createState() => _OwnBannerVideoState();
}

class _OwnBannerVideoState extends State<OwnBannerVideo> {
  File? _file;

  /// The sound track joins only once the disc is first pressed: a muted player holding one can still take the audio
  /// session at play() and stop another app's music. The view made then plays from the start.
  bool _heard = false;

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
      _heard = false;
      _fetch();
    }
  }

  void _fetch() {
    final videos = widget.videos ?? OwnBannerVideos.shared;
    if (videos == null) return;
    final url = widget.url;
    unawaited(
      videos.file(url, backups: widget.backups).then((file) {
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
                  children: [Positioned.fromRect(rect: video, child: _video(file))],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _video(File file) {
    final url = widget.url;
    SkinVideo video({bool muted = true}) => SkinVideo(
      key: const ValueKey('own-space-banner-video'),
      file: file,
      loop: true,
      placeholder: const SizedBox.expand(),
      sound: widget.muted != null && _heard,
      muted: muted,
      onShown: (shown) {
        final playing = widget.playing;
        if (playing == null) return;
        if (shown && widget.url == url) {
          playing.value = url;
        } else if (!shown && playing.value == url) {
          playing.value = null;
        }
      },
    );
    final muted = widget.muted;
    if (muted == null) return video();
    return ValueListenableBuilder<bool>(
      valueListenable: muted,
      builder: (context, value, _) {
        if (!value) _heard = true;
        return video(muted: value);
      },
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
