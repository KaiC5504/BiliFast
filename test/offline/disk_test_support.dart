import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/offline/offline_host.dart';
import 'package:bilifast/offline/offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

/// The background session as a test drives it: every call recorded, takeBack answering [results] once.
final class FakeOfflineHost implements OfflineHost {
  FakeOfflineHost({this.backgroundTransfers = true});

  @override
  final bool backgroundTransfers;
  int? free = 64000000000;
  final calls = <String>[];
  final handedOff = <List<BackgroundRange>>[];
  List<BackgroundRangeResult> results = [];
  Object? handOffError;
  String? excluded;
  VoidCallback? graceEnding;
  void Function(BackgroundRangeResult result)? rangeFinished;

  @override
  Future<int?> freeBytes() async => free;

  /// What [inBackground] answers, and how often it was asked.
  bool background = false;
  int backgroundAsks = 0;

  @override
  Future<bool> inBackground() async {
    backgroundAsks += 1;
    return background;
  }

  @override
  Future<void> excludeFromBackup(String path) async => excluded = path;

  @override
  Future<void> beginGrace() async => calls.add('beginGrace');

  @override
  Future<void> endGrace() async => calls.add('endGrace');

  @override
  set onGraceEnding(VoidCallback? callback) => graceEnding = callback;

  @override
  Future<void> handOff(List<BackgroundRange> ranges) async {
    calls.add('handOff');
    if (handOffError case final error?) throw error;
    handedOff.add(ranges);
  }

  @override
  Future<List<BackgroundRangeResult>> takeBack() async {
    calls.add('takeBack');
    final taken = results;
    results = [];
    return taken;
  }

  @override
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback) => rangeFinished = callback;
}

const toBackground = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
const toForeground = [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed];

void lifecycle(List<AppLifecycleState> states) {
  for (final state in states) {
    // ignore: invalid_use_of_protected_member
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
  }
}

OfflineRequest offlineRequest({int cid = 137649199, String bvid = 'BV1GJ411x7h7', int duration = 712}) =>
    OfflineRequest(
      bvid: bvid,
      aid: 80433022,
      cid: cid,
      title: '测试视频',
      duration: duration,
      cover: 'http://i0.hdslb.com/bfs/archive/cover$cid.jpg',
      ownerMid: 1,
      ownerName: 'UP主',
      ownerFace: 'https://i1.hdslb.com/bfs/face/face.jpg',
    );

/// One library on a temporary folder, with the canned API, a fake engine and host, and the pictures answered from
/// memory. [reopen] makes another on the same folder, as a relaunch would.
final class Rig {
  Rig({FakeOfflineHost? host, CodecMemory? memory, this.danmakuGap = Duration.zero})
    : host = host ?? FakeOfflineHost(),
      memory = memory ?? CodecMemory(),
      folder = Directory.systemTemp.createTempSync('offline_test').path;

  final String folder;
  final Duration danmakuGap;
  final FakeOfflineHost host;
  final CodecMemory memory;
  final http = Canned.http();
  var engine = FakeEngine();
  final logs = MemorySink();
  final pictureUrls = <Uri>[];
  final libraries = <DiskOfflineLibrary>[];

  /// The signed URLs are good for two more hours.
  DateTime now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 7200) * 1000);

  late final Logger logger = Logger(session: 'test')..add(logs);
  late final BiliClient client = BiliClient(
    transport: http,
    cookies: CookieJar(Canned.cookies),
    now: () => now,
    logger: logger,
  );

  DiskOfflineLibrary make() {
    final library = DiskOfflineLibrary(
      folder: folder,
      client: () => client,
      engine: () async => engine,
      host: host,
      codecMemory: memory,
      logger: logger,
      pictures: (url) async {
        pictureUrls.add(url);
        return Uint8List.fromList(utf8.encode('picture'));
      },
      now: () => now,
      danmakuGap: danmakuGap,
      retryGaps: const [Duration.zero],
    );
    libraries.add(library);
    return library;
  }

  Future<DiskOfflineLibrary> started() async {
    final library = make();
    await library.start();
    await library.settled();
    return library;
  }

  String part(int cid) => '$folder${Platform.pathSeparator}$cid';
  String file(int cid, String name) => '${part(cid)}${Platform.pathSeparator}$name';

  Map<String, Object?> entry(int cid) =>
      jsonDecode(File(file(cid, 'entry.json')).readAsStringSync()) as Map<String, Object?>;

  /// Every log line's fields, for checks that no address reached the log.
  String get logText => logs.events.map((event) => jsonEncode(event.toJson())).join('\n');

  /// Disposes [library] as the app's end would; the rest go in [dispose].
  void close(DiskOfflineLibrary library) {
    libraries.remove(library);
    library.dispose();
  }

  void dispose() {
    for (final library in libraries) {
      library.dispose();
    }
    libraries.clear();
    try {
      Directory(folder).deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold a file a moment longer; the temp folder is the OS's to clear.
    }
  }
}
