// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's PieceDownloader.swift.

import 'dart:async';
import 'dart:math';

import '../shared/byte_range.dart';
import 'attempt.dart';
import 'cancel.dart';
import 'connection_pool.dart';
import 'hurry_placement.dart';
import 'node_stats.dart';
import 'resolver.dart';
import 'transport.dart';

enum PieceMode {
  normal,

  /// The first segment of a playback or after a seek.
  startup,

  /// The first small piece of a startup range, raced over many nodes at once.
  probe,

  /// A piece of a seek's head ([RipperConfig.seekBurst]) or a small audio read ([RipperConfig.audioFirst]): its
  /// first copies all start at once on the best nodes, and any later one follows the startup rules.
  burst;

  QueueClass get queueClass => switch (this) {
    PieceMode.probe || PieceMode.burst => QueueClass.critical,
    PieceMode.startup => QueueClass.startup,
    PieceMode.normal => QueueClass.ordinary,
  };
}

/// Where the copies of one race go. A copy takes its node once it holds a connection permit: the first candidate no
/// other copy took that has room, or the first one left when every node is full. On the phone (2026-10-17) Akamai,
/// fastest and HTTP/1.1, was given 48-61 requests for its 8 connections while the mirrors sat idle, and 38 of them
/// ran out their first-byte timeout waiting inside URLSession. [laterCopies] orders the candidates for every copy
/// after the first.
final class CopyTargets {
  CopyTargets(
    this.candidates, {
    required this._nodes,
    List<String> Function(List<String>)? laterCopies,
    this.orderFirst = false,
    this.probation,
  }) : _laterCopies = laterCopies ?? ((left) => left);

  final List<String> candidates;
  final NodeStats _nodes;
  final List<String> Function(List<String>) _laterCopies;

  /// The first copy is placed by `laterCopies` too: copies that start together all go by expected finish.
  final bool orderFirst;

  /// A banned node on probation ([BanProbation]) takes the second copy.
  final String? probation;
  final _taken = <int, String>{};

  String? url(int copy) => _taken[copy];

  /// Where the next copy would go now.
  String next() {
    final trial = _trial(_taken.length);
    if (trial != null) return trial;
    final left = _laterCopies(_remaining());
    return left.where((url) => !_nodes.isFull(url)).firstOrNull ?? left.firstOrNull ?? candidates.first;
  }

  String claim(int copy) {
    final trial = _trial(copy);
    if (trial != null) {
      _nodes.beginFirstOpen([trial]);
      _taken[copy] = trial;
      return trial;
    }
    final left = _remaining();
    final order = copy == 0 && !orderFirst ? left : _laterCopies(left);
    final open = order.where((url) => !_taken.containsValue(url)).toList();
    final url = _nodes.beginFirstOpen(
      open.isNotEmpty
          ? open
          : left.isNotEmpty
          ? left
          : candidates,
    );
    _taken[copy] = url;
    return url;
  }

  String? _trial(int copy) => copy == 1 && probation != null && !_taken.containsValue(probation) ? probation : null;

  List<String> _remaining() => candidates.where((url) => !_taken.containsValue(url)).toList();
}

/// The longest prefix the copies of one piece have kept so far, shared by its rounds.
final class _Kept {
  Prefix prefix = Prefix.empty;
}

/// Port of PieceDownloader.swift.
final class PieceDownloader {
  PieceDownloader(this.ctx) : runner = AttemptRunner(ctx);

  static const resumeMinBytes = 32 * 1024;

  final EngineContext ctx;
  final AttemptRunner runner;

