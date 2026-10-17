import 'dart:async';

final class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => 'cancelled';
}

/// Cooperative cancellation; Dart futures cannot be cancelled from outside.
final class CancelToken {
  CancelToken([CancelToken? parent]) {
    if (parent == null) return;
    if (parent.isCancelled) {
      _cancelled = true;
    } else {
      _unlinkParent = parent.onCancel(cancel);
    }
  }

  bool _cancelled = false;
  final _callbacks = <int, void Function()>{};
  int _next = 0;
  void Function()? _unlinkParent;

  bool get isCancelled => _cancelled;

  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }

  /// Returns a function that removes the callback again.
  void Function() onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    final id = _next++;
    _callbacks[id] = callback;
    return () => _callbacks.remove(id);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _unlinkParent?.call();
    final callbacks = _callbacks.values.toList();
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// Detaches from the parent once this token's work is over, so long-lived parents don't collect callbacks.
  void dispose() {
    _unlinkParent?.call();
    _unlinkParent = null;
    _callbacks.clear();
  }

  /// Completes with the future's value, or throws as soon as this token is cancelled.
  Future<T> guard<T>(Future<T> future) {
    if (_cancelled) return Future.error(const CancelledException());
    final completer = Completer<T>();
    final remove = onCancel(() {
      if (!completer.isCompleted) completer.completeError(const CancelledException());
    });
    future.then(
      (value) {
        remove();
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        remove();
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    return completer.future;
  }
}
