import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilifast/app/appearance.dart';
import 'package:bilifast/device/ios/device_api.g.dart' show NativeInterfaceStyle;
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('appearance'));
  tearDown(() => folder.deleteSync(recursive: true));

  String path() => '${folder.path}/appearance.json';

  testWidgets('☾/☀ turns the other mode, stops following iOS, and is kept for the next launch', (tester) async {
    final styles = <NativeInterfaceStyle>[];
    final model = (await tester.runAsync(() => AppearanceModel.load(path(), native: styles.add)))!;
    addTearDown(model.dispose);
    model.attach();
    expect(model.dark, isFalse, reason: 'light by default');
    expect(styles.last, NativeInterfaceStyle.light);

    var heard = 0;
    model.addListener(() => heard++);
    await tester.runAsync(model.toggle);
    expect(BiliTheme.dark, isTrue);
    expect(heard, 1);
    expect(styles.last, NativeInterfaceStyle.dark);
    expect(jsonDecode(File(path()).readAsStringSync()), {'dark': true, 'followSystem': false});

    BiliTheme.dark = false;
    final again = (await tester.runAsync(() => AppearanceModel.load(path())))!;
    addTearDown(again.dispose);
    again.attach();
    expect(BiliTheme.dark, isTrue, reason: 'kept');
  });

  testWidgets('深色跟随系统 follows iOS as it changes; ☾/☀ then leaves it', (tester) async {
    final styles = <NativeInterfaceStyle>[];
    final model = AppearanceModel.memory(native: styles.add);
    addTearDown(model.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    model.attach();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(BiliTheme.dark, isFalse, reason: 'not following yet');

    await model.setFollowSystem(true);
    expect(BiliTheme.dark, isTrue);
    expect(styles.last, NativeInterfaceStyle.system, reason: "iOS's own sheets follow iOS too");
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(BiliTheme.dark, isFalse);

    await model.toggle();
    expect(model.followSystem, isFalse);
    expect(BiliTheme.dark, isTrue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(BiliTheme.dark, isTrue, reason: 'no longer following');
  });

  testWidgets('turning it off keeps the mode on screen, and its listeners still hear the switch', (tester) async {
    final model = AppearanceModel.memory(followSystem: true);
    addTearDown(model.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    model.attach();
    expect(BiliTheme.dark, isTrue);
    var heard = 0;
    model.addListener(() => heard++);
    await model.setFollowSystem(false);
    expect(BiliTheme.dark, isTrue);
    expect(model.followSystem, isFalse);
    expect(heard, 1);
  });

  testWidgets('a file that cannot be read is set aside and the defaults apply', (tester) async {
    File(path()).writeAsStringSync('{nope');
    final model = (await tester.runAsync(() => AppearanceModel.load(path())))!;
    addTearDown(model.dispose);
    model.attach();
    expect(BiliTheme.dark, isFalse);
    expect(File('${path()}.bad').existsSync(), isTrue);
  });

  testWidgets('the PC\'s --dark is dark for the run and saves nothing', (tester) async {
    final model = (await tester.runAsync(() => AppearanceModel.load(path())))!;
    addTearDown(model.dispose);
    model
      ..forced = true
      ..attach();
    expect(BiliTheme.dark, isTrue);
    await tester.runAsync(model.toggle);
    expect(File(path()).existsSync(), isFalse);
  });

  testWidgets('深色跟随系统 is kept for the next launch and follows iOS from the first frame', (tester) async {
    File(path()).writeAsStringSync(jsonEncode({'dark': false, 'followSystem': true}));
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    final styles = <NativeInterfaceStyle>[];
    final model = (await tester.runAsync(() => AppearanceModel.load(path(), native: styles.add)))!;
    addTearDown(model.dispose);
    model.attach();
    expect(model.followSystem, isTrue);
    expect(BiliTheme.dark, isTrue);
    expect(styles.last, NativeInterfaceStyle.system);
  });

  testWidgets("under the PC's --dark ☾/☀ still turns it, and nothing is saved", (tester) async {
    final model = (await tester.runAsync(() => AppearanceModel.load(path())))!;
    addTearDown(model.dispose);
    model
      ..forced = true
      ..attach();
    await tester.runAsync(model.toggle);
    expect(BiliTheme.dark, isFalse);
    await tester.runAsync(model.toggle);
    expect(BiliTheme.dark, isTrue);
    expect(File(path()).existsSync(), isFalse);
  });

  testWidgets("away from the screen iOS's trait flips are ignored, and the mode is settled on the way back", (
    tester,
  ) async {
    final model = AppearanceModel.memory(followSystem: true);
    addTearDown(model.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    model.attach();
    var heard = 0;
    model.addListener(() => heard++);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(heard, 0, reason: 'no redraw while away');
    expect(BiliTheme.dark, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(BiliTheme.dark, isTrue, reason: 'iOS is dark now');
    expect(heard, 1);
  });

  testWidgets('a page covered while the mode changes shows the new mode when uncovered, const widgets included', (
    tester,
  ) async {
    final model = AppearanceModel.memory();
    addTearDown(model.dispose);
    model.attach();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppearanceRedraw(
        model: model,
        builder: (context) => MaterialApp(navigatorKey: navigator, home: const _Swatch()),
      ),
    );
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ColoredBox(color: Color(0xFF000000)))));
    await tester.pumpAndSettle();
    await model.toggle();
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('swatch'))).color, const Color(0xFF17181A));
  });

  testWidgets('a change draws every widget again, const ones and painters included, state kept', (tester) async {
    final model = AppearanceModel.memory();
    addTearDown(model.dispose);
    model.attach();
    await tester.pumpWidget(
      AppearanceRedraw(
        model: model,
        builder: (context) => const Directionality(textDirection: TextDirection.ltr, child: _Counter()),
      ),
    );
    await tester.tap(find.byType(_Counter));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('box'))).color, BiliColors.card);
    final painter = tester.widget<CustomPaint>(find.byKey(const ValueKey('paint'))).painter! as _Card;
    expect(painter.painted.last, const Color(0xFFFFFFFF));

    await model.toggle();
    await tester.pump();
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('box'))).color, const Color(0xFF17181A));
    expect(painter.painted.last, const Color(0xFF17181A), reason: 'a painter that compares equal paints again');
    expect(find.text('1'), findsOneWidget, reason: 'state kept');
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  static final _painter = _Card();

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: Column(
      children: [
        ColoredBox(key: const ValueKey('box'), color: BiliColors.card, child: Text('$taps')),
        CustomPaint(key: const ValueKey('paint'), size: const Size(10, 10), painter: _painter),
      ],
    ),
  );
}

class _Card extends CustomPainter {
  final painted = <Color>[];

  @override
  void paint(Canvas canvas, Size size) => painted.add(BiliColors.card);

  @override
  bool shouldRepaint(_Card oldDelegate) => false;
}

class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(key: const ValueKey('swatch'), color: BiliColors.card, child: const SizedBox.expand());
}
