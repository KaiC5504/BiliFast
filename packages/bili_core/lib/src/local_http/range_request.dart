import 'dart:math';

import '../shared/byte_range.dart';
import 'text.dart';

sealed class RangeRequest {
  const RangeRequest();

  const factory RangeRequest.full() = RangeFull;
  const factory RangeRequest.range(ByteRange range) = RangePartial;
  const factory RangeRequest.unsatisfiable() = RangeUnsatisfiable;

  /// Single ranges only: "a-b", "a-" and the suffix form "-n". An end past the file is clamped.
  static RangeRequest parse(String? header, {required int totalSize}) {
    final value = header == null ? null : trimSpaces(header).toLowerCase();
    if (value == null || value.isEmpty) return const RangeFull();
    if (!value.startsWith('bytes=') || totalSize <= 0) return const RangeUnsatisfiable();
    final spec = value.substring(6);
    if (spec.contains(',')) return const RangeUnsatisfiable();
    final dash = spec.indexOf('-');
    if (dash < 0) return const RangeUnsatisfiable();
    final first = trimSpaces(spec.substring(0, dash));
    final second = trimSpaces(spec.substring(dash + 1));
    final int start;
    final int end;
    if (first.isEmpty) {
      final suffix = parseInt64(second);
      if (suffix == null || suffix <= 0) return const RangeUnsatisfiable();
      start = max(0, totalSize - suffix);
      end = totalSize - 1;
    } else {
      final parsedStart = parseInt64(first);
      if (parsedStart == null) return const RangeUnsatisfiable();
      start = parsedStart;
      if (second.isEmpty) {
        end = totalSize - 1;
      } else {
        final last = parseInt64(second);
        if (last == null) return const RangeUnsatisfiable();
        end = min(last, totalSize - 1);
      }
    }
    final range = ByteRange.of(start, end);
    if (start >= totalSize || range == null) return const RangeUnsatisfiable();
    return RangePartial(range);
  }
}

final class RangeFull extends RangeRequest {
  const RangeFull();

  @override
  bool operator ==(Object other) => other is RangeFull;

  @override
  int get hashCode => (RangeFull).hashCode;

  @override
  String toString() => 'RangeRequest.full';
}

final class RangePartial extends RangeRequest {
  const RangePartial(this.range);

  final ByteRange range;

  @override
  bool operator ==(Object other) => other is RangePartial && other.range == range;

  @override
  int get hashCode => range.hashCode;

  @override
  String toString() => 'RangeRequest.range($range)';
}

final class RangeUnsatisfiable extends RangeRequest {
  const RangeUnsatisfiable();

  @override
  bool operator ==(Object other) => other is RangeUnsatisfiable;

  @override
  int get hashCode => (RangeUnsatisfiable).hashCode;

  @override
  String toString() => 'RangeRequest.unsatisfiable';
}
