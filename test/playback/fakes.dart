import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:flutter/widgets.dart';

import '../support/fake_player.dart';

/// Answers from fixed routes; nothing ever reaches the network.
final class CannedHttp implements HTTPTransport {
  /// Keyed by path.
  final Map<String, (int, String)> routes = {};

  /// Byte-exact bodies (protobuf); checked before [routes].
  final Map<String, (int, Uint8List)> dataRoutes = {};
  final List<HTTPRequest> requests = [];

  /// Completes a request only when the test says so, keyed by path.
  final Map<String, Completer<void>> gates = {};

  /// Thrown instead of answering (a timeout, a lost connection), keyed by path.
  final Map<String, Object> errors = {};

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    requests.add(request);
    final path = request.url.path;
    await gates[path]?.future;
    final error = errors[path];
    if (error != null) throw error;
    final data = dataRoutes[path];
    if (data != null) return HTTPResponse(status: data.$1, headers: {}, body: data.$2, finalURL: request.url);
    final route = routes[path];
    if (route == null) return HTTPResponse(status: 404, headers: {}, body: Uint8List(0), finalURL: request.url);
    return HTTPResponse(status: route.$1, headers: {}, body: utf8.encode(route.$2), finalURL: request.url);
  }

  List<HTTPRequest> to(String path) => requests.where((request) => request.url.path == path).toList();

  List<String> get paths => [for (final request in requests) request.url.path];
}

final class FakeEngine implements PlaybackEngine {
  final prepared = <PlaybackRequest>[];
  final released = <String>[];
  final replaced = <({String token, TrackKind track, String primary, List<String> backups})>[];

  /// Thrown by the next prepares, in order.
  final prepareErrors = <Object>[];
  bool restartOnEnsure = false;
  int ensureCalls = 0;

  /// Thrown by every ensureServing while set.
  Object? ensureError;

  /// As IsolatePlaybackEngine once its isolate exited: every call fails with RipperError(closed).
  bool closed = false;

  /// Holds prepares until the test completes it.
  Completer<void>? prepareGate;
  String? sourceEntry = 'hvc1';
  bool rewroteHEV1 = false;
  bool disposed = false;
  final statsController = StreamController<EngineSnapshot>.broadcast(sync: true);
  final fatalController = StreamController<FatalReport>.broadcast(sync: true);
  final playheads = <({String token, double seconds, double rate})>[];
  final buffers = <({String token, double aheadSeconds, bool playing})>[];
  final stalls = <String>[];
  final hints = <({String token, double? seconds})>[];
  final preconnects = <List<String>>[];
  int cacheDrops = 0;
  int _next = 0;

  static Uri masterOf(String token) => Uri.parse('http://127.0.0.1:5555/$token/master.m3u8');

  @override
  Future<PreparedSource> prepare(PlaybackRequest request) async {
    prepared.add(request);
    await prepareGate?.future;
    if (closed) throw const RipperError(RipperErrorKind.closed);
    if (prepareErrors.isNotEmpty) throw prepareErrors.removeAt(0);
    final token = 'tok${++_next}';
    final direct = request.mode == PlaybackMode.direct;
    return PreparedSource(
      token: token,
      master: masterOf(token),
      video: direct ? Uri.parse(request.choice.video.baseURL) : Uri.parse('http://127.0.0.1:5555/$token/v.mp4'),
      audio: direct ? Uri.parse(request.choice.audio.baseURL) : Uri.parse('http://127.0.0.1:5555/$token/a.mp4'),
      mode: request.mode,
      rewroteHEV1: rewroteHEV1,
      sourceEntry: sourceEntry,
      mediaHeaders: direct ? request.mediaHeaders : const {},
    );
  }

  @override
  Future<void> release(String token) async => released.add(token);

  @override
  Future<void> replaceUrls(String token, TrackKind track, {required String primary, required List<String> backups}) async =>
      replaced.add((token: token, track: track, primary: primary, backups: backups));

  @override
  Future<void> networkChanged({required bool interfaceChanged}) async {}

  @override
  void updatePlayhead(String token, {required double seconds, required double rate}) =>
      playheads.add((token: token, seconds: seconds, rate: rate));

