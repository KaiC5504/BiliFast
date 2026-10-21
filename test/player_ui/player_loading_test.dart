import 'package:bili_core/engine.dart' show EngineSnapshot, PlaybackMode;
import 'package:bilifast/playback/overlay_stats.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/player_loading.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

const _measured = OverlayStats(mode: PlaybackMode.btr, engine: EngineSnapshot());

Future<void> _precache(WidgetTester tester) => tester.runAsync(() => AssetLottie(PlayerLoading.asset).load());

Widget _host(Widget child, {bool still = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 440, height: 247.5, child: child),
    ),
  ),
);

double _frame(WidgetTester tester) => tester.widget<Lottie>(find.byType(Lottie)).controller!.value;

void main() {
  group('the line', () {
    test('reads the speed in KB/s to two decimals, as the official app', () {
      expect(PlayerLoading.line(_measured.copyWith(downloadBps: 69.33 * 1024)), '正在缓冲... 69.33 KB/s');
      expect(PlayerLoading.line(_measured.copyWith(downloadBps: 460 * 1024)), '正在缓冲... 460.00 KB/s');
    });

    test('a measured zero still reads, as in 66', () {
      expect(PlayerLoading.line(_measured), '正在缓冲... 0.00 KB/s');
    });

    test('past 1024 KB/s it is MB/s', () {
      expect(PlayerLoading.speed(_measured.copyWith(downloadBps: 1023.99 * 1024)), '1023.99 KB/s');
      expect(PlayerLoading.speed(_measured.copyWith(downloadBps: 1023.999 * 1024)), '1.00 MB/s');
      expect(PlayerLoading.speed(_measured.copyWith(downloadBps: 3.5 * 1048576)), '3.50 MB/s');
    });

    test('no speed before the engine reports, in direct mode, or with no session', () {
      expect(PlayerLoading.line(const OverlayStats(mode: PlaybackMode.btr, downloadBps: 5000)), PlayerLoading.message);
      expect(PlayerLoading.line(const OverlayStats(mode: PlaybackMode.direct)), PlayerLoading.message);
      expect(PlayerLoading.line(null), PlayerLoading.message);
    });
  });

  testWidgets('loops the TV over the line, which follows the stats', (tester) async {
    await _precache(tester);
    final stats = ValueNotifier(const OverlayStats(mode: PlaybackMode.btr));
    addTearDown(stats.dispose);
    await tester.pumpWidget(_host(PlayerLoading(stats: stats)));
    await tester.pump();
    expect(find.text(PlayerLoading.message), findsOneWidget);
    expect(tester.getSize(find.byType(Lottie)), const Size.square(PlayerLoadingTheme.tvSize));
    expect(tester.getCenter(find.byType(Lottie)), const Offset(220, 247.5 / 2));
    final start = _frame(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_frame(tester), isNot(start));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.hasRunningAnimations, isTrue, reason: 'it loops');

    stats.value = _measured.copyWith(downloadBps: 69.33 * 1024);
    await tester.pump();
    expect(find.text('正在缓冲... 69.33 KB/s'), findsOneWidget);
    final line = tester.getRect(find.byKey(const ValueKey('player-loading-text')));
    expect(line.center.dx, closeTo(220, 0.01));
    expect(line.top, 247.5 / 2 + PlayerLoadingTheme.tvSize / 2 + PlayerLoadingTheme.gap);
  });

  testWidgets('Reduce Motion holds the TV on its first frame', (tester) async {
    await _precache(tester);
    await tester.pumpWidget(_host(const PlayerLoading(), still: true));
    await tester.pump(const Duration(seconds: 1));
    expect(_frame(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a muted ticker stops it', (tester) async {
    await _precache(tester);
    await tester.pumpWidget(_host(const TickerMode(enabled: false, child: PlayerLoading())));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('takes no touches', (tester) async {
    await _precache(tester);
    var taps = 0;
    await tester.pumpWidget(
      _host(
        Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(color: BiliColors.videoBackground),
            ),
            const PlayerLoading(),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(Lottie), warnIfMissed: false);
    expect(taps, 1);
  });

  group('PlayerWait', () {
    late ValueNotifier<PlayerStatus> status;
    late PlayerWait wait;

    setUp(() {
      status = ValueNotifier(PlayerStatus.playing);
      wait = PlayerWait(status);
    });

    tearDown(() {
      wait.dispose();
      status.dispose();
    });

    testWidgets('a wait for data shows once it has lasted the grace', (tester) async {
      status.value = PlayerStatus.buffering;
      await tester.pump(PlayerLoadingTheme.grace - const Duration(milliseconds: 1));
      expect(wait.value, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(wait.value, isTrue);
      status.value = PlayerStatus.playing;
      expect(wait.value, isFalse);
    });

    testWidgets('a short blip shows nothing, and the next wait starts the grace over', (tester) async {
      status.value = PlayerStatus.buffering;
      await tester.pump(const Duration(milliseconds: 400));
      status.value = PlayerStatus.playing;
      await tester.pump(const Duration(seconds: 1));
      expect(wait.value, isFalse);
      status.value = PlayerStatus.buffering;
      await tester.pump(const Duration(milliseconds: 400));
      expect(wait.value, isFalse);
      status.value = PlayerStatus.playing;
    });

    testWidgets('paused or ended is no wait', (tester) async {
      for (final rest in [PlayerStatus.paused, PlayerStatus.ended]) {
        status.value = PlayerStatus.buffering;
        await tester.pump(PlayerLoadingTheme.grace);
        expect(wait.value, isTrue);
        status.value = rest;
        expect(wait.value, isFalse);
        await tester.pump(PlayerLoadingTheme.grace);
        expect(wait.value, isFalse);
      }
    });

    testWidgets('inactive (a covered page) shows nothing, and the grace starts over when active again', (tester) async {
      status.value = PlayerStatus.buffering;
      await tester.pump(PlayerLoadingTheme.grace);
      wait.active = false;
      expect(wait.value, isFalse);
      await tester.pump(PlayerLoadingTheme.grace);
      expect(wait.value, isFalse);
      wait.active = true;
      expect(wait.value, isFalse);
      await tester.pump(PlayerLoadingTheme.grace);
      expect(wait.value, isTrue);
    });
  });
}
