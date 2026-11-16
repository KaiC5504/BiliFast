import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../api/live_models.dart';
import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import 'live_decode.dart';
import 'live_events.dart';
import 'live_packet.dart';

/// A room's danmaku feed as the room model sees it; [LiveSocket] on the network, a fake in tests and `--fake-account`.
abstract interface class LiveChannel {
  Stream<LiveEvent> get events;
  Stream<LiveSocketState> get states;

  /// Connects (again, after [close]); the hosts are tried in turn and a dropped connection comes back with a backoff.
  Future<void> start();
  Future<void> close();
}

/// One open connection: binary messages in, binary messages out.
abstract interface class LiveConnection {
  Stream<List<int>> get incoming;
  void send(List<int> bytes);
  Future<void> close();
}

/// Opens [uri] with [headers] on the upgrade; throws when it can't.
typedef LiveConnector = Future<LiveConnection> Function(Uri uri, Map<String, String> headers);

/// The socket's timers, so tests can move time by hand.
abstract interface class LiveTimers {
  static const LiveTimers system = _SystemTimers();

  Timer after(Duration delay, void Function() callback);
  Timer every(Duration period, void Function() callback);
}

final class _SystemTimers implements LiveTimers {
  const _SystemTimers();

  @override
  Timer after(Duration delay, void Function() callback) => Timer(delay, callback);

  @override
  Timer every(Duration period, void Function() callback) => Timer.periodic(period, (_) => callback());
}

/// The website's danmaku websocket (`wss://host:port/sub`), authenticated with [info]'s token as [uid] (0 logged out).
/// [headers] go with the upgrade (User-Agent, Origin, the `buvid3` cookie).
///
/// [states]: connecting on each attempt, open once the auth is accepted, failed when an attempt or an open connection
/// is lost (a reconnect is then due, unless [maxAttempts] in a row have failed: then it stops), refused when the
/// server turns the token down (it stops: the token won't work again), closed after [close]. After a stop, [start]
/// begins again.
final class LiveSocket implements LiveChannel {
  LiveSocket({
    required this.roomId,
    required this.uid,
    required this.info,
    this.headers = const {},
    Logger? logger,
    LiveConnector? connector,
    this._timers = LiveTimers.system,
    this._now = DateTime.now,
  }) : _logger = logger ?? Logger.shared,
       _connector = connector ?? connectWebSocket;

  final int roomId;
  final int uid;
  final LiveDanmuInfo info;
  final Map<String, String> headers;
  final Logger _logger;
  final LiveConnector _connector;
  final LiveTimers _timers;
  final DateTime Function() _now;

  static const fallbackHost = LiveSocketHost(host: 'broadcastlv.chat.bilibili.com', wssPort: 443);
  static const heartbeatPeriod = Duration(seconds: 30);
  static const authTimeout = Duration(seconds: 10);

  /// An open connection that lasts this long clears the backoff.
  static const steadyAfter = Duration(seconds: 60);
  static const backoff = [1, 2, 4, 8, 16, 30];

  /// Failed attempts in a row, with no steady connection between, after which the socket stops.
  static const maxAttempts = 8;

  final _events = StreamController<LiveEvent>.broadcast();
  final _states = StreamController<LiveSocketState>.broadcast();

  bool _running = false;

  /// Bumped by every attempt, loss and [close]: a callback from an older one finds it changed and does nothing.
  int _epoch = 0;
  int _failures = 0;
  int _hostIndex = 0;
  int _seq = 0;
  bool _open = false;

  /// Heartbeat ticks since the server last sent anything; it answers every heartbeat, so two means it's gone quiet.
  int _quietTicks = 0;

  LiveConnection? _connection;
  StreamSubscription<List<int>>? _subscription;
  LivePacketReader? _reader;
  Timer? _authTimer;
  Timer? _heartbeat;
  Timer? _steady;
  Timer? _retry;

  /// Commands that failed to decode since [start], each logged once.
  final _badCommands = <String>{};

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  Stream<LiveSocketState> get states => _states.stream;

