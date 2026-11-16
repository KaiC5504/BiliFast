import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/live.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/live_socket/$name.json').readAsStringSync()) as Map<String, Object?>;

LiveEvent? decode(Map<String, Object?> json) => LiveSocketDecode.command(json, now: () => DateTime.utc(2026, 11, 17));

LivePacket command(Object? json) =>
    LivePacket(op: LiveOp.command, protover: 0, body: Uint8List.fromList(utf8.encode(jsonEncode(json))));

LivePacket zlibCommands(List<LivePacket> inner) {
  final joined = BytesBuilder();
  for (final packet in inner) {
    joined.add(packet.encode());
  }
  return LivePacket(op: LiveOp.command, protover: 2, body: Uint8List.fromList(ZLibCodec().encode(joined.takeBytes())));
}

Uint8List authReply(int code) => LivePacket.json(op: LiveOp.authReply, json: {'code': code}).encode();

Uint8List heartbeatReply() => LivePacket(op: LiveOp.heartbeatReply, body: Uint8List.fromList([0, 0, 0, 1])).encode();

/// Timers that only fire when [elapse] moves the time past them.
final class FakeTimers implements LiveTimers {
  Duration now = Duration.zero;
  final _timers = <_FakeTimer>[];

  @override
  Timer after(Duration delay, void Function() callback) => _add(_FakeTimer(this, now + delay, null, callback));

  @override
  Timer every(Duration period, void Function() callback) => _add(_FakeTimer(this, now + period, period, callback));

  Timer _add(_FakeTimer timer) {
    _timers.add(timer);
    return timer;
  }

  int get active => _timers.where((timer) => timer.isActive).length;

  Future<void> elapse(Duration duration) async {
    final end = now + duration;
    while (true) {
      final due = _timers.where((timer) => timer.isActive && timer.due <= end).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final timer = due.first;
      now = timer.due;
      timer.fire();
      await pumpEventQueue();
    }
    now = end;
    await pumpEventQueue();
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this._owner, this.due, this.period, this.callback);

  final FakeTimers _owner;
  Duration due;
  final Duration? period;
  final void Function() callback;
  bool _active = true;
  int _ticks = 0;

  void fire() {
    _ticks++;
    if (period case final Duration every) {
      due += every;
    } else {
      _active = false;
    }
    callback();
  }

  @override
  void cancel() {
    _active = false;
    _owner._timers.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}

final class FakeConnection implements LiveConnection {
  FakeConnection(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
  final _incoming = StreamController<List<int>>();
  final sent = <LivePacket>[];
  bool closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  void send(List<int> bytes) => sent.addAll(LivePacket.split(Uint8List.fromList(bytes)));

  @override
  Future<void> close() async => closed = true;

  void push(List<int> bytes) => _incoming.add(bytes);

  void drop() => _incoming.close();

  List<LivePacket> sentOp(int op) => sent.where((packet) => packet.op == op).toList();
}

/// Answers each connect with a [FakeConnection], or throws while [refuse] is set.
final class FakeServer {
  final connections = <FakeConnection>[];
  final attempts = <Uri>[];
  bool refuse = false;

  Future<LiveConnection> connect(Uri uri, Map<String, String> headers) async {
    attempts.add(uri);
    if (refuse) throw const SocketException('refused');
    final connection = FakeConnection(uri, headers);
    connections.add(connection);
    return connection;
  }

  FakeConnection get last => connections.last;

  List<String> get hosts => [for (final uri in attempts) '${uri.host}:${uri.port}'];
}

final class MemorySink implements LogSink {
  final events = <LogEvent>[];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => jsonEncode(event.toJson())).join('\n');
}

const _token = 'made-up-token-0123456789';
const _uid = 987654321;

final class Harness {
  Harness({Map<String, String>? headers, List<LiveSocketHost>? hosts}) {
    logger.add(sink);
    socket = LiveSocket(
      roomId: 30001,
      uid: _uid,
      info: LiveDanmuInfo(
        token: _token,
        hosts:
            hosts ??
            const [
              LiveSocketHost(host: 'a.chat.example', wssPort: 2245),
              LiveSocketHost(host: 'b.chat.example', wssPort: 443),
            ],
      ),
      headers: headers ?? const {'User-Agent': 'test', 'Cookie': 'buvid3=made-up-buvid; other=1'},
      logger: logger,
      connector: server.connect,
      timers: timers,
      now: () => DateTime.utc(2026, 11, 17),
    );
    socket.states.listen(states.add);
    socket.events.listen(events.add);
  }

