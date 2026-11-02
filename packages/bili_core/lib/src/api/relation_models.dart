/// 我的好友's people and 分组, from the website's relation calls (`/x/relation/…`) with the web login's cookies.
library;

import 'dynamic_models.dart' show DynamicVerify, FollowingUser;
import 'json.dart';

/// A row of 我的好友 (163, 165): the person as 我的关注 draws them, and how the account stands with them.
final class RelationUser {
  const RelationUser({
    required this.user,
    this.attribute = RelationUser.followed,
    this.special = false,
    this.collectibleFace = false,
  });

  /// `attribute`'s values: neither way, 悄悄关注, 关注, 互粉 (128, 拉黑, reads as none).
  static const none = 0;
  static const whisper = 1;
  static const followed = 2;
  static const mutualValue = 6;

  final FollowingUser user;
  final int attribute;

  /// In 特别关注 (`special`).
  final bool special;

  /// The face is a 数字藏品 (`face_nft`), which 163 marks with a ◇ beside the verify bolt.
  final bool collectibleFace;

  int get mid => user.mid;

  /// The account follows them, quietly or not.
  bool get following => attribute == whisper || attribute == followed || attribute == mutualValue;

  /// They follow the account back.
  bool get mutual => attribute == mutualValue;
}

/// A page of [RelationUser]s; [total] is the whole list's size as the call counts it.
final class RelationPage {
  const RelationPage({required this.users, this.total = 0, this.hasMore = false});

  final List<RelationUser> users;
  final int total;
  final bool hasMore;
}

/// A 分组 (`/x/relation/tags`): [special] is 特别关注, [defaultGroup] 默认分组, the rest the account's own.
final class RelationTag {
  const RelationTag({required this.id, required this.name, this.count = 0, this.tip = ''});

  static const special = -10;
  static const defaultGroup = 0;

  final int id;
  final String name;
  final int count;

  /// The line under the name (特别关注's 第一时间收到该分组下用户更新稿件的通知).
  final String tip;
}

/// The decoders, each taking the envelope's `data`.
abstract final class RelationDecode {
  /// `/x/relation/followings`, its search and `/x/relation/fans`. An empty page ends the list whatever `total` says,
  /// so paging can't loop.
  static RelationPage page(Object? json, {required int page, required int pageSize}) {
    final data = JsonObject.from(json, 'relation page');
    final raw = switch (data.map['list']) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    };
    final total = data.count('total');
    return RelationPage(
      users: lossy(raw, _user),
      total: total,
      hasMore: raw.isNotEmpty && (total > 0 ? page * pageSize < total : raw.length >= pageSize),
    );
  }

  static List<RelationTag> tags(Object? json) => json is List ? lossy(json, _tag) : const [];

  /// `/x/relation/tag/user`: the 分组 one person is in, as `{"-10": "特别关注"}`; empty in none but 默认分组.
  static Set<int> tagsOf(Object? json) => {
    if (json is Map<String, Object?>)
      for (final key in json.keys) ?int.tryParse(key),
  };
}

RelationUser _user(Object? json) {
  final user = JsonObject.from(json, 'relation user');
  final mid = _int(user.map['mid']);
  if (mid == null) throw const DecodeError('relation user: missing mid');
  final vip = user.nested('vip');
  return RelationUser(
    user: FollowingUser(
      mid: mid,
      name: user.text('uname') ?? '',
      face: user.text('face') ?? '',
      sign: user.text('sign') ?? '',
      verify: switch (_int(user.nested('official_verify')?.map['type'])) {
        0 => DynamicVerify.personal,
        1 => DynamicVerify.organisation,
        _ => DynamicVerify.none,
      },
      vipPink:
          _int(vip?.map['vipStatus'] ?? vip?.map['status']) == 1 &&
          (_int(vip?.map['vipType'] ?? vip?.map['type']) ?? 0) > 0,
    ),
    attribute: _int(user.map['attribute']) ?? RelationUser.none,
    special: _int(user.map['special']) == 1,
    collectibleFace: _int(user.map['face_nft']) == 1,
  );
}

RelationTag _tag(Object? json) {
  final tag = JsonObject.from(json, 'relation tag');
  final id = _int(tag.map['tagid']);
  if (id == null) throw const DecodeError('relation tag: missing tagid');
  return RelationTag(id: id, name: tag.text('name') ?? '', count: tag.count('count'), tip: tag.text('tip') ?? '');
}

/// Ids come as numbers or as strings of digits, depending on the call.
int? _int(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value.trim()) : null);
