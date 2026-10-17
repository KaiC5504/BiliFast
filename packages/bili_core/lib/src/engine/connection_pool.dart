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
  _Waiter(this.priority, this.queueClass, this.deadline);

  final double priority;
  final QueueClass queueClass;
  final double Function()? deadline;
  final completer = Completer<void>();
}

/// BTR's `Semaphore` (port of ConnectionPool.swift): a connection budget whose waiters are served by class,
/// then priority, then arrival.
// Wave 0 added [deadline], [onChange] and the clock; urgency and aging come with ConnectionPoolTests.
final class ConnectionPool {
  ConnectionPool(int limit, {MonotonicClock? clock})
    : _limit = limit.clamp(1, 512),
      // ignore: unused_field
      _clock = clock ?? MonotonicClock.system;

  int _limit;
  int _active = 0;
  final _queue = <_Waiter>[];
  // ignore: unused_field
  final MonotonicClock _clock;

  /// Called after every change of active, limit or queued requests.
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
    final waiter = _Waiter(priority, queueClass, deadline);
    _queue.add(waiter);
    final remove = cancel?.onCancel(() {
      if (_queue.remove(waiter)) waiter.completer.completeError(const CancelledException());
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

  void _drain() {
    while (_active < _limit && _queue.isNotEmpty) {
      var best = 0;
      for (var index = 1; index < _queue.length; index++) {
        final candidate = _queue[index];
        final current = _queue[best];
        if (candidate.queueClass.index < current.queueClass.index ||
            (candidate.queueClass == current.queueClass && candidate.priority > current.priority)) {
          best = index;
        }
      }
      final waiter = _queue.removeAt(best);
      _active += 1;
      waiter.completer.complete();
    }
  }
}