  final server = FakeServer();
  final timers = FakeTimers();
  final logger = Logger(session: 'test');
  final sink = MemorySink();
  late final LiveSocket socket;
  final states = <LiveSocketState>[];
  final events = <LiveEvent>[];

  Future<void> start() async {
    await socket.start();
    await pumpEventQueue();
  }

  Future<void> open() async {
    await start();
    server.last.push(authReply(0));
    await pumpEventQueue();
  }
}

void main() {
  group('codec', () {
    test('a packet survives encode and read', () {
      final packet = LivePacket(op: LiveOp.auth, protover: 1, seq: 7, body: Uint8List.fromList(utf8.encode('{}')));
      final bytes = packet.encode();
      expect(bytes.length, 18);
      expect(ByteData.sublistView(bytes).getUint32(0), 18);
      expect(ByteData.sublistView(bytes).getUint16(4), 16);
      final read = LivePacket.split(bytes).single;
      expect((read.op, read.protover, read.seq, utf8.decode(read.body)), (LiveOp.auth, 1, 7, '{}'));
    });

    test('packets cut across reads come out whole, and several in one read all come out', () {
      final first = command({'cmd': 'LIVE'}).encode();
      final second = command({'cmd': 'PREPARING'}).encode();
      final all = [...first, ...second];
      final reader = LivePacketReader();
      final out = <LivePacket>[];
      for (final byte in all) {
        reader.add([byte]);
        out.addAll(reader.take());
      }
      expect(out.map((packet) => jsonDecode(utf8.decode(packet.body))['cmd']), ['LIVE', 'PREPARING']);
      expect(reader.pending, 0);

      final together = LivePacketReader()..add(all.sublist(0, all.length - 3));
      expect(together.take(), hasLength(1));
      together.add(all.sublist(all.length - 3));
      expect(together.take(), hasLength(1));
    });

    test('lengths that make no sense throw', () {
      final bytes = command({'cmd': 'LIVE'}).encode();
      ByteData.sublistView(bytes).setUint16(4, 8);
      expect(() => (LivePacketReader()..add(bytes)).take(), throwsA(isA<LivePacketError>()));
      expect(
        () => LivePacket.split(Uint8List.sublistView(command({}).encode(), 0, 17)),
        throwsA(isA<LivePacketError>()),
      );
    });

    test('a zlib body opens into its commands, nested ones too', () {
      final packet = zlibCommands([
        command({'cmd': 'LIVE'}),
        command({'cmd': 'WATCHED_CHANGE'}),
        zlibCommands([
          command({'cmd': 'PREPARING'}),
        ]),
      ]);
      final commands = packet.commands().map((body) => jsonDecode(utf8.decode(body))['cmd']);
      expect(commands, ['LIVE', 'WATCHED_CHANGE', 'PREPARING']);
    });

    test('a body that will not open costs only itself', () {
      final bad = LivePacket(op: LiveOp.command, protover: 2, body: Uint8List.fromList([1, 2, 3, 4]));
      final brotli = LivePacket(op: LiveOp.command, protover: 3, body: Uint8List.fromList([1, 2]));
      final outer = zlibCommands([
        bad,
        brotli,
        command({'cmd': 'LIVE'}),
      ]);
      final bad2 = <int>[];
      final commands = outer.commands(onBad: (protover, _) => bad2.add(protover));
      expect(commands.map((body) => jsonDecode(utf8.decode(body))['cmd']), ['LIVE']);
      expect(bad2, [2, 3]);
    });
  });

  group('socket', () {
    test('connects to the first host and authenticates with protover 2 and the buvid', () async {
      final harness = Harness();
      await harness.start();
      final connection = harness.server.last;
      expect(connection.uri.toString(), 'wss://a.chat.example:2245/sub');
      expect(connection.headers['Cookie'], contains('buvid3=made-up-buvid'));
      final auth = connection.sentOp(LiveOp.auth).single;
      expect(auth.protover, 1);
      expect(jsonDecode(utf8.decode(auth.body)), {
        'uid': _uid,
        'roomid': 30001,
        'protover': 2,
        'buvid': 'made-up-buvid',
        'platform': 'web',
        'type': 2,
        'key': _token,
      });
      expect(harness.states, [LiveSocketState.connecting]);
    });

    test('no buvid cookie, no buvid field', () async {
      final harness = Harness(headers: const {'User-Agent': 'test'});
      await harness.start();
      final auth = jsonDecode(utf8.decode(harness.server.last.sentOp(LiveOp.auth).single.body)) as Map;
      expect(auth.containsKey('buvid'), isFalse);
    });

    test('heartbeats only after the auth is accepted, then every 30 s', () async {
      final harness = Harness();
      await harness.start();
      final connection = harness.server.last;
      await harness.timers.elapse(const Duration(seconds: 5));
      expect(connection.sentOp(LiveOp.heartbeat), isEmpty);

      connection.push(authReply(0));
      await pumpEventQueue();
      expect(harness.states, [LiveSocketState.connecting, LiveSocketState.open]);
      expect(connection.sentOp(LiveOp.heartbeat), hasLength(1));

      for (var beat = 2; beat <= 4; beat++) {
        connection.push(heartbeatReply());
        await harness.timers.elapse(const Duration(seconds: 29));
        expect(connection.sentOp(LiveOp.heartbeat), hasLength(beat - 1));
        await harness.timers.elapse(const Duration(seconds: 1));
        expect(connection.sentOp(LiveOp.heartbeat), hasLength(beat));
      }
      final seqs = connection.sent.map((packet) => packet.seq).toList();
      expect(seqs, List.generate(seqs.length, (index) => index + 1));
      expect(harness.server.connections, hasLength(1));
    });

    test('a refused auth stops the socket: no retry with the same token', () async {
      final harness = Harness();
      await harness.start();
      harness.server.last.push(authReply(-101));
      await pumpEventQueue();
      expect(harness.server.connections.single.closed, isTrue);
      expect(harness.states, [LiveSocketState.connecting, LiveSocketState.refused]);
      expect(harness.timers.active, 0);

      await harness.timers.elapse(const Duration(minutes: 10));
      expect(harness.server.attempts, hasLength(1));
      expect(harness.sink.text, contains('live socket auth refused'));

      await harness.start();
      expect(harness.server.attempts, hasLength(2));
      expect(harness.states.last, LiveSocketState.connecting);
    });

    test('an unreadable auth reply is a failure, retried on the next host', () async {
      final harness = Harness();
      await harness.start();
      final garbled = LivePacket(op: LiveOp.authReply, body: Uint8List.fromList(utf8.encode('nope')));
      harness.server.last.push(garbled.encode());
      await pumpEventQueue();
      expect(harness.states.last, LiveSocketState.failed);
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.server.hosts, ['a.chat.example:2245', 'b.chat.example:443']);
    });

    test('failures back off 1, 2, 4, 8, 16, 30, 30 s and cycle through the hosts then the fallback', () async {
      final harness = Harness();
      harness.server.refuse = true;
      await harness.start();
      final gaps = <int>[];
      var last = Duration.zero;
      while (harness.server.attempts.length < 8) {
        final before = harness.server.attempts.length;
        while (harness.server.attempts.length == before) {
          await harness.timers.elapse(const Duration(milliseconds: 500));
        }
        gaps.add((harness.timers.now - last).inMilliseconds);
        last = harness.timers.now;
      }
      expect(gaps, [1000, 2000, 4000, 8000, 16000, 30000, 30000]);
      expect(harness.server.hosts, [
        'a.chat.example:2245',
        'b.chat.example:443',
        'broadcastlv.chat.bilibili.com:443',
        'a.chat.example:2245',
        'b.chat.example:443',
        'broadcastlv.chat.bilibili.com:443',
        'a.chat.example:2245',
        'b.chat.example:443',
      ]);
    });

    test('eight failures in a row stop it with gaveUp; start begins again', () async {
      final harness = Harness();
      harness.server.refuse = true;
      await harness.start();
      await harness.timers.elapse(const Duration(seconds: 1 + 2 + 4 + 8 + 16 + 30 + 30));
      expect(harness.server.attempts, hasLength(LiveSocket.maxAttempts));
      expect(harness.timers.active, 0);
      expect(harness.states.last, LiveSocketState.gaveUp);
      expect(harness.states.where((state) => state == LiveSocketState.gaveUp), hasLength(1));
      expect(
        harness.states.where((state) => state == LiveSocketState.failed),
        hasLength(LiveSocket.maxAttempts - 1),
        reason: 'every loss before the last is retryable',
      );
      expect(harness.sink.text, contains('live socket gave up'));
      await harness.timers.elapse(const Duration(minutes: 30));
      expect(harness.server.attempts, hasLength(LiveSocket.maxAttempts));

      harness.server.refuse = false;
      await harness.start();
      expect(harness.server.attempts, hasLength(LiveSocket.maxAttempts + 1));
      harness.server.last.push(authReply(0));
      await pumpEventQueue();
      expect(harness.states.last, LiveSocketState.open);
    });

    test('a steady connection between failures resets the count', () async {
      final harness = Harness();
      harness.server.refuse = true;
      await harness.start();
      await harness.timers.elapse(const Duration(seconds: 1 + 2 + 4 + 8 + 16 + 30));
      expect(harness.server.attempts, hasLength(7));
      harness.server.refuse = false;
      await harness.timers.elapse(const Duration(seconds: 30));
      expect(harness.server.attempts, hasLength(8));
      final steady = harness.server.last;
      steady.push(authReply(0));
      await pumpEventQueue();
      for (var i = 0; i < 3; i++) {
        steady.push(heartbeatReply());
        await harness.timers.elapse(const Duration(seconds: 30));
      }
      steady.drop();
      await pumpEventQueue();
      expect(harness.timers.active, 1, reason: 'a retry is due, not a stop');
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.server.attempts, hasLength(9));
    });

    test('the fallback host is not tried twice when the answer already lists it', () async {
      final harness = Harness(hosts: const [LiveSocketHost(host: 'broadcastlv.chat.bilibili.com', wssPort: 443)]);
      harness.server.refuse = true;
      await harness.start();
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.server.hosts, everyElement('broadcastlv.chat.bilibili.com:443'));
      expect(harness.server.hosts, hasLength(3));
    });

