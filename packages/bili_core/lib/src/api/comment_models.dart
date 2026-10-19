import 'json.dart';
import 'rich_text.dart';

String? _nonEmpty(String? text) => text == null || text.isEmpty ? null : text;

extension on JsonObject {
  /// The API mixes true/false and 0/1 for flags, sometimes within one response.
  bool commentFlag(String key) {
    final value = map[key];
    if (value is bool) return value;
    return count(key) != 0;
  }
}

enum CommentSort {
  /// The value is the `mode` of the cursor endpoint; the reply-thread endpoint uses `threadSort` instead.
  hot(3),
  time(2);

  const CommentSort(this.rawValue);

  final int rawValue;

  int get threadSort => this == hot ? 1 : 0;
}

final class CommentMember {
  const CommentMember({
    required this.mid,
    this.name = '',
    this.face = '',
    this.level = 0,
    this.isVip = false,
    this.pendant,
    this.fanCardImage,
    this.fanCardNumber,
    this.fanCardColor,
  });

  factory CommentMember.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final card = object.nested('user_sailing')?.nested('cardbg');
    final fan = card?.nested('fan');
    return CommentMember(
      // The member's own mid is a string here, unlike the number on the comment.
      mid: object.count('mid'),
      name: object.text('uname') ?? '',
      face: object.text('avatar') ?? '',
      level: object.nested('level_info')?.count('current_level') ?? 0,
      isVip: object.nested('vip')?.count('vipStatus') == 1,
      pendant: _nonEmpty(object.nested('pendant')?.text('image')),
      fanCardImage: _nonEmpty(card?.text('image')),
      fanCardNumber: _nonEmpty(fan?.text('num_desc')),
      fanCardColor: _nonEmpty(fan?.text('color')),
    );
  }

  final int mid;
  final String name;
  final String face;
  final int level;
  final bool isVip;
  final String? pendant;
  final String? fanCardImage;
  final String? fanCardNumber;

  /// The number's colour as the server writes it, such as "#f35543".
  final String? fanCardColor;

  @override
  bool operator ==(Object other) =>
      other is CommentMember &&
      other.mid == mid &&
      other.name == name &&
      other.face == face &&
      other.level == level &&
      other.isVip == isVip &&
      other.pendant == pendant &&
      other.fanCardImage == fanCardImage &&
      other.fanCardNumber == fanCardNumber &&
      other.fanCardColor == fanCardColor;

  @override
  int get hashCode => Object.hash(mid, name, face, level, isVip, pendant, fanCardImage, fanCardNumber, fanCardColor);

  @override
  String toString() =>
      'CommentMember($mid, $name, level: $level, vip: $isVip, pendant: $pendant, '
      'fanCard: $fanCardImage $fanCardNumber $fanCardColor)';
}

final class CommentPicture {
  const CommentPicture({required this.url, required this.width, required this.height});

  factory CommentPicture.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final url = object.text('img_src');
    if (url == null || url.isEmpty) throw const DecodeError('missing img_src');
    return CommentPicture(
      url: url,
      width: attempt(() => object.number('img_width')) ?? 0,
      height: attempt(() => object.number('img_height')) ?? 0,
    );
  }

  final String url;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is CommentPicture && other.url == url && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(url, width, height);

  @override
  String toString() => 'CommentPicture($url, $width x $height)';
}

final class Comment {
  /// `runs` defaults to the message as plain text, for fixtures and freshly typed comments.
  Comment({
    required this.rpid,
    this.oid = 0,
    this.mid = 0,
    this.root = 0,
    this.parent = 0,
    this.ctime = 0,
    this.likes = 0,
    this.replyCount = 0,
    this.action = 0,
    required this.member,
    required this.message,
    List<RichRun>? runs,
    this.pictures = const [],
    this.location,
    this.upLiked = false,
    this.isPinned = false,
    this.previewReplies = const [],
  }) : runs = runs ?? (message.isEmpty ? const [] : [RichRun.text(message)]);

  static const _locationPrefix = 'IP属地：';

