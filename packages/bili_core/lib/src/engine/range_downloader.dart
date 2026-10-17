// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's RangeDownloader.swift.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../shared/byte_range.dart';
import 'attempt.dart';
import 'cancel.dart';
import 'connection_pool.dart';
import 'hurry_placement.dart';
import 'piece_downloader.dart';
import 'primary_assigner.dart';
import 'resolver.dart';
import 'transport.dart';

/// Port of RangeDownloader.swift.
final class RangeDownloader {
  RangeDownloader(this.ctx) : pieces = PieceDownloader(ctx);

  final EngineContext ctx;
  final PieceDownloader pieces;
  final assigner = PrimaryAssigner();

  /// BTR `downloadStartupRange`: init and index in one request, raced over up to three nodes
  /// started 0, 120 and 300 ms apart; rounds as for pieces.
  Future<AttemptOutput> meta(ByteRange range, Resolver resolver, {CancelToken? cancel}) async {
    final started = ctx.clock.nowMs();
    Object lastError = const RipperError(RipperErrorKind.noNodes);
    for (var round = 0; round < ctx.config.pieceRounds; round++) {
      if (round > 0 && !await ctx.pauseBeforeRound(round, startedAt: started, cancel: cancel)) break;
      var candidates = resolver.startupCandidates().take(3).toList();
      if (candidates.isEmpty && round > 0) candidates = resolver.ordered(pieceIndex: round).take(3).toList();
      if (candidates.isEmpty) break;
      try {
        return await _firstOf(candidates, range, resolver, cancel);
      } catch (error) {
        if (cancel?.isCancelled ?? false) throw const CancelledException();
        lastError = error;
      }
    }
    throw lastError;
  }

  Future<AttemptOutput> _firstOf(List<String> candidates, ByteRange range, Resolver resolver, CancelToken? cancel) {
    const delays = [0.0, 120.0, 300.0];
    final race = CancelToken(cancel);
    final result = Completer<AttemptOutput>();
    var pending = candidates.length;
    Object lastError = const RipperError(RipperErrorKind.noNodes);

    Future<void> runOne(int index) async {
      try {
        await cancellableSleep(delays[index], race);
        final output = await pieces.runner.runAt(candidates[index],
            piece: range,
            progress: AttemptProgress(),
            resolver: resolver,
            priority: 220,
            queueClass: QueueClass.critical,
            cancel: race);
        if (!result.isCompleted) {
          result.complete(output);
          race.cancel();
        }
      } catch (error) {
        if (error is! CancelledException) lastError = error;
      } finally {
        pending -= 1;
        if (pending == 0 && !result.isCompleted) result.completeError(lastError);
      }
    }

    for (var index = 0; index < candidates.length; index++) {
      unawaited(runOne(index));
    }
    return result.future.whenComplete(race.dispose);
  }

  /// The bytes of [range] in file order, each piece handed to [emit] as soon as it and all before it are in.
  /// Every piece's advertised file size must equal [expectedTotal] (when given) and each other's; a piece that
  /// disagrees fails the range before any of its bytes are emitted. [hurry] says whether playback is about to
  /// need this range: it is read once here, to size and place the pieces, and again by each piece while it
  /// waits to send another copy.
  Future<void> stream(
    ByteRange range,
    Resolver resolver, {
    required bool startup,
    required double priority,
    required void Function(Uint8List bytes) emit,
    int? expectedTotal,
    bool Function()? hurry,
    CancelToken? cancel,
  }) async {
    final hurryCheck = ctx.config.hurry ? hurry : null;
    final hurried = hurryCheck?.call() ?? false;
    var knownTotal = expectedTotal;
    void check(AttemptOutput output) {
      final total = output.total;
      if (total == null) return;
      if (knownTotal != null && knownTotal != total) throw const RipperError(RipperErrorKind.totalMismatch);
      knownTotal = total;
    }

    var preferred = resolver.rangeCandidates();
    var assignable = preferred;
    var remaining = range;
    var indexOffset = 0;
    // In a hurry with nodes already measured, placement by expected finish takes the place of the race.
    if (startup && !(hurried && preferred.any(ctx.nodes.isKnown))) {
      // A small head piece raced over every candidate measures the nodes and gets the first bytes
      // to the player fast; the rest is then spread over the nodes that proved themselves.
      final headLength = min(range.length, max(64 * 1024, ctx.config.minChunkBytes));
      final head = ByteRange(range.start, range.start + headLength - 1);
      final result = await pieces.download(
        piece: head,
        index: 0,
        resolver: resolver,
        preferred: preferred,
        mode: PieceMode.probe,
        priority: 220,
        hurry: hurryCheck,
        cancel: cancel,
      );
      check(result);
      emit(result.bytes);
      if (head.end >= range.end) return;
      remaining = ByteRange(head.end + 1, range.end);
      preferred = [result.url, ...preferred.where((url) => url != result.url)];
      assignable = preferred.where((url) => url == result.url || resolver.speed(url) > 0).toList();
      indexOffset = 1;
    }
    final concurrency = ctx.pool.limit;
    final rescueReserve = concurrency >= 8 ? min(8, max(1, (concurrency + 7) ~/ 8)) : 0;
    final pieceConcurrency = max(1, concurrency - rescueReserve);
    // In a hurry many small requests get through best: right after a seek a node can be slow over a part
    // of the file it has not served lately, and a small piece is cheap to copy elsewhere (BTR PR 11).
    final minChunk = hurried
        ? ctx.config.minChunkBytes
        : ctx.meter.adaptiveMinChunk(
            base: ctx.config.minChunkBytes,
            rangeLength: remaining.length,
            pieceLimit: pieceConcurrency,
            hostCount: preferred.length);
    final parts = remaining.split(concurrency: pieceConcurrency, minChunk: minChunk);
    final primaries = hurried
        ? HurryPlacement.assign(
            urls: preferred,
            count: parts.length,
            pieceBytes: parts.first.length,
            nodes: ctx.nodes,
            delivered: (url) => resolver.bans?.hasDelivered(url) ?? true)
        : assigner.assign(
            urls: assignable,
            count: parts.length,
            speed: resolver.speed,
            trialKey: resolver,
            isFull: (url, placed) => ctx.nodes.isFull(url, extraInflight: placed));
    final mode = startup ? PieceMode.startup : PieceMode.normal;
    final order = preferred;

    final local = CancelToken(cancel);
    final done = Completer<void>();
    final ready = <int, AttemptOutput>{};
    var next = 0;

    Future<void> runPiece(int offset) async {
      final primary = offset < primaries.length ? primaries[offset] : order.firstOrNull;
      final piecePreferred = primary == null ? order : [primary, ...order.where((url) => url != primary)];
      final pieceIndex = offset + indexOffset;
      final piecePriority = startup ? 120.0 - min(30, pieceIndex) : priority - min(20, pieceIndex);
      try {
        final output = await pieces.download(
          piece: parts[offset],
          index: pieceIndex,
          resolver: resolver,
          preferred: piecePreferred,
          mode: mode,
          priority: piecePriority,
          hurry: hurryCheck,
          cancel: local,
        );
        if (done.isCompleted) return;
        check(output);
        ready[offset] = output;
        while (ready.containsKey(next)) {
          emit(ready.remove(next)!.bytes);
          next += 1;
        }
        if (next == parts.length) done.complete();
      } catch (error, stack) {
        if (done.isCompleted) return;
        done.completeError(error, stack);
        local.cancel();
      }
    }

    for (var offset = 0; offset < parts.length; offset++) {
      unawaited(runPiece(offset));
    }
    try {
      await done.future;
    } finally {
      local.dispose();
    }
  }
}
