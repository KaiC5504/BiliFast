import 'dart:convert';
import 'dart:typed_data';

import '../api/json.dart';
import '../api/live_models.dart';
import '../danmaku/protobuf_reader.dart';
import 'live_events.dart';

/// The danmaku socket's commands as events. Every reader is lenient about types (the answers mix numbers, strings
/// and JSON in strings); a command missing what it can't do without throws [DecodeError].
abstract final class LiveSocketDecode {
  /// The command's name without its suffix (`DANMU_MSG:4:0:2:2:2:0` is `DANMU_MSG`); empty when there is none.
  static String commandName(Map<String, Object?> json) {
    final cmd = json['cmd'];
    if (cmd is! String) return '';
    final colon = cmd.indexOf(':');
    return colon < 0 ? cmd : cmd.substring(0, colon);
  }

  /// The event [json] carries, or null for a command the room doesn't use (or a kind of one it doesn't draw).
  static LiveEvent? command(Map<String, Object?> json, {DateTime Function() now = DateTime.now}) {
    final data = _map(json['data']);
    return switch (commandName(json)) {
      'DANMU_MSG' => LiveDanmakuEvent(danmaku(json, now: now)),
      'SUPER_CHAT_MESSAGE' => LiveSuperChatEvent(superChat(_need(data, 'data'))),
      'SUPER_CHAT_MESSAGE_DELETE' => LiveSuperChatDeletedEvent([
        for (final id in _list(_need(data, 'data')['ids']) ?? const <Object?>[])
          if (_int(id) case final int value) value,
      ]),
      'WATCHED_CHANGE' => LiveWatchedEvent(_str(_need(data, 'data')['text_large']) ?? (throw _missing('text_large'))),
      'ONLINE_RANK_COUNT' => LiveOnlineCountEvent(
        _int(_need(data, 'data')['count']) ?? _int(data!['online_count']) ?? (throw _missing('count')),
      ),
      'ONLINE_RANK_V2' || 'ONLINE_RANK_TOP3' => _topFaces(_need(data, 'data')),
      'LIKE_INFO_V3_UPDATE' => LiveLikeCountEvent(
        _int(_need(data, 'data')['click_count']) ?? (throw _missing('click_count')),
      ),
      'LIKE_INFO_V3_CLICK' => LiveInteractEvent(LiveInteraction.liked, _interactUser(_need(data, 'data'))),
      'INTERACT_WORD' => _interact(_need(data, 'data')),
      'INTERACT_WORD_V2' => _interactV2(_need(data, 'data')),
      'ROOM_CHANGE' => LiveRoomChangedEvent(
        title: _str(_need(data, 'data')['title']) ?? (throw _missing('title')),
        areaName: _str(data!['area_name']) ?? '',
      ),
      'LIVE' => const LiveStatusEvent(live: true),
      'PREPARING' => const LiveStatusEvent(live: false),
      _ => null,
    };
  }

  /// `DANMU_MSG`: `info[0]` the danmaku (mode 1, colour 3, time 4, the whole-message emote 13, the sender and extra
  /// JSON 15), `info[1]` the text, `info[2]` the sender, `info[3]` the medal, `info[7]` the guard level, `info[9].ts`,
  /// `info[16][0]` the wealth level. The newer `info[0][15].user` wins where it is given.
  static LiveChatMessage danmaku(Map<String, Object?> json, {DateTime Function() now = DateTime.now}) {
    final info = _list(json['info']) ?? (throw _missing('info'));
    final text = _str(_at(info, 1)) ?? (throw _missing('info[1]'));
    final head = _list(_at(info, 0)) ?? const <Object?>[];
    final more = _map(_at(head, 15));
    final user = _map(more?['user']);
    final base = _map(user?['base']);
    final extra = _jsonMap(more?['extra']);
    final sender = _list(_at(info, 2)) ?? const <Object?>[];

    final uid = _int(user?['uid']) ?? _int(_at(sender, 0)) ?? 0;
    final medal = _medalArray(_list(_at(info, 3))) ?? _medal(_map(user?['medal']));
    final guard = _positive(_int(_at(info, 7))) ?? _int(_map(user?['guard'])?['level']) ?? medal?.guardLevel ?? 0;
    final liveUser = LiveUser(
      uid: uid,
      name: _nonEmpty(_str(base?['name'])) ?? _str(_at(sender, 1)) ?? '',
      face: _str(base?['face']) ?? '',
      medal: medal,
      wealthLevel:
          _positive(_int(_at(_list(_at(info, 16)) ?? const [], 0))) ?? _int(_map(user?['wealth'])?['level']) ?? 0,
      guardLevel: guard,
      nameColor: _color(base?['name_color_str']) ?? _color(_at(sender, 7)) ?? 0,
    );

    final emotes = <String, LiveEmote>{};
    for (final MapEntry(:key, :value) in (_map(extra?['emots']) ?? const <String, Object?>{}).entries) {
      if (_emote(_map(value), key) case final LiveEmote emote) emotes[key] = emote;
    }
    final bigEmote = _emote(_jsonMap(_at(head, 13)), text);

    final timeMs = _int(_at(head, 4));
    final ts = _int(_map(_at(info, 9))?['ts']);
    final time = timeMs != null && timeMs > 1000000000000
        ? DateTime.fromMillisecondsSinceEpoch(timeMs)
        : ts != null && ts > 0
        ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
        : now();

    final mode = _int(_at(head, 1));
    final color = _int(_at(head, 3));
    return LiveChatMessage(
      id: _nonEmpty(_str(extra?['id_str'])) ?? '$uid:${time.millisecondsSinceEpoch}:${text.hashCode}',
      user: liveUser,
      text: text,
      time: time,
      emotes: emotes,
      bigEmote: bigEmote,
      color: color == null ? 0xFFFFFFFF : _argb(color),
      mode: mode == 4 || mode == 5 ? mode! : 1,
      replyTo: _str(extra?['reply_uname']) ?? '',
    );
  }

