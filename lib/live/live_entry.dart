import 'package:bili_core/api.dart';

/// What a room opens with before its own calls answer: the card's id, cover and words, drawn at once.
final class LiveRoomEntry {
  const LiveRoomEntry({
    required this.roomId,
    this.uid = 0,
    this.title = '',
    this.cover = '',
    this.anchorName = '',
    this.anchorFace = '',
  });

  factory LiveRoomEntry.fromCard(LiveCard card) => LiveRoomEntry(
    roomId: card.roomId,
    uid: card.uid,
    title: card.title,
    cover: card.cover,
    anchorName: card.uname,
    anchorFace: card.face,
  );

  /// May be a short id; the play info answers the real one.
  final int roomId;
  final int uid;
  final String title;
  final String cover;
  final String anchorName;
  final String anchorFace;
}
