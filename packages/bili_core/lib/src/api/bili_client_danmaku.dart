part of 'bili_client.dart';

final class DanmakuDraft {
  const DanmakuDraft({
    required this.cid,
    required this.bvid,
    required this.text,
    required this.mode,
    required this.fontSize,
    required this.color,
    required this.gradient,
    required this.progressMs,
  });

  final int cid;
  final String bvid;
  final String text;
  final int mode;
  final int fontSize;

  /// 0xRRGGBB.
  final int color;

  /// The 大会员 gradient colour; the server refuses it for other accounts.
  final bool gradient;
  final int progressMs;
}

/// A danmaku's 👍 count, and whether this account gave one.
typedef DanmakuLikeStat = ({int likes, bool liked});

typedef _BlockRuleItem = ({int id, int? type, String? filter});

_BlockRuleItem _blockRuleItem(Object? json) {
  final object = JsonObject.from(json);
  return (
    id: object.required(object.integer('id'), 'id'),
    type: object.integer('type'),
    filter: object.string('filter'),
  );
}

BlockRule? _ruleOf(_BlockRuleItem item) {
  final type = item.type;
  final kind = type == null ? null : BlockRuleKind.fromRawValue(type);
  final filter = item.filter;
  if (kind == null || filter == null) return null;
  return BlockRule(id: item.id, kind: kind, filter: filter);
}

final _contentRangeStart = RegExp(r'^bytes\s+(\d+)-');

extension BiliClientDanmaku on BiliClient {
  /// Bytes [start] to [end] (inclusive; null runs to the end of the file) of a 人像防挡 mask file (DanmakuMaskInfo.url),
  /// by a Range request; only Bilibili's CDN hosts are asked. A whole file answered with 200 is cut to the range.
  /// The address is signed, so the log and errors carry its host and the status at most.
  Future<Uint8List> maskRange(Uri url, {required int start, int? end}) async {
    if (start < 0 || (end != null && end < start)) throw RangeError('mask range $start-${end ?? ''}');
    if (!DanmakuMaskInfo.isMaskUrl(url)) throw BiliError.invalidLink;
    final watch = Stopwatch()..start();
    final response = await _sendOver(
      HTTPRequest(url: url, headers: {...BiliClient.mediaHeaders, 'Range': 'bytes=$start-${end ?? ''}'}),
      'mask range',
    );
    final status = response.status;
    final body = response.body;
    final fields = {'host': url.host, 'status': status, 'bytes': body.length, 'ms': watch.elapsedMilliseconds};
    if (status != 200 && status != 206) {
      _logger.warn(LogCategory.api, 'mask range', fields);
      throw BiliError.http(status);
    }
    _logger.info(LogCategory.api, 'mask range', fields);
    final int from;
    if (status == 206) {
      final answered = _contentRangeStart.firstMatch(response.headers['content-range'] ?? '')?[1];
      if (answered != null && int.tryParse(answered) != start) {
        throw BiliError.decoding('mask range: answered from $answered, asked $start');
      }
      from = 0;
    } else {
      if (start >= body.length) throw BiliError.decoding('mask range: $start is past the end (${body.length})');
      from = start;
    }
    final to = end == null ? body.length : from + end - start + 1;
    if (from == 0 && to >= body.length) return body;
    // A copy, so a whole file answered with 200 isn't kept alive by the slice.
    return body.sublist(from, to < body.length ? to : body.length);
  }

  /// One 6-minute slice of a video's danmaku, `index` counting from 1.
  Future<DanmakuSegment> danmakuSegment({required int cid, required int index}) async => decodeDanmakuSegment(
    await danmakuSegmentData(cid: cid, index: index),
    index: index,
  );

  /// The segment's protobuf bytes, for a caller that decodes them off its own isolate.
  Future<Uint8List> danmakuSegmentData({required int cid, required int index}) async {
    final query = {'type': '1', 'oid': '$cid', 'segment_index': '$index'};
    try {
      return await getData('/x/v2/dm/web/seg.so', query: query, signed: false);
    } on BiliHTTPError catch (error) {
      if (error.status != 403 && error.status != 412) rethrow;
      // Risk control sometimes refuses the plain endpoint while the signed twin still answers.
      return getData('/x/v2/dm/wbi/web/seg.so', query: query, signed: true);
    }
  }

  static DanmakuSegment decodeDanmakuSegment(Uint8List data, {required int index}) {
    try {
      return DanmakuSegment.decode(data);
    } on Object catch (error) {
      throw BiliError.decoding('danmaku segment $index: $error');
    }
  }

  Future<List<BlockRule>> danmakuBlockRules() => get(
    '/x/dm/filter/user',
    signed: false,
    decode: (json) => [for (final item in JsonObject.from(json).lossyList('rule', _blockRuleItem)) ?_ruleOf(item)],
  );

  Future<BlockRule> addBlockRule(BlockRuleKind kind, {required String filter}) async {
    final added = await post(
      '/x/dm/filter/user/add',
      form: {'type': '${kind.rawValue}', 'filter': filter},
      decode: _blockRuleItem,
    );
    return _ruleOf(added) ?? BlockRule(id: added.id, kind: kind, filter: filter);
  }

  Future<void> deleteBlockRule({required int id}) => postVoid('/x/dm/filter/user/del', form: {'ids': '$id'});

  /// 当前弹幕列表's 👍: on, or taken back.
  Future<void> likeDanmaku({required int cid, required int dmid, required bool on}) async {
    try {
      await postVoid(
        '/x/v2/dm/thumbup/add',
        form: {'op': on ? '1' : '2', 'dmid': '$dmid', 'oid': '$cid', 'platform': 'web_player'},
      );
    } on BiliAPIError catch (error) {
      // 65006 already liked, 65004 never liked: the server is where the tap wanted it.
      if (error.code != (on ? 65006 : 65004)) rethrow;
    }
  }

  /// The 👍 counts of [dmids], keyed by danmaku id; an id the server doesn't answer for is left out.
  Future<Map<int, DanmakuLikeStat>> danmakuLikes({required int cid, required List<int> dmids}) async {
    if (dmids.isEmpty) return {};
    final stats = await _getIfPresent(
      '/x/v2/dm/thumbup/stats',
      query: {'oid': '$cid', 'ids': dmids.join(',')},
      signed: false,
      decode: (json) => JsonObject.from(json).map,
    );
    return {
      for (final MapEntry(:key, :value) in (stats ?? const {}).entries)
        if ((int.tryParse(key), value) case (final int id, final Map<String, Object?> stat))
          id: (likes: JsonObject(stat).count('likes'), liked: JsonObject(stat).flag('user_like')),
    };
  }

  /// Returns the new danmaku's id, or 0 when the server accepted it without one.
  Future<int> postDanmaku(DanmakuDraft draft) {
    final form = {
      'type': '1',
      'oid': '${draft.cid}',
      'bvid': draft.bvid,
      'msg': draft.text,
      'mode': '${draft.mode}',
      'fontsize': '${draft.fontSize}',
      'color': '${draft.color}',
      'progress': '${draft.progressMs}',
      'rnd': '${now().microsecondsSinceEpoch}',
      'pool': '0',
    };
    if (draft.gradient) form['colorful'] = '60001';
    return post(
      '/x/v2/dm/post',
      form: form,
      referer: 'https://www.bilibili.com/video/${draft.bvid}',
      decode: (json) => JsonObject.from(json).integer('dmid') ?? 0,
    );
  }
}
