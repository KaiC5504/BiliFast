import 'byte_range.dart';

final class MediaSegment {
  const MediaSegment({required this.index, required this.range, required this.startTime, required this.duration});

  final int index;
  final ByteRange range;

  /// Seconds from the start of the presentation.
  final double startTime;
  final double duration;

  double get endTime => startTime + duration;

  @override
  bool operator ==(Object other) =>
      other is MediaSegment &&
      other.index == index &&
      other.range == range &&
      other.startTime == startTime &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(index, range, startTime, duration);
}