  /// `SUPER_CHAT_MESSAGE`'s data: the same shape as the room's 醒目留言 list, read by its decoder.
  static LiveSuperChat superChat(Map<String, Object?> data) => LiveDecode.superChat(data);

  static LiveEvent? _topFaces(Map<String, Object?> data) {
    final rows = [
      for (final row in _list(data['list']) ?? const <Object?>[])
        if (_map(row) case final Map<String, Object?> map) map,
    ];
    rows.sort((a, b) => (_int(a['rank']) ?? 1 << 30).compareTo(_int(b['rank']) ?? 1 << 30));
    final faces = [
      for (final row in rows)
        if (_nonEmpty(_str(row['face'])) ?? _nonEmpty(_str(_map(_map(row['uinfo'])?['base'])?['face']))
            case final String face)
          face,
    ];
    // ONLINE_RANK_TOP3 is often only words (msg, rank) with no face: nothing to draw then.
    return faces.isEmpty ? null : LiveTopFacesEvent(faces.take(3).toList());
  }

  static LiveEvent? _interact(Map<String, Object?> data) {
    final kind = _interaction(_int(data['msg_type']));
    return kind == null ? null : LiveInteractEvent(kind, _interactUser(data));
  }

  static LiveUser _interactUser(Map<String, Object?> data) {
    final medal = _medal(_map(data['fans_medal']));
    return LiveUser(
      uid: _int(data['uid']) ?? 0,
      name: _str(data['uname']) ?? '',
      face: _str(_map(_map(data['uinfo'])?['base'])?['face']) ?? '',
      medal: medal,
      guardLevel: medal?.guardLevel ?? 0,
      nameColor: _color(data['uname_color']) ?? 0,
    );
  }

  /// `INTERACT_WORD_V2`'s `pb`: base64 protobuf. Field numbers as the community decodes it (no schema from
  /// Bilibili): 1 uid, 2 uname, 5 msg_type, 22 uinfo → 2 base → 2 face.
  static LiveEvent? _interactV2(Map<String, Object?> data) {
    final pb = _str(data['pb']) ?? (throw _missing('pb'));
    final Uint8List bytes;
    try {
      bytes = base64.decode(base64.normalize(pb));
    } on FormatException {
      throw const DecodeError('pb: not base64');
    }
    var uid = 0;
    var name = '';
    var face = '';
    int? type;
    try {
      final reader = ProtobufReader(bytes);
      for (var tag = reader.next(); tag != null; tag = reader.next()) {
        switch ((tag.field, tag.wireType)) {
          case (1, 0):
            uid = reader.varint();
          case (2, 2):
            name = utf8.decode(reader.lengthDelimited(), allowMalformed: true);
          case (5, 0):
            type = reader.varint();
          case (22, 2):
            face = _protoString(_protoField(reader.lengthDelimited(), 2), 2) ?? face;
          default:
            reader.skip(tag.wireType);
        }
      }
    } on ProtobufError catch (error) {
      throw DecodeError('pb: $error');
    }
    final kind = _interaction(type);
    if (kind == null) return null;
    return LiveInteractEvent(kind, LiveUser(uid: uid, name: name, face: face));
  }

  static LiveInteraction? _interaction(int? type) => switch (type) {
    1 => LiveInteraction.entered,
    2 => LiveInteraction.followed,
    3 => LiveInteraction.shared,
    _ => null,
  };

