import 'dart:ui' show Size;

/// The official iPhone app's own cover addresses, from a capture of its picture requests (2026-10-23). The CDN keeps
/// these made, since every official user asks the same ones, and answers their first byte in ~150-175 ms against
/// ~300 ms for a size only this app asks for. A cover site names the official screen's preset, or [exact]; one that
/// names none is given [forBox]'s.
enum CoverPreset {
  /// 推荐's cards. Answers 719×540 for its 630×473.
  feed(630, 473, '_85q_!pegasus-ios-v2', avif: true),

  /// The video page's related videos.
  related(360, 202, '_1e_1c_85q', avif: true),

  /// An uploader's space, its video rows.
  space(384, 216, '_1e_1c_85q', avif: false),

  /// 历史记录's rows.
  history(450, 251, '_1e_1c_85q', avif: true),

  list(540, 305, '_1e_1c_85q', avif: true),

  wide(630, 354, '_1s_1e_1c_85q', avif: true),

  /// The player box before the video plays, and anything larger than [wide].
  player(1260, 709, '_85q_!pegasus-ios-v2', avif: true),

  /// No preset: the box's exact size as JPEG. 搜索's rows ask it: ours is the web search, whose covers official users
  /// never ask by the app's 搜索 preset, so the CDN had none made (first byte 312-537 ms on the phone in (33)).
  exact(0, 0, '', avif: false);

  const CoverPreset(this.width, this.height, this.style, {required this.avif});

  final int width;
  final int height;
  final String style;

  /// Asked as AVIF, which only Apple's ImageIO reads here ([PictureHostApi]); without it the cover is asked at its
  /// box's exact size instead.
  final bool avif;

  String get suffix {
    assert(this != exact, 'exact has no address of its own');
    return '@${width}w_${height}h$style.${avif ? 'avif' : 'webp'}';
  }

  /// The preset for a cover site that names none, its box [pixels] in device pixels: [feed] for a box narrower than
  /// 3:2, otherwise the smallest wide preset at least 95% of the box each way, else [player]. Never [space], its
  /// own screen's, or [exact].
  static CoverPreset forBox(Size pixels) {
    if (pixels.width / pixels.height < 1.5) return feed;
    for (final preset in const [related, history, list, wide]) {
      if (preset.width >= pixels.width * 0.95 && preset.height >= pixels.height * 0.95) return preset;
    }
    return player;
  }
}
