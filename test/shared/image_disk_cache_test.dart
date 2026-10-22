import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A signed address, so a log line carrying any of it shows.
const _a = 'https://i0.hdslb.com/bfs/archive/a.jpg@240w_180h_1c.webp?sign=SECRET1&t=1';
const _b = 'https://i1.hdslb.com/bfs/face/b.jpg@120w_120h_1c.webp?sign=SECRET2&t=2';
const _c = 'https://i2.hdslb.com/bfs/archive/c.jpg';

/// Answers each download with [size] bytes of the ask's number; [hold] keeps answers back until it completes.
final class _Fetch {
  final asked = <Uri>[];
  final headers = <Map<String, String>?>[];
  int size = 100;
  Future<void>? hold;
  Object? error;

  Future<Uint8List> call(Uri url, Map<String, String>? headers) async {
    asked.add(url);
    this.headers.add(headers);
    await hold;
    final failure = error;
    if (failure != null) throw failure;
    return Uint8List.fromList(List.filled(size, asked.length));
  }
}

/// Answers every request with [status] and [body], recording what was asked.
final class _Client implements HttpClient {
  _Client(this.status, this.body);

  final int status;
  final List<int> body;
  final asked = <Uri>[];
  final sentHeaders = <String, Object>{};

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    asked.add(url);
    return _Request(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Request implements HttpClientRequest {
  _Request(this._client);

  final _Client _client;

  @override
  late final HttpHeaders headers = _Headers(_client.sentHeaders);

  @override
  Future<HttpClientResponse> close() async => _Response(_client.status, _client.body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Headers implements HttpHeaders {
  _Headers(this._sent);

  final Map<String, Object> _sent;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) => _sent[name] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this._body);

  @override
  final int statusCode;
  final List<int> _body;

  @override
  int get contentLength => _body.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(_body).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late MemorySink logs;
  late _Fetch fetch;
  final caches = <ImageDiskCache>[];

  ImageDiskCache cacheOf({int capBytes = ImageDiskCache.defaultCapBytes, String? at}) {
    final cache = ImageDiskCache(folder: at ?? folder.path, capBytes: capBytes, fetch: fetch.call);
    caches.add(cache);
    return cache;
  }

  List<String> names() => [
    for (final entity in folder.listSync())
      if (entity is File) entity.uri.pathSegments.last,
  ]..sort();

  Iterable<LogEvent> logged(String message) => logs.events.where((event) => event.msg == message);

  Future<void> age(File file, Duration by) => file.setLastModified(DateTime.now().subtract(by));

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('image_cache');
    logs = MemorySink();
    Logger.shared.add(logs);
    fetch = _Fetch();
  });

  tearDown(() async {
    for (final cache in caches) {
      await cache.settle();
      cache.dispose();
    }
    caches.clear();
    Logger.shared.remove(logs);
    for (final event in logs.events) {
      final line = [event.msg, for (final value in event.f.values) '${value.toJson()}'].join(' ');
      for (final part in ['hdslb', 'http', 'SECRET', '/bfs/']) {
        expect(line, isNot(contains(part)), reason: 'no address reaches the log: "$line"');
      }
    }
    await folder.delete(recursive: true);
  });

  test('a stored picture comes from storage, even after a relaunch, without downloading', () async {
    final first = cacheOf();
    final downloaded = await first.bytes(_a);
    await first.settle();
    expect(fetch.asked, hasLength(1));

    expect(await first.bytes(_a), downloaded);
    final relaunched = cacheOf();
    fetch.error = StateError('the network is not asked');
    expect(await relaunched.bytes(_a), downloaded);
    expect(fetch.asked, hasLength(1));
  });

  test('a miss downloads the address with its headers and stores the picture under a hash of the address', () async {
    final cache = cacheOf();
    final bytes = await cache.bytes(_a, headers: const {'Referer': 'https://www.bilibili.com'});
    await cache.settle();
    expect('${fetch.asked.single}', _a);
    expect(fetch.headers.single, {'Referer': 'https://www.bilibili.com'});
    expect(await cache.fileOf(_a).readAsBytes(), bytes);
    expect(names().single, isNot(contains('hdslb')));
    expect(cache.fileOf(_a).path, isNot(cache.fileOf(_b).path));
  });

