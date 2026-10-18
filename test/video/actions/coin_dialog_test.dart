import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/actions/coin_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';

final class Rig {
  Rig({double balance = 873, int maxCoins = 2}) : actions = FakeVideoActions(balance: balance, maxCoins: maxCoins);

  final FakeVideoActions actions;
  final links = <Uri>[];
  bool linkOpens = true;
  int closes = 0;

  Future<bool> openLink(Uri link) async {
    links.add(link);
    return linkOpens;
  }

  int get balanceAsks => actions.calls.where((call) => call == 'coinBalance').length;

  List<String> get sent => actions.calls.where((call) => call.startsWith('coin ')).toList();

  Future<void> mount(WidgetTester tester, {Size size = const Size(440, 956), bool settle = true}) async {
    final landscape = size.width > size.height;
    final padding = landscape
        ? const EdgeInsets.only(left: 62, right: 62, bottom: 21)
        : const EdgeInsets.only(top: 62, bottom: 34);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: 3, padding: padding, viewPadding: padding),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            key: UniqueKey(),
            initialEntries: [
              OverlayEntry(
                builder: (context) => CoinDialog(actions: actions, onClose: () => closes++, openLink: openLink),
              ),
            ],
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }
}

/// The toast fades in, waits two seconds and fades out, each step starting a frame after the last ends.
Future<void> expireToast(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Size crate(WidgetTester tester, int multiply) => tester.getSize(find.bySemanticsLabel('$multiply 硬币'));

void main() {
  setUp(() => CoinDialog.alsoLike = true);

  testWidgets('opens on the two-coin crate, the balance -- until it is known', (tester) async {
    final rig = Rig();
    await rig.mount(tester, settle: false);
    expect(find.text('硬币余额：--'), findsOneWidget);
    expect(find.text('上滑或点击22娘投硬币'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('硬币余额：873.0'), findsOneWidget);
    expect(crate(tester, 2).width, ActionTheme.selectedCrate);
    expect(crate(tester, 1).width, ActionTheme.crate);
    expect(tester.getCenter(find.bySemanticsLabel('2 硬币')).dx, closeTo(220, 0.5));
    expect(tester.getCenter(find.bySemanticsLabel('2 硬币')).dy, closeTo(956 * ActionTheme.cratesCentre, 0.5));
    expect(rig.balanceAsks, 1);
  });

  testWidgets('the arrows pick a crate, and so does a tap on the other one', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.bySemanticsLabel('选择1硬币'));
    await tester.pumpAndSettle();
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);
    expect(tester.getCenter(find.bySemanticsLabel('1 硬币')).dx, closeTo(220, 0.5));

    await tester.tap(find.bySemanticsLabel('选择2硬币'));
    await tester.pumpAndSettle();
    expect(crate(tester, 2).width, ActionTheme.selectedCrate);

    await tester.tap(find.bySemanticsLabel('1 硬币'));
    await tester.pumpAndSettle();
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);
    expect(rig.sent, isEmpty);
  });

  testWidgets('a sideways swipe picks: left for two, right for one', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.drag(find.bySemanticsLabel('投币'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);

    await tester.drag(find.bySemanticsLabel('投币'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(crate(tester, 2).width, ActionTheme.selectedCrate);
    expect(rig.sent, isEmpty);
  });

  testWidgets('a repost offers only the one-coin crate, with no arrows', (tester) async {
    final rig = Rig(maxCoins: 1);
    await rig.mount(tester);

    expect(find.bySemanticsLabel('2 硬币'), findsNothing);
    expect(find.bySemanticsLabel('选择1硬币'), findsNothing);
    expect(find.bySemanticsLabel('选择2硬币'), findsNothing);
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);
    expect(tester.getCenter(find.bySemanticsLabel('1 硬币')).dx, closeTo(220, 0.5));

    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 1 alsoLike=true']);
  });

  testWidgets('the balance is asked three times, a second and then two apart, and says so if all fail', (
    tester,
  ) async {
    final sink = MemorySink();
    Logger.shared.add(sink);
    addTearDown(() => Logger.shared.remove(sink));
    final rig = Rig();
    rig.actions.balanceFailure = Exception('offline');
    await rig.mount(tester, settle: false);
    await tester.pump();
    expect(rig.balanceAsks, 1);

    await tester.pump(const Duration(milliseconds: 990));
    expect(rig.balanceAsks, 1);
    expect(find.text('硬币余额：--'), findsOneWidget, reason: 'still trying');
    await tester.pump(const Duration(milliseconds: 20));
    expect(rig.balanceAsks, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(rig.balanceAsks, 3);
    await tester.pump(const Duration(seconds: 10));
    expect(rig.balanceAsks, 3);
    expect(find.text('硬币余额获取失败'), findsOneWidget);
    expect(find.text('硬币余额：--'), findsNothing);
    expect(
      [
        for (final event in sink.events)
          if (event.msg == 'coin balance failed') event.f['error'],
      ],
      List.filled(3, const LogString('Exception: offline')),
    );

    // Unknown, both crates stay open as far as the coins still allowed.
    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 2 alsoLike=true']);
  });

  testWidgets('a retry that succeeds shows the balance', (tester) async {
    final rig = Rig(balance: 12.5);
    rig.actions.balanceFailure = Exception('offline');
    await rig.mount(tester, settle: false);
    await tester.pump();
    rig.actions.balanceFailure = null;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(rig.balanceAsks, 2);
    expect(find.text('硬币余额：12.5'), findsOneWidget);
  });

  testWidgets('a closed dialog stops asking', (tester) async {
    final rig = Rig();
    rig.actions.balanceFailure = Exception('offline');
    await rig.mount(tester, settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.pump(const Duration(seconds: 5));
    expect(rig.balanceAsks, 1);
  });

  testWidgets('with one coin and a half it moves to the one-coin crate', (tester) async {
    final rig = Rig(balance: 1.5);
    await rig.mount(tester);
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);
    expect(find.text('上滑或点击22娘投硬币'), findsOneWidget);
  });

  testWidgets('a relation that lands while it is up, with one coin given, leaves only the one-coin crate', (
    tester,
  ) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(crate(tester, 2).width, ActionTheme.selectedCrate);

    rig.actions
      ..coins = 1
      ..maxCoins = 1
      ..changed();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 硬币'), findsNothing);
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);
    expect(tester.getCenter(find.bySemanticsLabel('1 硬币')).dx, closeTo(220, 0.5));
    expect(find.text('上滑或点击22娘投硬币'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 1 alsoLike=true']);
  });

  testWidgets('a relation that lands at the limit closes it, and coin() says it is full', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.actions
      ..coins = 2
      ..maxCoins = 0
      ..changed();
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 1 alsoLike=false']);
    expect(rig.closes, 1);
  });

  testWidgets('a change while its own coin flies neither stops the throw nor closes it twice', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    rig.actions
      ..coins = 2
      ..maxCoins = 0
      ..changed();
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 2 alsoLike=true']);
    expect(rig.closes, 1);
  });

  testWidgets('without enough coins 22娘 says so and nothing is sent', (tester) async {
    final rig = Rig(balance: 0.5);
    await rig.mount(tester);
    expect(find.text('硬币不足'), findsOneWidget);
    expect(find.text('硬币余额：0.5'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pump();
    expect(find.text('硬币不足'), findsNWidgets(2), reason: 'the hint and the toast');
    await tester.drag(find.bySemanticsLabel('投币'), const Offset(0, -150));
    await expireToast(tester);
    expect(rig.sent, isEmpty);
    expect(rig.closes, 0);
  });

  testWidgets('a tap on 22娘 throws: the coin goes out with 同时点赞内容, then the dialog closes', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.sent, isEmpty, reason: 'the coin is still flying');
    await tester.pump(const Duration(milliseconds: 250));
    expect(rig.sent, ['coin 2 alsoLike=true']);
    expect(rig.closes, 0);
    await tester.pumpAndSettle();
    expect(rig.closes, 1);

    await tester.tap(find.bySemanticsLabel('投币').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(rig.sent, hasLength(1), reason: 'one throw per dialog');
  });

  testWidgets('同时点赞内容 off sends the coin alone, and stays off for the next dialog', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.bySemanticsLabel('同时点赞内容'));
    await tester.pump();
    expect(CoinDialog.alsoLike, isFalse);
    await tester.tap(find.bySemanticsLabel('选择1硬币'));
    await tester.pumpAndSettle();
    await tester.drag(find.bySemanticsLabel('投币'), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 1 alsoLike=false']);

    final next = Rig();
    await next.mount(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('同时点赞内容')),
      isSemantics(label: '同时点赞内容', hasToggledState: true, isToggled: false, hasTapAction: true),
    );
    semantics.dispose();
  });

  testWidgets('a tap on the picked crate throws too', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tap(find.bySemanticsLabel('2 硬币'));
    await tester.pumpAndSettle();
    expect(rig.sent, ['coin 2 alsoLike=true']);
  });

  testWidgets('✕ and a tap on the dim close without sending', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.tap(find.bySemanticsLabel('关闭'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(rig.closes, 1);

    final dim = Rig();
    await dim.mount(tester);
    await tester.tapAt(const Offset(220, 150));
    await tester.pumpAndSettle();
    expect(dim.closes, 1);
    expect([...rig.sent, ...dim.sent], isEmpty);
  });

  testWidgets('a tap between the controls on the crates row does not close', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tapAt(Offset(220 + ActionTheme.crateSpacing, 956 * ActionTheme.cratesCentre + 60));
    await tester.pumpAndSettle();
    expect(rig.closes, 0);
  });

  testWidgets('如何获取硬币？ opens the help page, or says how to earn coins when it cannot', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tap(find.bySemanticsLabel('如何获取硬币？'));
    await tester.pump();
    expect(rig.links, [CoinDialog.helpLink]);
    expect(find.text('每日登录可获得1硬币'), findsNothing);

    rig.linkOpens = false;
    await tester.tap(find.bySemanticsLabel('如何获取硬币？'));
    await tester.pump();
    expect(find.text('每日登录可获得1硬币'), findsOneWidget);
    await expireToast(tester);
    expect(rig.closes, 0);
  });

  testWidgets('a help link that throws is logged with its error and still says how to earn coins', (tester) async {
    final sink = MemorySink();
    Logger.shared.add(sink);
    addTearDown(() => Logger.shared.remove(sink));
    final rig = Rig();
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 956)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => CoinDialog(
                  actions: rig.actions,
                  onClose: () => rig.closes++,
                  openLink: (_) async => throw StateError('no browser'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('如何获取硬币？'));
    await tester.pump();
    expect(find.text('每日登录可获得1硬币'), findsOneWidget);
    expect(
      [
        for (final event in sink.events)
          if (event.msg == 'coin help link failed') event.f['error'],
      ],
      [const LogString('Bad state: no browser')],
    );
    await expireToast(tester);
  });

  testWidgets('landscape full screen lays the column out in the middle, every control reachable', (tester) async {
    final rig = Rig();
    await rig.mount(tester, size: const Size(956, 440));
    expect(tester.takeException(), isNull);

    final two = tester.getRect(find.bySemanticsLabel('2 硬币'));
    expect(two.center.dx, closeTo(478, 1));
    expect(two.top, greaterThanOrEqualTo(0));
    final close = tester.getRect(find.bySemanticsLabel('关闭'));
    expect(close.bottom, lessThanOrEqualTo(440 - 21));
    expect(tester.getRect(find.bySemanticsLabel('同时点赞内容')).left, greaterThan(close.left - 300));

    await tester.tap(find.bySemanticsLabel('同时点赞内容'));
    await tester.tap(find.bySemanticsLabel('选择1硬币'));
    await tester.pumpAndSettle();
    expect(CoinDialog.alsoLike, isFalse);
    expect(crate(tester, 1).width, closeTo(ActionTheme.selectedCrate * (two.width / ActionTheme.selectedCrate), 0.5));
    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.pumpAndSettle();
    expect(rig.closes, 1);
  });

  testWidgets('everything presses through accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);

    tester.semantics.tap(find.semantics.byLabel('选择1硬币'));
    await tester.pumpAndSettle();
    expect(crate(tester, 1).width, ActionTheme.selectedCrate);
    tester.semantics.tap(find.semantics.byLabel('同时点赞内容'));
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel('如何获取硬币？'));
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel('投币'));
    await tester.pumpAndSettle();

    expect(rig.links, hasLength(1));
    expect(rig.sent, ['coin 1 alsoLike=false']);
    expect(rig.closes, 1);
    semantics.dispose();
  });

  testWidgets('with animations off the throw is immediate', (tester) async {
    final rig = Rig();
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 956), disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => CoinDialog(actions: rig.actions, onClose: () => rig.closes++),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('投币'));
    await tester.pump();
    await tester.pump();
    expect(rig.sent, ['coin 2 alsoLike=true']);
    await tester.pumpAndSettle();
    expect(rig.closes, 1);
  });
}
