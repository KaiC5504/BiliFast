import 'dart:math';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_orientation_host.dart';

void main() {
  late FakeOrientationHost host;
  late RecordingDeviceControls controls;
  late MemorySink logs;
  late OrientationController orientation;
  final page = Object();

  setUp(() {
    host = FakeOrientationHost();
    controls = RecordingDeviceControls();
    logs = MemorySink();
    final logger = Logger(session: 'test')..add(logs);
    orientation = OrientationController(controls: controls, host: host, logger: logger);
  });

  tearDown(() => orientation.dispose());

  List<Map<String, Object>> presentationLogs() => [
        for (final event in logs.events.where((event) => event.msg == 'presentation'))
          event.f.map((key, value) => MapEntry(key, value.toJson())),
      ];

  group('without a host', () {
    test('every move applies at once', () {
      final inWindow = OrientationController(controls: controls);
      inWindow.begin(page, videoIsVertical: false);
      inWindow.enterLandscape();
      expect(inWindow.presentation, Presentation.landscape);
      inWindow.enterVertical();
      expect(inWindow.presentation, Presentation.vertical);
      inWindow.exitToInline();
      expect(inWindow.presentation, Presentation.inline);
      inWindow.dispose();
    });
  });

  group('owners', () {
    test('a new owner while another is set lifts the lock and goes inline first', () async {
      final covered = Object();
      orientation.begin(covered, videoIsVertical: false);
      orientation.enterLandscape();
      orientation.toggleLock();
      expect(orientation.locked, isTrue);

      orientation.begin(page, videoIsVertical: true);
      expect(orientation.locked, isFalse);
      expect(orientation.presentation, Presentation.inline);
      expect(orientation.videoIsVertical, isTrue);
    });

    test("a covered page's late end does nothing to the page on top", () async {
      final covered = Object();
      orientation.begin(covered, videoIsVertical: false);
      orientation.begin(page, videoIsVertical: true);
      orientation.enterVertical();
      orientation.toggleLock();

      orientation.end(covered);
      orientation.setVideoIsVertical(false, owner: covered);
      expect(orientation.presentation, Presentation.vertical);
      expect(orientation.locked, isTrue);
      expect(orientation.videoIsVertical, isTrue);
    });

    test('the owner ends: lock off, vertical off, back inline', () async {
      orientation.begin(page, videoIsVertical: true);
      orientation.enterVertical();
      orientation.toggleLock();
      orientation.end(page);
      expect(orientation.presentation, Presentation.inline);
      expect(orientation.locked, isFalse);
      expect(orientation.videoIsVertical, isFalse);
    });

    test('the same page beginning again keeps its full screen and lock', () {
      orientation.begin(page, videoIsVertical: false);
      orientation.enterLandscape();
      orientation.toggleLock();
      orientation.begin(page, videoIsVertical: false);
      expect(orientation.presentation, Presentation.landscape);
      expect(orientation.locked, isTrue);
    });

    test('device orientation events start at the first begin and stop at end', () async {
      orientation.begin(page, videoIsVertical: false);
      orientation.begin(Object(), videoIsVertical: false);
      await settle();
      expect(host.events, [true]);

      orientation.end(page);
      await settle();
      expect(host.events, [true], reason: 'not the owner');
    });

    test('events after end are ignored', () async {
      orientation.begin(page, videoIsVertical: false);
      orientation.end(page);
      await settle();
      expect(host.events, [true, false]);
      host.turn(PhoneOrientation.landscapeLeft);
      expect(orientation.presentation, Presentation.inline);
    });
  });

  group('turning the phone', () {
    setUp(() => orientation.begin(page, videoIsVertical: false));

    test('inline turned landscape goes landscape, and back upright goes inline', () {
      host.turn(PhoneOrientation.landscapeLeft);
      expect(orientation.presentation, Presentation.landscape);
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.inline);
    });

    test('flat or upside down changes nothing', () {
      host.turn(PhoneOrientation.landscapeRight);
      host.turn(PhoneOrientation.faceUp);
      host.turn(PhoneOrientation.portraitUpsideDown);
      expect(orientation.presentation, Presentation.landscape);
    });

    test('locked, turning does nothing until the lock is lifted', () {
      orientation.toggleLock();
      host.turn(PhoneOrientation.landscapeLeft);
      expect(orientation.presentation, Presentation.inline);
      orientation.toggleLock();
      host.turn(PhoneOrientation.landscapeRight);
      expect(orientation.presentation, Presentation.landscape);
      orientation.toggleLock();
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.landscape);
    });

    test('a vertical video ignores rotation', () {
      orientation.setVideoIsVertical(true, owner: page);
      host.turn(PhoneOrientation.landscapeLeft);
      expect(orientation.presentation, Presentation.inline);
      orientation.enterVertical();
      host.turn(PhoneOrientation.portrait);
      host.turn(PhoneOrientation.landscapeRight);
      expect(orientation.presentation, Presentation.vertical);
    });

    test('the button with the phone flat: lifting it reports portrait, which waits for a real landscape', () async {
      host.turn(PhoneOrientation.faceUp);
      orientation.enterLandscape();
      await settle();
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.landscape);

      host.turn(PhoneOrientation.landscapeLeft);
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.inline);
    });

    test('the button with the phone already landscape: portrait exits at once', () async {
      host.phone = PhoneOrientation.landscapeRight;
      orientation.enterLandscape();
      await settle();
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.inline);
    });

    test('going inline clears the wait, so the next rotation is ordinary', () async {
      orientation.enterLandscape();
      orientation.exitToInline();
      host.turn(PhoneOrientation.landscapeLeft);
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.inline);
    });
  });

  group('requests', () {
    setUp(() => orientation.begin(page, videoIsVertical: false));

    test('each presentation asks for its mask, in order', () async {
      orientation.enterLandscape();
      orientation.enterVertical();
      orientation.exitToInline();
      await settle();
      expect(host.requests, [
        (1, OrientationMask.landscape),
        (2, OrientationMask.portrait),
        (3, OrientationMask.portrait),
      ]);
    });

    test('a refusal moves back to the previous presentation', () async {
      orientation.enterLandscape();
      await settle();
      host.refuse(host.lastRequest);
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(host.lastMask, OrientationMask.portrait);
      expect(controls.calls, ['enter', 'leave']);
      expect(logs.events.where((event) => event.msg == 'orientation request refused').single.level, LogLevel.warn);
      expect(presentationLogs().last, {'from': 'landscape', 'to': 'inline', 'reason': 'rotation refused'});
    });

    test('a refusal from vertical to landscape goes back to vertical, still full screen', () async {
      orientation.enterVertical();
      orientation.enterLandscape();
      await settle();
      host.refuse(host.lastRequest);
      expect(orientation.presentation, Presentation.vertical);
      expect(controls.calls, ['enter']);
    });

    test('a late refusal cannot undo a newer move', () async {
      orientation.enterLandscape();
      await settle();
      final stale = host.lastRequest;
      orientation.enterVertical();
      host.refuse(stale);
      expect(orientation.presentation, Presentation.vertical);
    });

    test('going inline is never undone', () async {
      orientation.enterLandscape();
      orientation.exitToInline();
      await settle();
      host.refuse(host.lastRequest);
      expect(orientation.presentation, Presentation.inline);
    });

    test('a retried landscape that is refused stays put', () async {
      orientation.enterLandscape();
      orientation.enterLandscape();
      await settle();
      host.refuse(host.lastRequest);
      expect(orientation.presentation, Presentation.landscape);
    });

    test("the revert's own request being refused changes nothing more", () async {
      orientation.enterLandscape();
      await settle();
      final request = host.lastRequest;
      host.refuse(request);
      await settle();
      host.refuse(request);
      expect(orientation.presentation, Presentation.inline);
      expect(controls.calls, ['enter', 'leave']);
    });

    test('a request that fails moves back to the previous presentation', () async {
      host.failing.add(1);
      orientation.enterLandscape();
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(controls.calls, ['enter', 'leave']);
      expect(presentationLogs().last, {'from': 'landscape', 'to': 'inline', 'reason': 'request failed'});
      expect(logs.events.where((event) => event.msg == 'orientation host failed'), isNotEmpty);
    });

    test('a landscape whose side cannot be read moves back, then asks for portrait', () async {
      host.interfaceError = StateError('no window scene');
      orientation.toggleLock();
      orientation.enterLandscape();
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(host.requests, [(1, OrientationMask.portrait)]);
    });

    test('a failure of an older request cannot undo a newer move', () async {
      host.failing.add(1);
      orientation.enterLandscape();
      orientation.enterVertical();
      await settle();
      expect(orientation.presentation, Presentation.vertical);
      expect(host.requests, [(2, OrientationMask.portrait)]);
    });

    test('a failed move inline is never undone', () async {
      orientation.enterLandscape();
      await settle();
      host.failing.add(2);
      orientation.exitToInline();
      await settle();
      expect(orientation.presentation, Presentation.inline);
      expect(controls.calls, ['enter', 'leave']);
    });

    test('locked in landscape keeps the side it is on', () async {
      host.screen = ScreenOrientation.landscapeLeft;
      orientation.enterLandscape();
      orientation.toggleLock();
      await settle();
      expect(host.lastMask, OrientationMask.landscapeLeft);

      host.screen = ScreenOrientation.landscapeRight;
      orientation.enterLandscape();
      await settle();
      expect(host.lastMask, OrientationMask.landscapeRight);

      orientation.toggleLock();
      await settle();
      expect(host.lastMask, OrientationMask.landscape);
    });

    test('locking inline asks for nothing', () async {
      orientation.toggleLock();
      await settle();
      expect(host.requests, isEmpty);
    });
  });

  group('full screen and the device controls', () {
    test('entering and leaving full screen call the controls once each way', () async {
      orientation.begin(page, videoIsVertical: false);
      orientation.enterLandscape();
      orientation.enterVertical();
      orientation.enterLandscape();
      orientation.exitToInline();
      orientation.exitToInline();
      orientation.enterVertical();
      orientation.end(page);
      await settle();
      expect(controls.calls, ['enter', 'leave', 'enter', 'leave']);
    });

    test('every change of presentation is logged', () {
      orientation.begin(page, videoIsVertical: false);
      orientation.enterLandscape();
      orientation.enterLandscape();
      orientation.exitToInline();
      expect(presentationLogs(), [
        {'from': 'inline', 'to': 'landscape'},
        {'from': 'landscape', 'to': 'inline'},
      ]);
    });

    test('listeners hear presentation and lock changes', () {
      var heard = 0;
      orientation.addListener(() => heard++);
      orientation.begin(page, videoIsVertical: false);
      final afterBegin = heard;
      orientation.enterLandscape();
      expect(heard, greaterThan(afterBegin));
      final afterMove = heard;
      orientation.toggleLock();
      expect(heard, greaterThan(afterMove));
    });
  });

  group('the turn takeover (旋转动画)', () {
    test('the host has it only while a page owns the orientation, the one page that draws the turns', () async {
      await orientation.setTurnTakeover(true);
      expect(host.takeovers, isEmpty);
      expect(orientation.turnTakeover, isFalse);

      orientation.begin(page, videoIsVertical: false);
      expect(orientation.turnTakeover, isTrue);
      await settle();
      expect(host.takeovers, [true]);

      orientation.end(page);
      expect(orientation.turnTakeover, isFalse);
      await settle();
      expect(host.takeovers, [true, false]);
    });

    test('the switch flipped while a page owns the orientation reaches the host at once; off, nothing is armed',
        () async {
      orientation.begin(page, videoIsVertical: false);
      await settle();
      expect(host.takeovers, isEmpty);
      await orientation.setTurnTakeover(true);
      expect(host.takeovers, [true]);
      await orientation.setTurnTakeover(false);
      expect(host.takeovers, [true, false]);

      orientation
        ..end(page)
        ..begin(page, videoIsVertical: false)
        ..enterLandscape();
      await settle();
      expect(host.takeovers, [true, false]);
      expect(orientation.turnTakeover, isFalse);
    });

    test("the owner's end hands the turns back before its exit to inline goes out, so the system turns it", () async {
      await orientation.setTurnTakeover(true);
      orientation
        ..begin(page, videoIsVertical: false)
        ..enterLandscape();
      await settle();
      expect(host.sent, ['takeover on', 'landscape']);

      orientation.end(page);
      await settle();
      expect(host.sent, ['takeover on', 'landscape', 'takeover off', 'portrait']);
    });

    test("a page beginning over a full-screen one: the covered page's exit goes out unarmed, and the turns are taken "
        "over again from the new page's first move", () async {
      final covered = Object();
      await orientation.setTurnTakeover(true);
      orientation
        ..begin(covered, videoIsVertical: false)
        ..enterLandscape();
      await settle();
      host.sent.clear();

      orientation.begin(page, videoIsVertical: false);
      expect(orientation.turnTakeover, isFalse);
      await settle();
      expect(host.sent, ['takeover off', 'portrait']);

      orientation.enterLandscape();
      expect(orientation.turnTakeover, isTrue);
      await settle();
      expect(host.sent, ['takeover off', 'portrait', 'takeover on', 'landscape']);
    });

    test('a host that fails to take the turns over leaves them to the system, and the next move asks again', () async {
      host.takeoverError = StateError('channel closed');
      await orientation.setTurnTakeover(true);
      orientation.begin(page, videoIsVertical: false);
      await settle();
      expect(orientation.turnTakeover, isFalse);
      expect(logs.events.where((event) => event.msg == 'orientation host failed'), hasLength(1));

      host.takeoverError = null;
      orientation.enterLandscape();
      expect(orientation.turnTakeover, isTrue);
      await settle();
      expect(host.sent, ['takeover on', 'landscape']);
    });
  });

  group('旋转动画 (the 开发者 choice)', () {
    test('the choice is kept whether armed or not', () async {
      expect(orientation.turnTakeoverChosen, isFalse);
      await orientation.setTurnTakeover(true);
      expect(orientation.turnTakeoverChosen, isTrue);
      expect(orientation.turnTakeover, isFalse);
      orientation.begin(page, videoIsVertical: false);
      expect(orientation.turnTakeover, isTrue);
      await orientation.setTurnTakeover(false);
      expect(orientation.turnTakeoverChosen, isFalse);
      expect(host.takeovers, [true, false]);
    });

    test('setting the same choice again sends nothing', () async {
      orientation.begin(page, videoIsVertical: false);
      await orientation.setTurnTakeover(true);
      await orientation.setTurnTakeover(true);
      orientation.enterLandscape();
      await settle();
      expect(host.sent, ['takeover on', 'landscape']);
    });

    test('系统 disarms, and the moves after it go out unarmed', () async {
      orientation.begin(page, videoIsVertical: false);
      await orientation.setTurnTakeover(true);
      await orientation.setTurnTakeover(false);
      expect(orientation.turnTakeover, isFalse);
      orientation.enterLandscape();
      await settle();
      expect(host.sent, ['takeover on', 'takeover off', 'landscape']);
    });

    test('nothing goes out while no page owns the orientation; the choice goes out when one begins', () async {
      await orientation.setTurnTakeover(false);
      await orientation.setTurnTakeover(true);
      await settle();
      expect(host.sent, isEmpty);
      expect(orientation.turnTakeover, isFalse);

      orientation.begin(page, videoIsVertical: false);
      await settle();
      expect(host.takeovers, [true]);
    });

    test('a failed change resets, so setting it again resends', () async {
      orientation.begin(page, videoIsVertical: false);
      host.takeoverError = StateError('channel closed');
      await orientation.setTurnTakeover(true);
      expect(orientation.turnTakeover, isFalse);
      expect(logs.events.where((event) => event.msg == 'orientation host failed'), hasLength(1));

      host.takeoverError = null;
      await orientation.setTurnTakeover(true);
      expect(orientation.turnTakeover, isTrue);
      expect(host.takeovers, [true]);
    });

    test('a failed hand-back leaves the host unknown, so the next sync sends off again', () async {
      orientation.begin(page, videoIsVertical: false);
      await orientation.setTurnTakeover(true);
      host.takeoverError = StateError('channel closed');
      await orientation.setTurnTakeover(false);
      host.takeoverError = null;

      orientation.end(page);
      await settle();
      expect(host.sent, ['takeover on', 'takeover off']);
      orientation.begin(page, videoIsVertical: false);
      await settle();
      expect(host.sent, ['takeover on', 'takeover off']);
    });

    test('turns pass through with their ids', () async {
      final turns = <TurnStart>[];
      final subscription = orientation.turns.listen(turns.add);
      host.startTurn(pi / 2, duration: const Duration(milliseconds: 300));
      host.startTurn(-pi / 2);
      expect(turns, [
        (id: 1, angle: pi / 2, duration: const Duration(milliseconds: 300)),
        (id: 2, angle: -pi / 2, duration: const Duration(milliseconds: 280)),
      ]);
      await subscription.cancel();
    });

    test('turnDrawn carries the turn id; a failure is only logged', () async {
      orientation
        ..turnDrawn(3)
        ..turnDrawn(5);
      await settle();
      expect(host.drawnTurns, [3, 5]);

      host.drawnError = StateError('channel closed');
      orientation.turnDrawn(6);
      await settle();
      expect(host.drawnTurns, [3, 5]);
      expect(logs.events.where((event) => event.msg == 'orientation host failed'), hasLength(1));
    });

    test('without a host nothing is armed and the turn stream is empty', () async {
      final inWindow = OrientationController(controls: controls);
      await inWindow.setTurnTakeover(true);
      inWindow.begin(page, videoIsVertical: false);
      expect(inWindow.turnTakeover, isFalse);
      expect(inWindow.turnTakeoverChosen, isTrue);
      inWindow.turnDrawn(1);
      expect(await inWindow.turns.isEmpty, isTrue);
      inWindow.dispose();
    });
  });
}