  test('asks for one address at once share one download', () async {
    final cache = cacheOf();
    final release = Completer<void>();
    fetch.hold = release.future;
    final first = cache.bytes(_a);
    final second = cache.bytes(_a);
    await pumpEventQueue();
    expect(fetch.asked, hasLength(1));
    release.complete();
    expect(await first, await second);
    expect(fetch.asked, hasLength(1));
  });

  test('a picture is written under a temporary name and renamed, so a half-written one is never read', () async {
    final halfWritten = File('${cacheOf().fileOf(_a).path}.deadrun-0.tmp')..writeAsBytesSync([1, 2]);
    final cache = cacheOf();
    expect(await cache.bytes(_a), hasLength(100), reason: 'the half-written file is no picture');
    await cache.settle();
    expect(fetch.asked, hasLength(1));
    expect(await cache.fileOf(_a).length(), 100);
    expect(names(), [cache.fileOf(_a).uri.pathSegments.last, halfWritten.uri.pathSegments.last]..sort());

    await cacheOf().start();
    expect(halfWritten.existsSync(), isFalse, reason: 'start deletes what a run that died mid-write left');
    expect(cache.fileOf(_a).existsSync(), isTrue);
  });

  test('start makes the folder, totals it and, past the cap, deletes the oldest first to well under it', () async {
    final seed = cacheOf();
    final files = [for (var i = 0; i < 5; i++) seed.fileOf('$_c?n=$i')];
    for (final (index, file) in files.indexed) {
      file.writeAsBytesSync(List.filled(300, index));
      await age(file, Duration(hours: 5 - index));
    }
    await cacheOf(capBytes: 1000).start();
    expect(files.map((file) => file.existsSync()), [false, false, false, true, true]);
    final log = logged('image cache').single;
    expect(log.f['files']?.toJson(), 2);
    expect(log.f['trimmed']?.toJson(), 3);
    expect(log.f['mb']?.toJson(), 0.0);

    final fresh = '${folder.path}${Platform.pathSeparator}made';
    await cacheOf(at: fresh).start();
    expect(Directory(fresh).existsSync(), isTrue);
  });

  test('past the cap during a run, the oldest go in the background', () async {
    final cache = cacheOf(capBytes: 1000);
    await cache.start();
    fetch.size = 400;
    await cache.bytes(_a);
    await cache.bytes(_b);
    await cache.settle();
    await age(cache.fileOf(_a), const Duration(hours: 2));
    await age(cache.fileOf(_b), const Duration(hours: 1));
    expect(logged('image cache trimmed'), isEmpty);

    await cache.bytes(_c);
    await cache.settle();
    expect(cache.fileOf(_a).existsSync(), isFalse);
    expect(cache.fileOf(_b).existsSync(), isTrue);
    expect(cache.fileOf(_c).existsSync(), isTrue);
    expect(await cache.sizeBytes(), 800);
    expect(logged('image cache trimmed').single.f['trimmed']?.toJson(), 1);
  });

  test('a picture shown again is kept over one long unseen', () async {
    final cache = cacheOf(capBytes: 1000);
    await cache.start();
    fetch.size = 400;
    await cache.bytes(_a);
    await cache.bytes(_b);
    await cache.settle();
    await age(cache.fileOf(_a), const Duration(hours: 2));
    await age(cache.fileOf(_b), const Duration(hours: 1));
    await cache.bytes(_a);
    await cache.bytes(_c);
    await cache.settle();
    // The touch on a hit is not awaited; it lands long before the trim lists the folder.
    expect(cache.fileOf(_a).existsSync(), isTrue);
    expect(cache.fileOf(_b).existsSync(), isFalse);
  });

