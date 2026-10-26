import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../player_ui/end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../space/space_route.dart';
import '../../space/uploader_tap.dart';
import '../../video/page_playback.dart';
import '../../video/video_route.dart';
import '../post/post_route.dart';

/// Where a card's taps lead. Tests swap them for recorders, so nothing pushes a real page or reaches the platform.
abstract final class DynamicOpen {
  static Future<void> Function(BuildContext context, {required String id, DynamicItem? item, bool toComments}) post =
      openDynamicPost;
  static Future<void> Function(BuildContext context, VideoRoute route) video = openVideoPage;
  static Future<void> Function(BuildContext context, UploaderRef uploader) space = openSpace;
  static Future<bool> Function(Uri link) browser = _browser;
  static ShareLink share = shareThroughSystem;

  static Future<bool> _browser(Uri link) => launchUrl(link, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static void reset() {
    post = openDynamicPost;
    video = openVideoPage;
    space = openSpace;
    browser = _browser;
    share = shareThroughSystem;
  }
}

/// The video page for a post's [video]: with an inline card's running [playback] it goes on from that frame with
/// sound, otherwise it starts from [start] on part [cid] when the card had played.
Future<void> openDynamicVideo(
  BuildContext context,
  DynamicVideo video, {
  PagePlayback? playback,
  double? start,
  int? cid,
}) => DynamicOpen.video(
  context,
  VideoRoute(
    bvid: video.bvid,
    cid: playback == null && cid != null && cid > 0 ? cid : null,
    start: playback == null ? start : null,
    title: video.title.isEmpty ? null : video.title,
    cover: playback == null && video.cover.isNotEmpty ? video.cover : null,
    playback: playback,
  ),
);

/// A post opened from a card: a video post plays, 直播 and 番剧 aren't built, anything else opens on its own page.
Future<void> openDynamicItem(BuildContext context, DynamicItem item, {bool toComments = false}) async {
  if (item.major case final DynamicVideo video) return openDynamicVideo(context, video);
  if (item.kind == DynamicKind.live || item.kind == DynamicKind.pgc) {
    showToast(context, notBuilt);
    return;
  }
  await DynamicOpen.post(context, id: item.id, item: item, toComments: toComments);
}

/// A web address in a post: a bilibili.com video opens in the app, a space its space, anything else the browser.
Future<void> openDynamicLink(BuildContext context, String url) async {
  final link = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
  if (link == null || !(link.scheme == 'http' || link.scheme == 'https')) {
    showToast(context, '无法打开链接');
    return;
  }
  final host = link.host.toLowerCase();
  final segments = link.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (host.endsWith('bilibili.com')) {
    if (segments case ['video', final id, ...] when id.startsWith('BV')) {
      return DynamicOpen.video(context, VideoRoute(bvid: id));
    }
  }
  final mid = switch ((host, segments)) {
    ('space.bilibili.com', [final id, ...]) => int.tryParse(id),
    ('m.bilibili.com', ['space', final id, ...]) => int.tryParse(id),
    _ => null,
  };
  if (mid != null && mid > 0) return DynamicOpen.space(context, UploaderRef(mid: mid));
  var opened = false;
  try {
    opened = await DynamicOpen.browser(link);
  } catch (error) {
    Logger.shared.warn(LogCategory.ui, 'dynamic link failed', {'error': '${error.runtimeType}'});
  }
  if (!opened && context.mounted) showToast(context, '无法打开链接');
}

/// What a tap on anything not built yet says.
const notBuilt = '暂未开放';

/// The card's words, read from [BiliFonts.family] where they're built.
TextStyle dynamicStyle(double size, Color color, {FontWeight weight = FontWeight.w400, double? line}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: line == null ? null : line / size,
  leadingDistribution: TextLeadingDistribution.even,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// The card's art: the APK's dynamic icons and the official icon font's glyphs, white at 3× for tinting.
abstract final class DynamicArt {
  static const forward = 'assets/images/dynamic/dy_ic_arrow_share_line_24.png';
  static const comment = 'assets/images/dynamic/dy_ic_bubble_comment_line_24.png';
  static const like = 'assets/images/dynamic/dy_ic_hand_thumbsup_line_24.png';
  static const liked = 'assets/images/dynamic/dy_ic_hand_thumbsup_fill_24.png';
  static const more = 'assets/images/dynamic/more_vertical_fill.png';
  static const gift = 'assets/images/dynamic/gift_lottery_line.png';
  static const videoLink = 'assets/images/dynamic/video_circle_line.png';
  static const lock = 'assets/images/dynamic/lock_locked_line.png';
  static const share = 'assets/images/dynamic/arrow_share_line.png';
  static const unfollow = 'assets/images/dynamic/person_unfollow_line.png';
  static const report = 'assets/images/dynamic/warning_report_triangle_line.png';
  static const tv = 'assets/images/dynamic/ic_upper_tv_play.png';
  static const muted = 'assets/images/card/inline_muted.png';
  static const sound = 'assets/images/card/inline_sound.png';
}

/// [asset] tinted [color], [width] wide at its own shape.
class DynamicIcon extends StatelessWidget {
  const DynamicIcon(this.asset, {super.key, required this.width, required this.color, this.height});

  final String asset;
  final double width;
  final double? height;
  final Color color;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: width,
    height: height,
    fit: BoxFit.contain,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}
