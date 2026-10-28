import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_orientation_host.dart';

void main() {
  late FakeOrientationHost host;
  late RecordingDeviceControls controls;
  late OrientationController orientation;
  final page = Object();

  OrientationController make() =>
      OrientationController(controls: controls, host: host, logger: Logger(session: 'test')..add(MemorySink()));

  setUp(() {
    host = FakeOrientationHost();
    controls = RecordingDeviceControls();
  });

  group('the iPad', () {
    setUp(() {
      FormFactor.device = FormFactor.pad;
      orientation = make()..begin(page, videoIsVertical: false);
    });

    tearDown(() {
      orientation.dispose();
      FormFactor.device = FormFactor.phone;
    });

    test('never asks the system to rotate or to report turns', () async {
      orientation.enterLandscape();
      orientation.toggleLock();
      orientation.toggleLock();
      orientation.exitToInline();
      orientation.enterVertical();
      orientation.exitToInline();
      orientation.end(page);
      await settle();
      expect(host.requests, isEmpty);
      expect(host.events, isEmpty);
    });

    test('full screen comes and goes only by the button and back, whichever way it is held', () async {
      host.phone = PhoneOrientation.portrait;
      orientation.enterLandscape();
      await settle();
      expect(orientation.presentation, Presentation.landscape);
      orientation.exitToInline();
      expect(orientation.presentation, Presentation.inline);

      host.phone = PhoneOrientation.landscapeLeft;
      orientation.enterLandscape();
      await settle();
      expect(orientation.presentation, Presentation.landscape);
      orientation.exitToInline();
      expect(orientation.presentation, Presentation.inline);
      expect(controls.calls, ['enter', 'leave', 'enter', 'leave']);
    });

    test('a physical turn neither enters nor leaves full screen', () {
      host.turn(PhoneOrientation.landscapeLeft);
      expect(orientation.presentation, Presentation.inline);
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.inline);

      orientation.enterLandscape();
      host.turn(PhoneOrientation.portrait);
      host.turn(PhoneOrientation.landscapeRight);
      host.turn(PhoneOrientation.portraitUpsideDown);
      expect(orientation.presentation, Presentation.landscape);
    });

    test('has no 竖屏: the request for it opens the ordinary full screen', () async {
      orientation.setVideoIsVertical(true, owner: page);
      orientation.enterVertical();
      expect(orientation.presentation, Presentation.landscape);
      orientation.exitToInline();
      expect(orientation.presentation, Presentation.inline);
      await settle();
      expect(host.requests, isEmpty);
    });

    test('the lock keeps the presentation and asks nothing', () async {
      orientation.enterLandscape();
      orientation.toggleLock();
      expect(orientation.locked, isTrue);
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.landscape);
      await settle();
      expect(host.requests, isEmpty);
    });

    test('never arms the drawn turn', () async {
      await orientation.setTurnTakeover(true);
      orientation.enterLandscape();
      orientation.exitToInline();
      await settle();
      expect(orientation.turnTakeoverChosen, isTrue);
      expect(orientation.turnTakeover, isFalse);
      expect(host.takeovers, isEmpty);
    });
  });

  group('the iPhone, beside it', () {
    setUp(() => orientation = make()..begin(page, videoIsVertical: false));
    tearDown(() => orientation.dispose());

    test('the same steps still ask for masks, turn with the phone and enter 竖屏', () async {
      host.turn(PhoneOrientation.landscapeLeft);
      expect(orientation.presentation, Presentation.landscape);
      host.turn(PhoneOrientation.portrait);
      expect(orientation.presentation, Presentation.inline);
      orientation.enterVertical();
      expect(orientation.presentation, Presentation.vertical);
      await orientation.setTurnTakeover(true);
      await settle();
      expect(host.events, [true]);
      expect(host.requests.map((request) => request.$2),
          [OrientationMask.landscape, OrientationMask.portrait, OrientationMask.portrait]);
      expect(host.takeovers, [true]);
    });
  });
}
