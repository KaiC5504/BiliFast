import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:bilifast/offline/ios/ios_offline_host.dart';
import 'package:bilifast/offline/ios/offline_api.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'disk_test_support.dart';

const _channel = 'dev.flutter.pigeon.bilifast.OfflineHostApi.beginContinued';
const mib = 1 << 20;

/// OfflineHost.swift's beginContinued on the far end of the test messenger: answers [refusal] (null takes the
/// request), or [error] while set, and counts the asks.
final class _NativeSide {
  String? refusal;
  PlatformException? error;
  var asks = 0;

  MessageCodec<Object?> get _codec => OfflineHostApi.pigeonChannelCodec;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, (message) async {
      asks += 1;
      if (error case final error?) return _codec.encodeMessage(<Object?>[error.code, error.message, error.details]);
      return _codec.encodeMessage(<Object?>[refusal]);
    });
  }

  void uninstall() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, null);
}

/// The test host, its continued processing answered through the phone's [IosOfflineHost].
final class _PhoneContinued extends FakeOfflineHost {
  _PhoneContinued(this.phone);

  final IosOfflineHost phone;

  @override
  bool get continuedProcessing => phone.continuedProcessing;

  @override
  Future<String?> beginContinued({required String title, required String subtitle}) {
    calls.add('beginContinued');
    continuedBegun.add((title: title, subtitle: subtitle));
    return phone.beginContinued(title: title, subtitle: subtitle);
  }
}

/// A re-signed install (SideStore, AltStore) whose bundle id no longer heads the continued processing identifier:
/// OfflineHost.swift refuses for the rest of the run, and the phone's host stops the library asking.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NativeSide native;

  setUp(() => native = _NativeSide()..install());

  tearDown(() => native.uninstall());

  group('IosOfflineHost', () {
    test('a refusal for the rest of the run turns continued processing off, its reason handed on as is', () async {
      final host = IosOfflineHost();
      expect(host.continuedProcessing, isTrue);

      native.refusal = 'unavailable: identifier outside the bundle id';
      expect(await host.beginContinued(title: '离线缓存', subtitle: '测试视频'), native.refusal);
      expect(host.continuedProcessing, isFalse);

      native.refusal = 'unavailable: BGTaskSchedulerErrorDomain 3';
      final notPermitted = IosOfflineHost();
      await notPermitted.beginContinued(title: '离线缓存', subtitle: '测试视频');
      expect(notPermitted.continuedProcessing, isFalse, reason: "iOS's not permitted holds for the rest of the run too");
    });

    test('a passing refusal, a taken request and a failed call leave it on', () async {
      final host = IosOfflineHost();

      native.refusal = 'BGTaskSchedulerErrorDomain 4';
      expect(await host.beginContinued(title: '离线缓存', subtitle: '测试视频'), 'BGTaskSchedulerErrorDomain 4');
      expect(host.continuedProcessing, isTrue, reason: 'busy now may pass at the next action');

      native.refusal = null;
      expect(await host.beginContinued(title: '离线缓存', subtitle: '测试视频'), isNull);
      expect(host.continuedProcessing, isTrue);

      native.error = PlatformException(code: 'channel-error');
      await expectLater(host.beginContinued(title: '离线缓存', subtitle: '测试视频'), throwsA(isA<PlatformException>()));
      expect(host.continuedProcessing, isTrue);
    });
  });

  group('the library on a re-signed install', () {
    late Rig rig;

    setUp(() {
      rig = Rig(host: _PhoneContinued(IosOfflineHost()))..trials = BackgroundTrials.new;
      native.refusal = 'unavailable: identifier outside the bundle id';
    });

    tearDown(() {
      rig.dispose();
      if (TestWidgetsFlutterBinding.instance.lifecycleState case final state? when state != AppLifecycleState.resumed) {
        lifecycle(toForeground);
      }
    });

    Iterable<LogEvent> logged(String msg) => rig.logs.events.where((event) => event.msg == msg);

    Iterable<LogEvent> continued(String event) =>
        logged('offline continued').where((line) => line.f['event']?.toJson() == event);

    test('asks once, logs the refusal once with its reason, and hands the downloads off on the leave', () async {
      const cid = 137649199;
      final library = await rig.started();
      await library.enqueue([offlineRequest(cid: cid)]);
      await library.settled();
      library
        ..pause(cid)
        ..resume(cid);
      await library.settled();
      library
        ..pause(cid)
        ..startAll();
      await library.settled();
      rig.engine.gaps['$cid'] = DownloadGaps(
        id: '$cid',
        video: [ByteRange(0, 40 * mib - 1)],
        audio: [ByteRange(0, mib - 1)],
        videoTotal: 40 * mib,
        audioTotal: mib,
      );
      lifecycle(toBackground);
      await library.settled();
      lifecycle(toForeground);
      await library.settled();

      expect(native.asks, 1);
      expect(continued('asked').single.f['why']?.toJson(), 'enqueue');
      expect(continued('refused').single.f['reason']?.toJson(), 'unavailable: identifier outside the bundle id');
      expect(logged('offline continued'), hasLength(2), reason: 'resume, 全部开始 and the return ask nothing');

      final away = logged('offline away').single;
      expect(away.f['arm']?.toJson(), 'handoff-3x128');
      expect(away.f['why']?.toJson(), 'untried', reason: 'continued, untried too, is no candidate');
      expect(rig.host.handedOff, hasLength(1));
      expect(rig.host.calls.where((call) => call.startsWith('endContinued')), isEmpty);
    });
  });
}
