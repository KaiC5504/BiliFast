import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart' show BiliClient, HTTPRequest, HTTPResponse, HTTPTransport;
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

/// Answers every request with [status] and [body], recording what was asked; while [hold] is pending, answers wait
/// for it.
final class _Client implements HttpClient {
  _Client(this.status, this.body);

  final int status;
  final List<int> body;
  final asked = <Uri>[];
  final sentHeaders = <String, Object>{};
  Future<void>? hold;
  int aborted = 0;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    asked.add(url);
    return _Request(this, hold);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Request implements HttpClientRequest {
  _Request(this._client, this._hold);

  final _Client _client;
  final Future<void>? _hold;

  @override
  late final HttpHeaders headers = _Headers(_client.sentHeaders);

  @override
  Future<HttpClientResponse> close() async {
    await _hold;
    return _Response(_client.status, _client.body);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => _client.aborted++;

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

/// Stands in for the iPhone's URLSession: records each request and answers [status] with [body]; while [hold] is
/// pending, answers wait for it, and [error] is thrown in place of an answer.
final class _Transport implements HTTPTransport {
  final sent = <HTTPRequest>[];
  int status = HttpStatus.ok;
  List<int> body = const [1, 2, 3];
  Future<void>? hold;
  Object? error;

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    sent.add(request);
    await hold;
    final failure = error;
    if (failure != null) throw failure;
    return HTTPResponse(status: status, headers: const {}, body: Uint8List.fromList(body), finalURL: request.url);
  }
}

/// As cupertino_http's errors, whose text carries the address.
final class _AddressedError implements Exception {
  const _AddressedError(this.url);

  final Uri url;

  @override
  String toString() => 'ClientException: connection lost, uri=$url';
}

/// A cache whose folder can't be listed while [listError] is set; [listings] counts the tries.
final class _Unlisted extends ImageDiskCache {
  _Unlisted({required super.folder, required super.capBytes, required ImageFetch fetch}) : super(fetch: fetch);

  Object? listError;
  int listings = 0;

  @override
  Stream<FileSystemEntity> listFolder() {
    listings += 1;
    final error = listError;
    return error == null ? super.listFolder() : Stream.error(error);
  }
}

const _denied = FileSystemException('Directory listing failed', '', OSError('Access is denied.', 5));

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

  _Unlisted unlisted({int capBytes = ImageDiskCache.defaultCapBytes, String? at}) {
    final cache = _Unlisted(folder: at ?? folder.path, capBytes: capBytes, fetch: fetch.call);
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

  test('after a start that could not list the folder, the next store counts it afresh and the cap holds', () async {
    final cache = unlisted(capBytes: 1000)..listError = _denied;
    await cache.start();
    expect(logged('image cache not read').single.f['error']?.toJson(), 'Access is denied.');
    cache.listError = null;
    fetch.size = 400;
    await cache.bytes(_a);
    await cache.settle();
    expect(logged('image cache').single.f['files']?.toJson(), 1, reason: 'counted afresh');
    await age(cache.fileOf(_a), const Duration(hours: 2));
    await cache.bytes(_b);
    await cache.settle();
    await age(cache.fileOf(_b), const Duration(hours: 1));

    await cache.bytes(_c);
    await cache.settle();
    expect(cache.fileOf(_a).existsSync(), isFalse);
    expect(await cache.sizeBytes(), 800);
  });

  test('a trim that cannot list the folder warns once and is tried again only after more stores', () async {
    final cache = unlisted(capBytes: 1000);
    await cache.start();
    cache.listError = _denied;
    final before = cache.listings;
    fetch.size = 400;
    for (var i = 0; i < 20; i++) {
      await cache.bytes('$_c?n=$i');
      await cache.settle();
    }
    expect(logged('image cache not trimmed').single.f['error']?.toJson(), 'Access is denied.');
    // The third store passed the cap and its trim failed; the next 16 were let by, and the twentieth tried again.
    expect(cache.listings - before, 2);
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

  test('a folder that cannot be listed warns with the reason; one not made yet is quietly empty', () async {
    final missing = cacheOf(at: '${folder.path}${Platform.pathSeparator}missing');
    expect(await missing.sizeBytes(), 0);
    await missing.clear();
    expect(logged('image cache cleared').single.f['files']?.toJson(), 0);
    expect(logs.events.where((event) => event.level == LogLevel.warn), isEmpty);

    final denied = unlisted()..listError = _denied;
    expect(await denied.sizeBytes(), 0);
    expect(logged('image cache size not read').single.f['error']?.toJson(), 'Access is denied.');
    await denied.clear();
    final warning = logged('image cache not cleared').single;
    expect(warning.f['error']?.toJson(), 'Access is denied.');
    expect(warning.f['files']?.toJson(), 0);
    expect(logged('image cache cleared'), hasLength(1), reason: "only the missing folder's");
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

    test('one that stalls gives up after its timeout with a TimeoutException and closes the connection', () async {
      final client = _Client(HttpStatus.ok, [1, 2, 3])..hold = Completer<void>().future;
      debugNetworkImageHttpClientProvider = () => client;
      expect(ImageDiskCache.downloadTimeout, const Duration(seconds: 30));
      await expectLater(
        ImageDiskCache.download(Uri.parse(_a), null, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.aborted, 1);
    });

    test('after one stalled, the next ask for that address downloads afresh', () async {
      final client = _Client(HttpStatus.ok, [1, 2, 3])..hold = Completer<void>().future;
      debugNetworkImageHttpClientProvider = () => client;
      final cache = ImageDiskCache(
        folder: folder.path,
        fetch: (url, headers) => ImageDiskCache.download(url, headers, timeout: const Duration(milliseconds: 50)),
      );
      caches.add(cache);
      await expectLater(cache.bytes(_a), throwsA(isA<TimeoutException>()));
      await cache.settle();
      client.hold = null;
      expect(await cache.bytes(_a), [1, 2, 3]);
      expect(client.asked, hasLength(2));
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

  group('the picture session', () {
    const cover = 'https://i1.hdslb.com/bfs/archive/cover.jpg@633w_475h_1c_90q.jpg';
    late _Transport transport;
    late DateTime now;
    late PictureSession session;

    setUp(() {
      transport = _Transport();
      now = DateTime(2026, 10, 23, 12);
      session = PictureSession(transport, now: () => now);
    });

    tearDown(() {
      ImageDiskCache.session = null;
      debugNetworkImageHttpClientProvider = null;
    });

    test('the PC has none: pictures come through dart:io there', () {
      expect(PictureSession.platform(), isNull);
      expect(ImageDiskCache.session, isNull);
    });

    test(
      'with one, every download goes through it: a GET with the headers and a 15 s wait, the body for a 200',
      () async {
        final dartIo = _Client(HttpStatus.ok, [9]);
        debugNetworkImageHttpClientProvider = () => dartIo;
        ImageDiskCache.session = session;
        final cache = ImageDiskCache(folder: folder.path);
        caches.add(cache);
        expect(await cache.bytes(_a, headers: const {'User-Agent': 'test'}), [1, 2, 3]);
        final request = transport.sent.single;
        expect(request.method, 'GET');
        expect('${request.url}', _a);
        expect(request.headers, {'User-Agent': 'test'});
        expect(request.timeout, PictureSession.requestTimeout);
        expect(PictureSession.requestTimeout, const Duration(seconds: 15));
        expect(request.body, isNull);
        expect(dartIo.asked, isEmpty, reason: 'dart:io is not asked as well');
        expect(session.open, isTrue);
      },
    );

    test('a status other than 200 throws NetworkImageLoadException; the connection still answered', () async {
      transport.status = HttpStatus.notFound;
      await expectLater(
        session.download(Uri.parse(_b), null),
        throwsA(isA<NetworkImageLoadException>().having((error) => error.statusCode, 'statusCode', 404)),
      );
      expect(session.open, isTrue);
    });

    test('one that never answers gives up after its timeout with a TimeoutException', () async {
      transport.hold = Completer<void>().future;
      expect(ImageDiskCache.downloadTimeout, const Duration(seconds: 30));
      await expectLater(
        session.download(Uri.parse(_a), null, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
      expect(session.open, isFalse);
    });

    test('past its timeout the request is cancelled too, as URLSession only gives up on a wait between chunks',
        () async {
      transport.hold = Completer<void>().future;
      var cancelled = false;
      final download = session.download(Uri.parse(_a), null, timeout: const Duration(milliseconds: 200));
      unawaited(transport.sent.single.abort!.then((_) => cancelled = true));
      await pumpEventQueue();
      expect(cancelled, isFalse);
      await expectLater(download, throwsA(isA<TimeoutException>()));
      await pumpEventQueue();
      expect(cancelled, isTrue);
    });

    test("a failure on the way is a network failure whose text leaves the address out", () async {
      transport.error = _AddressedError(Uri.parse(_a));
      final failure = await session.download(Uri.parse(_a), null).then<Object?>((_) => null, onError: (Object e) => e);
      expect(failure, isA<PictureDownloadException>().having((error) => error.reason, 'reason', '_AddressedError'));
      expect(failure, isA<IOException>(), reason: 'kept on disk: a network failure is no bad picture');
      expect('$failure', isNot(contains('hdslb')));
    });

    group('warmed as a refresh starts', () {
      test(
        'sends a HEAD with the picture headers for the given picture before any download, at most one at once',
        () async {
          final hold = Completer<void>();
          transport.hold = hold.future;
          final sent = session.warm(picture: cover);
          expect(sent, isNotNull);
          final head = transport.sent.single;
          expect(head.method, 'HEAD');
          expect('${head.url}', cover);
          expect(head.headers, BiliClient.mediaHeaders);
          expect(head.headers.keys.map((name) => name.toLowerCase()), isNot(contains('cookie')));
          expect(session.warming, isTrue);
          expect(session.warm(picture: cover), isNull, reason: 'one is out');
          expect(transport.sent, hasLength(1));

          hold.complete();
          expect(await sent, isTrue);
          expect(session.warming, isFalse);
          expect(session.open, isTrue);
          expect(logged('picture warm failed'), isEmpty);
        },
      );

      test('skipped while the connection answered within 10 s; sent again after', () async {
        expect(session.warm(picture: cover), isNotNull);
        await pumpEventQueue();
        now = now.add(const Duration(seconds: 9));
        expect(session.warm(picture: cover), isNull);
        await session.download(Uri.parse(cover), null);
        now = now.add(const Duration(seconds: 9));
        expect(session.warm(picture: cover), isNull, reason: 'a download answered 9 s ago');
        now = now.add(PictureSession.keepAlive);
        expect(session.warm(picture: cover), isNotNull);
        expect([for (final request in transport.sent) request.method], ['HEAD', 'GET', 'HEAD']);
      });

      test('asks for the last picture downloaded on i1 without a query, in place of the one given', () async {
        const face = 'https://i1.hdslb.com/bfs/face/f.jpg@120w_120h_1c.webp';
        await session.download(Uri.parse(face), null);
        await session.download(Uri.parse('https://i1.hdslb.com/bfs/face/signed.jpg?sign=x'), null);
        await session.download(Uri.parse('https://archive.biliimg.com/bfs/archive/x.jpg'), null);
        now = now.add(PictureSession.keepAlive);
        expect(session.warm(picture: cover), isNotNull);
        expect('${transport.sent.last.url}', face);
      });

      test('skipped with no picture, or one on another host', () {
        expect(session.warm(), isNull);
        expect(session.warm(picture: 'https://i0.hdslb.com/bfs/archive/a.jpg'), isNull);
        expect(session.warm(picture: 'https://archive.biliimg.com/bfs/archive/a.jpg'), isNull);
        expect(session.warm(picture: 'http://i1.hdslb.com/bfs/archive/a.jpg'), isNull);
        expect(transport.sent, isEmpty);
      });

      test('a failed warm or download leaves the connection closed, so the next refresh warms it', () async {
        transport.error = _AddressedError(Uri.parse(cover));
        expect(await session.warm(picture: cover), isFalse);
        expect(session.warming, isFalse);
        expect(session.open, isFalse);
        expect(await session.warm(picture: cover), isFalse);

        transport.error = null;
        await session.download(Uri.parse(cover), null);
        expect(session.open, isTrue);
        transport.error = _AddressedError(Uri.parse(cover));
        await expectLater(session.download(Uri.parse(cover), null), throwsA(isA<PictureDownloadException>()));
        expect(session.open, isFalse);
        expect(session.warm(picture: cover), isNotNull);
      });

      test('a failed warm warns once per reason, the reason without the address', () async {
        transport.error = _AddressedError(Uri.parse(cover));
        await session.warm(picture: cover);
        await session.warm(picture: cover);
        transport.error = TimeoutException('head');
        await session.warm(picture: cover);
        await session.warm(picture: cover);
        final warnings = logged('picture warm failed').toList();
        expect([for (final warning in warnings) warning.f['reason']?.toJson()], ['_AddressedError', 'TimeoutException']);
        expect(warnings.map((warning) => (warning.level, warning.cat)), everyElement((LogLevel.warn, LogCategory.api)));
        expect(warnings.map((warning) => warning.f.keys.toList()), everyElement(['reason']));
      });

      test('an Error in a warm is a bug, not a failed warm: it is thrown, not logged', () async {
        transport.error = StateError('bug');
        await expectLater(session.warm(picture: cover), throwsStateError);
        expect(session.warming, isFalse);
        expect(logged('picture warm failed'), isEmpty);
      });
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

  test('a store failure warns once per reason, and the next trim line counts the pictures not stored', () async {
    final cache = cacheOf(capBytes: 250);
    await cache.start();
    // A folder where each picture's file should be: the rename into place fails.
    Directory(cache.fileOf(_a).path).createSync();
    Directory(cache.fileOf(_b).path).createSync();
    expect(await cache.bytes(_a), hasLength(100));
    expect(await cache.bytes(_b), hasLength(100));
    await cache.settle();
    expect(logged('image not stored'), hasLength(1), reason: 'the same reason twice');

    // A file where the folder should be: the folder can't be made again.
    folder.deleteSync(recursive: true);
    File(folder.path).writeAsStringSync('a file, not a folder');
    expect(await cache.bytes(_c), hasLength(100));
    await cache.settle();
    final reasons = [for (final warning in logged('image not stored')) '${warning.f['error']?.toJson()}'];
    expect(reasons, hasLength(2), reason: 'another reason');
    expect(reasons.toSet(), hasLength(2));

    File(folder.path).deleteSync();
    folder.createSync();
    for (var i = 0; i < 3; i++) {
      await cache.bytes('$_c?n=$i');
      await cache.settle();
    }
    expect(logged('image cache trimmed').single.f['notStored']?.toJson(), 3);
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
