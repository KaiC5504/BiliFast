import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/skin/skin_video.dart';
import 'package:bilifast/space/own/own_banner_video.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = 'https://i0.hdslb.com/bfs/garb/made-up/banner.mp4?made=up';
const _other = 'https://i0.hdslb.com/bfs/garb/made-up/other.mp4';

void main() {
  late Directory folder;
  late List<Uri> fetched;
  Object? failure;

  /// A fresh folder; file work runs on the real clock, as the app's does.
  Future<void> prepare(WidgetTester tester) async {
    final made = folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('own_banner_video')))!;
    addTearDown(() => made.deleteSync(recursive: true));
    fetched = [];
    failure = null;
  }

  OwnBannerVideos store() => OwnBannerVideos(
    folder: '${folder.path}${Platform.pathSeparator}space_banner',
    fetch: (url) async {
      fetched.add(url);
      if (failure case final error?) throw error;
      return Uint8List.fromList([0, 0, 0, 24, ...'ftypmp42'.codeUnits]);
    },
  );

  group('the video file', () {
    testWidgets('is downloaded once and kept by its address\'s hash', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        final videos = store();
        final file = (await videos.file(_video))!;
        expect(await file.length(), 12);
        expect(file.path, isNot(contains('banner.mp4')), reason: 'the address never names the file');
        expect(await videos.file(_video), isNotNull);
        expect(await store().file(_video), isNotNull, reason: 'a later page finds it on disk');
      });
      expect(fetched, [Uri.parse(_video.replaceFirst('i0.', 'i1.'))], reason: 'asked from i1, as pictures are');
    });

    testWidgets('a new one replaces the old', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        final videos = store();
        final first = (await videos.file(_video))!;
        final second = (await videos.file(_other))!;
        expect(await first.exists(), isFalse);
        expect(await second.exists(), isTrue);
        expect(Directory(videos.folder).listSync(), hasLength(1));
      });
    });

    testWidgets('only Bilibili\'s CDN hosts over https are asked, and the refusal names no path', (tester) async {
      await prepare(tester);
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await tester.runAsync(() async {
        final videos = store();
        expect(await videos.file('https://example.com/made-up/banner.mp4'), isNull);
        expect(await videos.file('https://i0.hdslb.com.example.com/made-up/banner.mp4'), isNull);
        expect(await videos.file('https://i0.hdslb.com:8443/made-up/banner.mp4'), isNull);
      });
      expect(fetched, isEmpty);
      final lines = logs.events.where((event) => event.msg == 'own space banner video failed').toList();
      expect(lines, hasLength(3));
      expect(lines.map((line) => line.encode()).join(), isNot(contains('made-up')));
    });

    testWidgets('the app\'s download stops and keeps nothing past the cap, length declared or not', (tester) async {
      await prepare(tester);
      for (final declared in [false, true]) {
        final client = _Client(chunks: OwnBannerVideos.maxBytes ~/ _Client.chunk + 4, declared: declared);
        final videos = OwnBannerVideos(
          folder: '${folder.path}${Platform.pathSeparator}space_banner',
          client: () => client,
        );
        expect(await tester.runAsync(() => videos.file(_video)), isNull);
        expect(client.asked, [_video.replaceFirst('i0.', 'i1.')]);
        expect(
          client.sent,
          lessThanOrEqualTo(OwnBannerVideos.maxBytes ~/ _Client.chunk + 1),
          reason: 'stopped, not read to the end',
        );
        if (declared) expect(client.sent, 0, reason: 'a declared length past the cap is refused before the body');
        expect(Directory(videos.folder).existsSync() && Directory(videos.folder).listSync().isNotEmpty, isFalse);
      }
    });

    testWidgets('the app\'s download keeps a video within the cap', (tester) async {
      await prepare(tester);
      final client = _Client(chunks: 2, declared: true);
      final videos = OwnBannerVideos(
        folder: '${folder.path}${Platform.pathSeparator}space_banner',
        client: () => client,
      );
      final file = await tester.runAsync(() => videos.file(_video));
      expect(await tester.runAsync(() => file!.length()), 2 * _Client.chunk);
    });

    testWidgets('the one asked last stays when one asked before it finishes later', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        // Made on the real clock: a fake-async completer would never deliver here.
        final old = Completer<Uint8List>();
        final videos = OwnBannerVideos(
          folder: '${folder.path}${Platform.pathSeparator}space_banner',
          fetch: (url) async => '$url'.contains('other') ? old.future : Uint8List.fromList([1, 2, 3]),
        );
        final slow = videos.file(_other);
        await Directory(videos.folder).create(recursive: true);
        final part = File('${videos.fileOf(_other).path}.part')..writeAsBytesSync([9]);
        final latest = (await videos.file(_video))!;
        expect(part.existsSync(), isTrue, reason: 'the other load is still writing it');

        old.complete(Uint8List.fromList([4, 5]));
        expect(await (await slow)!.readAsBytes(), [4, 5]);
        expect(await latest.readAsBytes(), [1, 2, 3], reason: 'the old download deletes nothing');

        expect(await videos.file(_other), isNotNull, reason: 'asked again, it is the latest');
        final third = (await videos.file('https://i0.hdslb.com/bfs/garb/made-up/third.mp4'))!;
        expect(Directory(videos.folder).listSync().map((entry) => entry.path), [third.path]);
      });
    });

    testWidgets('two asks at once share one download', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        final answer = Completer<Uint8List>();
        var fetches = 0;
        final videos = OwnBannerVideos(
          folder: '${folder.path}${Platform.pathSeparator}space_banner',
          fetch: (url) {
            fetches++;
            return answer.future;
          },
        );
        final first = videos.file(_video);
        final second = videos.file(_video);
        answer.complete(Uint8List.fromList([1]));
        expect((await first)!.path, (await second)!.path);
        expect(fetches, 1);
      });
    });

    testWidgets('an empty answer is null and writes nothing', (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        final videos = OwnBannerVideos(
          folder: '${folder.path}${Platform.pathSeparator}space_banner',
          fetch: (url) async => Uint8List(0),
        );
        expect(await videos.file(_video), isNull);
        expect(Directory(videos.folder).existsSync() && Directory(videos.folder).listSync().isNotEmpty, isFalse);
      });
    });

    testWidgets('a failed download is null and logged without the address', (tester) async {
      await prepare(tester);
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      failure = const SocketException('made up');
      expect(await tester.runAsync(() => store().file(_video)), isNull);
      final lines = logs.events.where((event) => event.msg == 'own space banner video failed').toList();
      expect(lines, hasLength(1));
      expect(lines.single.encode(), isNot(contains('made-up')));
    });
  });

  group('the video', () {
    Future<void> show(
      WidgetTester tester,
      double alignY, {
      ({int width, int height})? size = (width: 1080, height: 1620),
      ValueListenable<bool>? muted,
      ValueNotifier<String?>? playing,
    }) async {
      await prepare(tester);
      final videos = store();
      await tester.runAsync(() => videos.file(_video));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              height: 295,
              child: OwnBannerVideo(
                url: _video,
                size: size,
                alignY: alignY,
                still: const ColoredBox(key: ValueKey('still'), color: Color(0xFF000000)),
                videos: videos,
                muted: muted,
                playing: playing,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('loops over the still, covering the box, cut about the crop', (tester) async {
      await show(tester, -1);
      expect(find.byKey(const ValueKey('still')), findsOneWidget);
      final video = tester.widget<SkinVideo>(find.byType(SkinVideo));
      expect(video.loop, isTrue);
      // 1080 × 1620 across 440 is 660 tall.
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, 0, 440, 660));
      await show(tester, 0);
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, (295 - 660) / 2, 440, 660));
      await show(tester, 1);
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, 295 - 660, 440, 660));
    });

    testWidgets('without its size it fills the box', (tester) async {
      await show(tester, -1, size: null);
      expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTWH(0, 0, 440, 295));
    });

    testWidgets('silent without a muted notifier; with one it keeps its sound and follows the notifier', (
      tester,
    ) async {
      await show(tester, -1);
      var video = tester.widget<SkinVideo>(find.byType(SkinVideo));
      expect((video.sound, video.muted), (false, true));

      final muted = ValueNotifier(true);
      addTearDown(muted.dispose);
      await show(tester, -1, muted: muted);
      video = tester.widget<SkinVideo>(find.byType(SkinVideo));
      expect((video.sound, video.muted), (true, true));
      muted.value = false;
      await tester.pump();
      expect(tester.widget<SkinVideo>(find.byType(SkinVideo)).muted, isFalse);
    });

    group('on the phone', () {
      late Map<int, List<MethodCall>> sent;

      setUp(() {
        sent = {};
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            final id = (call.arguments as Map<Object?, Object?>)['id']! as int;
            sent[id] = [];
            messenger.setMockMethodCallHandler(MethodChannel('bilifast/skin_video/$id'), (call) async {
              sent[id]!.add(call);
              return null;
            });
          }
          return null;
        });
      });
      tearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );

      Future<void> fromNative(WidgetTester tester, int id, MethodCall call) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'bilifast/skin_video/$id',
          const StandardMethodCodec().encodeMethodCall(call),
          (_) {},
        );
        await tester.pump();
      }

      testWidgets('says it is playing once its first frame shows, and not after a failure', (tester) async {
        final muted = ValueNotifier(true);
        final playing = ValueNotifier<String?>(null);
        addTearDown(muted.dispose);
        addTearDown(playing.dispose);
        await show(tester, -1, muted: muted, playing: playing);
        final id = sent.keys.single;
        expect(playing.value, isNull, reason: 'downloaded is not yet drawn');
        await fromNative(tester, id, const MethodCall('ready'));
        expect(playing.value, _video);

        muted.value = false;
        await tester.pump();
        expect(sent[id]!.map((call) => (call.method, call.arguments)), [('play', null), ('setMuted', false)]);

        await fromNative(tester, id, const MethodCall('failed', 'AVFoundationErrorDomain -11819'));
        expect(playing.value, isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    });
  });
}

/// dart:io's client answering 200 with [chunks] made-up chunks of [chunk] bytes, its length [declared] or not;
/// nothing leaves the machine. [sent] counts the chunks the body handed out.
class _Client implements HttpClient {
  _Client({required this.chunks, required this.declared});

  static const chunk = 1024 * 1024;

  final int chunks;
  final bool declared;
  final asked = <String>[];
  int sent = 0;

  @override
  Duration? connectionTimeout;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    asked.add('$url');
    return _Request(this);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.client);

  final _Client client;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async => _Response(client);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.client);

  final _Client client;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  bool get isRedirect => false;

  @override
  int get contentLength => client.declared ? client.chunks * _Client.chunk : -1;

  Stream<List<int>> _body() async* {
    for (var i = 0; i < client.chunks; i++) {
      client.sent++;
      yield Uint8List(_Client.chunk);
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body().listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
