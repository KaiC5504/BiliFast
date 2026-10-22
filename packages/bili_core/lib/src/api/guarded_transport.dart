import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import 'bili_error.dart';
import 'http.dart';

/// The Windows build's guard on the account (KaiC, 2026-10-22: one PC login, read only). Every request the client
/// sends passes here: a write (anything but GET) is refused before it leaves the PC unless its path is in
/// [writesAllowed]; reads are paced to [burst] at once and one per [refill] after that; and after [cap] requests in
/// one run nothing more is sent until the app restarts. Refused requests are never sent and don't count.
final class GuardedTransport implements HTTPTransport {
  /// [clock] (time since any fixed point) and [wait] are for tests; the defaults are real time.
  GuardedTransport(
    this._inner, {
    this.writesAllowed = const {},
    this.burst = 8,
    this.refill = const Duration(seconds: 1),
    this.cap = 200,
    Logger? logger,
    Duration Function()? clock,
    Future<void> Function(Duration)? wait,
  }) : assert(burst > 0),
       _logger = logger ?? Logger.shared,
       _clock = clock ?? _realClock(),
       _wait = wait ?? Future<void>.delayed;

  /// [BiliAPIError.code] of a write the guard refused.
  static const readOnlyCode = -9001;

  /// [BiliAPIError.code] once [cap] requests went out.
  static const capCode = -9002;

  final HTTPTransport _inner;
  final Set<String> writesAllowed;
  final int burst;
  final Duration refill;
  final int cap;
  final Logger _logger;
  final Duration Function() _clock;
  final Future<void> Function(Duration) _wait;

  /// Requests let through, sent or still waiting for their turn; every one of them is sent.
  int _admitted = 0;
  int _sent = 0;

  /// When the bucket would be full again had nothing more been sent (GCRA's theoretical arrival time).
  Duration? _full;

  final Set<String> _refusedPaths = {};
  bool _capLogged = false;

  /// Requests sent this run.
  int get sent => _sent;

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    final path = request.url.path;
    if (request.method.toUpperCase() != 'GET' && !writesAllowed.contains(path)) {
      // A heartbeat is refused every few seconds; once per path says as much.
      if (_refusedPaths.add(path)) {
        _logger.warn(LogCategory.api, 'pc guard refused', {'method': request.method, 'path': path});
      }
      throw const BiliError.api(code: readOnlyCode, message: 'PC 只读，未发送');
    }
    // Counted when let through rather than when sent, so nothing waits its turn only to be refused at the cap.
    if (_admitted >= cap) {
      if (!_capLogged) {
        _capLogged = true;
        _logger.error(LogCategory.api, 'pc guard cap reached', {'cap': cap});
      }
      throw const BiliError.api(code: capCode, message: 'PC 本次调用已达上限，请重启应用');
    }
    _admitted += 1;
    final delay = _reserve();
    if (delay > Duration.zero) await _wait(delay);
    _sent += 1;
    return _inner.send(request);
  }

  /// How long this request waits for a token. Each waiting request's turn is at least [refill] after the one before
  /// it, handed out as it is called, so requests go in the order they came.
  Duration _reserve() {
    final now = _clock();
    final full = _full;
    final from = full == null || full < now ? now : full;
    final turn = from - refill * (burst - 1);
    _full = from + refill;
    return turn > now ? turn - now : Duration.zero;
  }

  static Duration Function() _realClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}
