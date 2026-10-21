import 'dart:async';
import 'dart:math';

import 'package:bili_core/api.dart';

import 'search_api.dart';
import 'search_filters.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no search leaves the machine. Rows are paged
/// [pageSize] at a time; [calls] lists what was asked, in order.
class FakeSearchApi implements SearchApi {
  FakeSearchApi({
    this._defaultWord,
    this._hotWords = const [],
    this._discovery = const [],
    this._suggest,
    this._videos = const [],
    this._users = const [],
    this.pageSize = 20,
  });

  /// The demo the PC's `--fake-account` run searches against: rows made up around whatever is searched, 筛选 applied
  /// as the search would, and 搜索发现 turning over on every ↻. [now] is the moment its rows' dates count back from.
  factory FakeSearchApi.demo({DateTime? now}) =>
      FakeSearchApi(defaultWord: _Demo.defaultWord, hotWords: _Demo.hotWords, suggest: _Demo.suggestions)
        .._demo = _Demo(now ?? DateTime.now());

  final String? _defaultWord;
  final List<HotWord> _hotWords;
  final List<DiscoveryWord> _discovery;
  final List<SearchSuggestion> Function(String term)? _suggest;
  final List<SearchVideo> _videos;
  final List<SearchUser> _users;
  final int pageSize;
  _Demo? _demo;

  final calls = <String>[];

  /// What each `videos` call was given, in order.
  final videoFilters = <SearchFilters>[];

  /// Each `videos` call's `asOf`, in order.
  final videoMoments = <DateTime>[];

  /// Methods whose calls wait for [release]: `defaultWord`, `hotWords`, `discovery`, `suggestions`, `videos`,
  /// `users`.
  final held = <String>{};
  final _waiting = <(String, Completer<void>)>[];
  final _failures = <String, List<Object>>{};

  /// The most search calls (`videos` and `users`) out at once so far.
  int maxSearchesOut = 0;

  /// The most `suggestions` calls out at once so far.
  int maxSuggestionsOut = 0;

  /// The most search and `suggestions` calls out at once so far, counted together.
  int maxCallsOut = 0;
  int _searchesOut = 0;
  int _suggestionsOut = 0;

  /// How many held calls are waiting.
  int get waiting => _waiting.length;

  /// Lets the oldest held call (of [method], if given) answer.
  void release([String? method]) {
    final index = _waiting.indexWhere((entry) => method == null || entry.$1 == method);
    if (index < 0) throw StateError('no ${method ?? 'held'} call is waiting');
    _waiting.removeAt(index).$2.complete();
  }

  /// The next call of [method] throws [error], once any hold is released.
  void failNext(String method, [Object error = const BiliError.http(502)]) =>
      _failures.putIfAbsent(method, () => []).add(error);

  @override
  Future<String?> defaultWord() => _answer('defaultWord', 'defaultWord', () => _defaultWord);

  @override
  Future<List<HotWord>> hotWords() => _answer('hotWords', 'hotWords', () => _hotWords);

  var _discoveryAsked = 0;

  @override
  Future<List<DiscoveryWord>> discovery() =>
      _answer('discovery', 'discovery', () => _demo?.discovery(_discoveryAsked++) ?? _discovery);

  @override
  Future<List<SearchSuggestion>> suggestions(String term) =>
      _answer('suggestions', 'suggestions $term', () => _suggest?.call(term) ?? const []);

  @override
  Future<SearchPage<SearchVideo>> videos(
    String keyword, {
    required int page,
    required SearchFilters filters,
    required DateTime asOf,
  }) {
    videoFilters.add(filters);
    videoMoments.add(asOf);
    return _answer(
      'videos',
      'videos $keyword $page',
      () => _page(_demo?.videos(keyword, filters, asOf) ?? _videos, page),
    );
  }

  @override
  Future<SearchPage<SearchUser>> users(String keyword, {required int page}) =>
      _answer('users', 'users $keyword $page', () => _page(_demo?.users(keyword) ?? _users, page));

  Future<T> _answer<T>(String method, String call, T Function() answer) async {
    calls.add(call);
    final search = method == 'videos' || method == 'users';
    final suggestion = method == 'suggestions';
    if (search) maxSearchesOut = max(maxSearchesOut, ++_searchesOut);
    if (suggestion) maxSuggestionsOut = max(maxSuggestionsOut, ++_suggestionsOut);
    maxCallsOut = max(maxCallsOut, _searchesOut + _suggestionsOut);
    try {
      if (held.contains(method)) {
        final gate = Completer<void>();
        _waiting.add((method, gate));
        await gate.future;
      }
      final failures = _failures[method];
      if (failures != null && failures.isNotEmpty) throw failures.removeAt(0);
      return answer();
    } finally {
      if (search) _searchesOut--;
      if (suggestion) _suggestionsOut--;
    }
  }

