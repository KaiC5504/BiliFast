import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/paste_button.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// The paste button as the link field holds it: at the end of a row the field's height tall.
Widget field(PasteButton button) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 300,
        height: BiliMetrics.linkFieldHeight,
        child: Row(children: [const Expanded(child: SizedBox()), button]),
      ),
    ),
  ),
);

void main() {
  late List<MethodCall> clipboard;
  late String? clipboardText;

  setUp(() {
    clipboard = [];
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method != 'Clipboard.getData') return null;
      clipboard.add(call);
      return clipboardText == null ? null : <String, Object?>{'text': clipboardText};
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  group('elsewhere', () {
    testWidgets('a tap reads the clipboard and hands over its text trimmed, or empty', (tester) async {
      final pasted = <String>[];
      await tester.pumpWidget(field(PasteButton(enabled: true, onText: pasted.add)));
      expect(find.byType(UiKitView), findsNothing);
      expect(tester.getSize(find.byType(IconButton)), const Size(40, BiliMetrics.linkFieldHeight));
      clipboardText = '  https://b23.tv/BV1GJ411x7h7 \n';
      await tester.tap(find.byType(PasteButton));
      await tester.pump();
      clipboardText = null;
      await tester.tap(find.byType(PasteButton));
      await tester.pump();
      expect(pasted, ['https://b23.tv/BV1GJ411x7h7', '']);
    });

    testWidgets('disabled, a tap reads nothing', (tester) async {
      final pasted = <String>[];
      clipboardText = 'BV1GJ411x7h7';
      await tester.pumpWidget(field(PasteButton(enabled: false, onText: pasted.add)));
      await tester.tap(find.byType(PasteButton), warnIfMissed: false);
      await tester.pump();
      expect(clipboard, isEmpty);
      expect(pasted, isEmpty);
    });
  });

  group('on iOS', () {
    late List<MethodCall> views;
    late List<MethodCall> sent;

    int viewId() => (views.firstWhere((call) => call.method == 'create').arguments as Map<Object?, Object?>)['id']! as int;

    Future<void> fromNative(WidgetTester tester, MethodCall call) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'bilifast/paste_control/${viewId()}',
          const StandardMethodCodec().encodeMethodCall(call),
          (_) {},
        );

    Future<void> host(WidgetTester tester, PasteButton button) async {
      views = [];
      sent = [];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        views.add(call);
        if (call.method == 'create') {
          final id = (call.arguments as Map<Object?, Object?>)['id']! as int;
          messenger.setMockMethodCallHandler(MethodChannel('bilifast/paste_control/$id'), (call) async {
            sent.add(call);
            return null;
          });
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform_views, null));
      await tester.pumpWidget(field(button));
      await tester.pump();
    }

    testWidgets('is the system paste control: pink, opaque to touches, claiming them at once', (tester) async {
      await host(tester, PasteButton(enabled: true, onText: (_) {}));
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, 'bilifast/paste_control');
      expect(view.creationParams, {'fill': BiliColors.pink.toARGB32(), 'glyph': BiliColors.onPink.toARGB32()});
      expect(view.creationParamsCodec, isA<StandardMessageCodec>());
      expect(view.hitTestBehavior, PlatformViewHitTestBehavior.opaque);
      final recognizer = view.gestureRecognizers!.single.constructor();
      expect(recognizer, isA<EagerGestureRecognizer>());
      recognizer.dispose();
      expect(find.byType(IconButton), findsNothing);
      expect(tester.getSize(find.byType(UiKitView)), const Size(40, BiliMetrics.linkFieldHeight),
          reason: 'where the 18 pt icon in a compact button was');

      final create = views.firstWhere((call) => call.method == 'create').arguments as Map<Object?, Object?>;
      expect(create['viewType'], 'bilifast/paste_control');
      expect(const StandardMessageCodec().decodeMessage(ByteData.sublistView(create['params']! as Uint8List)),
          {'fill': 0xFFFF6699, 'glyph': 0xFFFFFFFF});
    }, variant: ios);

    testWidgets('a tap goes to the control and never reads the clipboard from Dart', (tester) async {
      await host(tester, PasteButton(enabled: true, onText: (_) {}));
      await tester.tap(find.byType(PasteButton));
      await tester.pump();
      expect(views.where((call) => call.method == 'acceptGesture'), hasLength(1));
      expect(clipboard, isEmpty, reason: 'Clipboard.getData is what made iOS ask every time');
    }, variant: ios);

    testWidgets('what the control pastes reaches onText trimmed', (tester) async {
      final pasted = <String>[];
      await host(tester, PasteButton(enabled: true, onText: pasted.add));
      await fromNative(tester, const MethodCall('paste', ' 【标题】 https://b23.tv/abc \n'));
      await fromNative(tester, const MethodCall('paste', ''));
      expect(pasted, ['【标题】 https://b23.tv/abc', '']);
    }, variant: ios);

    testWidgets('disabled: touches are refused in Dart and a late paste is dropped', (tester) async {
      final pasted = <String>[];
      await host(tester, PasteButton(enabled: true, onText: pasted.add));
      await tester.pumpWidget(field(PasteButton(enabled: false, onText: pasted.add)));
      expect(sent, isEmpty, reason: 'the control enables itself from the clipboard; forcing it brings the prompt back');
      expect(tester.widget<IgnorePointer>(
        find.ancestor(of: find.byType(UiKitView), matching: find.byType(IgnorePointer)).first,
      ).ignoring, isTrue);
      await tester.tap(find.byType(PasteButton), warnIfMissed: false);
      await tester.pump();
      expect(views.where((call) => call.method == 'acceptGesture'), isEmpty);
      expect(views.where((call) => call.method == 'rejectGesture'), hasLength(1),
          reason: 'the native side holds the touch back from the control');
      await fromNative(tester, const MethodCall('paste', 'BV1GJ411x7h7'));
      expect(pasted, isEmpty);

      await tester.pumpWidget(field(PasteButton(enabled: true, onText: pasted.add)));
      await fromNative(tester, const MethodCall('paste', 'BV1GJ411x7h7'));
      expect(pasted, ['BV1GJ411x7h7']);
      expect(sent, isEmpty);
    }, variant: ios);

    testWidgets('the control says once how much room it got against what it wants, for the log', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await host(tester, PasteButton(enabled: true, onText: (_) {}));
      await fromNative(
        tester,
        const MethodCall('layout', {'width': 40.0, 'height': 34.0, 'wantedWidth': 44.0, 'wantedHeight': 44.0}),
      );
      final event = logs.events.singleWhere((event) => event.msg == 'paste control');
      expect(event.f.map((key, value) => MapEntry(key, value.toJson())),
          {'width': 40.0, 'height': 34.0, 'wantedWidth': 44.0, 'wantedHeight': 44.0});
    }, variant: ios);
  });
}
