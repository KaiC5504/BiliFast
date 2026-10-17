import 'package:bili_core/api.dart';

/// Codec kinds the player refused on this phone, so they are not tried first again (port of CodecMemory.swift).
/// Kept in memory until settings storage arrives; the Swift app keeps it in `playback.failedCodecs`.
final class CodecMemory {
  static const fallbackOrder = [VideoCodec.hevc, VideoCodec.av1, VideoCodec.avc];

  final Set<String> _failed = {};
  bool _hev1LabelsHoldHEV1 = false;

  Set<String> get failedKinds => Set.unmodifiable(_failed);

  List<VideoCodec> order({required VideoCodec preferred}) => [
        preferred,
        ...fallbackOrder.where((codec) => codec != preferred),
      ].where((codec) => !_failed.contains(codec.name)).toList();

  void markFailed(String kind) => _failed.add(kind);

  /// Set once a stream labelled hev1 held a real hev1 sample entry. Direct mode cannot rename one, so it then
  /// skips hev1 labels before fetching anything; until then it reads the bytes, which can be hvc1.
  bool get hev1LabelsHoldHEV1 => _hev1LabelsHoldHEV1;

  void noteHEV1Entry() => _hev1LabelsHoldHEV1 = true;

  void reset() {
    _failed.clear();
    _hev1LabelsHoldHEV1 = false;
  }
}