  factory Comment.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final rpid = object.count('rpid');
    if (rpid == 0) throw const DecodeError('missing rpid');
    final mid = object.count('mid');
    final memberJson = object.map['member'];
    final member =
        (memberJson == null ? null : attempt(() => CommentMember.fromJson(memberJson))) ?? CommentMember(mid: mid);

    var message = '';
    var emotes = <String, EmoteRef>{};
    var mentions = <String, int>{};
    final links = <String, LinkRef>{};
    var pictures = <CommentPicture>[];
    final content = object.nested('content');
    if (content != null) {
      message = content.text('message') ?? '';
      emotes = content.table('emote', (json) {
        final entry = JsonObject.from(json);
        final size = entry.nested('meta')?.count('size') ?? 1;
        return EmoteRef(url: entry.text('url') ?? '', size: size < 1 ? 1 : size);
      });
      mentions = content.table('at_name_to_mid', (json) => asRequiredInt(json, 'at_name_to_mid'));
      final jumps = content.table('jump_url', (json) {
        final entry = JsonObject.from(json);
        return (title: entry.text('title') ?? '', pcURL: entry.text('pc_url') ?? '');
      });
      for (final MapEntry(:key, value: entry) in jumps.entries) {
        links[key] = LinkRef(
          title: entry.title.isEmpty ? key : entry.title,
          url: _absolute(entry.pcURL, orElse: key),
        );
      }
      pictures = content.lenientList('pictures', CommentPicture.fromJson);
    }
    // A reply's "@name" is the name the target had when it was written; at_name_to_mid holds the current one.
    final target = object.nested('parent_reply_member')?.text('name');
    if (target != null && mentions[target] == null && message.contains('@$target')) {
      final unmatched = mentions.entries.where((entry) => !message.contains('@${entry.key}')).toList();
      if (unmatched.length == 1) mentions[target] = unmatched.single.value;
    }

    final location = object.nested('reply_control')?.text('location');
    final place = location == null
        ? null
        : location.startsWith(_locationPrefix)
        ? location.substring(_locationPrefix.length)
        : location;
    return Comment(
      rpid: rpid,
      oid: object.count('oid'),
      mid: mid,
      root: object.count('root'),
      parent: object.count('parent'),
      ctime: object.count('ctime'),
      likes: object.count('like'),
      replyCount: object.count('rcount', 'count'),
      action: object.count('action'),
      member: member,
      message: message,
      runs: RichText.runs(message, emotes: emotes, mentions: mentions, links: links),
      pictures: pictures,
      location: _nonEmpty(place),
      upLiked: object.nested('up_action')?.commentFlag('like') ?? false,
      previewReplies: object.lenientList('replies', Comment.fromJson),
    );
  }

  /// Jump links come protocol-relative ("//search.bilibili.com/..."); a word with no link at all is shown as is.
  static String _absolute(String url, {required String orElse}) {
    if (url.isEmpty) return orElse;
    return url.startsWith('//') ? 'https:$url' : url;
  }

  final int rpid;
  final int oid;
  final int mid;
  final int root;
  final int parent;
  final int ctime;
  final int likes;
  final int replyCount;

  /// The viewer's own reaction: 0 none, 1 liked, 2 disliked.
  final int action;
  final CommentMember member;
  final String message;
  final List<RichRun> runs;
  final List<CommentPicture> pictures;
  final String? location;
  final bool upLiked;
  final bool isPinned;
  final List<Comment> previewReplies;

  int get id => rpid;

  /// Swift's Comment is a value type with these fields mutable; here a changed copy stands in for the mutation.
  Comment copyWith({int? likes, int? replyCount, int? action, bool? isPinned, List<Comment>? previewReplies}) =>
      Comment(
        rpid: rpid,
        oid: oid,
        mid: mid,
        root: root,
        parent: parent,
        ctime: ctime,
        likes: likes ?? this.likes,
        replyCount: replyCount ?? this.replyCount,
        action: action ?? this.action,
        member: member,
        message: message,
        runs: runs,
        pictures: pictures,
        location: location,
        upLiked: upLiked,
        isPinned: isPinned ?? this.isPinned,
        previewReplies: previewReplies ?? this.previewReplies,
      );

  @override
  bool operator ==(Object other) =>
      other is Comment &&
      other.rpid == rpid &&
      other.oid == oid &&
      other.mid == mid &&
      other.root == root &&
      other.parent == parent &&
      other.ctime == ctime &&
      other.likes == likes &&
      other.replyCount == replyCount &&
      other.action == action &&
      other.member == member &&
      other.message == message &&
      listEquals(other.runs, runs) &&
      listEquals(other.pictures, pictures) &&
      other.location == location &&
      other.upLiked == upLiked &&
      other.isPinned == isPinned &&
      listEquals(other.previewReplies, previewReplies);

  @override
  int get hashCode => Object.hash(
    rpid,
    oid,
    mid,
    root,
    parent,
    ctime,
    likes,
    replyCount,
    action,
    member,
    message,
    Object.hashAll(runs),
    Object.hashAll(pictures),
    location,
    upLiked,
    isPinned,
    Object.hashAll(previewReplies),
  );

  @override
  String toString() => 'Comment($rpid, $message)';
}

