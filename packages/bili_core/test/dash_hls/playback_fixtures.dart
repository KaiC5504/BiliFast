import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';

typedef HeaderFixture = ({TrackChoice choice, Uint8List bytes, int total});

/// Port of DebugSupport.headerFixture: ftyp, optionally a moov, then a version 0 sidx with one 1000-byte,
/// 2-second reference. The moov is empty, or holds one HEVC sample entry of type [videoEntry] whose hvcC
/// carries [nalTypes] (VPS, SPS and PPS by default). Both tracks of the choice point at the same layout,
/// each with a primary address on primary.invalid and one backup per host in [backupHosts].
HeaderFixture headerFixture({
  required bool withMoov,
  List<String> backupHosts = const ['backup.invalid'],
  String? videoEntry,
  String videoCodecs = 'avc1.640032',
  List<int> nalTypes = const [32, 33, 34],
  bool withSidx = true,
  int videoId = 80,
  String audioCodecs = 'mp4a.40.2',
  String? frameRate = '30',
}) {
  List<int> uint32(int value) => [for (var i = 0; i < 4; i++) (value >> (24 - 8 * i)) & 0xff];
  List<int> box(String type, List<int> payload) => [...uint32(8 + payload.length), ...ascii.encode(type), ...payload];
  List<int> sampleEntry(String type) {
    final parameterSets = [
      for (final nal in nalTypes) ...[nal, 0, 1, 0, 2, 0xAA, 0xBB],
    ];
    final hvcC = box('hvcC', [...List.filled(22, 0), nalTypes.length, ...parameterSets]);
    final stsd = box('stsd', [...uint32(0), ...uint32(1), ...box(type, [...List.filled(78, 0), ...hvcC])]);
    return box('trak', box('mdia', box('minf', box('stbl', stsd))));
  }

  final ftyp = box('ftyp', [...ascii.encode('isom'), ...uint32(0)]);
  final moov = withMoov ? box('moov', videoEntry == null ? [] : sampleEntry(videoEntry)) : <int>[];
  final sidx = withSidx
      ? box('sidx', [
          ...uint32(0), ...uint32(1), ...uint32(1000), ...uint32(0), ...uint32(0), 0, 0, 0, 1,
          ...uint32(1000), ...uint32(2000), ...uint32(0),
        ])
      : box('free', List.filled(36, 0));
  final initEnd = ftyp.length + moov.length - 1;
  final bytes = Uint8List.fromList([...ftyp, ...moov, ...sidx]);
  final total = bytes.length + 1000;
  DashStream stream(int id, String codecs) => DashStream(
        id: id,
        baseURL: 'https://primary.invalid/upgcxcode/$id.m4s?deadline=1&upsig=sig',
        backupURLs: [for (final host in backupHosts) 'https://$host/upgcxcode/$id.m4s?deadline=1&upsig=sig'],
        bandwidth: 1000000,
        mimeType: 'video/mp4',
        codecs: codecs,
        codecid: 7,
        width: 1920,
        height: 1080,
        frameRate: frameRate,
        initialization: ByteRange(0, initEnd),
        indexRange: ByteRange(initEnd + 1, bytes.length - 1),
      );
  return (
    choice: TrackChoice(video: stream(videoId, videoCodecs), audio: stream(30280, audioCodecs)),
    bytes: bytes,
    total: total,
  );
}

enum FixtureAnswer {
  /// 403.
  refuse,

  /// 200 with the whole file.
  wholeFile,

  /// 206 labelled with a range one byte off.
  wrongRange,

  /// 206 with an unknown total (`bytes a-b/*`).
  noTotal,

  /// 206 whose body is one byte short.
  shortBody,

  /// 206 whose body is one byte long.
  longBody,

  /// No headers until cancelled.
  hang,

  /// Headers and the first byte arrive, then nothing until the body is cancelled.
  stallBody,
}

/// Port of DebugSupport.FixtureTransport: serves `bytes` as the start of a `total`-byte file, and hosts in
/// [answers] misbehave instead. A body that must not be read to the end never closes, so a builder that
/// waited on it would hang, and its cancellation shows in [cancelledBodies].
final class FixtureTransport implements RangeTransport {
  FixtureTransport({required this.bytes, required this.total, this.answers = const {}});

  final Uint8List bytes;
  final int total;
  final Map<String, FixtureAnswer> answers;

  final List<({String host, ByteRange range})> requests = [];

  /// Hosts whose request was cancelled through its CancelToken before the headers came.
  final List<String> cancelledRequests = [];

  /// Hosts whose body subscription was cancelled before the body ended.
  final List<String> cancelledBodies = [];

  /// Called with each request as it starts.
  void Function(String host)? onRequest;

  @override
  int? get connectionsPerHost => null;

  @override
  String get name => 'fixture';

  @override
  void close() {}

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    final host = url.host;
    requests.add((host: host, range: range));
    onRequest?.call(host);
    if (cancel?.isCancelled ?? false) return Future.error(const CancelledException());
    if (range.start >= bytes.length) {
      return Future.value(_response(416, {'content-range': 'bytes */$total'}, host, []));
    }
    final end = range.end < bytes.length - 1 ? range.end : bytes.length - 1;
    final slice = bytes.sublist(range.start, end + 1);
    final good = 'bytes ${range.start}-${range.end}/$total';
    return switch (answers[host]) {
      FixtureAnswer.refuse => Future.value(_response(403, {}, host, [], close: false)),
      FixtureAnswer.wholeFile => Future.value(_response(200, {'content-length': '$total'}, host, bytes, close: false)),
      FixtureAnswer.wrongRange => Future.value(_response(
          206, {'content-range': 'bytes ${range.start + 1}-${range.end + 1}/$total'}, host, slice, close: false)),
      FixtureAnswer.noTotal => Future.value(
          _response(206, {'content-range': 'bytes ${range.start}-${range.end}/*'}, host, slice, close: false)),
      FixtureAnswer.shortBody =>
        Future.value(_response(206, {'content-range': good}, host, slice.sublist(0, slice.length - 1))),
      FixtureAnswer.longBody => Future.value(_response(206, {'content-range': good}, host, [...slice, 0])),
      FixtureAnswer.hang => _hang(host, cancel),
      FixtureAnswer.stallBody =>
        Future.value(_response(206, {'content-range': good}, host, slice.sublist(0, 1), close: false)),
      null => Future.value(_response(206, {'content-range': good}, host, slice)),
    };
  }

  Future<TransportResponse> _hang(String host, CancelToken? cancel) {
    final completer = Completer<TransportResponse>();
    cancel?.onCancel(() {
      cancelledRequests.add(host);
      completer.completeError(const CancelledException());
    });
    return completer.future;
  }

  TransportResponse _response(int status, Map<String, String> headers, String host, List<int> body,
      {bool close = true}) {
    var ended = false;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        if (body.isNotEmpty) controller.add(Uint8List.fromList(body));
        if (close) {
          ended = true;
          controller.close();
        }
      },
      onCancel: () {
        if (!ended) cancelledBodies.add(host);
      },
    );
    return TransportResponse(status: status, headers: headers, body: controller.stream);
  }
}

/// Collects Logger.shared's player events while a test runs.
final class CapturedLog implements LogSink {
  CapturedLog() {
    Logger.shared.add(this);
  }

  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) {
    if (event.cat == LogCategory.player) events.add(event);
  }

  void stop() => Logger.shared.remove(this);

  List<LogEvent> named(String msg) => events.where((event) => event.msg == msg).toList();
}
