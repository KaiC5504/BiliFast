import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/skin/skin_video.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

const placeholderKey = Key('placeholder');
final video = File('/support/skin/head_myself_mp4_bg.mp4');

Widget host(SkinVideo child, {bool ticking = true}) => Directionality(
  textDirection: TextDirection.ltr,
  child: TickerMode(
    enabled: ticking,
    child: Center(child: SizedBox(width: 440, height: 300, child: child)),
  ),
);

SkinVideo skinVideo({File? file, bool loop = true}) => SkinVideo(
  file: file ?? video,
  loop: loop,
  placeholder: const ColoredBox(key: placeholderKey, color: Color(0xFF123456)),
);

bool placeholderShown(WidgetTester tester) =>
    tester.widget<Visibility>(find.ancestor(of: find.byKey(placeholderKey), matching: find.byType(Visibility))).visible;

void main() {
  testWidgets('off iOS it is the placeholder alone', (tester) async {
    await tester.pumpWidget(host(skinVideo()));
    expect(find.byKey(placeholderKey), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
    expect(tester.getSize(find.byKey(placeholderKey)), const Size(440, 300));
  });

  group('on iOS', () {
    late List<MethodCall> views;
    late Map<int, List<MethodCall>> sent;

    List<int> viewIds() => [
      for (final call in views)
        if (call.method == 'create') (call.arguments as Map<Object?, Object?>)['id']! as int,
    ];

    Future<void> fromNative(WidgetTester tester, int id, MethodCall call) => tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('bilifast/skin_video/$id', const StandardMethodCodec().encodeMethodCall(call), (_) {});

    Future<void> pump(WidgetTester tester, Widget widget) async {
      await tester.pumpWidget(widget);
      await tester.pump();
    }

    setUp(() {
      views = [];
      sent = {};
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        views.add(call);
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

    testWidgets('is the native view over the placeholder, with the file and loop, letting touches through', (
      tester,
    ) async {
      await pump(tester, host(skinVideo(loop: false)));
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, 'bilifast/skin_video');
      expect(view.creationParams, {'path': video.path, 'loop': false});
      expect(view.creationParamsCodec, isA<StandardMessageCodec>());
      expect(view.hitTestBehavior, PlatformViewHitTestBehavior.transparent);
      expect(
        find.ancestor(of: find.byType(UiKitView), matching: find.byType(IgnorePointer)),
        findsWidgets,
        reason: 'a background: the header\'s controls get the touches',
      );
      expect(tester.getRect(find.byType(UiKitView)), tester.getRect(find.byKey(placeholderKey)));

      final create = views.firstWhere((call) => call.method == 'create').arguments as Map<Object?, Object?>;
      expect(create['viewType'], 'bilifast/skin_video');
      expect(const StandardMessageCodec().decodeMessage(ByteData.sublistView(create['params']! as Uint8List)), {
        'path': video.path,
        'loop': false,
      });
    }, variant: ios);

    testWidgets('the placeholder shows until the view says its first frame is up', (tester) async {
      await pump(tester, host(skinVideo()));
      expect(placeholderShown(tester), isTrue);
      await fromNative(tester, viewIds().single, const MethodCall('ready'));
      await tester.pump();
      expect(placeholderShown(tester), isFalse);
      expect(tester.getSize(find.byType(UiKitView)), const Size(440, 300), reason: 'the placeholder still sizes it');
    }, variant: ios);

    testWidgets('plays while its TickerMode is on, pauses while off', (tester) async {
      await pump(tester, host(skinVideo()));
      final id = viewIds().single;
      expect(sent[id]!.map((call) => call.method), ['play']);

      await pump(tester, host(skinVideo(), ticking: false));
      await pump(tester, host(skinVideo(), ticking: false));
      expect(sent[id]!.map((call) => call.method), ['play', 'pause']);

      await pump(tester, host(skinVideo()));
      expect(sent[id]!.map((call) => call.method), ['play', 'pause', 'play']);
    }, variant: ios);

    testWidgets('made under a muted TickerMode, it is never told to play until shown', (tester) async {
      await pump(tester, host(skinVideo(), ticking: false));
      final id = viewIds().single;
      expect(sent[id], isEmpty, reason: 'a new view waits paused');
      await pump(tester, host(skinVideo()));
      expect(sent[id]!.map((call) => call.method), ['play']);
    }, variant: ios);

    testWidgets('another file is a new view, behind the placeholder again until it draws', (tester) async {
      await pump(tester, host(skinVideo()));
      await fromNative(tester, viewIds().single, const MethodCall('ready'));
      await tester.pump();
      expect(placeholderShown(tester), isFalse);

      await pump(tester, host(skinVideo(file: File('/support/skin/other.mp4'))));
      expect(viewIds(), hasLength(2));
      expect(views.where((call) => call.method == 'dispose'), hasLength(1));
      expect(placeholderShown(tester), isTrue);
      final second = viewIds().last;
      expect(sent[second]!.map((call) => call.method), ['play']);

      await fromNative(tester, viewIds().first, const MethodCall('ready'));
      await tester.pump();
      expect(placeholderShown(tester), isTrue, reason: 'the old view\'s word counts for nothing');
      await fromNative(tester, second, const MethodCall('ready'));
      await tester.pump();
      expect(placeholderShown(tester), isFalse);
    }, variant: ios);

    testWidgets('a file that won\'t play keeps the placeholder and is logged once', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await pump(tester, host(skinVideo(file: File('/support/skin/broken.mp4'))));
      final id = viewIds().single;
      await fromNative(tester, id, const MethodCall('failed', 'AVFoundationErrorDomain -11829'));
      await fromNative(tester, id, const MethodCall('failed', 'AVFoundationErrorDomain -11829'));
      await tester.pump();
      expect(placeholderShown(tester), isTrue);
      final event = logs.events.singleWhere((event) => event.msg == 'skin video failed');
      expect(event.f.map((key, value) => MapEntry(key, value.toJson())), {
        'file': 'broken.mp4',
        'reason': 'AVFoundationErrorDomain -11829',
      });
    }, variant: ios);
  });
}