  test('sizeBytes totals the folder; a folder not made yet is empty', () async {
    expect(await cacheOf(at: '${folder.path}${Platform.pathSeparator}missing').sizeBytes(), 0);
    final cache = cacheOf();
    await cache.bytes(_a);
    fetch.size = 250;
    await cache.bytes(_b);
    await cache.settle();
    expect(await cache.sizeBytes(), 350);
  });

  test('clear deletes every stored picture, and a download in flight is not stored after it', () async {
    final cache = cacheOf();
    await cache.start();
    await cache.bytes(_a);
    await cache.settle();
    final release = Completer<void>();
    fetch.hold = release.future;
    final flying = cache.bytes(_b);
    await pumpEventQueue();

    await cache.clear();
    release.complete();
    expect(await flying, hasLength(100), reason: 'the page still gets its picture');
    await cache.settle();
    expect(names(), isEmpty);
    expect(await cache.sizeBytes(), 0);
    expect(logged('image cache cleared').single.f['files']?.toJson(), 1);

    fetch.hold = null;
    await cache.bytes(_a);
    expect(fetch.asked, hasLength(3), reason: 'a cleared picture downloads again');
  });

  test('forget deletes a stored picture, so the next ask downloads it again', () async {
    final cache = cacheOf();
    await cache.bytes(_a);
    await cache.settle();
    await cache.forget(_a);
    expect(cache.fileOf(_a).existsSync(), isFalse);
    await cache.forget(_b);
    await cache.bytes(_a);
    expect(fetch.asked, hasLength(2));
  });

  test('forget waits for the store under way', () async {
    final cache = cacheOf();
    await cache.bytes(_a);
    await cache.forget(_a);
    await cache.settle();
    expect(cache.fileOf(_a).existsSync(), isFalse);
  });

  group('the download', () {
    tearDown(() => debugNetworkImageHttpClientProvider = null);

    test('sends the headers and answers the body for a 200', () async {
      final client = _Client(HttpStatus.ok, [1, 2, 3]);
      debugNetworkImageHttpClientProvider = () => client;
      final cache = ImageDiskCache(folder: folder.path);
      caches.add(cache);
      expect(await cache.bytes(_a, headers: const {'User-Agent': 'test'}), [1, 2, 3]);
      expect('${client.asked.single}', _a);
      expect(client.sentHeaders, {'User-Agent': 'test'});
    });

    test('a status other than 200 throws NetworkImageLoadException and stores nothing', () async {
      debugNetworkImageHttpClientProvider = () => _Client(HttpStatus.notFound, const []);
      await expectLater(
        ImageDiskCache.download(Uri.parse(_b), null),
        throwsA(isA<NetworkImageLoadException>().having((error) => error.statusCode, 'statusCode', 404)),
      );
      final cache = ImageDiskCache(folder: folder.path);
      caches.add(cache);
      await expectLater(cache.bytes(_b), throwsA(isA<NetworkImageLoadException>()));
      await cache.settle();
      expect(names(), isEmpty);
    });
  });

  test('a picture that cannot be stored still shows, and the failure warns once with a reason', () async {
    final blocker = File('${folder.path}${Platform.pathSeparator}blocker')..writeAsStringSync('a file, not a folder');
    final cache = cacheOf(at: '${blocker.path}${Platform.pathSeparator}images');
    await cache.start();
    expect(logged('image cache not read'), hasLength(1));
    expect(await cache.bytes(_a), hasLength(100));
    expect(await cache.bytes(_b), hasLength(100));
    await cache.settle();
    final warning = logged('image not stored').single;
    expect(warning.level, LogLevel.warn);
    expect('${warning.f['error']?.toJson()}', isNotEmpty);
  });

  test('a low-memory warning logs images cleared with what the memory cache still holds live', () async {
    final cache = cacheOf();
    await cache.bytes(_a);
    await cache.bytes(_b);
    await cache.settle();
    await cache.start();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage(<String, Object?>{'type': 'memoryPressure'}),
      (_) {},
    );
    final log = logged('images cleared').single;
    expect(log.f['live']?.toJson(), PaintingBinding.instance.imageCache.liveImageCount);
    expect(log.f['files']?.toJson(), 2);
  });
}
