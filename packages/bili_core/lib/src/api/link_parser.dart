sealed class VideoLink {
  const VideoLink();

  const factory VideoLink.bvid(String id, {int? page}) = BvidLink;
  const factory VideoLink.aid(int id, {int? page}) = AidLink;
  const factory VideoLink.short(Uri url) = ShortLink;

  bool get isShort => this is ShortLink;
}

final class BvidLink extends VideoLink {
  const BvidLink(this.id, {this.page});

  final String id;
  final int? page;

  @override
  bool operator ==(Object other) => other is BvidLink && other.id == id && other.page == page;

  @override
  int get hashCode => Object.hash(id, page);

  @override
  String toString() => 'VideoLink.bvid($id, page: $page)';
}

final class AidLink extends VideoLink {
  const AidLink(this.id, {this.page});

  final int id;
  final int? page;

  @override
  bool operator ==(Object other) => other is AidLink && other.id == id && other.page == page;

  @override
  int get hashCode => Object.hash(id, page);

  @override
  String toString() => 'VideoLink.aid($id, page: $page)';
}

final class ShortLink extends VideoLink {
  const ShortLink(this.url);

  final Uri url;

  @override
  bool operator ==(Object other) => other is ShortLink && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'VideoLink.short($url)';
}

abstract final class LinkParser {
  static final _shortPattern = RegExp(r'https?://(?:b23\.tv|bili2233\.cn)/[A-Za-z0-9]+');
  static final _pagePattern = RegExp(r'[?&]p=(\d+)');
  static final _bvPattern = RegExp(r'BV1[0-9A-Za-z]{9}(?![0-9A-Za-z])');
  static final _avPattern = RegExp(r'(?:^|[^a-z0-9])av(\d+)', caseSensitive: false);

  /// Finds a video in anything a user might paste: a URL, a bare id, or the share text of the official app.
  static VideoLink? parse(String text) {
    final input = text.trim();
    final short = _shortPattern.firstMatch(input)?.group(0);
    if (short != null) {
      final url = Uri.tryParse(short);
      if (url != null) return VideoLink.short(url);
    }
    final pageText = _pagePattern.firstMatch(input)?.group(1);
    final page = pageText == null ? null : int.tryParse(pageText);
    final bv = _bvPattern.firstMatch(input)?.group(0);
    if (bv != null) return VideoLink.bvid(bv, page: page);
    final av = _avPattern.firstMatch(input)?.group(1);
    final id = av == null ? null : int.tryParse(av);
    if (id != null) return VideoLink.aid(id, page: page);
    return null;
  }
}
