import 'package:bili_core/api.dart' show BiliClient;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart' show PlaybackEngine;
import 'package:flutter/foundation.dart';

import '../playback/codec_memory.dart';
import 'offline_host.dart';
import 'offline_models.dart';

/// 离线缓存: every part cached on the phone, the queue that fills them, and the space they take. Listeners hear every
/// change, progress included (about once a second while a part downloads).
abstract class OfflineLibrary extends ChangeNotifier {
  /// Newest added first.
  List<OfflineItem> get items;

  OfflineItem? item(int cid);

  /// What every part's files take on the phone.
  int get usedBytes;

  /// What the phone has left; null when unknown (the sheet then writes 剩余 -).
  int? get freeBytes;

  /// 同时缓存数量: how many parts download at once, 1 to 3 (147).
  int get concurrency;
  void setConcurrency(int count);

  /// Something was added or finished since 离线缓存 was last opened: 查看缓存's red dot (141).
  bool get unseen;
  void markSeen();

  /// Reads what is on the phone and resumes unfinished parts. Called once at launch.
  Future<void> start();

  /// Queues [parts] at the highest quality the account gets ([quality] null) or the best at or below [quality].
  /// Parts already in the library are left as they are.
  Future<void> enqueue(List<OfflineRequest> parts, {int? quality});

  void pause(int cid);
  void resume(int cid);

  /// 全部暂停 and 全部开始 (146, 148).
  void pauseAll();
  void startAll();

  /// Stops and removes the parts, files and all.
  Future<void> delete(Iterable<int> cids);

  /// Where playback of [cid] stopped, for the cover's progress (145).
  void savePosition(int cid, double seconds);

  /// The files of a finished part; null while it isn't finished or its files are gone.
  Future<OfflinePlayback?> playback(int cid);

  /// Asks the phone for its free space again.
  Future<void> refreshFreeSpace();
}

/// The library as the app runs it: files in the support folder's `offline`, downloads through the engine while the
/// app is open and through iOS's background transfers once it isn't.
class DiskOfflineLibrary extends OfflineLibrary {
  DiskOfflineLibrary({
    required this.folder,
    required this.client,
    required this.engine,
    required this.host,
    this.codecMemory,
    Logger? logger,
  }) : logger = logger ?? Logger.shared;

  /// Absolute, looked up this launch; everything kept inside it is named relative to it.
  final String folder;
  final BiliClient Function() client;

  /// A lease on the app's shared engine; the library keeps it and asks again once the engine is gone.
  final Future<PlaybackEngine> Function() engine;
  final OfflineHost host;
  final CodecMemory? codecMemory;
  final Logger logger;

  @override
  List<OfflineItem> get items => const [];

  @override
  OfflineItem? item(int cid) => null;

  @override
  int get usedBytes => 0;

  @override
  int? get freeBytes => null;

  @override
  int get concurrency => 1;

  @override
  void setConcurrency(int count) {}

  @override
  bool get unseen => false;

  @override
  void markSeen() {}

  @override
  Future<void> start() async {}

  @override
  Future<void> enqueue(List<OfflineRequest> parts, {int? quality}) async {}

  @override
  void pause(int cid) {}

  @override
  void resume(int cid) {}

  @override
  void pauseAll() {}

  @override
  void startAll() {}

  @override
  Future<void> delete(Iterable<int> cids) async {}

  @override
  void savePosition(int cid, double seconds) {}

  @override
  Future<OfflinePlayback?> playback(int cid) async => null;

  @override
  Future<void> refreshFreeSpace() async {}
}
