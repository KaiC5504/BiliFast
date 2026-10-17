part of 'bili_client.dart';

extension BiliClientComments on BiliClient {
  /// `offset` is the previous page's `nextOffset`; null or empty asks for the first page.
  Future<CommentPage> comments({required int aid, required CommentSort sort, String? offset}) async {
    final cursor = offset ?? '';
    final query = {
      'oid': '$aid',
      'type': '1',
      'mode': '${sort.rawValue}',
      'pagination_str': jsonEncode({'offset': cursor}),
    };
    CommentPage page;
    try {
      page = await get('/x/v2/reply/wbi/main', query: query, signed: true, decode: decodeCommentList);
    } on BiliError catch (error) {
      if (!_isRiskControl(error)) rethrow;
      page = await get('/x/v2/reply/main', query: query, signed: false, decode: decodeCommentList);
    }
    return cursor.isEmpty ? page : page.copyWith(pinned: () => null);
  }

  Future<ThreadPage> thread({required int aid, required int root, required int page, CommentSort sort = CommentSort.time}) {
    final query = {
      'oid': '$aid',
      'type': '1',
      'root': '$root',
      'pn': '$page',
      'ps': '20',
      'sort': '${sort.threadSort}',
    };
    return get('/x/v2/reply/reply', query: query, signed: false, decode: decodeCommentThread);
  }

  /// `root` and `parent` stay 0 for a top-level comment; a reply to a reply sets `parent` to that reply.
  Future<Comment> postComment(
      {required int aid, required String message, int root = 0, int parent = 0, bool syncToDynamic = false}) {
    final form = {'oid': '$aid', 'type': '1', 'message': message};
    if (root != 0) form['root'] = '$root';
    if (parent != 0) form['parent'] = '$parent';
    if (syncToDynamic) form['sync_to_dynamic'] = '1';
    return post('/x/v2/reply/add',
        form: form, referer: 'https://www.bilibili.com/video/av$aid', decode: decodePostedComment);
  }

  Future<void> likeComment({required int aid, required int rpid, required bool on}) =>
      postVoid('/x/v2/reply/action', form: _reaction(aid, rpid, on));

  Future<void> hateComment({required int aid, required int rpid, required bool on}) =>
      postVoid('/x/v2/reply/hate', form: _reaction(aid, rpid, on));

  Future<void> deleteComment({required int aid, required int rpid}) =>
      postVoid('/x/v2/reply/del', form: {'oid': '$aid', 'type': '1', 'rpid': '$rpid'});

  Future<List<EmotePackage>> emotePackages() =>
      get('/x/emote/user/panel/web', query: {'business': 'reply'}, signed: false, decode: decodeEmotePanel);

  Map<String, String> _reaction(int aid, int rpid, bool on) =>
      {'oid': '$aid', 'type': '1', 'rpid': '$rpid', 'action': on ? '1' : '0'};

  /// The signed route is the newer one; risk control sometimes refuses it while the plain route still answers.
  static bool _isRiskControl(BiliError error) => switch (error) {
        BiliAPIError(:final code) => code == -352 || code == -403,
        BiliHTTPError(:final status) => status == 412,
        _ => false,
      };
}