  /// One piece, in up to `pieceRounds` rounds. Each round walks the candidates three at a time: the
  /// first copy starts at once, the backup copy once the first is late (see [hedgeDue]), and in a hurry
  /// a third once the backup is late too (see [hurryHedgeDue]); the first to finish wins and the others
  /// are cancelled. A copy skips a full node while another has room ([CopyTargets]). Bytes already
  /// received survive into the next try. [deadline] returns when playback needs the piece (monotonic ms).
  /// In [PieceMode.burst] the first [burstWidth] copies of a group start together.
  Future<AttemptOutput> download({
    required ByteRange piece,
    required int index,
    required Resolver resolver,
    required List<String> preferred,
    required PieceMode mode,
    required double priority,
    double Function()? deadline,
    bool Function()? hurry,
    CancelToken? cancel,
    int burstWidth = 3,
    RequestLane lane = RequestLane.any,
    bool Function()? holdingUp,
    bool probation = false,
  }) async {
    final started = ctx.clock.nowMs();
    final kept = _Kept();
    Object lastError = const RipperError(RipperErrorKind.noNodes);
    for (var round = 0; round < ctx.config.pieceRounds; round++) {
      if (round > 0 && !await ctx.pauseBeforeRound(round, startedAt: started, cancel: cancel)) break;
      final candidates = PieceDownloader.candidates(preferred, resolver, pieceIndex: index, round: round);
      final limit = min(8, candidates.length);
      final width = switch (mode) {
        PieceMode.probe => limit,
        PieceMode.burst => max(3, burstWidth),
        _ => 3,
      };
      final tried = <String>{};
      while (tried.length < limit) {
        cancel?.throwIfCancelled();
        final untried = candidates.where((url) => !tried.contains(url)).toList();
        final allowed = untried.where(resolver.allows).toList();
        final whole = allowed.where((url) => !resolver.avoids(url, piece)).toList();
        final nodes = ctx.nodes;
        final pool = whole.isNotEmpty ? whole : (allowed.isNotEmpty ? allowed : untried);
        // Prefetch only: a player read can't afford the trial. The turn is taken only when a second copy can run.
        final trial = probation && mode == PieceMode.normal && round == 0 && tried.isEmpty && pool.length > 1
            ? resolver.probationCopy(piece, hurried: hurry?.call() ?? false)
            : null;
        // BTR PR 11 `pick`: by speed alone a backup went to cosov, 661-673 ms to its first byte, while Akamai
        // answered in 15-24 ms (phone, 2026-10-17).
        final targets = CopyTargets(
          pool,
          nodes: nodes,
          laterCopies: (left) => hurry?.call() ?? false
              ? HurryPlacement.byExpectedFinish(
                  left,
                  pieceBytes: piece.length,
                  nodes: nodes,
                  delivered: (url) => resolver.bans?.hasDelivered(url) ?? true,
                )
              : left,
          probation: trial,
          // Under keepsOffSlow a hurried piece's first copy also goes by expected finish when it gets its connection:
          // the range was planned before Akamai's 8 connections freed up again.
          orderFirst:
              (mode == PieceMode.burst || (nodes.keepsOffSlow && mode != PieceMode.probe && (hurry?.call() ?? false))) &&
              whole.any(nodes.isKnown),
        );
        if (targets.candidates.isEmpty) break;
        final copies = [for (final _ in targets.candidates.take(width)) AttemptProgress()];
        try {
          final output = await _race(
            targets,
            copies,
            piece,
            resolver,
            mode,
            priority,
            deadline,
            hurry,
            kept,
            cancel,
            burstWidth,
            lane,
            holdingUp: holdingUp,
            probation: trial != null,
          );
          ctx.auto?.delivered(piece.length);
          ctx.stats.delivered(piece.length);
          return output;
        } catch (error) {
          if (cancel?.isCancelled ?? false) throw const CancelledException();
          lastError = error;
        }
        // A copy that never sent its request leaves its node to a later group of this round.
        final used = [
          for (var copy = 0; copy < copies.length; copy++)
            if (copies[copy].started && targets.url(copy) != trial) ?targets.url(copy),
        ];
        tried.addAll(used.isEmpty ? [targets.candidates.first] : used);
      }
    }
    throw lastError;
  }

