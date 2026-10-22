import 'json.dart';

/// `/x/web-interface/nav/stat`: 我的's three counts.
final class NavStat {
  const NavStat({required this.following, required this.follower, required this.dynamicCount});

  factory NavStat.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return NavStat(
      following: object.count('following'),
      follower: object.count('follower'),
      dynamicCount: object.count('dynamic_count'),
    );
  }

  /// 关注.
  final int following;

  /// 粉丝.
  final int follower;

  /// 动态.
  final int dynamicCount;

  @override
  bool operator ==(Object other) =>
      other is NavStat &&
      other.following == following &&
      other.follower == follower &&
      other.dynamicCount == dynamicCount;

  @override
  int get hashCode => Object.hash(following, follower, dynamicCount);

  @override
  String toString() => 'NavStat(following: $following, follower: $follower, dynamic: $dynamicCount)';
}