  /// The bytes of length-delimited field [number] in [message], the last one when repeated.
  static Uint8List? _protoField(Uint8List message, int number) {
    Uint8List? found;
    final reader = ProtobufReader(message);
    for (var tag = reader.next(); tag != null; tag = reader.next()) {
      if (tag.field == number && tag.wireType == 2) {
        found = reader.lengthDelimited();
      } else {
        reader.skip(tag.wireType);
      }
    }
    return found;
  }

  static String? _protoString(Uint8List? message, int number) {
    if (message == null) return null;
    final bytes = _protoField(message, number);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// `info[3]`: level, name, anchor name, room, colour, '', 0, border, start, end, guard level, lit, anchor uid.
  static LiveMedal? _medalArray(List<Object?>? array) {
    if (array == null || array.length < 2) return null;
    final name = _str(array[1]);
    if (name == null || name.isEmpty) return null;
    final color = _int(_at(array, 4));
    final lit = _int(_at(array, 11));
    return LiveMedal(
      name: name,
      level: _int(array[0]) ?? 0,
      colorStart: _rgbOrZero(_int(_at(array, 8)) ?? color),
      colorEnd: _rgbOrZero(_int(_at(array, 9)) ?? color),
      border: _rgbOrZero(_int(_at(array, 7))),
      guardLevel: _int(_at(array, 10)) ?? 0,
      lit: lit == null || lit != 0,
    );
  }

  /// A medal object in any of its spellings: the user's `medal` (name, level, color_start…), `fans_medal` and
  /// `medal_info` (medal_name, medal_level, medal_color_start…).
  static LiveMedal? _medal(Map<String, Object?>? map) {
    if (map == null) return null;
    final name = _nonEmpty(_str(map['name'])) ?? _nonEmpty(_str(map['medal_name']));
    if (name == null) return null;
    final level = _int(map['level']) ?? _int(map['medal_level']) ?? 0;
    final lit = _int(map['is_light']) ?? _int(map['is_lighted']);
    final color = _color(map['medal_color']);
    return LiveMedal(
      name: name,
      level: level,
      colorStart: _color(map['color_start']) ?? _color(map['medal_color_start']) ?? color ?? 0,
      colorEnd: _color(map['color_end']) ?? _color(map['medal_color_end']) ?? color ?? 0,
      border: _color(map['color_border']) ?? _color(map['medal_color_border']) ?? 0,
      guardLevel: _int(map['guard_level']) ?? 0,
      lit: lit == null || lit != 0,
    );
  }

  static LiveEmote? _emote(Map<String, Object?>? map, String text) {
    final url = _nonEmpty(_str(map?['url']));
    if (map == null || url == null) return null;
    final width = _int(map['width']) ?? 0;
    return LiveEmote(
      text: text,
      url: url,
      unique: _str(map['emoticon_unique']) ?? '',
      width: width,
      height: _int(map['height']) ?? width,
    );
  }

  static DecodeError _missing(String what) => DecodeError('missing $what');

  static Map<String, Object?> _need(Map<String, Object?>? map, String what) => map ?? (throw _missing(what));

  static Object? _at(List<Object?> list, int index) => index < list.length ? list[index] : null;

  static Map<String, Object?>? _map(Object? value) => value is Map<String, Object?> ? value : null;

  static List<Object?>? _list(Object? value) => value is List<Object?> ? value : null;

  static String? _str(Object? value) => value is String ? value : null;

  static String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

  static int? _positive(int? value) => value != null && value > 0 ? value : null;

  /// A number, or a number written as a string ("123", as some ids come).
  static int? _int(Object? value) => value is String ? int.tryParse(value) : asInt(value);

  /// An object, or one written as a JSON string (`extra`, `info[0][13]`); null when neither.
  static Map<String, Object?>? _jsonMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is! String || !value.startsWith('{')) return null;
    try {
      return _map(jsonDecode(value));
    } on FormatException {
      return null;
    }
  }

  /// A colour as ARGB from an RGB number or `#RRGGBB` / `#RRGGBBAA`; null for none, empty or unreadable.
  static int? _color(Object? value) {
    if (value is String) {
      final hex = value.startsWith('#') ? value.substring(1) : value;
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed == null || hex.isEmpty) return null;
      return switch (hex.length) {
        6 => _argb(parsed),
        8 => (parsed & 0xFF) << 24 | parsed >>> 8,
        _ => null,
      };
    }
    final number = asInt(value);
    return number == null || number == 0 ? null : _argb(number);
  }

  static int _rgbOrZero(int? rgb) => rgb == null || rgb == 0 ? 0 : _argb(rgb);

  static int _argb(int rgb) => 0xFF000000 | (rgb & 0xFFFFFF);
}