final class CommentPage {
  const CommentPage({required this.comments, this.pinned, this.nextOffset, this.isEnd = true, this.total = 0});

  final List<Comment> comments;
  final Comment? pinned;

  /// Null on the last page.
  final String? nextOffset;
  final bool isEnd;
  final int total;

  CommentPage copyWith({List<Comment>? comments, Comment? Function()? pinned, int? total}) => CommentPage(
    comments: comments ?? this.comments,
    pinned: pinned == null ? this.pinned : pinned(),
    nextOffset: nextOffset,
    isEnd: isEnd,
    total: total ?? this.total,
  );

  @override
  bool operator ==(Object other) =>
      other is CommentPage &&
      listEquals(other.comments, comments) &&
      other.pinned == pinned &&
      other.nextOffset == nextOffset &&
      other.isEnd == isEnd &&
      other.total == total;

  @override
  int get hashCode => Object.hash(Object.hashAll(comments), pinned, nextOffset, isEnd, total);
}

final class ThreadPage {
  const ThreadPage({required this.root, required this.replies, required this.total, required this.isEnd});

  final Comment root;
  final List<Comment> replies;
  final int total;
  final bool isEnd;

  ThreadPage copyWith({Comment? root, List<Comment>? replies, int? total, bool? isEnd}) => ThreadPage(
    root: root ?? this.root,
    replies: replies ?? this.replies,
    total: total ?? this.total,
    isEnd: isEnd ?? this.isEnd,
  );

  @override
  bool operator ==(Object other) =>
      other is ThreadPage &&
      other.root == root &&
      listEquals(other.replies, replies) &&
      other.total == total &&
      other.isEnd == isEnd;

  @override
  int get hashCode => Object.hash(root, Object.hashAll(replies), total, isEnd);
}

final class Emote {
  const Emote({required this.token, required this.url, required this.large});

  factory Emote.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final token = object.text('text');
    if (token == null || token.isEmpty) throw const DecodeError('missing text');
    return Emote(token: token, url: object.text('url') ?? '', large: (object.nested('meta')?.count('size') ?? 1) != 1);
  }

  /// What the comment text carries for the emote, such as "[doge]".
  final String token;

  /// Empty for the text (kaomoji) packages, whose token is the picture.
  final String url;
  final bool large;

  @override
  bool operator ==(Object other) => other is Emote && other.token == token && other.url == url && other.large == large;

  @override
  int get hashCode => Object.hash(token, url, large);

  @override
  String toString() => 'Emote($token, $url, large: $large)';
}

final class EmotePackage {
  const EmotePackage({
    required this.id,
    required this.name,
    required this.icon,
    required this.isText,
    required this.emotes,
  });

  factory EmotePackage.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return EmotePackage(
      id: object.count('id'),
      name: object.text('text') ?? '',
      icon: object.text('url') ?? '',
      isText: object.count('type') == 4,
      emotes: object.lenientList('emote', Emote.fromJson),
    );
  }

  final int id;
  final String name;
  final String icon;
  final bool isText;
  final List<Emote> emotes;

  @override
  bool operator ==(Object other) =>
      other is EmotePackage &&
      other.id == id &&
      other.name == name &&
      other.icon == icon &&
      other.isText == isText &&
      listEquals(other.emotes, emotes);

  @override
  int get hashCode => Object.hash(id, name, icon, isText, Object.hashAll(emotes));
}

