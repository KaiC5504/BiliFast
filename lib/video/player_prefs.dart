import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart' show VideoCodec;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart' show NodeMode;

import '../player/bili_player.dart';
import 'player_session.dart';

/// 设置's CDN 节点 (Swift `AppSettings.NodeChoice`).
enum NodeChoice {
  overseas('海外节点'),
  mainland('大陆节点');

  const NodeChoice(this.label);

  final String label;

  NodeMode get mode => this == overseas ? NodeMode.overseas : NodeMode.mainland;
}

/// 首页自动播放 (179) and 动态视频是否自动播放 (178): when a list's video plays by itself. 免流 can't be told from
/// mobile data, so [wifiOnly] plays on Wi-Fi alone.
enum AutoplayChoice { always, wifiOnly, off }

/// The player settings Swift's AppSettings kept in UserDefaults (自动连播, 循环播放, 画面尺寸, BTR 加速, CDN 节点,
/// 显示统计, the quality and codec asked for, and danmaku on or off), as a small JSON file in the support folder.
class PlayerPrefs {
  PlayerPrefs._(this._path, Map<String, Object?> values, this._logger) {
    _read(values);
  }

  /// Kept in memory only, for tests and for platforms without a support folder.
  factory PlayerPrefs.memory({Logger? logger}) => PlayerPrefs._(null, const {}, logger ?? Logger.shared);

  /// What the video page's sessions read; the app puts the loaded file here at launch, and until then it holds the
  /// defaults in memory.
  static PlayerPrefs shared = PlayerPrefs.memory();

