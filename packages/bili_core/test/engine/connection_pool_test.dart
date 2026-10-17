import 'dart:async';
import 'dart:math';

import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/cancel.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:test/test.dart';

Future<void> _waitUntil(bool Function() condition) async {
  for (var tries = 0; tries < 200; tries++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition never became true');
}

/// Swift's `Task.yield()`.
Future<void> _yield() => Future<void>.delayed(Duration.zero);

void main() {
  test('waits for release', () async {
    final pool = ConnectionPool(1);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final waiter = pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    await _waitUntil(() => pool.queued == 1);
    expect(pool.active, 1);
    held
      ..release()
      ..release();
    final second = await waiter;
    expect(pool.active, 1);
    second.release();
    expect(pool.active, 0);
  });

  test('class, then priority, then arrival', () async {
    final pool = ConnectionPool(1);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final order = <String>[];
    final tasks = <Future<void>>[];
    for (final (name, priority, queueClass) in [
      ('low', 0.0, QueueClass.ordinary),
      ('high', 50.0, QueueClass.ordinary),
      ('critical', 0.0, QueueClass.critical),
    ]) {
      final expected = tasks.length + 1;
      tasks.add(() async {
        final permit = await pool.acquire(priority: priority, queueClass: queueClass);
        order.add(name);
        permit.release();
      }());
      await _waitUntil(() => pool.queued == expected);
    }
    held.release();
    await Future.wait(tasks);
    expect(order, ['critical', 'high', 'low']);
  });

  test('an overdue deadline wins within a class', () async {
    final manual = ManualClock(10000);
    final pool = ConnectionPool(1, clock: manual.clock);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final order = <String>[];
    final relaxed = () async {
      final permit = await pool.acquire(priority: 5, queueClass: QueueClass.ordinary);
      order.add('relaxed');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 1);
    final urgent = () async {
      final permit = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary, deadline: () => 9000);
      order.add('urgent');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 2);
    held.release();
    await relaxed;
    await urgent;
    expect(order, ['urgent', 'relaxed']);
  });

  test('cancelling a waiter removes it', () async {
    final pool = ConnectionPool(1);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final cancel = CancelToken();
    final waiter = pool.acquire(priority: 0, queueClass: QueueClass.ordinary, cancel: cancel);
    await _waitUntil(() => pool.queued == 1);
    cancel.cancel();
    await expectLater(waiter, throwsA(isA<CancelledException>()));
    expect(pool.queued, 0);
    held.release();
    expect(pool.active, 0);
  });

  test('raising the limit grants waiters', () async {
    final pool = ConnectionPool(1);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final waiter = pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    await _waitUntil(() => pool.queued == 1);
    pool.setLimit(2);
    final second = await waiter;
    expect(pool.active, 2);
    held.release();
    second.release();
  });

  test('a cancelled waiter is never granted a permit', () async {
    final pool = ConnectionPool(1);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final cancel = CancelToken();
    final cancelled = pool.acquire(priority: 100, queueClass: QueueClass.critical, cancel: cancel);
    await _waitUntil(() => pool.queued == 1);
    final survivor = pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    await _waitUntil(() => pool.queued == 2);
    cancel.cancel();
    await expectLater(cancelled, throwsA(isA<CancelledException>()));
    expect(pool.queued, 1);
    held.release();
    final permit = await survivor;
    expect(pool.active, 1);
    expect(pool.queued, 0);
    permit.release();
    expect(pool.active, 0);
  });

  test('acquire with an already cancelled token throws without queueing', () async {
    final pool = ConnectionPool(1);
    final cancel = CancelToken()..cancel();
    await expectLater(
      pool.acquire(priority: 0, queueClass: QueueClass.ordinary, cancel: cancel),
      throwsA(isA<CancelledException>()),
    );
    expect(pool.active, 0);
    expect(pool.queued, 0);
    final permit = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    expect(pool.active, 1);
    permit.release();
  });

  test('releasing twice does not raise capacity', () async {
    final pool = ConnectionPool(1);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    held
      ..release()
      ..release();
    expect(pool.active, 0);
    final first = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final waiter = pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    await _waitUntil(() => pool.queued == 1);
    held.release();
    expect(pool.active, 1);
    expect(pool.queued, 1);
    first.release();
    final second = await waiter;
    expect(pool.active, 1);
    second.release();
    expect(pool.active, 0);
  });

  test('lowering the limit does not strand waiters', () async {
    final pool = ConnectionPool(2);
    final first = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final second = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    pool.setLimit(1);
    final waiter = pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    await _waitUntil(() => pool.queued == 1);
    first.release();
    expect(pool.active, 1);
    expect(pool.queued, 1);
    second.release();
    final third = await waiter;
    expect(pool.active, 1);
    expect(pool.limit, 1);
    third.release();
    expect(pool.active, 0);
  });

  test('the limit is clamped', () {
    expect(ConnectionPool(0).limit, 1);
    expect(ConnectionPool(10000).limit, 512);
    final pool = ConnectionPool(4)..setLimit(-3);
    expect(pool.limit, 1);
  });

  test('class beats an overdue deadline', () async {
    final manual = ManualClock(10000);
    final pool = ConnectionPool(1, clock: manual.clock);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final order = <String>[];
    final overdue = () async {
      final permit = await pool.acquire(priority: 50, queueClass: QueueClass.ordinary, deadline: () => 0);
      order.add('overdue');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 1);
    final startup = () async {
      final permit = await pool.acquire(priority: 0, queueClass: QueueClass.startup);
      order.add('startup');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 2);
    held.release();
    await overdue;
    await startup;
    expect(order, ['startup', 'overdue']);
  });

  test('a long-waiting request with a deadline overtakes newer ones', () async {
    final manual = ManualClock(0);
    final pool = ConnectionPool(1, clock: manual.clock);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final order = <String>[];
    final old = () async {
      final permit = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary, deadline: () => 1000000);
      order.add('old');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 1);
    manual.advance(900);
    final newer = () async {
      final permit = await pool.acquire(priority: 10, queueClass: QueueClass.ordinary);
      order.add('newer');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 2);
    held.release();
    await old;
    await newer;
    expect(order, ['old', 'newer']);
  });

  test('an infinite deadline does not age', () async {
    final manual = ManualClock(0);
    final pool = ConnectionPool(1, clock: manual.clock);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final order = <String>[];
    final unbounded = () async {
      final permit = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary, deadline: () => double.infinity);
      order.add('unbounded');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 1);
    manual.advance(4500);
    final newer = () async {
      final permit = await pool.acquire(priority: 10, queueClass: QueueClass.ordinary);
      order.add('newer');
      permit.release();
    }();
    await _waitUntil(() => pool.queued == 2);
    held.release();
    await unbounded;
    await newer;
    expect(order, ['newer', 'unbounded']);
  });

  // Swift races a task's start against its cancellation. In one isolate the cancellation can come before the
  // call, between the grant and the caller resuming, or a microtask later; each ordering is tried.
  test('cancellation racing a free pool never leaks a permit', () async {
    final pool = ConnectionPool(1);
    for (var index = 0; index < 300; index++) {
      final cancel = CancelToken();
      if (index % 3 == 0) cancel.cancel();
      final task = pool.acquire(priority: 0, queueClass: QueueClass.critical, cancel: cancel);
      if (index % 3 == 1) cancel.cancel();
      if (index % 3 == 2) scheduleMicrotask(cancel.cancel);
      try {
        (await task).release();
      } on CancelledException {
        // Expected for most orderings.
      }
      expect(pool.active, 0);
      expect(pool.queued, 0);
    }
  });

  test('onChange reports every state change', () async {
    final pool = ConnectionPool(1);
    final events = <List<int>>[];
    pool.onChange = (active, limit, queued) => events.add([active, limit, queued]);
    final held = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    final waiter = pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    await _waitUntil(() => events.any((event) => event.join(',') == '1,1,1'));
    held.release();
    final second = await waiter;
    second.release();
    expect(events, contains(equals([1, 1, 0])));
    expect(events, contains(equals([1, 1, 1])));
    expect(events.last, [0, 1, 0]);
  });

  test('onChange may read the pool', () async {
    final pool = ConnectionPool(1);
    final seen = <int>[];
    pool.onChange = (_, _, _) => seen.add(pool.active);
    final permit = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    permit.release();
    expect(seen, isNotEmpty);
  });

  test('stress never exceeds the limit and leaks nothing', () async {
    final pool = ConnectionPool(3);
    var inFlight = 0;
    var peak = 0;
    await Future.wait([
      for (var index = 0; index < 150; index++)
        () async {
          final cancel = CancelToken();
          final inner = () async {
            final permit = await pool.acquire(
              priority: (index % 7).toDouble(),
              queueClass: index % 5 == 0 ? QueueClass.critical : QueueClass.ordinary,
              cancel: cancel,
            );
            inFlight += 1;
            peak = max(peak, inFlight);
            await _yield();
            inFlight -= 1;
            permit.release();
          }();
          if (index % 3 == 0) {
            await _yield();
            cancel.cancel();
          }
          try {
            await inner;
          } on CancelledException {
            // Cancelled while waiting.
          }
        }(),
    ]);
    expect(peak, lessThanOrEqualTo(3));
    expect(pool.active, 0);
    expect(pool.queued, 0);
    final permit = await pool.acquire(priority: 0, queueClass: QueueClass.ordinary);
    expect(pool.active, 1);
    permit.release();
  });
}
