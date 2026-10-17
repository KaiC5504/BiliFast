// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's ConnectionPool.swift.

import 'dart:async';

import '../shared/clock.dart';
import 'cancel.dart';

enum QueueClass {
  /// Init/index and the first probe of a range.
  critical,
  startup,
  ordinary,
}

final class Permit {
  Permit._(this._pool);

  final ConnectionPool _pool;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _pool._releaseOne();
  }
}

final class _Waiter {
  _Waiter(this.priority, this.queueClass, this.deadline, {required this.ages, required this.queuedAt});

  final double priority;
  final QueueClass queueClass;
  final double Function()? deadline;
  final bool ages;
  final double queuedAt;
  final completer = Completer<void>();
}

/// BTR's `Semaphore` (port of ConnectionPool.swift): a connection budget whose waiters are served by class,
/// deadline urgency and age.
final class ConnectionPool {
  ConnectionPool(int limit, {MonotonicClock? clock})
    : _limit = limit.clamp(1, 512),
      _clock = clock ?? MonotonicClock.system;

  /// A hedge copy's +20 is worth 0.9 s of waiting.
  static const agingPerMs = 20.0 / 900.0;

  int _limit;
  int _active = 0;
  final _queue = <_Waiter>[];
  final MonotonicClock _clock;

  /// Called after every change, once the pool's state is settled, so the handler may read the pool.
  void Function(int active, int limit, int queued)? onChange;

  int get limit => _limit;
  int get active => _active;
  int get queued => _queue.length;

  void setLimit(int limit) {
    _limit = limit.clamp(1, 512);
    _drain();
  }

  /// [deadline] returns the monotonic time (ms) playback needs this request; it is re-read on every pass.
  Future<Permit> acquire({
    required double priority,
    required QueueClass queueClass,
    double Function()? deadline,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final ages = queueClass == QueueClass.ordinary && (deadline?.call().isFinite ?? false);
    final waiter = _Waiter(priority, queueClass, deadline, ages: ages, queuedAt: _clock.nowMs());
    _queue.add(waiter);
    // Whoever takes the waiter out of the queue owns its completer, so it completes once.
    final remove = cancel?.onCancel(() {
      if (!_queue.remove(waiter)) return;
      waiter.completer.completeError(const CancelledException());
      _notify();
    });
    _drain();
    try {
      await waiter.completer.future;
    } finally {
      remove?.call();
    }
    final permit = Permit._(this);
    // Granted while the cancellation was on its way.
    if (cancel?.isCancelled ?? false) {
      permit.release();
      throw const CancelledException();
    }
    return permit;
  }

  void _releaseOne() {
    if (_active > 0) _active -= 1;
    _drain();
  }

  double _rank(_Waiter waiter, double now) {
    var urgency = 0.0;
    final deadline = waiter.deadline?.call();
    if (deadline != null && deadline.isFinite) {
      final remaining = deadline - now;
      urgency = remaining <= 0
          ? 12
          : remaining <= 750
          ? 9
          : remaining <= 2000
          ? 6
          : 0;
    }
    return waiter.priority + urgency + (waiter.ages ? (now - waiter.queuedAt) * agingPerMs : 0);
  }

  void _drain() {
    final now = _clock.nowMs();
    while (_active < _limit && _queue.isNotEmpty) {
      var best = 0;
      var bestRank = _rank(_queue[0], now);
      for (var index = 1; index < _queue.length; index++) {
        final candidate = _queue[index];
        final current = _queue[best];
        final candidateRank = _rank(candidate, now);
        if (candidate.queueClass.index < current.queueClass.index ||
            (candidate.queueClass == current.queueClass && candidateRank > bestRank)) {
          best = index;
          bestRank = candidateRank;
        }
      }
      final waiter = _queue.removeAt(best);
      _active += 1;
      waiter.completer.complete();
    }
    _notify();
  }

  void _notify() => onChange?.call(_active, _limit, _queue.length);
}