  SearchPage<T> _page<T>(List<T> rows, int page) {
    final pages = rows.isEmpty ? 1 : (rows.length + pageSize - 1) ~/ pageSize;
    final start = (page - 1) * pageSize;
    final items = start >= rows.length ? <T>[] : rows.sublist(start, (start + pageSize).clamp(0, rows.length));
    return SearchPage(items: items, page: page, pages: pages);
  }
}

/// The demo's made-up words, videos and uploaders. Ids are small and BV ids a character too long, so none is real;
/// covers and avatars are empty and the badges' pictures are on a host that never answers, so nothing is fetched.
final class _Demo {
  _Demo(this.now);

  final DateTime now;

  static const defaultWord = '雨后山间的清晨';

  static const _hot = 'https://example.invalid/bfs/search/hot.png';
  static const _new = 'https://example.invalid/bfs/search/new.png';

  static const hotWords = [
    HotWord(keyword: '雨后山间的清晨', showName: '雨后山间的清晨', icon: _hot),
    HotWord(keyword: '十分钟家常菜挑战', showName: '十分钟家常菜挑战', icon: _hot),
    HotWord(keyword: '旧电脑改造家庭影院', showName: '旧电脑改造家庭影院', icon: _new),
    HotWord(keyword: '周末骑行一百公里', showName: '周末骑行一百公里'),
    HotWord(keyword: '像素画入门', showName: '像素画入门', icon: _new),
    HotWord(keyword: '手冲咖啡水温', showName: '手冲咖啡的水温到底多少度'),
    HotWord(keyword: '露营装备清单', showName: '露营装备清单', icon: _hot),
    HotWord(keyword: '纸模型城市', showName: '纸模型城市', icon: _new),
    HotWord(keyword: '钢琴即兴伴奏', showName: '钢琴即兴伴奏'),
    HotWord(keyword: '机械键盘调音', showName: '机械键盘调音', icon: _new),
  ];

  static const _discoveryWords = [
    '城市夜景延时',
    '家常菜',
    '白噪音',
    '多肉养护',
    '旧物改造',
    '手账排版',
    '骑行路线',
    '咖啡拉花',
    '像素动画',
    '纸模型',
    '即兴伴奏',
    '键盘轴体',
    '露营做饭',
    '收纳技巧',
    '胶片相机',
    '口琴入门',
    '水彩风景',
    '折纸教程',
    '桌面布置',
    '登山路线',
  ];

  /// Twelve words, six further on at every ↻.
  List<DiscoveryWord> discovery(int asked) =>
      [for (var i = 0; i < 12; i++) _discoveryWords[(asked * 6 + i) % _discoveryWords.length]]
          .map((word) => DiscoveryWord(keyword: word, showName: word))
          .toList();

  static const _suggestionShapes = [
    ('', '教程'),
    ('', '合集'),
    ('', '是什么'),
    ('', '推荐'),
    ('', ' 4K'),
    ('如何', ''),
    ('', '入门'),
    ('', '名场面'),
    ('', '测评'),
    ('', '日常'),
  ];

  static List<SearchSuggestion> suggestions(String term) => [
    for (final (before, after) in _suggestionShapes)
      SearchSuggestion(keyword: '$before$term$after', text: _marked(before, term, after)),
  ];

  static HighlightedText _marked(String before, String term, String after) => HighlightedText([
    if (before.isNotEmpty) HighlightRun(before),
    HighlightRun(term, highlighted: true),
    if (after.isNotEmpty) HighlightRun(after),
  ]);

  static const _titleShapes = [
    ('一口气看完', '的全部玩法'),
    ('【4K】', '，雨后的清晨'),
    ('', '入门教程：从零开始的第一课'),
    ('三分钟带你了解', ''),
    ('我花了一年时间研究', ''),
    ('', '合集（持续更新）'),
    ('关于', '，你可能不知道的十件事'),
    ('', '实测：到底值不值'),
    ('新手也能学会的', ''),
    ('周末和朋友一起', '是什么体验'),
    ('', '的正确打开方式'),
    ('全站最详细的', '攻略'),
    ('用一台旧电脑做', ''),
    ('', '日常vlog'),
    ('深夜', '，白噪音放松向'),
  ];

  static const _parts = ['', '（第二期）', '（完整版）'];