  List<LiveSocketHost> get _hosts => [
    ...info.hosts,
    if (!info.hosts.any((each) => each.host == fallbackHost.host)) fallbackHost,
  ];

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _failures = 0;
    _hostIndex = 0;
    _badCommands.clear();
    unawaited(_connect());
  }

  @override
  Future<void> close() async {
    if (!_running) return;
    _running = false;
    _epoch++;
    _retry?.cancel();
    _retry = null;
    _teardown();
    _logger.info(LogCategory.api, 'live socket closed');
    _states.add(LiveSocketState.closed);
  }

  Future<void> _connect() async {
    final epoch = ++_epoch;
    final hosts = _hosts;
    final index = _hostIndex % hosts.length;
    final host = hosts[index];
    _states.add(LiveSocketState.connecting);
    _logger.info(LogCategory.api, 'live socket connect', {'host': index, 'attempt': _failures + 1});
    final LiveConnection connection;
    try {
      connection = await _connector(Uri(scheme: 'wss', host: host.host, port: host.wssPort, path: '/sub'), headers);
    } catch (error) {
      if (epoch != _epoch) return;
      _logger.warn(LogCategory.api, 'live socket connect failed', {'host': index, 'error': error.runtimeType});
      _lost(epoch, 'connect failed');
      return;
    }
    if (epoch != _epoch) {
      unawaited(connection.close().catchError((_) {}));
      return;
    }
    _connection = connection;
    _reader = LivePacketReader();
    _subscription = connection.incoming.listen(
      (bytes) => _receive(epoch, bytes),
      onError: (Object _) => _lost(epoch, 'error'),
      onDone: () => _lost(epoch, 'dropped'),
      cancelOnError: true,
    );
    _authTimer = _timers.after(authTimeout, () => _lost(epoch, 'auth timeout'));
    _send(epoch, LivePacket.json(op: LiveOp.auth, json: _authBody()));
  }

  Map<String, Object> _authBody() {
    final buvid = _cookie('buvid3');
    return {
      'uid': uid,
      'roomid': roomId,
      // 2 asks zlib bodies; 3 would be brotli, which Dart can't open.
      'protover': 2,
      'buvid': ?buvid,
      'platform': 'web',
      'type': 2,
      'key': info.token,
    };
  }

  String? _cookie(String name) {
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() != 'cookie') continue;
      for (final pair in value.split(';')) {
        final equals = pair.indexOf('=');
        if (equals > 0 && pair.substring(0, equals).trim() == name) {
          final cookie = pair.substring(equals + 1).trim();
          return cookie.isEmpty ? null : cookie;
        }
      }
    }
    return null;
  }

  void _send(int epoch, LivePacket packet) {
    final connection = _connection;
    if (epoch != _epoch || connection == null) return;
    try {
      connection.send(LivePacket(op: packet.op, protover: packet.protover, seq: ++_seq, body: packet.body).encode());
    } catch (_) {
      _lost(epoch, 'send failed');
    }
  }

  void _receive(int epoch, List<int> bytes) {
    final reader = _reader;
    if (epoch != _epoch || reader == null) return;
    _quietTicks = 0;
    final List<LivePacket> packets;
    try {
      reader.add(bytes);
      packets = reader.take();
    } on LivePacketError {
      _lost(epoch, 'unreadable stream');
      return;
    }
    for (final packet in packets) {
      if (epoch != _epoch) return;
      switch (packet.op) {
        case LiveOp.authReply:
          _authReply(epoch, packet);
        case LiveOp.command:
          for (final body in packet.commands(onBad: _badBody)) {
            _command(body);
          }
      }
    }
  }

  void _authReply(int epoch, LivePacket packet) {
    if (_open) return;
    Object? code;
    try {
      final reply = jsonDecode(utf8.decode(packet.body));
      if (reply is Map<String, Object?>) code = reply['code'];
    } on FormatException {
      code = null;
    }
    if (code is! int) {
      _lost(epoch, 'auth reply unreadable');
      return;
    }
    if (code != 0) {
      _logger.warn(LogCategory.api, 'live socket auth refused', {'code': code});
      _stop(LiveSocketState.refused);
      return;
    }
    _authTimer?.cancel();
    _authTimer = null;
    _open = true;
    _quietTicks = 0;
    _logger.info(LogCategory.api, 'live socket open', {'host': _hostIndex % _hosts.length});
    _states.add(LiveSocketState.open);
    _send(epoch, LivePacket(op: LiveOp.heartbeat, body: Uint8List(0)));
    _heartbeat = _timers.every(heartbeatPeriod, () => _beat(epoch));
    _steady = _timers.after(steadyAfter, () {
      if (epoch == _epoch) _failures = 0;
    });
  }

  void _beat(int epoch) {
    if (epoch != _epoch) return;
    if (++_quietTicks >= 2) {
      _lost(epoch, 'quiet');
      return;
    }
    _send(epoch, LivePacket(op: LiveOp.heartbeat, body: Uint8List(0)));
  }

  void _badBody(int protover, Object error) {
    _logger.warn(LogCategory.api, 'live body undecodable', {'protover': protover, 'error': error.runtimeType});
  }

  void _command(Uint8List body) {
    Map<String, Object?>? json;
    var name = '';
    try {
      final decoded = jsonDecode(utf8.decode(_fromBrace(body), allowMalformed: true));
      if (decoded is! Map<String, Object?>) throw const FormatException('not an object');
      json = decoded;
      name = LiveSocketDecode.commandName(decoded);
      final event = LiveSocketDecode.command(decoded, now: _now);
      if (event != null) _events.add(event);
    } catch (error) {
      // Untrusted input: whatever a message throws costs that message only.
      final key = json == null ? '(json)' : name;
      if (_badCommands.add(key)) {
        _logger.warn(LogCategory.api, 'live command undecodable', {'cmd': key, 'error': error.runtimeType});
      }
    }
  }

  /// Some bodies carry a few bytes before their JSON (WATCHED_CHANGE has been seen so); start at the first `{`.
  static Uint8List _fromBrace(Uint8List body) {
    final brace = body.indexOf(0x7B);
    return brace <= 0 ? body : Uint8List.sublistView(body, brace);
  }

  void _lost(int epoch, String reason) {
    if (epoch != _epoch || !_running) return;
    _epoch++;
    _teardown();
    _failures++;
    _hostIndex++;
    if (_failures >= maxAttempts) {
      _logger.warn(LogCategory.api, 'live socket gave up', {'reason': reason, 'attempts': _failures});
      _stop(LiveSocketState.failed);
      return;
    }
    final seconds = backoff[(_failures - 1).clamp(0, backoff.length - 1)];
    _logger.info(LogCategory.api, 'live socket lost', {'reason': reason, 'retry_s': seconds});
    _states.add(LiveSocketState.failed);
    _retry = _timers.after(Duration(seconds: seconds), () {
      _retry = null;
      if (_running) unawaited(_connect());
    });
  }

  void _stop(LiveSocketState state) {
    _running = false;
    _epoch++;
    _retry?.cancel();
    _retry = null;
    _teardown();
    _states.add(state);
  }

  void _teardown() {
    _open = false;
    _authTimer?.cancel();
    _authTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _steady?.cancel();
    _steady = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final connection = _connection;
    _connection = null;
    _reader = null;
    if (connection != null) unawaited(connection.close().catchError((_) {}));
  }
}

/// [LiveConnector] over dart:io's WebSocket.
Future<LiveConnection> connectWebSocket(Uri uri, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final pending = WebSocket.connect(uri.toString(), headers: headers, customClient: client);
  try {
    return _WebSocketConnection(await pending.timeout(const Duration(seconds: 15)));
  } on TimeoutException {
    // The upgrade may still land after the timeout; it mustn't stay open behind the next attempt.
    unawaited(pending.then((socket) => socket.close(), onError: (_) => null));
    rethrow;
  } finally {
    client.close();
  }
}

final class _WebSocketConnection implements LiveConnection {
  _WebSocketConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<List<int>> get incoming => _socket.where((message) => message is List<int>).cast<List<int>>();

  @override
  void send(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() => _socket.close();
}
