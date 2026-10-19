import 'dart:async';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/settings/follow_font.dart';
import 'package:bilifast/settings/font_page.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/feed_fakes.dart';

final trueType = Uint8List.fromList([0, 1, 0, 0, ...List.filled(60, 7)]);

/// Text whose style is built once and never rebuilt by anything around it.
class Frozen extends StatelessWidget {
  const Frozen({super.key});

  @override
  Widget build(BuildContext context) =>
      Text('冻结', key: const ValueKey('frozen'), style: TextStyle(fontFamily: BiliFonts.family));
}

void main() {
  late FontStore fonts;
  late List<String> loaded;

  setUp(() {
    loaded = [];
    fonts = FontStore.memory(loader: (bytes, family) async => loaded.add(family), logger: Logger(session: 'test'));
  });

  tearDown(() => BiliFonts.family = BiliFonts.miSans);

  Future<void> show(WidgetTester tester, Future<PickedFont?> Function() pick) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: FontPage(fonts: fonts, pick: pick)));
  }

  Finder tick(String row) => find.descendant(of: find.byKey(ValueKey(row)), matching: find.byIcon(Icons.check));

  String? familyOf(WidgetTester tester, String row, String text) => tester
      .widget<Text>(find.descendant(of: find.byKey(ValueKey(row)), matching: find.text(text)))
      .style
      ?.fontFamily;

  /// Lets a toast run out, so its timer is not left pending.
  Future<void> toastGone(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('each font is listed in itself, with a tick on the one in use; a tap switches at once', (tester) async {
    await show(tester, () async => null);
    expect(find.byKey(const ValueKey('font-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('font-miSans')), findsOneWidget);
    expect(find.byKey(const ValueKey('font-imported')), findsNothing, reason: 'nothing imported yet');
    expect(tick('font-miSans'), findsOneWidget);
    expect(tick('font-system'), findsNothing);
    expect(familyOf(tester, 'font-miSans', 'MiSans'), BiliFonts.miSans);
    expect(familyOf(tester, 'font-system', '系统字体'), isNot(BiliFonts.miSans),
        reason: 'the system row previews the system font, not the one the page is in');

    await tester.tap(find.byKey(const ValueKey('font-system')));
    await tester.pump();
    expect(fonts.choice, FontChoice.system);
    expect(BiliFonts.family, isNull);
    expect(tick('font-system'), findsOneWidget);
    expect(tick('font-miSans'), findsNothing);
  });

  testWidgets('导入字体 imports the picked file, lists it ticked and says so', (tester) async {
    await show(tester, () async => (name: '霞鹜文楷.ttf', bytes: trueType));
    await tester.tap(find.byKey(const ValueKey('font-import')));
    await tester.pump();
    expect(loaded, hasLength(1));
    expect(find.text('已使用 霞鹜文楷'), findsOneWidget);
    expect(tick('font-imported'), findsOneWidget);
    expect(familyOf(tester, 'font-imported', '霞鹜文楷'), loaded.single);
    expect(find.text('导入其他字体'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('a file that is not a font, or a picker that fails, says so and changes nothing', (tester) async {
    var answer = () async => (name: 'photo.ttf', bytes: Uint8List(40)) as PickedFont?;
    await show(tester, () => answer());
    await tester.tap(find.byKey(const ValueKey('font-import')));
    await tester.pump();
    expect(find.text('这不是字体文件'), findsOneWidget);
    expect(fonts.choice, FontChoice.miSans);
    await toastGone(tester);

    answer = () async => throw StateError('no picker');
    await tester.tap(find.byKey(const ValueKey('font-import')));
    await tester.pump();
    expect(find.text('无法打开文件'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('cancelling the picker says nothing', (tester) async {
    await show(tester, () async => null);
    await tester.tap(find.byKey(const ValueKey('font-import')));
    await tester.pump();
    expect(find.byKey(const ValueKey('toast')), findsNothing);
  });

  testWidgets('the rows press through accessibility, as VoiceOver and the Windows test driver do', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, () async => null);
    tester.semantics.tap(find.semantics.byLabel('系统字体'));
    await tester.pump();
    expect(fonts.choice, FontChoice.system);
    semantics.dispose();
  });

  testWidgets('设置 shows the font in use and opens 字体', (tester) async {
    final services = AppServices(
      environment: await AppEnvironment.load(
        keychain: FakeKeychain(const NoStoredCookies()),
        http: FeedHttp(),
        logger: Logger(session: 'test'),
      ),
      playback: AppPlayback(() => Completer<Never>().future),
      recents: await RecentStore.load(null),
      fonts: fonts,
    );
    addTearDown(services.playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SettingsPage(),
      ),
    );
    expect(find.text('MiSans'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-font')));
    await tester.pumpAndSettle();
    expect(find.byType(FontPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('font-system')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pumpAndSettle();
    expect(find.text('系统字体'), findsOneWidget);
  });

  testWidgets('a new font reaches styles nothing else rebuilds, and the page underneath keeps its state',
      (tester) async {
    await tester.pumpWidget(
      FollowFont(
        fonts: fonts,
        builder: (context) => MaterialApp(
          theme: ThemeData(fontFamily: BiliFonts.family),
          home: const Scaffold(body: Column(children: [Frozen(), _Counter()])),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('counter')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('frozen'))).style?.fontFamily, BiliFonts.miSans);

    fonts.select(FontChoice.system);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('frozen'))).style?.fontFamily, isNull);
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, isNot(BiliFonts.miSans));
    expect(find.text('1'), findsOneWidget, reason: 'state survives the rebuild');
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) =>
      TextButton(key: const ValueKey('counter'), onPressed: () => setState(() => _taps++), child: Text('$_taps'));
}