  static const _authors = [
    '夜景摄影师',
    '一年一更',
    '厨房小白',
    '山间录音',
    '折腾实验室',
    '周末骑行',
    '像素小屋',
    '手冲研究所',
    '露营的阿伟',
    '纸模工坊',
    '琴房日记',
    '键盘调音师',
  ];

  /// Under 10 minutes, 10-30, 30-60, 60-120 and over 120, so every 内容时长 has rows.
  static const _durations = [95, 645, 1268, 2105, 3720, 5480, 8100, 312, 7260];

  /// About 45 videos with [keyword] in every title, as the search marks it, then 筛选 as the video search applies it:
  /// 内容时长 only to its buckets (over 60 minutes is one), so 60-120 and 120+ are cut by the model; 发布时间 back
  /// from [asOf].
  List<SearchVideo> videos(String keyword, SearchFilters filters, DateTime asOf) {
    final within = filters.published.within;
    final since = within == null ? null : asOf.subtract(within);
    final rows = [for (var i = 0; i < 45; i++) _video(i, keyword)]
        .where(
          (video) =>
              _inBucket(filters.length.duration, video.duration) &&
              (since == null || !video.published!.isBefore(since)),
        )
        .toList();
    switch (filters.order) {
      case FilterOrder.relevance:
        break;
      case FilterOrder.newest:
        rows.sort((a, b) => b.published!.compareTo(a.published!));
      case FilterOrder.plays:
        rows.sort((a, b) => b.play.compareTo(a.play));
      case FilterOrder.danmaku:
        rows.sort((a, b) => b.danmaku.compareTo(a.danmaku));
    }
    return rows;
  }

  SearchVideo _video(int i, String keyword) {
    final (before, after) = _titleShapes[i % _titleShapes.length];
    final play = 1200 + (i * 7919 % 9973) * 137;
    return SearchVideo(
      aid: 9400 + i,
      bvid: 'BV1Find${i.toString().padLeft(2, '0')}x7h7',
      title: _marked(before, keyword, '$after${_parts[i ~/ _titleShapes.length % _parts.length]}'),
      author: _authors[i % _authors.length],
      mid: 4100 + i % _authors.length,
      cover: '',
      play: play,
      danmaku: play ~/ (35 + i % 40),
      duration: _durations[i % _durations.length],
      published: now.subtract(Duration(hours: 1 + 3 * i * i)),
    );
  }

  static bool _inBucket(SearchDuration bucket, int seconds) => switch (bucket) {
    SearchDuration.any => true,
    SearchDuration.under10 => seconds < 600,
    SearchDuration.from10to30 => seconds >= 600 && seconds < 1800,
    SearchDuration.from30to60 => seconds >= 1800 && seconds < 3600,
    SearchDuration.over60 => seconds >= 3600,
  };

  static const _nameShapes = [
    ('', '研究所'),
    ('小', ''),
    ('', '日常'),
    ('爱', '的阿伟'),
    ('', '官方'),
    ('', '_Official'),
    ('今天也在', ''),
    ('', '同好会'),
    ('', '观察员'),
    ('一只', ''),
    ('', '小剧场'),
    ('', '实验室'),
    ('', '酱'),
    ('', '整理君'),
    ('', '不打烊'),
    ('', '字幕组'),
    ('', '画画中'),
    ('慢慢', ''),
    ('', '的一天'),
    ('', '情报站'),
    ('', '2333'),
    ('', '旅行社'),
    ('', '练习生'),
    ('隔壁', ''),
    ('', '杂货铺'),
  ];

  static const _fans = [2386000, 856000, 124500, 45210, 9870, 3210, 870, 96, 12];

  static const _signs = ['每周更新，欢迎关注', '这个人很懒，什么都没有写', '商务合作请私信', '记录生活，分享快乐', ''];

  /// 25 uploaders named around [keyword], at every level, a few verified as a person or an organisation and two
  /// already followed.
  List<SearchUser> users(String keyword) => [
    for (var i = 0; i < _nameShapes.length; i++)
      SearchUser(
        mid: 4200 + i,
        name: '${_nameShapes[i].$1}$keyword${_nameShapes[i].$2}',
        face: '',
        fans: _fans[i % _fans.length] + i * 13,
        videos: i * 37 % 600 + 1,
        level: i % 6 + 1,
        sign: _signs[i % _signs.length],
        officialType: i % 7 == 0 ? 0 : (i % 11 == 5 ? 1 : null),
        officialDesc: i % 7 == 0 ? '知识区创作者（演示）' : (i % 11 == 5 ? '演示机构账号' : ''),
        following: i == 2 || i == 9,
      ),
  ];
}
