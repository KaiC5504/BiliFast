// ignore_for_file: unused_field, unused_import (contracts stub; the builder removes this line)
import 'dart:async';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import 'bili_error.dart';
import 'http.dart';

/// The Windows build's guard on the account (KaiC, 2026-10-22: one PC login, read only). Every request the client
/// sends passes here: a write (anything but GET) is refused before it leaves the PC unless its path is in
/// [writesAllowed]; reads are paced to [burst] at once and one per [refill] after that; and after [cap] requests in
/// one run nothing more is sent until the app restarts. Refused requests are never sent and don't count.
final class GuardedTransport implements HTTPTransport {
  GuardedTransport(
    this._inner, {
    this.writesAllowed = const {},
    this.burst = 8,
    this.refill = const Duration(seconds: 1),
    this.cap = 200,
    Logger? logger,
  }) : _logger = logger ?? Logger.shared;

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

  /// Requests sent this run.
  int get sent => throw UnimplementedError();

  @override
  Future<HTTPResponse> send(HTTPRequest request) => throw UnimplementedError();
}