List<EmotePackage> decodeEmotePanel(Object? json) => JsonObject.from(json).lossyList('packages', EmotePackage.fromJson);

CommentPage decodeCommentList(Object? json) {
  final object = JsonObject.from(json);
  final replies = object.lossyList('replies', Comment.fromJson);
  final top = object.lossyList('top_replies', Comment.fromJson);
  final cursor = object.nested('cursor');
  final next = _nonEmpty(cursor?.nested('pagination_reply')?.text('next_offset'));
  return CommentPage(
    comments: replies,
    pinned: top.firstOrNull?.copyWith(isPinned: true),
    nextOffset: next,
    // Without an offset there is no way to ask for more, whatever is_end says.
    isEnd: next == null || cursor?.commentFlag('is_end') == true,
    total: cursor?.count('all_count') ?? 0,
  );
}

ThreadPage decodeCommentThread(Object? json) {
  final object = JsonObject.from(json);
  final rootJson = object.map['root'];
  if (rootJson == null) throw const DecodeError('missing root');
  final root = Comment.fromJson(rootJson);
  final replies = object.lossyList('replies', Comment.fromJson);
  final paging = object.nested('page');
  final total = paging?.count('count') ?? 0;
  final seen = (paging?.count('num') ?? 0) * (paging?.count('size') ?? 0);
  return ThreadPage(root: root, replies: replies, total: total, isEnd: replies.isEmpty || seen >= total);
}

Comment decodePostedComment(Object? json) {
  final reply = JsonObject.from(json).map['reply'];
  if (reply == null) throw const DecodeError('missing reply');
  return Comment.fromJson(reply);
}

/// Someone the viewer follows, offered by the composer's @ picker.
final class MentionCandidate {
  const MentionCandidate({required this.mid, required this.name, this.face = ''});

  /// One entry of `/x/relation/followings` or its search.
  factory MentionCandidate.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final mid = object.count('mid');
    final name = object.text('uname') ?? '';
    if (mid == 0 || name.isEmpty) throw const DecodeError('missing mid or uname');
    return MentionCandidate(mid: mid, name: name, face: object.text('face') ?? '');
  }

  final int mid;
  final String name;
  final String face;

  @override
  bool operator ==(Object other) =>
      other is MentionCandidate && other.mid == mid && other.name == name && other.face == face;

  @override
  int get hashCode => Object.hash(mid, name, face);

  @override
  String toString() => 'MentionCandidate($mid, $name)';
}

/// A picture uploaded for a comment, as `/x/v2/reply/add`'s `pictures` takes it back.
final class UploadedPicture {
  const UploadedPicture({required this.url, required this.width, required this.height, required this.sizeKb});

  /// `/x/dynamic/feed/draw/upload_bfs`'s data.
  factory UploadedPicture.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final url = object.text('image_url');
    if (url == null || url.isEmpty) throw const DecodeError('missing image_url');
    return UploadedPicture(
      url: url,
      width: object.count('image_width'),
      height: object.count('image_height'),
      sizeKb: attempt(() => object.number('img_size')) ?? 0,
    );
  }

  final String url;
  final int width;
  final int height;
  final double sizeKb;

  /// One entry of `/x/v2/reply/add`'s `pictures`.
  Map<String, Object> toJson() => {'img_src': url, 'img_width': width, 'img_height': height, 'img_size': sizeKb};

  @override
  bool operator ==(Object other) =>
      other is UploadedPicture &&
      other.url == url &&
      other.width == width &&
      other.height == height &&
      other.sizeKb == sizeKb;

  @override
  int get hashCode => Object.hash(url, width, height, sizeKb);

  @override
  String toString() => 'UploadedPicture($url, $width x $height, $sizeKb KB)';
}

/// A search that matches no one can answer without a list.
List<MentionCandidate> decodeMentionCandidates(Object? json) =>
    JsonObject.from(json).lenientList('list', MentionCandidate.fromJson);