    test('a dropped connection comes back on the next host; a long-lived one clears the backoff', () async {
      final harness = Harness();
      harness.server.refuse = true;
      await harness.start();
      await harness.timers.elapse(const Duration(seconds: 1 + 2));
      expect(harness.server.attempts, hasLength(3));
      harness.server.refuse = false;
      await harness.timers.elapse(const Duration(seconds: 4));
      expect(harness.server.attempts, hasLength(4));
      harness.server.last.push(authReply(0));
      await pumpEventQueue();

      // Dropped before it settled: the backoff goes on from 4 s.
      harness.server.last.drop();
      await pumpEventQueue();
      expect(harness.states.last, LiveSocketState.failed);
      await harness.timers.elapse(const Duration(seconds: 7));
      expect(harness.server.attempts, hasLength(4));
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.server.attempts, hasLength(5));

      final steady = harness.server.last;
      steady.push(authReply(0));
      await pumpEventQueue();
      for (var i = 0; i < 3; i++) {
        steady.push(heartbeatReply());
        await harness.timers.elapse(const Duration(seconds: 30));
      }
      steady.drop();
      await pumpEventQueue();
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.server.attempts, hasLength(6));
    });

    test('an auth that never answers counts as a failure', () async {
      final harness = Harness();
      await harness.start();
      await harness.timers.elapse(LiveSocket.authTimeout);
      expect(harness.server.connections.single.closed, isTrue);
      expect(harness.states.last, LiveSocketState.failed);
    });

    test('a server that goes quiet for a minute is given up', () async {
      final harness = Harness();
      await harness.open();
      await harness.timers.elapse(const Duration(seconds: 59));
      expect(harness.server.last.closed, isFalse);
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.server.connections.first.closed, isTrue);
      expect(harness.states.last, LiveSocketState.failed);
    });

    test('close stops the heartbeat and the reconnect, and start works again', () async {
      final harness = Harness();
      await harness.open();
      final first = harness.server.last;
      first.drop();
      await pumpEventQueue();
      await harness.socket.close();
      expect(harness.states.last, LiveSocketState.closed);
      expect(harness.timers.active, 0);
      await harness.timers.elapse(const Duration(minutes: 5));
      expect(harness.server.attempts, hasLength(1));

      await harness.start();
      expect(harness.server.hosts.last, 'a.chat.example:2245');
      final second = harness.server.last;
      second.push(authReply(0));
      await pumpEventQueue();
      await harness.socket.close();
      expect(second.closed, isTrue);
      final beats = second.sentOp(LiveOp.heartbeat).length;
      await harness.timers.elapse(const Duration(minutes: 5));
      expect(second.sentOp(LiveOp.heartbeat), hasLength(beats));
      expect(harness.server.attempts, hasLength(2));
    });

    test('close while a connect is out closes what it brings', () async {
      final harness = Harness();
      final gate = Completer<void>();
      final pending = <FakeConnection>[];
      final socket = LiveSocket(
        roomId: 1,
        uid: 0,
        info: const LiveDanmuInfo(token: 't', hosts: []),
        logger: harness.logger,
        timers: harness.timers,
        connector: (uri, headers) async {
          await gate.future;
          final connection = FakeConnection(uri, headers);
          pending.add(connection);
          return connection;
        },
      );
      await socket.start();
      await socket.close();
      gate.complete();
      await pumpEventQueue();
      expect(pending.single.closed, isTrue);
      expect(pending.single.sent, isEmpty);
    });

    test('start twice keeps one connection', () async {
      final harness = Harness();
      await harness.start();
      await harness.start();
      expect(harness.server.attempts, hasLength(1));
    });

    test('commands become events; a bad one costs only itself', () async {
      final harness = Harness();
      await harness.open();
      final connection = harness.server.last;
      final broken = LivePacket(op: LiveOp.command, protover: 0, body: Uint8List.fromList(utf8.encode('{"cmd":')));
      final malformed = command({
        'cmd': 'DANMU_MSG',
        'info': [<Object?>[], 42],
      });
      final batch = zlibCommands([
        command(fixture('danmu_msg')),
        broken,
        malformed,
        command({'cmd': 'SOMETHING_NEW', 'data': <String, Object?>{}}),
        command({
          'cmd': 'WATCHED_CHANGE',
          'data': {'num': 12000, 'text_small': '1.2万', 'text_large': '1.2万人看过'},
        }),
      ]);
      final bytes = [
        ...batch.encode(),
        ...command({'cmd': 'PREPARING'}).encode(),
      ];
      connection.push(bytes.sublist(0, 20));
      connection.push(bytes.sublist(20));
      await pumpEventQueue();

      expect(harness.events, hasLength(3));
      expect((harness.events[0] as LiveDanmakuEvent).message.text, '测试弹幕[dog]');
      expect((harness.events[1] as LiveWatchedEvent).text, '1.2万人看过');
      expect((harness.events[2] as LiveStatusEvent).live, isFalse);
      expect(harness.states.last, LiveSocketState.open);
      expect(harness.sink.text, contains('live command undecodable'));
      expect(harness.sink.text, contains('DANMU_MSG'));
    });

    test('logs carry no token, uid, cookie or message text', () async {
      final harness = Harness();
      await harness.open();
      harness.server.last.push(zlibCommands([command(fixture('danmu_msg'))]).encode());
      harness.server.last.push(command({'cmd': 'DANMU_MSG', 'info': 'x'}).encode());
      harness.server.last.drop();
      await pumpEventQueue();
      await harness.timers.elapse(const Duration(seconds: 1));
      await harness.socket.close();
      final text = harness.sink.text;
      expect(text, contains('live socket open'));
      expect(text, contains('live socket lost'));
      for (final secret in [_token, '$_uid', 'made-up-buvid', '测试弹幕', '30001']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('a stream that falls out of step reconnects', () async {
      final harness = Harness();
      await harness.open();
      final bytes = command({'cmd': 'LIVE'}).encode();
      ByteData.sublistView(bytes).setUint16(4, 3);
      harness.server.last.push(bytes);
      await pumpEventQueue();
      expect(harness.states.last, LiveSocketState.failed);
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.server.attempts, hasLength(2));
    });
  });

  group('decode', () {
    test('DANMU_MSG in its current shape', () {
      final message = (decode(fixture('danmu_msg')) as LiveDanmakuEvent).message;
      expect(message.id, 'made0up0000000000000000001');
      expect(message.text, '测试弹幕[dog]');
      expect(message.time, DateTime.fromMillisecondsSinceEpoch(1763350000123));
      expect(message.color, 0xFFFFFFFF);
      expect(message.mode, 1);
      expect(message.replyTo, '被回复的人');
      expect(message.bigEmote, isNull);
      final emote = message.emotes['[dog]']!;
      expect(
        (emote.text, emote.url, emote.unique, emote.width, emote.height),
        ('[dog]', 'https://i0.hdslb.com/bfs/live/emote-0001.png', 'emoji_208', 20, 20),
      );
      final user = message.user;
      expect((user.uid, user.name, user.face), (10002, '测试观众', 'https://i0.hdslb.com/bfs/face/face-0101.jpg'));
      expect(user.wealthLevel, 24);
      expect(user.guardLevel, 3);
      expect(user.nameColor, 0xFF00D1F1);
      final medal = user.medal!;
      expect((medal.name, medal.level, medal.guardLevel, medal.lit), ('测试牌', 21, 3, true));
      expect((medal.colorStart, medal.colorEnd, medal.border), (0xFF06154C, 0xFF6888F1, 0xFF06154C));
    });

    test('DANMU_MSG in the older shape, with a suffixed command', () {
      final message = (decode(fixture('danmu_msg_legacy')) as LiveDanmakuEvent).message;
      expect(message.text, '老格式');
      expect((message.user.uid, message.user.name), (10003, '旧*观众'));
      expect(message.user.wealthLevel, 12);
      expect(message.user.guardLevel, 0);
      expect(message.user.nameColor, 0);
      expect(message.mode, 5);
      expect(message.color, 0xFFFF0000);
      expect(message.time, DateTime.fromMillisecondsSinceEpoch(1763350100 * 1000));
      expect(message.emotes, isEmpty);
      expect(message.replyTo, '');
      expect(message.id, isNotEmpty);
      final medal = message.user.medal!;
      expect((medal.name, medal.level, medal.lit, medal.colorStart), ('旧牌', 5, false, 0xFF5C968E));
    });

    test('DANMU_MSG whose whole message is an emote', () {
      final message = (decode(fixture('danmu_msg_big_emote')) as LiveDanmakuEvent).message;
      final emote = message.bigEmote!;
      expect(
        (emote.text, emote.url, emote.unique, emote.width, emote.height),
        ('赞', 'https://i0.hdslb.com/bfs/live/emote-big-0001.png', 'room_30001_1234', 162, 162),
      );
      expect(message.emotes, isEmpty);
      expect(message.user.medal, isNotNull, reason: "info[3] is empty, so the user's own medal is read");
      expect(message.user.wealthLevel, 24, reason: 'info[16][0] is 0, so the user’s wealth is read');
    });

    test('DANMU_MSG without its text throws', () {
      expect(
        () => decode({
          'cmd': 'DANMU_MSG',
          'info': [<Object?>[]],
        }),
        throwsA(isA<DecodeError>()),
      );
      expect(() => decode({'cmd': 'DANMU_MSG'}), throwsA(isA<DecodeError>()));
    });

    test('SUPER_CHAT_MESSAGE and its delete', () {
      final chat = (decode(fixture('super_chat')) as LiveSuperChatEvent).superChat;
      expect((chat.id, chat.price, chat.batteries, chat.message), (7000001, 30, 300, '这是一条醒目留言'));
      expect(chat.start, DateTime.fromMillisecondsSinceEpoch(1763350300 * 1000));
      expect(chat.end, DateTime.fromMillisecondsSinceEpoch(1763350360 * 1000));
      expect(
        (chat.background, chat.backgroundBottom, chat.headerColor, chat.priceColor),
        (0xFFEDF5FF, 0xFF2A60B2, 0xFF3171D2, 0xFF7497CD),
      );
      final user = chat.user;
      expect(
        (user.uid, user.name, user.guardLevel, user.nameColor, user.wealthLevel),
        (10004, '醒目的人', 2, 0xFFE17AFF, 31),
      );
      expect(user.faceFrame, 'https://i0.hdslb.com/bfs/live/frame-0001.png');
      expect((user.medal!.name, user.medal!.level, user.medal!.colorStart), ('测试牌', 25, 0xFF06154C));

      final deleted = decode({
        'cmd': 'SUPER_CHAT_MESSAGE_DELETE',
        'roomid': 30001,
        'data': {
          'ids': [7000001, '7000002'],
        },
      });
      expect((deleted as LiveSuperChatDeletedEvent).ids, [7000001, 7000002]);
    });

    test('SUPER_CHAT_MESSAGE with both: uinfo’s medal wins over medal_info', () {
      final chat = (decode(fixture('super_chat_uinfo_medal')) as LiveSuperChatEvent).superChat;
      final medal = chat.user.medal!;
      expect((medal.name, medal.level, medal.lit, medal.guardLevel), ('新牌', 30, true, 1));
      expect((medal.colorStart, medal.border), (0xCC4775EF, 0xFF58A1F8));
      expect((chat.user.name, chat.user.face), ('牌子甲', 'https://i0.hdslb.com/bfs/face/face-0105.jpg'));
    });

    test('counts, faces and room changes', () {
      expect(
        (decode({
          'cmd': 'ONLINE_RANK_COUNT',
          'data': {'count': 9349, 'count_text': '9349'},
        }) as LiveOnlineCountEvent).count,
        9349,
      );
      expect(
        (decode({
          'cmd': 'ONLINE_RANK_COUNT',
          'data': {'online_count': 120},
        }) as LiveOnlineCountEvent).count,
        120,
      );
      expect((decode(fixture('online_rank_v2')) as LiveTopFacesEvent).faces, [
        'https://i0.hdslb.com/bfs/face/face-0111.jpg',
        'https://i0.hdslb.com/bfs/face/face-0112.jpg',
        'https://i0.hdslb.com/bfs/face/face-0113.jpg',
      ]);
      expect(
        decode({
          'cmd': 'ONLINE_RANK_TOP3',
          'data': {
            'dmscore': 112,
            'list': [
              {'msg': '恭喜 某人 成为高能榜', 'rank': 1},
            ],
          },
        }),
        isNull,
      );
      expect(
        (decode({
          'cmd': 'LIKE_INFO_V3_UPDATE',
          'data': {'click_count': 124000},
        }) as LiveLikeCountEvent).count,
        124000,
      );
      final changed = decode({
        'cmd': 'ROOM_CHANGE',
        'data': {'title': '新标题', 'area_id': 1, 'area_name': '聊天室', 'parent_area_name': '娱乐'},
      }) as LiveRoomChangedEvent;
      expect((changed.title, changed.areaName), ('新标题', '聊天室'));
      expect((decode({'cmd': 'LIVE', 'roomid': 30001}) as LiveStatusEvent).live, isTrue);
      expect((decode({'cmd': 'PREPARING', 'roomid': '30001'}) as LiveStatusEvent).live, isFalse);
      expect(decode({'cmd': 'SEND_GIFT', 'data': {}}), isNull);
      expect(decode({'data': {}}), isNull);
      expect(() => decode({'cmd': 'WATCHED_CHANGE', 'data': {}}), throwsA(isA<DecodeError>()));
    });

    test("a command's medal objects read as the calls' do: v2 colours first, then RGB or #hex, then medal_color", () {
      LiveMedal medalOf(Map<String, Object?> fansMedal) =>
          (decode({
                    'cmd': 'INTERACT_WORD',
                    'data': {'uid': 10007, 'uname': '牌子', 'msg_type': 1, 'fans_medal': fansMedal},
                  })
                  as LiveInteractEvent)
              .user
              .medal!;

      final v2 = {
        'medal_name': '新牌',
        'medal_level': 9,
        'medal_color_start': 398668,
        'medal_color_end': 6850801,
        'medal_color_border': 398668,
        'v2_medal_color_start': '#4775EFCC',
        'v2_medal_color_end': '#4775EFCC',
        'v2_medal_color_border': '#58A1F8FF',
      };
      expect((medalOf(v2).colorStart, medalOf(v2).colorEnd, medalOf(v2).border), (0xCC4775EF, 0xCC4775EF, 0xFF58A1F8));
      final fromCalls = LiveDecode.medal(v2)!;
      expect(
        (fromCalls.name, fromCalls.level, fromCalls.colorStart, fromCalls.border),
        ('新牌', 9, 0xCC4775EF, 0xFF58A1F8),
      );

      final single = medalOf({'medal_name': '单色', 'medal_level': 3, 'medal_color': 6067854, 'is_lighted': 0});
      expect((single.colorStart, single.colorEnd, single.border, single.lit), (0xFF5C968E, 0xFF5C968E, 0, false));

      final hex = medalOf({'name': '字串', 'level': 4, 'color_start': '#06154C', 'color_end': '398668'});
      expect((hex.colorStart, hex.colorEnd), (0xFF06154C, 0xFF06154C));
    });

    test('INTERACT_WORD kinds and LIKE_INFO_V3_CLICK', () {
      final base = fixture('interact_word');
      LiveEvent? kind(int type) => decode({
        'cmd': 'INTERACT_WORD',
        'data': {...base['data'] as Map<String, Object?>, 'msg_type': type},
      });
      final entered = kind(1) as LiveInteractEvent;
      expect(entered.kind, LiveInteraction.entered);
      expect((entered.user.uid, entered.user.name, entered.user.nameColor), (10005, '进来的人', 0xFF00D1F1));
      expect((entered.user.medal!.name, entered.user.medal!.level, entered.user.guardLevel), ('测试牌', 12, 3));
      expect((kind(2) as LiveInteractEvent).kind, LiveInteraction.followed);
      expect((kind(3) as LiveInteractEvent).kind, LiveInteraction.shared);
      expect(kind(5), isNull);

      final liked = decode({
        'cmd': 'LIKE_INFO_V3_CLICK',
        'data': {'uid': 10006, 'uname': '点赞的人', 'like_text': '为主播点赞了', 'msg_type': 6},
      }) as LiveInteractEvent;
      expect((liked.kind, liked.user.uid, liked.user.name), (LiveInteraction.liked, 10006, '点赞的人'));
    });

    test('INTERACT_WORD_V2 reads its protobuf', () {
      final pb = _Proto()
        ..varint(1, 10007)
        ..string(2, '分享的人')
        ..string(3, '#00D1F1')
        ..varint(5, 3)
        ..varint(6, 30001)
        ..message(
          22,
          _Proto()
            ..varint(1, 10007)
            ..message(
              2,
              _Proto()
                ..string(1, '分享的人')
                ..string(2, 'https://i0.hdslb.com/bfs/face/face-0107.jpg'),
            ),
        );
      final event = decode({
        'cmd': 'INTERACT_WORD_V2',
        'data': {'dmscore': 12, 'pb': base64.encode(pb.bytes)},
      }) as LiveInteractEvent;
      expect(event.kind, LiveInteraction.shared);
      expect(
        (event.user.uid, event.user.name, event.user.face),
        (10007, '分享的人', 'https://i0.hdslb.com/bfs/face/face-0107.jpg'),
      );

      final unknownKind = _Proto()
        ..varint(1, 10008)
        ..varint(5, 9);
      expect(
        decode({
          'cmd': 'INTERACT_WORD_V2',
          'data': {'pb': base64.encode(unknownKind.bytes)},
        }),
        isNull,
      );
      expect(
        () => decode({
          'cmd': 'INTERACT_WORD_V2',
          'data': {
            'pb': base64.encode([0x0A, 0x05, 0x41]),
          },
        }),
        throwsA(isA<DecodeError>()),
      );
      expect(
        () => decode({
          'cmd': 'INTERACT_WORD_V2',
          'data': {'pb': '%%%'},
        }),
        throwsA(isA<DecodeError>()),
      );
    });
  });
}

/// Just enough protobuf writing to build INTERACT_WORD_V2's `pb`.
final class _Proto {
  final _out = BytesBuilder();

  Uint8List get bytes => _out.toBytes();

  void _varint(int value) {
    var rest = value;
    while (rest >= 0x80) {
      _out.addByte((rest & 0x7F) | 0x80);
      rest >>= 7;
    }
    _out.addByte(rest);
  }

  void varint(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  void _bytes(int field, List<int> value) {
    _varint(field << 3 | 2);
    _varint(value.length);
    _out.add(value);
  }

  void string(int field, String value) => _bytes(field, utf8.encode(value));

  void message(int field, _Proto value) => _bytes(field, value.bytes);
}
