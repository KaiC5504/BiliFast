import 'package:bili_core/api.dart';

/// 58's 排序方式.
enum FilterOrder {
  relevance('默认排序', SearchOrder.totalrank),
  newest('新发布', SearchOrder.pubdate),
  plays('播放多', SearchOrder.click),
  danmaku('弹幕多', SearchOrder.dm);

  const FilterOrder(this.label, this.order);

  final String label;
  final SearchOrder order;
}

/// 58's 发布时间. The custom date range under it is left out.
enum FilterPublished {
  any('不限', null),
  day('最近一天', Duration(days: 1)),
  week('最近一周', Duration(days: 7)),
  halfYear('最近半年', Duration(days: 182));

  const FilterPublished(this.label, this.within);

  final String label;
  final Duration? within;
}

/// 58's 内容时长. The search knows only "over 60 minutes", so 60-120 and 120+ are cut from its rows by length.
enum FilterLength {
  any('不限', SearchDuration.any, null, null),
  under10('0-10分钟', SearchDuration.under10, null, null),
  from10to30('10-30分钟', SearchDuration.from10to30, null, null),
  from30to60('30-60分钟', SearchDuration.from30to60, null, null),
  from60to120('60-120分钟', SearchDuration.over60, null, 120 * 60),
  over120('120分钟+', SearchDuration.over60, 120 * 60, null);

  const FilterLength(this.label, this.duration, this.minSeconds, this.maxSeconds);

  final String label;
  final SearchDuration duration;

  /// Bounds on a row's length in seconds, kept on our side; null is open.
  final int? minSeconds;
  final int? maxSeconds;

  bool admits(int seconds) {
    final min = minSeconds;
    final max = maxSeconds;
    return (min == null || seconds >= min) && (max == null || seconds < max);
  }
}

/// 综合's 筛选 (58), without its 音画质量 and 范围 rows.
class SearchFilters {
  const SearchFilters({
    this.order = FilterOrder.relevance,
    this.published = FilterPublished.any,
    this.length = FilterLength.any,
  });

  final FilterOrder order;
  final FilterPublished published;
  final FilterLength length;

  /// 综合 without 筛选 asks the mixed search; any filter asks the video search.
  bool get isDefault => order == FilterOrder.relevance && published == FilterPublished.any && length == FilterLength.any;

  SearchFilters copyWith({FilterOrder? order, FilterPublished? published, FilterLength? length}) => SearchFilters(
    order: order ?? this.order,
    published: published ?? this.published,
    length: length ?? this.length,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters && other.order == order && other.published == published && other.length == length;

  @override
  int get hashCode => Object.hash(order, published, length);
}