  /// Copy k waits on copy k - 1; a copy that is never needed ends without sending a request. As with Swift's task
  /// group, the race ends only once every copy has, so a losing copy has reported to the node records and the
  /// resolver by the time the piece is returned.
  Future<AttemptOutput> _race(
    CopyTargets targets,
    List<AttemptProgress> copies,
    ByteRange piece,
    Resolver resolver,
    PieceMode mode,
    double priority,
    double Function()? deadline,
    bool Function()? hurry,
    _Kept kept,
    CancelToken? cancel,
    int burstWidth,
    RequestLane lane, {
    bool Function()? holdingUp,
    bool probation = false,
  }) {
    final hasDeadline = deadline?.call().isFinite ?? false;
    final race = CancelToken(cancel);
    final result = Completer<AttemptOutput>();
    AttemptOutput? winner;
    var pending = copies.length;
    Object lastError = const RipperError(RipperErrorKind.noNodes);

    Prefix resumeFor(int position) {
      Prefix? live;
      for (final copy in copies.take(position)) {
        final prefix = copy.prefix();
        if (live == null || prefix.bytes > live.bytes) live = prefix;
      }
      return resumeBase(prefix: kept.prefix, live: live, pieceLength: piece.length);
    }

    Future<void> runCopy(int position) async {
      final progress = copies[position];
      try {
        if (mode == PieceMode.burst && position < burstWidth) {
          // A burst's copies ask for their connections together, piece by piece. Started one after the other, the
          // first copy of every head piece took a connection before any second copy asked, all of them on the node
          // expected to be fastest, which had nothing of that part of the file.
          await Future<void>.value();
        } else if (position > 0) {
          final go = await _waitForCopy(
            position,
            previous: copies[position - 1],
            previousURL: () => targets.url(position - 1) ?? targets.candidates.first,
            copyURL: targets.next,
            candidates: targets.candidates,
            pieceLength: piece.length,
            resolver: resolver,
            mode: mode,
            hasDeadline: hasDeadline,
            deadline: deadline,
            hurry: hurry,
            holdingUp: holdingUp,
            probation: probation,
            cancel: race,
          );
          if (!go) return;
        }
        try {
          final output = await runner.run(
            claim: () => targets.claim(position),
            piece: piece,
            progress: progress,
            resolver: resolver,
            priority: priority + (position > 0 ? 20 : 0),
            queueClass: mode.queueClass,
            deadline: deadline,
            copy: mode == PieceMode.probe ? 1 : position + 1,
            resumeBase: () => resumeFor(position),
            cancel: race,
            lane: lane,
          );
          if (winner == null) {
            winner = output;
            for (final copy in copies) {
              copy.outrun = true;
            }
            race.cancel();
          }
        } catch (error) {
          final prefix = progress.prefix();
          if (prefix.bytes < piece.length && prefix.bytes > kept.prefix.bytes) kept.prefix = prefix;
          progress.failed = true;
          rethrow;
        }
      } catch (error) {
        if (error is! CancelledException) lastError = error;
      } finally {
        pending -= 1;
        if (pending == 0) {
          final output = winner;
          if (output != null) {
            result.complete(output);
          } else {
            result.completeError((cancel?.isCancelled ?? false) ? const CancelledException() : lastError);
          }
        }
      }
    }

    for (var position = 0; position < copies.length; position++) {
      unawaited(runCopy(position));
    }
    return result.future.whenComplete(race.dispose);
  }

  static Prefix resumeBase({required Prefix prefix, required Prefix? live, required int pieceLength}) {
    var base = prefix.bytes >= resumeMinBytes ? prefix : Prefix.empty;
    if (live != null && live.bytes >= resumeMinBytes && live.bytes > base.bytes) base = live;
    return base.bytes >= pieceLength ? Prefix.empty : base;
  }

  /// Whether copy [position] sends its request. In a hurry it goes once the copy before it is late or has
  /// failed. Otherwise the second copy follows [hedgeDue] or the delay, and a third waits for a hurry: when
  /// the second fails first, the round's walk moves on instead. A burst's copies after those that started together
  /// follow the startup rules.
  Future<bool> _waitForCopy(
    int position, {
    required AttemptProgress previous,
    required String Function() previousURL,
    required String Function() copyURL,
    required List<String> candidates,
    required int pieceLength,
    required Resolver resolver,
    required PieceMode mode,
    required bool hasDeadline,
    required double Function()? deadline,
    required bool Function()? hurry,
    required CancelToken cancel,
    bool Function()? holdingUp,
    bool probation = false,
  }) async {
    if (mode == PieceMode.probe) return true;
    // A probation copy goes second, and a prefetch piece's second copy would otherwise rarely start.
    if (position == 1 && probation) return true;
    final measured = ctx.meter.hedgeDelayMs(ctx.config.hedgeDelayMs);
    final delay = mode == PieceMode.startup || mode == PieceMode.burst
        ? min(hasDeadline ? 200.0 : 250.0, measured)
        : measured;
    final waitStarted = ctx.clock.nowMs();
    while (true) {
      final hurried = hurry?.call() ?? false;
      if (previous.failed) return hurried || position == 1;
      if (hurried) {
        if (previous.started &&
            (hurryHedgeDue(previous, url: previousURL(), pieceLength: pieceLength, candidates: candidates) ||
                ((holdingUp?.call() ?? false) &&
                    HurryPlacement.tailBackupDue(
                      url: previousURL(),
                      backupURL: copyURL(),
                      nodes: ctx.nodes,
                      pieceBytes: pieceLength,
                      elapsedMs: ctx.clock.nowMs() - previous.startedAt,
                      receivingMs: previous.gotHeaders ? ctx.clock.nowMs() - previous.headersAt : null,
                      receivedBytes: previous.received,
                      resumedBytes: previous.base.bytes,
                    )))) {
          return true;
        }
      } else if (position == 1) {
        if (hasDeadline && deadline != null) {
          if (previous.started &&
              hedgeDue(previous, delayMs: delay, deadlineAt: deadline(), copyBps: resolver.speed(copyURL()))) {
            return true;
          }
        } else if (ctx.clock.nowMs() - waitStarted >= delay) {
          return true;
        }
      }
      await cancellableSleep(50, cancel);
    }
  }

