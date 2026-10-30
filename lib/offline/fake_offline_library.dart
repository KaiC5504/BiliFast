import 'package:bili_core/api.dart' show DashStream;
import 'package:bili_core/engine.dart' show LocalPlaybackRequest;
import 'package:bili_core/shared.dart' show ByteRange;

import 'offline_library.dart';
import 'offline_models.dart';

/// A library held in memory, for tests and `--fake-account`: [enqueue] adds parts as 等待缓存 and nothing downloads
/// until a test moves them with [put]. [demo] is a finished 合集, one single video and one part downloading.
class FakeOfflineLibrary extends OfflineLibrary {
  FakeOfflineLibrary({List<OfflineItem> items = const [], this.free = 74400000000, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    for (final item in items) {
      _items[item.cid] = item;
    }
  }

  factory FakeOfflineLibrary.demo() {
    final added = DateTime(2026, 10, 30, 17, 10);
    const collection = OfflineCollection(id: 4001, title: '星铁');
    OfflineRequest request(int index, String title, int duration, {OfflineCollection? collection}) => OfflineRequest(
      bvid: 'BV1fake0000$index',
      aid: 9000 + index,
      cid: 7000 + index,
      title: title,
      duration: duration,
      cover: '',
      ownerMid: 100 + index,
      ownerName: collection == null ? '火播君' : '问寒不留白',
      collection: collection,
    );
    return FakeOfflineLibrary(
      items: [
        OfflineItem(
          request: request(1, '终末命途前置解读！各体系大补强时代，老东西终于要站起来了？', 411, collection: collection),
          state: OfflineState.done,
          addedAt: added,
          quality: 116,
          qualityName: '1080P 60帧',
          vipOnly: true,
          bytes: 78643200,
          totalBytes: 78643200,
        ),
        OfflineItem(
          request: request(2, '真珠虚照怎么抽？直接读评论区问题，放心对号入座', 219, collection: collection),
          state: OfflineState.done,
          addedAt: added.add(const Duration(minutes: 1)),
          quality: 116,
          qualityName: '1080P 60帧',
          vipOnly: true,
          bytes: 10066329,
          totalBytes: 10066329,
          position: 3,
        ),
        OfflineItem(
          request: request(3, '神枪看小羊崽复播：你看这次她真的自己打的，她表情会动', 383),
          state: OfflineState.done,
          addedAt: added.add(const Duration(minutes: 2)),
          quality: 80,
          qualityName: '1080P 高清',
          bytes: 82208358,
          totalBytes: 82208358,
          position: 23,
        ),
        OfflineItem(
          request: request(4, '只能靠法大王对抗深渊吗？不妨把视野投向群星', 512),
          state: OfflineState.downloading,
          addedAt: added.add(const Duration(minutes: 3)),
          quality: 80,
          qualityName: '1080P 高清',
          bytes: 15728640,
          totalBytes: 134846054,
          bps: 2400000,
        ),
      ],
    );
  }

  final DateTime Function() _now;
  final _items = <int, OfflineItem>{};

  int? free;
  int _concurrency = 1;
  bool _unseen = false;
  bool started = false;
  final enqueued = <({List<OfflineRequest> parts, int? quality})>[];
  final deleted = <int>[];

  /// Adds or replaces an item, as a download's progress would.
  void put(OfflineItem item) {
    _items[item.cid] = item;
    notifyListeners();
  }

  @override
  List<OfflineItem> get items => _items.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  @override
  OfflineItem? item(int cid) => _items[cid];

  @override
  int get usedBytes => _items.values.fold(0, (sum, item) => sum + item.bytes);

  @override
  int? get freeBytes => free;

  @override
  int get concurrency => _concurrency;

  @override
  void setConcurrency(int count) {
    _concurrency = count.clamp(1, 3);
    notifyListeners();
  }

  @override
  bool get unseen => _unseen;

  @override
  void markSeen() {
    if (!_unseen) return;
    _unseen = false;
    notifyListeners();
  }

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> enqueue(List<OfflineRequest> parts, {int? quality}) async {
    enqueued.add((parts: parts, quality: quality));
    for (final part in parts) {
      _items.putIfAbsent(part.cid, () => OfflineItem(request: part, state: OfflineState.waiting, addedAt: _now()));
    }
    _unseen = true;
    notifyListeners();
  }

  void _set(int cid, OfflineState Function(OfflineItem item) state) {
    final item = _items[cid];
    if (item == null || item.isDone) return;
    _items[cid] = item.copyWith(state: state(item), bps: 0, clearFailure: true);
  }

  @override
  void pause(int cid) {
    _set(cid, (_) => OfflineState.paused);
    notifyListeners();
  }

  @override
  void resume(int cid) {
    _set(cid, (_) => OfflineState.waiting);
    notifyListeners();
  }

  @override
  void pauseAll() {
    for (final cid in _items.keys.toList()) {
      _set(cid, (_) => OfflineState.paused);
    }
    notifyListeners();
  }

  @override
  void startAll() {
    for (final cid in _items.keys.toList()) {
      _set(cid, (_) => OfflineState.waiting);
    }
    notifyListeners();
  }

  @override
  Future<void> delete(Iterable<int> cids) async {
    for (final cid in cids) {
      if (_items.remove(cid) != null) deleted.add(cid);
    }
    notifyListeners();
  }

  @override
  void savePosition(int cid, double seconds) {
    final item = _items[cid];
    if (item == null) return;
    _items[cid] = item.copyWith(position: seconds);
    notifyListeners();
  }

  /// A finished part's playback with made-up streams and paths; tests that play give their own engine.
  @override
  Future<OfflinePlayback?> playback(int cid) async {
    final item = _items[cid];
    if (item == null || !item.isDone) return null;
    return OfflinePlayback(
      item: item,
      files: LocalPlaybackRequest(
        video: _stream(item.quality == 0 ? 80 : item.quality, 'avc1.640032', 'video/mp4'),
        audio: _stream(30280, 'mp4a.40.2', 'audio/mp4'),
        videoPath: 'offline/$cid/v.m4s',
        audioPath: 'offline/$cid/a.m4s',
      ),
    );
  }

  static DashStream _stream(int id, String codecs, String mime) => DashStream(
    id: id,
    baseURL: '',
    backupURLs: const [],
    bandwidth: 1000000,
    mimeType: mime,
    codecs: codecs,
    codecid: 7,
    width: mime == 'video/mp4' ? 1920 : 0,
    height: mime == 'video/mp4' ? 1080 : 0,
    frameRate: null,
    initialization: ByteRange(0, 999),
    indexRange: ByteRange(1000, 1999),
  );

  @override
  Future<void> refreshFreeSpace() async {}
}
