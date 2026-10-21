part of 'bili_client.dart';

/// The video page's 点赞, 投币 and 不喜欢 on the official app's calls, which carry the app token.
extension BiliClientActionsOfficial on BiliClient {
  Future<void> officialLike({required int aid, required bool on}) =>
      _officialPostVoid('/x/v2/view/like', {'aid': '$aid', 'like': on ? '0' : '1'});

  Future<void> officialCoin({required int aid, required int multiply, required bool alsoLike}) => _officialPostVoid(
    '/x/v2/view/coin/add',
    {'aid': '$aid', 'multiply': '$multiply', 'select_like': alsoLike ? '1' : '0'},
  );

  /// `on: true` dislikes the video, `on: false` takes it back.
  Future<void> officialDislike({required int aid, required bool on}) =>
      _officialPostVoid('/x/v2/view/dislike', {'aid': '$aid', 'dislike': on ? '0' : '1'});
}
