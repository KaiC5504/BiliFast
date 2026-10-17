import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'log_server_discovery.dart';

/// The network sink and the 发送日志到电脑 switch are compiled in for dev builds only, as the Swift app's
/// `DEV_TOOLS`; like the Swift app, builds keep it on until a public release passes `--dart-define=DEV_TOOLS=false`.
const devToolsEnabled = bool.fromEnvironment('DEV_TOOLS', defaultValue: true);

/// Sends Logger.shared to the PC's `tools/logserver.py` while switched on (port of DevLogSetup.swift's network
/// half). Off by default and kept in memory for now; `--dart-define=LOG_SERVER=host:port` starts it on.
class LogForwarder extends ChangeNotifier {
  LogForwarder({
    Logger? logger,
    LogServerDiscovery? discovery,
    LogPoster Function(LogServerEndpoint endpoint)? poster,
    String initialTarget = defineTarget,
    this._statusInterval = const Duration(seconds: 1),
  })  : _logger = logger ?? Logger.shared,
        _discovery = discovery ?? LogServerDiscovery.platform(),
        _poster = poster ?? _httpPoster {
    if (initialTarget.trim().isNotEmpty) {
      _manual = initialTarget.trim();
      setEnabled(true);
    }
  }

  static const defineTarget = String.fromEnvironment('LOG_SERVER');

  final Logger _logger;
  final LogServerDiscovery _discovery;
  final LogPoster Function(LogServerEndpoint endpoint) _poster;
  final Duration _statusInterval;

  bool _enabled = false;
  String _manual = '';
  LogServerEndpoint? _service;
  List<LogServerEndpoint> _discovered = const [];
  StreamSubscription<List<LogServerEndpoint>>? _browsing;
  NetworkSink? _sink;
  LogServerEndpoint? _applied;
  Timer? _statusTimer;
  String _lastStatus = '';

  bool get enabled => _enabled;
  String get manual => _manual;

  /// The discovered server picked by the user; it wins over the typed address.
  LogServerEndpoint? get service => _service;
  List<LogServerEndpoint> get discovered => _discovered;
  LogServerEndpoint? get target => _service ?? parseManual(_manual);
  NetworkSink? get sink => _sink;

  static LogPoster _httpPoster(LogServerEndpoint endpoint) =>
      NetworkSink.httpPoster(host: endpoint.host, port: endpoint.port);

  /// `host:port`, or a bare host on the log server's default port.
  static LogServerEndpoint? parseManual(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    if (parts.length > 2 || parts.first.isEmpty) return null;
    var port = LogServerEndpoint.defaultPort;
    if (parts.length == 2) {
      final parsed = int.tryParse(parts[1]);
      if (parsed == null || parsed <= 0 || parsed > 65535) return null;
      port = parsed;
    }
    return LogServerEndpoint(name: trimmed, host: parts.first, port: port);
  }

  String get status {
    if (_enabled && target == null) {
      return _manual.trim().isEmpty ? '请选择电脑，或输入 IP:端口' : '地址无效，格式为 IP:端口';
    }
    final sink = _sink;
    if (sink == null) return '未开启';
    return switch (sink.state) {
      NetworkSinkIdle() => '连接中…',
      NetworkSinkConnected() => '已连接，待发送 ${sink.pending} 条',
      NetworkSinkFailing(:final reason) => '连不上：$reason',
    };
  }

  void setEnabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (on) {
      _browsing = _discovery.browse().listen((servers) {
        _discovered = servers;
        notifyListeners();
      }, onError: (Object error) {
        _logger.warn(LogCategory.app, 'log server discovery failed', {'error': '$error'});
      });
    } else {
      unawaited(_browsing?.cancel());
      _browsing = null;
      _discovered = const [];
    }
    _apply();
  }

  /// Applied when the field is submitted, not per keystroke: every prefix of an address is a valid host.
  void setManual(String text) {
    _manual = text;
    _service = null;
    _apply();
  }

  void selectService(LogServerEndpoint? endpoint) {
    _service = endpoint;
    _apply();
  }

  void _apply() {
    final wanted = _enabled ? target : null;
    if (_sink != null && _same(wanted, _applied)) {
      notifyListeners();
      return;
    }
    _stopSink();
    if (wanted != null) {
      final sink = NetworkSink(poster: _poster(wanted));
      _logger.add(sink);
      sink.start();
      _sink = sink;
      _applied = wanted;
      _statusTimer = Timer.periodic(_statusInterval, (_) => _refreshStatus());
      _logger.info(LogCategory.app, 'log server on', {'target': '${wanted.host}:${wanted.port}'});
    }
    notifyListeners();
  }

  void _refreshStatus() {
    final now = status;
    if (now == _lastStatus) return;
    _lastStatus = now;
    notifyListeners();
  }

  void _stopSink() {
    final sink = _sink;
    if (sink != null) {
      sink.stop();
      _logger.remove(sink);
    }
    _sink = null;
    _applied = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  static bool _same(LogServerEndpoint? a, LogServerEndpoint? b) =>
      a == null ? b == null : b != null && a.host == b.host && a.port == b.port;

  @override
  void dispose() {
    _stopSink();
    unawaited(_browsing?.cancel());
    _browsing = null;
    super.dispose();
  }
}
