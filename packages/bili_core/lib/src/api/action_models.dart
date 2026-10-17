import 'json.dart';

final class VideoRelation {
  const VideoRelation({
    required this.like,
    required this.dislike,
    required this.favorite,
    required this.attention,
    required this.coins,
  });

  factory VideoRelation.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return VideoRelation(
      like: object.flag('like'),
      dislike: object.flag('dislike'),
      favorite: object.flag('favorite'),
      attention: object.flag('attention'),
      coins: object.count('coin'),
    );
  }

  final bool like;
  final bool dislike;
  final bool favorite;
  final bool attention;

  /// Coins this account has given the video, 0 to 2.
  final int coins;

  @override
  bool operator ==(Object other) =>
      other is VideoRelation &&
      other.like == like &&
      other.dislike == dislike &&
      other.favorite == favorite &&
      other.attention == attention &&
      other.coins == coins;

  @override
  int get hashCode => Object.hash(like, dislike, favorite, attention, coins);

  @override
  String toString() => 'VideoRelation(like: $like, dislike: $dislike, favorite: $favorite, attention: $attention, '
      'coins: $coins)';
}

final class UploaderCard {
  const UploaderCard({
    required this.mid,
    required this.name,
    required this.face,
    required this.fans,
    required this.videos,
    required this.isVip,
    required this.following,
  });

  factory UploaderCard.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final card = object.nested('card');
    if (card == null) throw const DecodeError('missing card');
    return UploaderCard(
      // The card spells mid as a string.
      mid: card.count('mid'),
      name: card.string('name') ?? '',
      face: card.string('face') ?? '',
      fans: object.count('follower'),
      videos: object.count('archive_count'),
      isVip: attempt(() => card.nested('vip')?.integer('status', 'vipStatus')) == 1,
      following: object.flag('following'),
    );
  }

  final int mid;
  final String name;
  final String face;
  final int fans;
  final int videos;
  final bool isVip;
  final bool following;

  @override
  bool operator ==(Object other) =>
      other is UploaderCard &&
      other.mid == mid &&
      other.name == name &&
      other.face == face &&
      other.fans == fans &&
      other.videos == videos &&
      other.isVip == isVip &&
      other.following == following;

  @override
  int get hashCode => Object.hash(mid, name, face, fans, videos, isVip, following);
}

final class TripleResult {
  const TripleResult({required this.like, required this.coin, required this.favorite, required this.multiply});

  factory TripleResult.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return TripleResult(
      like: object.flag('like'),
      coin: object.flag('coin'),
      favorite: object.flag('fav', 'favorite'),
      multiply: object.count('multiply'),
    );
  }

  final bool like;
  final bool coin;
  final bool favorite;

  /// Coins spent, 0 when the account had none to give.
  final int multiply;

  @override
  bool operator ==(Object other) =>
      other is TripleResult &&
      other.like == like &&
      other.coin == coin &&
      other.favorite == favorite &&
      other.multiply == multiply;

  @override
  int get hashCode => Object.hash(like, coin, favorite, multiply);
}

final class FavFolder {
  const FavFolder({
    required this.id,
    required this.title,
    required this.count,
    required this.isPrivate,
    required this.contains,
    required this.isDefault,
  });

  factory FavFolder.fromJson(Object? json) {
    final object = JsonObject.from(json);
    // attr bit 0 marks a private folder; bit 1 is clear on the account's default folder.
    final attr = object.count('attr');
    return FavFolder(
      id: object.required(object.integer('id'), 'id'),
      title: object.string('title') ?? '',
      count: object.count('media_count'),
      isPrivate: attr & 1 == 1,
      contains: object.flag('fav_state'),
      isDefault: attr & 2 == 0,
    );
  }

  final int id;
  final String title;
  final int count;
  final bool isPrivate;

  /// Whether the video the list was asked about is already in this folder.
  final bool contains;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is FavFolder &&
      other.id == id &&
      other.title == title &&
      other.count == count &&
      other.isPrivate == isPrivate &&
      other.contains == contains &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(id, title, count, isPrivate, contains, isDefault);

  @override
  String toString() =>
      'FavFolder($id, $title, count: $count, private: $isPrivate, contains: $contains, default: $isDefault)';
}

enum VideoTagKind { normal, topic, bgm }

final class VideoTag {
  const VideoTag({required this.id, required this.name, required this.kind});

  factory VideoTag.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return VideoTag(
      id: object.integer('tag_id') ?? 0,
      name: object.required(object.string('tag_name'), 'tag_name'),
      kind: switch (object.string('tag_type')) {
        'topic' => VideoTagKind.topic,
        'bgm' => VideoTagKind.bgm,
        _ => VideoTagKind.normal,
      },
    );
  }

  final int id;
  final String name;
  final VideoTagKind kind;

  @override
  bool operator ==(Object other) => other is VideoTag && other.id == id && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, kind);

  @override
  String toString() => 'VideoTag($id, $name, $kind)';
}