  /// BTR `hedgeDue`, without the rescue budgets.
  bool hedgeDue(AttemptProgress first, {required double delayMs, required double deadlineAt, required double copyBps}) {
    final now = ctx.clock.nowMs();
    final usual = ctx.meter.connectionBps;
    final ran = now - first.startedAt;
    if (first.received != first.seenBytes) {
      first
        ..seenBytes = first.received
        ..seenAt = now;
    }
    if (ran < delayMs) return false;
    if (first.received == 0 || now - first.seenAt >= delayMs) return true;
    final rate = first.received * 1000 / ran;
    final remaining = max(0, first.length - first.received);
    if (now + remaining * 1000 / rate <= deadlineAt - 1500) return false;
    if (copyBps > rate * 1.5) return true;
    if (!(usual > 0) || rate < usual * 0.6) return true;
    return !(copyBps > 0);
  }

  /// BTR PR 11 `overdue` with little buffered: a second copy costs less than the wait, since a node can take
  /// seconds over a part of the file it has not served lately. Due when the copy before is late to its first
  /// byte (twice its node's usual, within 250-600 ms), has stopped for 1 s, or is past twice its node's
  /// expected time with under three quarters in.
  bool hurryHedgeDue(
    AttemptProgress previous, {
    required String url,
    required int pieceLength,
    List<String> candidates = const [],
  }) {
    final now = ctx.clock.nowMs();
    final ttfb = ctx.nodes.ttfbMs(url);
    // A node not measured yet is held to the best known candidate, or one that answers and then trickles
    // keeps the piece for twice the hedge delay.
    var expected = ctx.nodes.expectedMs(url, pieceBytes: pieceLength);
    if (expected == null) {
      for (final candidate in candidates) {
        final value = ctx.nodes.expectedMs(candidate, pieceBytes: pieceLength);
        if (value != null && (expected == null || value < expected)) expected = value;
      }
    }
    final elapsed = now - previous.startedAt;
    final floor = ctx.config.hurryHedgeMinMs;
    if (!previous.gotHeaders) return elapsed >= (ttfb > 0 ? min(600, max(floor, ttfb * 2)) : floor);
    if (now - previous.lastProgressAt >= 1000) return true;
    final arrived = previous.base.bytes + previous.received;
    return elapsed >= max(400, (expected ?? ctx.config.hedgeDelayMs) * 2) && arrived < pieceLength * 0.75;
  }

  /// BTR `pieceCandidates`: the assigned node first, then the fastest known nodes.
  static List<String> candidates(
    List<String> preferred,
    Resolver resolver, {
    required int pieceIndex,
    required int round,
  }) {
    final offset = preferred.isEmpty ? 0 : round % preferred.length;
    final rotated = [...preferred.sublist(offset), ...preferred.sublist(0, offset)];
    final rescue = resolver.rescueCandidates().where((url) => !rotated.contains(url));
    final rest = _bySpeed([...rotated.skip(1), ...rescue], resolver);
    final list = rotated.isEmpty ? rest : [rotated.first, ...rest];
    for (final url in resolver.ordered(pieceIndex: pieceIndex)) {
      if (!list.contains(url)) list.add(url);
    }
    return list;
  }

  static List<String> _bySpeed(List<String> urls, Resolver resolver) {
    final speeds = [for (final url in urls) resolver.speed(url)];
    final order = List<int>.generate(urls.length, (index) => index)
      ..sort((a, b) {
        final bySpeed = speeds[b].compareTo(speeds[a]);
        return bySpeed != 0 ? bySpeed : a.compareTo(b);
      });
    return [for (final index in order) urls[index]];
  }
}