  @override
  void reportBuffer(String token, {required double aheadSeconds, required bool playing}) =>
      buffers.add((token: token, aheadSeconds: aheadSeconds, playing: playing));

  @override
  void reportStall(String token) => stalls.add(token);

  @override
  void dropCache() => cacheDrops += 1;

  @override
  void hint(String token, double? seconds) => hints.add((token: token, seconds: seconds));

  @override
  void preconnect(List<String> urls) => preconnects.add(urls);

  @override
  Stream<FatalReport> get fatals => fatalController.stream;

  @override
  Future<bool> ensureServing() async {
    ensureCalls += 1;
    if (closed) throw const RipperError(RipperErrorKind.closed);
    final error = ensureError;
    if (error != null) throw error;
    final restarted = restartOnEnsure;
    restartOnEnsure = false;
    return restarted;
  }

  @override
  Stream<EngineSnapshot> get stats => statsController.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await statsController.close();
    await fatalController.close();
  }
}

/// [inner] with the calls named in [refused] failing, as a platform player's can: `seek`, `rate`, `fit`, `mirrored`
/// and `pip`. Everything else, events included, is [inner]'s.
final class RefusingPlayer implements BiliPlayer {
  RefusingPlayer(this.inner, [Set<String>? refused]) : refused = refused ?? {};

  final FakePlayer inner;
  final Set<String> refused;

  Future<void> _call(String name, Future<void> Function() call) async {
    if (refused.contains(name)) throw StateError('$name refused');
    await call();
  }

  @override
  PlayerCapabilities get capabilities => inner.capabilities;

  @override
  Stream<PlayerEvent> get events => inner.events;

  @override
  Widget buildView() => inner.buildView();

  @override
  Future<void> load(PlayerSource source) => inner.load(source);

  @override
  Future<void> unload() => inner.unload();

  @override
  Future<void> play() => inner.play();

  @override
  Future<void> pause() => inner.pause();

  @override
  Future<void> seek(double seconds, {bool precise = false}) =>
      _call('seek', () => inner.seek(seconds, precise: precise));

  @override
  Future<void> setRate(double rate) => _call('rate', () => inner.setRate(rate));

  @override
  Future<void> setMuted(bool muted) => inner.setMuted(muted);

  @override
  bool get muted => inner.muted;

  @override
  Future<void> setKeepAwake(bool on) => inner.setKeepAwake(on);

  @override
  Future<void> setFit(FitMode fit) => _call('fit', () => inner.setFit(fit));

  @override
  Future<void> setMirrored(bool mirrored) => _call('mirrored', () => inner.setMirrored(mirrored));

  @override
  Future<void> startPictureInPicture() => _call('pip', inner.startPictureInPicture);

  @override
  Future<void> stopPictureInPicture() => inner.stopPictureInPicture();

  @override
  Future<void> setAutoPictureInPicture(bool enabled) => inner.setAutoPictureInPicture(enabled);

  @override
  Future<bool> captureFrame() => inner.captureFrame();

  @override
  Future<void> dispose() => inner.dispose();
}

final class FakeTimer implements Timer {
  FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// Records the timers a controller starts; a test fires them by hand.
final class FakeTimers {
  final all = <FakeTimer>[];

  Timer start(Duration delay, void Function() callback) {
    final timer = FakeTimer(delay, callback);
    all.add(timer);
    return timer;
  }

  List<FakeTimer> get active => all.where((timer) => timer.isActive).toList();