  /// [path] null keeps the settings in memory. A file that can't be read is set aside as `.bad` and the defaults
  /// apply; a value of the wrong type falls back to its default alone, logged by its key (never its value).
  static Future<PlayerPrefs> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return PlayerPrefs._(null, const {}, log);
    final file = File(path);
    if (!await file.exists()) return PlayerPrefs._(path, const {}, log);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      return PlayerPrefs._(path, json, log);
    } catch (error) {
      log.warn(LogCategory.app, 'player prefs unreadable, using defaults', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'player prefs not set aside', {'error': _reason(error)});
    }
    return PlayerPrefs._(path, const {}, log);
  }

  final String? _path;
  final Logger _logger;
  Future<void> _writing = Future.value();

  bool _autoplay = true;
  LoopMode _loop = LoopMode.off;
  FitMode _fit = FitMode.fit;
  bool _btr = true;
  NodeChoice _node = NodeChoice.overseas;
  bool _showStats = false;
  bool _danmakuOn = true;
  bool _coinAlsoLike = true;
  bool _danmakuStyleHintSeen = false;
  bool _turnTakeover = true;
  int? _quality;
  VideoCodec? _codec;
  bool _cellularAutoplay = true;
  bool _detailAutoplay = true;
  bool _detailFullScreen = false;
  AutoplayChoice _homeAutoplay = AutoplayChoice.always;
  AutoplayChoice _listAutoplay = AutoplayChoice.always;
  bool _bigCardSound = false;
  bool _verticalFullScreen = true;
  bool _autoPip = true;
  bool _backgroundListen = true;
  bool _backgroundNext = true;

  bool get autoplay => _autoplay;
  set autoplay(bool value) => _set(() => _autoplay = value);

  LoopMode get loop => _loop;
  set loop(LoopMode value) => _set(() => _loop = value);

  FitMode get fit => _fit;
  set fit(FitMode value) => _set(() => _fit = value);

  bool get btr => _btr;
  set btr(bool value) => _set(() => _btr = value);

  NodeChoice get node => _node;
  set node(NodeChoice value) => _set(() => _node = value);

  bool get showStats => _showStats;
  set showStats(bool value) => _set(() => _showStats = value);

  bool get danmakuOn => _danmakuOn;
  set danmakuOn(bool value) => _set(() => _danmakuOn = value);

  /// The coin dialog's 同时点赞内容.
  bool get coinAlsoLike => _coinAlsoLike;
  set coinAlsoLike(bool value) => _set(() => _coinAlsoLike = value);

  /// The send bar's A has been pressed once, so its red dot is gone for good.
  bool get danmakuStyleHintSeen => _danmakuStyleHintSeen;
  set danmakuStyleHintSeen(bool value) => _set(() => _danmakuStyleHintSeen = value);

  /// 开发者's 旋转动画: turns drawn by Flutter (自绘) rather than animated by iOS (系统).
  bool get turnTakeover => _turnTakeover;
  set turnTakeover(bool value) => _set(() => _turnTakeover = value);

  /// Null until the user picks one: the controller's own default applies.
  int? get quality => _quality;
  set quality(int? value) => _set(() => _quality = value);

  VideoCodec? get codec => _codec;
  set codec(VideoCodec? value) => _set(() => _codec = value);

  /// 自动播放设置 (172)'s 流量网络下自动播放: off, nothing from the network plays by itself on mobile data, the video
  /// page included; a cached video still follows 详情页直接播放.
  bool get cellularAutoplay => _cellularAutoplay;
  set cellularAutoplay(bool value) => _set(() => _cellularAutoplay = value);

  /// 详情页直接播放: a video page opened plays at once; off, it opens paused.
  bool get detailAutoplay => _detailAutoplay;
  set detailAutoplay(bool value) => _set(() => _detailAutoplay = value);

  /// 详情页直接全屏播放: a video page opened goes straight to full screen.
  bool get detailFullScreen => _detailFullScreen;
  set detailFullScreen(bool value) => _set(() => _detailFullScreen = value);

  /// 推荐's big card.
  AutoplayChoice get homeAutoplay => _homeAutoplay;
  set homeAutoplay(AutoplayChoice value) => _set(() => _homeAutoplay = value);

  /// 动态's video cards and every other list's.
  AutoplayChoice get listAutoplay => _listAutoplay;
  set listAutoplay(AutoplayChoice value) => _set(() => _listAutoplay = value);

  /// 首页推荐设置's 大卡默认声音 (170): the big cards start with sound; read at launch (重启后生效).
  bool get bigCardSound => _bigCardSound;
  set bigCardSound(bool value) => _set(() => _bigCardSound = value);

  /// 竖屏模式设置 (173)'s 竖屏视频全屏用竖屏模式播放: off, an upright video's full screen is the ordinary landscape one,
  /// pillarboxed, as on the iPad.
  bool get verticalFullScreen => _verticalFullScreen;
  set verticalFullScreen(bool value) => _set(() => _verticalFullScreen = value);

  /// 应用外自动小窗播放 (174): leaving the app while a video plays starts the small window.
  bool get autoPip => _autoPip;
  set autoPip(bool value) => _set(() => _autoPip = value);

  /// 后台听视频 (174, and ⋮'s row): a video keeps playing with the screen locked or the app in the background.
  bool get backgroundListen => _backgroundListen;
  set backgroundListen(bool value) => _set(() => _backgroundListen = value);

  /// With 后台听视频 on, a video that ends in the background opens the next one and plays it (174's
  /// 后台听视频时，自动连播相关视频).
  bool get backgroundNext => _backgroundNext;
  set backgroundNext(bool value) => _set(() => _backgroundNext = value);

  void _read(Map<String, Object?> values) {
    void ignored(String key) => _logger.warn(LogCategory.app, 'player prefs value ignored', {'key': key});
    T? pick<T>(String key) {
      final value = values[key];
      if (value is T) return value;
      if (value != null) ignored(key);
      return null;
    }

    E? named<E extends Enum>(String key, List<E> all) {
      final name = pick<String>(key);
      if (name == null) return null;
      final match = all.where((value) => value.name == name).firstOrNull;
      if (match == null) ignored(key);
      return match;
    }

    _autoplay = pick<bool>('autoplay') ?? _autoplay;
    _loop = named('loop', LoopMode.values) ?? _loop;
    _fit = named('fit', FitMode.values) ?? _fit;
    _btr = pick<bool>('btr') ?? _btr;
    _node = named('node', NodeChoice.values) ?? _node;
    _showStats = pick<bool>('showStats') ?? _showStats;
    _danmakuOn = pick<bool>('danmakuOn') ?? _danmakuOn;
    _coinAlsoLike = pick<bool>('coinAlsoLike') ?? _coinAlsoLike;
    _danmakuStyleHintSeen = pick<bool>('danmakuStyleHintSeen') ?? _danmakuStyleHintSeen;
    // A 1.0.0 (13) or (14) file holds a turnMethod instead, where every method but 系统 draws the turn; the next
    // write drops it and its turnPicture and turnSpinStart.
    _turnTakeover = pick<bool>('turnTakeover') ?? values['turnMethod'] != 'system';
    _quality = pick<int>('quality');
    _codec = named('codec', VideoCodec.values);
    _cellularAutoplay = pick<bool>('cellularAutoplay') ?? _cellularAutoplay;
    _detailAutoplay = pick<bool>('detailAutoplay') ?? _detailAutoplay;
    _detailFullScreen = pick<bool>('detailFullScreen') ?? _detailFullScreen;
    _homeAutoplay = named('homeAutoplay', AutoplayChoice.values) ?? _homeAutoplay;
    _listAutoplay = named('listAutoplay', AutoplayChoice.values) ?? _listAutoplay;
    _bigCardSound = pick<bool>('bigCardSound') ?? _bigCardSound;
    _verticalFullScreen = pick<bool>('verticalFullScreen') ?? _verticalFullScreen;
    _autoPip = pick<bool>('autoPip') ?? _autoPip;
    _backgroundListen = pick<bool>('backgroundListen') ?? _backgroundListen;
    _backgroundNext = pick<bool>('backgroundNext') ?? _backgroundNext;
  }

  Map<String, Object?> toJson() => {
    'autoplay': _autoplay,
    'loop': _loop.name,
    'fit': _fit.name,
    'btr': _btr,
    if (_node != NodeChoice.overseas) 'node': _node.name,
    'showStats': _showStats,
    'danmakuOn': _danmakuOn,
    'coinAlsoLike': _coinAlsoLike,
    if (_danmakuStyleHintSeen) 'danmakuStyleHintSeen': true,
    if (!_turnTakeover) 'turnTakeover': false,
    'quality': ?_quality,
    'codec': ?_codec?.name,
    if (!_cellularAutoplay) 'cellularAutoplay': false,
    if (!_detailAutoplay) 'detailAutoplay': false,
    if (_detailFullScreen) 'detailFullScreen': true,
    if (_homeAutoplay != AutoplayChoice.always) 'homeAutoplay': _homeAutoplay.name,
    if (_listAutoplay != AutoplayChoice.always) 'listAutoplay': _listAutoplay.name,
    if (_bigCardSound) 'bigCardSound': true,
    if (!_verticalFullScreen) 'verticalFullScreen': false,
    if (!_autoPip) 'autoPip': false,
    if (!_backgroundListen) 'backgroundListen': false,
    if (!_backgroundNext) 'backgroundNext': false,
  };

  void _set(void Function() change) {
    change();
    final path = _path;
    if (path == null) return;
    final text = jsonEncode(toJson());
    // One write after another, so an older state never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'player prefs not saved', {'error': _reason(error)});
    }
  }

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}