  FakeTimer? activeWith(Duration delay) => active.where((timer) => timer.delay == delay).lastOrNull;
}

/// Lets queued microtasks and zero-length timers run.
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A protobuf `DmSegMobileReply` with plain scrolling danmaku at the given milliseconds.
Uint8List danmakuSegmentBytes(List<(int ms, String text)> items, {bool closed = false}) {
  final out = BytesBuilder();
  void varint(int value) {
    var v = value;
    while (v >= 0x80) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  for (final (ms, text) in items) {
    final elem = BytesBuilder();
    void elemVarint(int field, int value) {
      elem.addByte(field << 3);
      var v = value;
      while (v >= 0x80) {
        elem.addByte((v & 0x7F) | 0x80);
        v >>= 7;
      }
      elem.addByte(v);
    }

    elemVarint(2, ms);
    elemVarint(3, 1);
    elemVarint(4, 25);
    elemVarint(5, 0xFFFFFF);
    final content = utf8.encode(text);
    elem.addByte(7 << 3 | 2);
    elem.addByte(content.length);
    elem.add(content);
    final bytes = elem.toBytes();
    out.addByte(1 << 3 | 2);
    varint(bytes.length);
    out.add(bytes);
  }
  if (closed) {
    out.addByte(2 << 3);
    varint(1);
  }
  return out.toBytes();
}

abstract final class Canned {
  static const navPath = '/x/web-interface/nav';
  static const viewPath = '/x/web-interface/view';
  static const playUrlPath = '/x/player/wbi/playurl';
  static const signedViewPath = '/x/web-interface/wbi/view';
  static const segmentPath = '/x/v2/dm/web/seg.so';

  /// The signed URLs' `deadline`.
  static const deadline = 1760000000;

  static const navLoggedIn = r'''
{"code":0,"message":"0","ttl":1,"data":{"isLogin":true,"mid":12345,"uname":"测试用户","face":"https://i0.hdslb.com/bfs/face/test.jpg","vipStatus":1,"vipType":2,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}''';

  static const navLoggedOut = r'''
{"code":-101,"message":"账号未登录","ttl":1,"data":{"isLogin":false,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}''';

  static const view = r'''
{"code":0,"message":"0","ttl":1,"data":{"bvid":"BV1GJ411x7h7","aid":80433022,"title":"测试视频","owner":{"mid":1,"name":"UP主"},"pages":[{"cid":137649199,"page":1,"part":"第一集","duration":712},{"cid":137649200,"page":2,"part":"第二集","duration":100}]}}''';

  /// 4K in HEVC (hev1 label) and AVC, 1080P in AV1, two AAC tracks; every URL signed until [deadline].
  static String playUrl({String tag = 'a'}) => '''
{"code":0,"message":"0","ttl":1,"data":{"quality":120,"accept_quality":[126,125,120,80],"accept_description":["杜比视界","真彩 HDR","超清 4K","高清 1080P"],
"dash":{"duration":712,
"video":[
{"id":120,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/v/120-hevc.m4s?deadline=$deadline&upsig=$tag","backupUrl":["https://upos-sz-mirrorali.bilivideo.com/v/120-hevc.m4s?deadline=$deadline&upsig=$tag"],"bandwidth":12000000,"mimeType":"video/mp4","codecs":"hev1.1.6.L153.90","width":3840,"height":2160,"frameRate":"29.412","SegmentBase":{"Initialization":"0-1104","indexRange":"1105-1688"},"codecid":12},
{"id":120,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/v/120-avc.m4s?deadline=$deadline&upsig=$tag","backupUrl":[],"bandwidth":15000000,"mimeType":"video/mp4","codecs":"avc1.640034","width":3840,"height":2160,"SegmentBase":{"Initialization":"0-1000","indexRange":"1001-1600"},"codecid":7},
{"id":80,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/v/80-av1.m4s?deadline=$deadline&upsig=$tag","backupUrl":[],"bandwidth":2000000,"mimeType":"video/mp4","codecs":"av01.0.08M.08","width":1920,"height":1080,"SegmentBase":{"Initialization":"0-900","indexRange":"901-1500"},"codecid":13}
],
"audio":[
{"id":30280,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/a/30280.m4s?deadline=$deadline&upsig=$tag","backupUrl":[],"bandwidth":320000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","SegmentBase":{"Initialization":"0-907","indexRange":"908-1491"},"codecid":0}
]}}}''';

  static CannedHttp http({bool loggedIn = true}) => CannedHttp()
    ..routes[navPath] = (200, loggedIn ? navLoggedIn : navLoggedOut)
    ..routes[viewPath] = (200, view)
    ..routes[signedViewPath] = (200, view)
    ..routes[playUrlPath] = (200, playUrl())
    ..dataRoutes[segmentPath] = (200, danmakuSegmentBytes([(1000, '前方高能'), (2000, '来了')]));

  /// Fingerprint cookies already set, so no `spi` call happens.
  static const cookies = {'SESSDATA': 's', 'bili_jct': 'j', 'buvid3': 'b3', 'buvid4': 'b4'};
}
