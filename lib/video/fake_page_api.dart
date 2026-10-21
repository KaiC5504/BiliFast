import 'dart:async';
import 'dart:math' show max, min;

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';

import 'page_api.dart';

/// A [PageApi] that answers from memory: the tests' fake, and the actions' backend in `--fake-account` runs on the
/// PC, so every button can be pressed there without a call reaching Bilibili or KaiC's account.
class FakePageApi implements PageApi {
  FakePageApi({
    this.relationValue = const VideoRelation(like: false, dislike: false, favorite: false, attention: false, coins: 0),
    this.uploader,
    this.tagsValue = const [],
    this.online = '1',
    this.balance = 10,
    List<FavFolder>? folders,
    this.delay = Duration.zero,
  }) : _folders = [...?folders];

  /// What the PC run shows: an uploader with fans, two folders (one private), coins to give, topic and BGM chips,
  /// and 评论 with threads, pictures, emotes and people to @, dated back from [now].
  factory FakePageApi.demo({DateTime? now}) => FakePageApi(
        uploader: const UploaderCard(
          mid: 1,
          name: '',
          face: '',
          fans: 475000,
          videos: 410,
          isVip: true,
          following: false,
          official: OfficialKind.person,
        ),
        tagsValue: const [
          VideoTag(id: 1, name: '《グランドエスケープ》', kind: VideoTagKind.bgm),
          VideoTag(id: 2, name: '动漫二创激励计划', kind: VideoTagKind.topic),
          VideoTag(id: 3, name: '必剪创作', kind: VideoTagKind.normal),
        ],
        online: '53',
        balance: 873,
        folders: const [
          FavFolder(id: 11, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
          FavFolder(id: 12, title: '二乃', count: 8, isPrivate: true, contains: false, isDefault: false),
        ],
        delay: const Duration(milliseconds: 300),
      )
        .._fillDemoComments(now ?? DateTime.now())
        .._fillDemoHistory(now ?? DateTime.now());

  VideoRelation relationValue;
  UploaderCard? uploader;
  List<VideoTag> tagsValue;
  String online;
  double balance;
  final List<FavFolder> _folders;

  /// How long each answer takes, so optimistic changes and spinners show.
  Duration delay;

  /// Every call, as its method name with the arguments that matter (`like on=true`, `coin multiply=2 like=true`).
  final List<String> calls = [];

  /// A method named here (`like`, `coinBalance`, ...) throws this instead of answering.
  final Map<String, Object> failures = {};

  /// A method named here waits for its completer before it answers (or throws), so a test can look at what shows
  /// while the server hasn't answered. The call is in [calls] already.
  final Map<String, Completer<void>> holds = {};

  /// False: folder lists leave out the folders [createFolder] made, as a list fetched before them would.
  bool listsNewFolders = true;

  var _nextFolderId = 100;

  List<FavFolder> get folders => List.unmodifiable(_folders);

  Future<T> _answer<T>(String name, String call, T Function() value) async {
    calls.add(call);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  @override
  Future<VideoRelation> relation({required int aid, required String bvid}) =>
      _answer('relation', 'relation', () => relationValue);

  /// Says what [uploader] was when asked, so a held answer can be one a 关注 made since has outdated.
  @override
  Future<UploaderCard> uploaderCard({required int mid}) {
    final card = uploader;
    return _answer('uploaderCard', 'uploaderCard mid=$mid', () {
      if (card == null) throw const BiliError.api(code: -404, message: '啥都木有');
      // Answers for whichever uploader is asked about, so a real video's owner gets the canned counts.
      return UploaderCard(
        mid: mid,
        name: card.name,
        face: card.face,
        fans: card.fans,
        videos: card.videos,
        isVip: card.isVip,
        following: card.following,
        official: card.official,
      );
    });
  }

  @override
  Future<List<VideoTag>> tags({required String bvid, required int cid}) =>
      _answer('tags', 'tags cid=$cid', () => tagsValue);

  @override
  Future<String> onlineCount({required int aid, required String bvid, required int cid}) =>
      _answer('onlineCount', 'onlineCount cid=$cid', () => online);

  @override
  Future<void> like({required int aid, required String bvid, required bool on}) => _answer('like', 'like on=$on', () {
        relationValue = _relation(like: on, dislike: on ? false : relationValue.dislike);
      });

  @override
  Future<TripleResult> triple({required int aid, required String bvid}) => _answer('triple', 'triple', () {
        final multiply = 2 - relationValue.coins;
        relationValue = _relation(like: true, favorite: true, coins: relationValue.coins + multiply);
        return TripleResult(like: true, coin: multiply > 0, favorite: true, multiply: multiply);
      });

  @override
  Future<void> dislike({required int aid, required bool on}) => _answer('dislike', 'dislike on=$on', () {
        relationValue = _relation(dislike: on, like: on ? false : relationValue.like);
      });

  @override
  Future<void> coin({required int aid, required String bvid, required int multiply, required bool alsoLike}) =>
      _answer('coin', 'coin multiply=$multiply like=$alsoLike', () {
        if (balance < multiply) throw const BiliError.api(code: -104, message: '硬币不足');
        balance -= multiply;
        relationValue = _relation(coins: relationValue.coins + multiply, like: alsoLike || relationValue.like);
      });

  @override
  Future<double> coinBalance() => _answer('coinBalance', 'coinBalance', () => balance);

  @override
  Future<List<FavFolder>> favouriteFolders({required int mid, required int aid}) =>
      _answer('favouriteFolders', 'favouriteFolders', () => folders);

  @override
  Future<void> updateFavourites({required int aid, required List<int> add, required List<int> remove}) =>
      _answer('updateFavourites', 'updateFavourites add=${add.join(',')} remove=${remove.join(',')}', () {
        for (var i = 0; i < _folders.length; i++) {
          final folder = _folders[i];
          final added = add.contains(folder.id) && !folder.contains;
          final removed = remove.contains(folder.id) && folder.contains;
          if (!added && !removed) continue;
          _folders[i] = FavFolder(
            id: folder.id,
            title: folder.title,
            count: folder.count + (added ? 1 : -1),
            isPrivate: folder.isPrivate,
            contains: added,
            isDefault: folder.isDefault,
          );
        }
        relationValue = _relation(favorite: _folders.any((folder) => folder.contains));
      });

  @override
  Future<FavFolder> createFolder({required String title, required bool isPrivate}) =>
      _answer('createFolder', 'createFolder title=$title private=$isPrivate', () {
        final folder = FavFolder(
          id: _nextFolderId++,
          title: title,
          count: 0,
          isPrivate: isPrivate,
          contains: false,
          isDefault: false,
        );
        if (listsNewFolders) _folders.add(folder);
        return folder;
      });

  @override
  Future<void> countShare({required int aid}) => _answer('countShare', 'countShare', () {});

  @override
  Future<void> follow({required int mid, required bool on}) => _answer('follow', 'follow on=$on', () {
        relationValue = _relation(attention: on);
        // The card answers for every uploader, so a space opened again shows the change too.
        if (uploader case final card?) {
          uploader = UploaderCard(
            mid: card.mid,
            name: card.name,
            face: card.face,
            fans: card.fans,
            videos: card.videos,
            isVip: card.isVip,
            following: on,
            official: card.official,
          );
        }
      });

  @override
  Future<void> favSeason({required int seasonId, required bool on}) =>
      _answer('favSeason', 'favSeason season=$seasonId on=$on', () {
        relationValue = _relation(seasonFav: on);
      });

  @override
  Future<void> addToWatchLater({required int aid}) => _answer('addToWatchLater', 'addToWatchLater aid=$aid', () {});

  /// 评论's top-level comments in 按热度's order (按时间 sorts them by ctime, newest first), [commentPageSize] to a page
  /// with an offset string to the next.
  List<Comment> commentList = [];
  Comment? pinnedComment;

  /// Each root's replies; a root not here answers its preview replies. 按时间 is oldest first, 按热度 most liked.
  Map<int, List<Comment>> threadReplies = {};
  int commentPageSize = 20;
  int threadPageSize = 20;

  List<EmotePackage> emotes = const [];

  List<MentionCandidate> followed = const [];

  /// What each [postComment] was sent, in order.
  final List<PostedArguments> posts = [];

  /// Who a posted comment is written as: `--fake-account`'s 测试账号.
  static const accountMember = CommentMember(
    mid: 1,
    name: '测试账号',
    face: '${_DemoComments._cdn}/face/member/noface.jpg',
    level: 4,
  );

  static const _offsetPrefix = 'demo-offset-';

  var _nextRpid = 1000;
  CommentPage? _firstPage;

  /// 评论's first page. Set, it is answered as given for the first page, with the comments as they are now, and
  /// later pages come back empty.
  CommentPage get commentPage => _firstPage ?? _commentPage(CommentSort.hot, 0);
  set commentPage(CommentPage page) {
    _firstPage = page;
    commentList = [...page.comments];
    pinnedComment = page.pinned;
  }

  /// The pinned comment and the list with every reply, as Bilibili's all_count counts them.
  int get commentTotal => [?pinnedComment, ...commentList].fold(0, (sum, comment) => sum + 1 + comment.replyCount);

  @override
  Future<CommentPage> comments({required int aid, required CommentSort sort, String? offset}) =>
      _answer('comments', 'comments sort=${sort.name} offset=${offset ?? ''}', () {
        if (_firstPage case final first?) {
          if (offset != null) return const CommentPage(comments: []);
          return first.copyWith(comments: commentList, pinned: () => pinnedComment);
        }
        final start = offset == null ? 0 : int.tryParse(offset.replaceFirst(_offsetPrefix, ''));
        if (start == null) return const CommentPage(comments: []);
        return _commentPage(sort, start);
      });

  CommentPage _commentPage(CommentSort sort, int start) {
    final ordered = sort == CommentSort.hot ? commentList : _ordered(commentList, (a, b) => b.ctime.compareTo(a.ctime));
    final end = min(ordered.length, start + commentPageSize);
    final more = end < ordered.length;
    return CommentPage(
      comments: start >= end ? const [] : ordered.sublist(start, end),
      pinned: start == 0 ? pinnedComment : null,
      nextOffset: more ? '$_offsetPrefix$end' : null,
      isEnd: !more,
      total: commentTotal,
    );
  }

  @override
  Future<ThreadPage> thread({required int aid, required int root, required int page, required CommentSort sort}) =>
      _answer('thread', 'thread root=$root page=$page sort=${sort.name}', () {
        final rootComment = _find(root) ?? Comment(rpid: root, member: const CommentMember(mid: 0), message: '');
        final replies = threadReplies[root] ?? rootComment.previewReplies;
        final ordered = sort == CommentSort.time
            ? _ordered(replies, (a, b) => a.ctime.compareTo(b.ctime))
            : _ordered(replies, (a, b) => b.likes.compareTo(a.likes));
        final start = (page - 1) * threadPageSize;
        final end = min(ordered.length, start + threadPageSize);
        return ThreadPage(
          root: rootComment,
          replies: start >= end ? const [] : ordered.sublist(start, end),
          total: rootComment.replyCount,
          isEnd: end >= ordered.length,
        );
      });

  @override
  Future<Comment> postComment({
    required int aid,
    required String message,
    int root = 0,
    int parent = 0,
    bool syncToDynamic = false,
    Map<String, int> mentions = const {},
    List<UploadedPicture> pictures = const [],
  }) => _answer('postComment', 'postComment root=$root parent=$parent message=$message', () {
    posts.add((
      message: message,
      root: root,
      parent: parent,
      syncToDynamic: syncToDynamic,
      mentions: mentions,
      pictures: pictures,
    ));
    final comment = Comment(
      rpid: _nextRpid++,
      oid: aid,
      mid: accountMember.mid,
      root: root,
      parent: parent,
      ctime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      member: accountMember,
      message: message,
      runs: RichText.runs(message, emotes: _emoteRefs(message), mentions: mentions, links: const {}),
      pictures: [
        for (final picture in pictures)
          CommentPicture(url: picture.url, width: picture.width.toDouble(), height: picture.height.toDouble()),
      ],
    );
    if (root == 0) {
      commentList = [comment, ...commentList];
    } else {
      threadReplies[root] = [...?(threadReplies[root] ?? _find(root)?.previewReplies), comment];
      _change(root, (target) => target.copyWith(replyCount: target.replyCount + 1));
    }
    return comment;
  });

  @override
  Future<void> likeComment({required int aid, required int rpid, required bool on}) =>
      _answer('likeComment', 'likeComment rpid=$rpid on=$on', () {
        _change(rpid, (comment) {
          if (on == (comment.action == 1)) return comment;
          return comment.copyWith(likes: max(0, comment.likes + (on ? 1 : -1)), action: on ? 1 : 0);
        });
      });

  @override
  Future<void> hateComment({required int aid, required int rpid, required bool on}) =>
      _answer('hateComment', 'hateComment rpid=$rpid on=$on', () {
        _change(rpid, (comment) {
          if (on == (comment.action == 2)) return comment;
          if (!on) return comment.copyWith(action: 0);
          return comment.copyWith(likes: comment.action == 1 ? max(0, comment.likes - 1) : comment.likes, action: 2);
        });
      });

  /// A comment the fake doesn't hold is deleted all the same, as a widget test's own comments are.
  @override
  Future<void> deleteComment({required int aid, required int rpid}) =>
      _answer('deleteComment', 'deleteComment rpid=$rpid', () {
        final root = _find(rpid)?.root ?? 0;
        Comment withoutReply(Comment comment) => comment.previewReplies.any((reply) => reply.rpid == rpid)
            ? comment.copyWith(previewReplies: [for (final reply in comment.previewReplies) if (reply.rpid != rpid) reply])
            : comment;
        commentList = [for (final comment in commentList) if (comment.rpid != rpid) withoutReply(comment)];
        if (pinnedComment case final pinned?) pinnedComment = pinned.rpid == rpid ? null : withoutReply(pinned);
        threadReplies = {
          for (final MapEntry(key: thread, value: replies) in threadReplies.entries)
            if (thread != rpid) thread: [for (final reply in replies) if (reply.rpid != rpid) reply],
        };
        if (root != 0) _change(root, (comment) => comment.copyWith(replyCount: max(0, comment.replyCount - 1)));
      });

  @override
  Future<List<EmotePackage>> emotePackages() => _answer('emotePackages', 'emotePackages', () => emotes);

  @override
  Future<List<MentionCandidate>> mentionCandidates({required int mid, String query = ''}) =>
      _answer('mentionCandidates', 'mentionCandidates query=$query', () {
        return [for (final who in followed) if (who.name.contains(query)) who];
      });

  @override
  Future<UploadedPicture> uploadCommentPicture({required List<int> bytes, required String filename}) =>
      _answer('uploadCommentPicture', 'uploadCommentPicture $filename', () {
        // example.invalid never resolves, so on the PC a posted picture shows as one that failed to load.
        return UploadedPicture(
          url: 'https://example.invalid/bfs/new_dyn/$filename',
          width: 1080,
          height: 1440,
          sizeKb: bytes.length / 1024,
        );
      });

  /// The account's 弹幕屏蔽词 as the fake server holds them.
  List<BlockRule> blockRules = [];
  int _nextRuleId = 1;

  /// Every danmaku [postDanmaku] was sent.
  final List<DanmakuDraft> postedDanmaku = [];
  int _nextDmid = 9000;

  /// 👍 counts by danmaku id; one not here has none.
  final Map<int, DanmakuLikeStat> danmakuLikeStats = {};

  @override
  Future<List<BlockRule>> danmakuBlockRules() =>
      _answer('danmakuBlockRules', 'danmakuBlockRules', () => List.of(blockRules));

  @override
  Future<BlockRule> addBlockRule(BlockRuleKind kind, {required String filter}) =>
      _answer('addBlockRule', 'addBlockRule ${kind.name}=$filter', () {
        final rule = BlockRule(id: _nextRuleId++, kind: kind, filter: filter);
        blockRules = [...blockRules, rule];
        return rule;
      });

  @override
  Future<void> deleteBlockRule({required int id}) => _answer('deleteBlockRule', 'deleteBlockRule id=$id', () {
        blockRules = [for (final rule in blockRules) if (rule.id != id) rule];
      });

  @override
  Future<int> postDanmaku(DanmakuDraft draft) => _answer('postDanmaku', 'postDanmaku ${draft.text}', () {
        postedDanmaku.add(draft);
        return _nextDmid++;
      });

  @override
  Future<void> likeDanmaku({required int cid, required int dmid, required bool on}) =>
      _answer('likeDanmaku', 'likeDanmaku dmid=$dmid on=$on', () {
        final stat = danmakuLikeStats[dmid] ?? (likes: 0, liked: false);
        if (stat.liked == on) return;
        danmakuLikeStats[dmid] = (likes: max(0, stat.likes + (on ? 1 : -1)), liked: on);
      });

  @override
  Future<Map<int, DanmakuLikeStat>> danmakuLikes({required int cid, required List<int> dmids}) =>
      _answer('danmakuLikes', 'danmakuLikes ${dmids.length}', () => {
            for (final id in dmids) id: ?danmakuLikeStats[id],
          });

  /// 历史记录, newest first, answered [historyPageSize] at a time; the page after the last is empty, as Bilibili's.
  List<HistoryItem> historyItems = [];
  int historyPageSize = 20;

  @override
  Future<HistoryPage> history({HistoryCursor? after}) =>
      _answer('history', 'history after=${after?.max ?? 0}', () {
        final start = after == null
            ? 0
            : historyItems.indexWhere((item) => item.aid == after.max && item.viewAt == after.viewAt) + 1;
        final rows = start <= 0 && after != null
            ? const <HistoryItem>[]
            : historyItems.skip(start).take(historyPageSize).toList();
        final last = rows.isEmpty ? null : rows.last;
        return HistoryPage(items: rows, next: last == null ? null : HistoryCursor(max: last.aid, viewAt: last.viewAt));
      });

  @override
  Future<void> deleteHistory(HistoryItem item) => _answer('deleteHistory', 'deleteHistory aid=${item.aid}', () {
        historyItems = [for (final row in historyItems) if (row.id != item.id) row];
      });

  /// The comment with [rpid] wherever the fake holds it: the list, the pinned comment, a preview or a thread.
  Comment? _find(int rpid) {
    for (final comment in [?pinnedComment, ...commentList, for (final replies in threadReplies.values) ...replies]) {
      if (comment.rpid == rpid) return comment;
      for (final reply in comment.previewReplies) {
        if (reply.rpid == rpid) return reply;
      }
    }
    return null;
  }

  /// Changes every copy of [rpid] the fake holds.
  void _change(int rpid, Comment Function(Comment comment) change) {
    Comment apply(Comment comment) {
      var changed = comment.rpid == rpid ? change(comment) : comment;
      if (changed.previewReplies.any((reply) => reply.rpid == rpid)) {
        changed = changed.copyWith(
          previewReplies: [for (final reply in changed.previewReplies) reply.rpid == rpid ? change(reply) : reply],
        );
      }
      return changed;
    }

    commentList = [for (final comment in commentList) apply(comment)];
    if (pinnedComment case final pinned?) pinnedComment = apply(pinned);
    threadReplies = {
      for (final MapEntry(key: root, value: replies) in threadReplies.entries)
        root: [for (final reply in replies) apply(reply)],
    };
  }

  /// The picture emotes of [emotes] whose tokens are in [message], as the server sends them with a comment.
  Map<String, EmoteRef> _emoteRefs(String message) => {
    for (final package in emotes)
      if (!package.isText)
        for (final emote in package.emotes)
          if (message.contains(emote.token)) emote.token: EmoteRef(url: emote.url, size: emote.large ? 2 : 1),
  };

  /// Sorted by [compare], ties kept in their order (List.sort isn't stable).
  static List<Comment> _ordered(List<Comment> comments, int Function(Comment a, Comment b) compare) {
    final indexed = [for (var index = 0; index < comments.length; index++) (index, comments[index])];
    indexed.sort((a, b) {
      final order = compare(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
    return [for (final (_, comment) in indexed) comment];
  }

  /// 评论 for the PC run: a pinned comment and 25 more over two pages, VIP and plain names at levels 2-6, pictures,
  /// timestamps, a BV id and an @, threads that page in both sorts, a comment and a reply of 测试账号's to delete,
  /// three emote packages (one of 颜文字) and people to @. The images are public ones on Bilibili's CDN, asked for with
  /// no cookies so the PC run looks like the phone: Bilibili's own accounts' avatars, its emotes and decorations, and
  /// game studios' video covers. Tests never draw them.
  /// About 30 rows over 今天, 昨天 and 更早 (two pages), watched on the phone and the PC, one to the end and one
  /// hours long; no covers, so nothing is fetched.
  void _fillDemoHistory(DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    final sinceMidnight = now.difference(midnight);
    int unix(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
    final times = [
      for (var i = 1; i <= 6; i++) unix(midnight.add(sinceMidnight * (1 - i / 7))),
      for (final (hour, minute) in const [(22, 33), (22, 30), (22, 30), (22, 18), (20, 35), (20, 4), (20, 4), (19, 12)])
        unix(midnight.subtract(const Duration(days: 1)).add(Duration(hours: hour, minutes: minute))),
      for (var i = 0; i < 16; i++)
        unix(midnight.subtract(Duration(days: 2 + i ~/ 4)).add(Duration(hours: 23 - (i % 4) * 5, minutes: 10 + i))),
    ];
    const titles = [
      '一口气看完系列：三分钟带你了解城市夜景延时摄影的全部流程',
      '这期视频做了一年',
      '新手也能学会的家常菜，十分钟上桌',
      '【4K】雨后山间的清晨，白噪音放松向',
      '我们把旧电脑改造成了家庭影院',
      '周末骑行一百公里是什么体验？',
    ];
    const uploaders = ['夜景摄影师', '一年一更', '厨房小白', '山间录音', '折腾实验室', '周末骑行'];
    historyItems = [
      for (var i = 0; i < times.length; i++)
        HistoryItem(
          aid: 9100 + i,
          bvid: i == 0 ? 'BV1GJ411x7h7' : 'BV1Demo${i.toString().padLeft(2, '0')}x7h7',
          cid: 0,
          title: titles[i % titles.length],
          cover: '',
          ownerName: uploaders[i % uploaders.length],
          progress: i == 19 ? -1 : 2 + i * 7,
          duration: i == 17 ? 13230 : 90 + i * 37,
          viewAt: times[i],
          device: i % 3 == 1 ? 1 : 2,
          part: null,
        ),
    ];
  }

  void _fillDemoComments(DateTime now) {
    final demo = _DemoComments(now.millisecondsSinceEpoch ~/ 1000);
    emotes = _DemoComments.emotes;
    followed = _DemoComments.followed;
    demo.build();
    pinnedComment = demo.pinned;
    commentList = demo.comments;
    threadReplies = demo.threads;
    _nextRpid = demo.nextRpid;
  }

  VideoRelation _relation({bool? like, bool? dislike, bool? favorite, bool? attention, int? coins, bool? seasonFav}) =>
      VideoRelation(
        like: like ?? relationValue.like,
        dislike: dislike ?? relationValue.dislike,
        favorite: favorite ?? relationValue.favorite,
        attention: attention ?? relationValue.attention,
        coins: coins ?? relationValue.coins,
        seasonFav: seasonFav ?? relationValue.seasonFav,
      );
}

/// What [FakePageApi.postComment] was sent.
typedef PostedArguments = ({
  String message,
  int root,
  int parent,
  bool syncToDynamic,
  Map<String, int> mentions,
  List<UploadedPicture> pictures,
});

/// The demo's comments, dated back from [now] (in seconds since the epoch).
final class _DemoComments {
  _DemoComments(this.now);

  final int now;
  int nextRpid = 5001;
  Comment? pinned;
  List<Comment> comments = [];
  final Map<int, List<Comment>> threads = {};

  static const _cdn = 'https://i0.hdslb.com/bfs';

  static const _up = CommentMember(
    mid: 2,
    name: '演示UP主',
    face: '$_cdn/face/0c84b9f4ad546d3f20324809d45fc439a2a8ddab.jpg',
    level: 6,
    isVip: true,
  );
  static const _ming = CommentMember(
    mid: 3003,
    name: '小明',
    face: 'https://i1.hdslb.com/bfs/face/040528a1ec634b9907ba3a9ba957819bb07def06.jpg',
    level: 5,
  );
  static const _hong = CommentMember(
    mid: 3004,
    name: '小红',
    face: '$_cdn/face/8f6a614a48a3813d90da7a11894ae56a59396fcd.jpg',
    level: 4,
    isVip: true,
  );
  static const _hoshino = CommentMember(
    mid: 3005,
    name: '星野',
    face: 'https://i1.hdslb.com/bfs/face/2254162161a60b528cfec449f3450409a81ebc37.jpg',
    level: 6,
    isVip: true,
    fanCardImage: '$_cdn/garb/item/66b16c3dd13072c9f906ec27e218802385f97c71.png',
    fanCardNumber: '031467',
    fanCardColor: '#f35543',
  );
  static const _nino = CommentMember(
    mid: 3006,
    name: '二乃',
    face: 'https://i2.hdslb.com/bfs/face/d655b5efeb97cb4ca5d4926bc53cddee66f429a5.jpg',
    level: 3,
  );
  static const _passer = CommentMember(
    mid: 3007,
    name: '路过的观众',
    face: 'https://i2.hdslb.com/bfs/face/bc7498227fea0d11a455e4c2587c86466515623d.jpg',
    level: 2,
  );
  static const _early = CommentMember(
    mid: 3008,
    name: '今天也要早睡',
    face: 'https://i2.hdslb.com/bfs/face/ae8149db0fe146563cdbf7ff346eb9bb3dc25a12.jpg',
    level: 5,
    isVip: true,
  );
  static const _kirito = CommentMember(
    mid: 3009,
    name: 'kirito_0423',
    face: 'https://i1.hdslb.com/bfs/face/c6712277697434a6dc40c0185c0108c39b2fc6fa.jpg',
    level: 4,
  );
  static const _fish = CommentMember(
    mid: 3010,
    name: '一只咸鱼',
    face: '$_cdn/baselabs/b3283b94df495648262ce268bcaf4c7853efc7ea.png',
    level: 6,
    pendant: 'https://i2.hdslb.com/bfs/garb/item/f8bb9af4f245cce0fcba5df248069f1eedd8cbb7.png',
  );
  static const _members = [_ming, _hong, _hoshino, _nino, _passer, _early, _kirito, _fish];
  static const _places = ['广东', '上海', '北京', '浙江', '四川', '江苏', '湖北', '福建', '海外'];

  /// Each emote's name and the file Bilibili serves it as.
  static const _faces = [
    ('doge', '3087d273a78ccaff4bb1e9972e2ba2a7583c9f11'),
    ('笑哭', 'c3043ba94babf824dea03ce500d0e73763bf4f40'),
    ('妙啊', 'b4cb77159d58614a9b787b91b1cd22a81f383535'),
    ('吃瓜', '4191ce3c44c2b3df8fd97c33f85d3ab15f4f3c84'),
    ('打call', '431432c43da3ee5aab5b0e4f8931953e649e9975'),
    ('脱单doge', 'bf7e00ecab02171f8461ee8cf439c73db9797748'),
    ('喜欢', '8a10a4d73a89f665feff3d46ca56e83dc68f9eb8'),
    ('OK', '4683fd9ffc925fa6423110979d7dcac5eda297f4'),
    ('星星眼', '63c9d1a31c0da745b61cdb35e0ecb28635675db2'),
    ('呲牙', 'b5a5898491944a4268360f2e7a84623149672eb6'),
    ('大哭', '2caafee2e5db4db72104650d87810cc2c123fc86'),
    ('歪嘴', '4384050fbab0586259acdd170b510fe262f08a17'),
    ('思考', 'cfa9b7e89e4bfe04bbcd34ccb1b0df37f4fa905c'),
    ('捂脸', '6921bb43f0c634870b92f4a8ad41dada94a5296d'),
    ('辣眼睛', '35d62c496d1e4ea9e091243fa812866f5fecc101'),
    ('藏狐', 'ba0937ef6f3ccca85e2e0047e6263f3b4da37201'),
  ];
  static const _tv = [
    ('小电视_笑', 'f80d384875183dfe2e24be13011c595c0210d273'),
    ('小电视_赞', '86ccf6d0b5480169bf80f3582fae09d7ed455c06'),
    ('小电视_害羞', 'de3aee88f7b6cc20ba9480c96c02f83a844381a9'),
    ('小电视_哭泣', '938bdf98df945576ae88e2a22931db07ded9e663'),
    ('小电视_吃惊', '05188008ea84c70d94e0076e28de15bf56f4c441'),
    ('小电视_太太喜欢', 'eb41a8c04840e4f77e76a4bff7a29ac89c432f4e'),
  ];
  static const _kaomoji = [
    '(⌒▽⌒)', '（￣▽￣）', '(=・ω・=)', '(｀・ω・´)', '(〜￣△￣)〜', '(･∀･)', '(°∀°)ﾉ', '(￣3￣)', '╮(￣▽￣)╭',
    '_(:3」∠)_', '(；¬＿¬)', '(ﾟДﾟ≡ﾟдﾟ)!?',
  ];

  static final emotes = [
    EmotePackage(
      id: 1,
      name: '小黄脸',
      icon: '$_cdn/emote/3087d273a78ccaff4bb1e9972e2ba2a7583c9f11.png',
      isText: false,
      emotes: [for (final (name, file) in _faces) Emote(token: '[$name]', url: '$_cdn/emote/$file.png', large: false)],
    ),
    EmotePackage(
      id: 2,
      name: '颜文字',
      icon: '',
      isText: true,
      emotes: [for (final token in _kaomoji) Emote(token: token, url: '', large: false)],
    ),
    EmotePackage(
      id: 3,
      name: '小电视',
      icon: '$_cdn/emote/ce49073ff96606a1a2674b3b4ef8e15fb0a399ff.png',
      isText: false,
      emotes: [for (final (name, file) in _tv) Emote(token: '[$name]', url: '$_cdn/emote/$file.png', large: true)],
    ),
  ];

  static const followed = [
    MentionCandidate(mid: 3003, name: '小明'),
    MentionCandidate(mid: 3004, name: '小红'),
    MentionCandidate(mid: 2, name: '演示UP主'),
    MentionCandidate(mid: 3005, name: '星野'),
    MentionCandidate(mid: 3006, name: '二乃'),
    MentionCandidate(mid: 3009, name: 'kirito_0423'),
  ];

  static const _replyTexts = [
    '同感', '确实，这段我也看了好几遍[吃瓜]', '前排', '02:15 那里真的绝了', '求BGM', '已三连，等下一期', '哈哈哈哈哈哈哈哈',
    '有没有人知道这是用什么剪的', '这个转场我学会了(=・ω・=)', '路过，顺便点个赞',
  ];

  /// Portrait and square ones are cropped by the CDN (`@…_1c`), so each size is the one served.
  static const _pictures = [
    CommentPicture(
      url: 'https://i2.hdslb.com/bfs/archive/6b29c1cf3a9efa4049f84d93a7a3e770187bf550.jpg@810w_1080h_1c.jpg',
      width: 810,
      height: 1080,
    ),
    CommentPicture(
      url: 'https://i1.hdslb.com/bfs/archive/0f25a7ea7fc3b6dd99fbd0fc450b040f5f681084.jpg',
      width: 1920,
      height: 1080,
    ),
    CommentPicture(
      url: 'https://i1.hdslb.com/bfs/archive/355a71a4759258731ba3e6d6bd942b77d92af83d.jpg@900w_900h_1c.jpg',
      width: 900,
      height: 900,
    ),
    CommentPicture(
      url: 'https://i2.hdslb.com/bfs/archive/6b29c1cf3a9efa4049f84d93a7a3e770187bf550.jpg',
      width: 1920,
      height: 1080,
    ),
  ];

  void build() {
    pinned = _thread(
      _comment(
        '感谢大家的支持！新系列每周五更新，记得三连[doge] 有问题可以在评论区留言，我会挑一些在下期回答',
        member: _up,
        likes: 5321,
        minutesAgo: 2880,
        place: 1,
      ).copyWith(isPinned: true),
      (root) => [
        _comment('支持！', member: _ming, likes: 88, minutesAgo: 2800, root: root, parent: root),
        _comment('UP主辛苦了[喜欢]', member: _hong, likes: 230, minutesAgo: 2700, root: root, parent: root, place: 2),
        _comment('每周五准时来报到', member: _fish, likes: 41, minutesAgo: 2000, root: root, parent: root, place: 4),
      ],
    );
    comments = [
      _thread(
        _comment(
          '前方高能 02:15 这里的转场太丝滑了，反复看了好几遍[妙啊]',
          member: _hoshino,
          likes: 3021,
          minutesAgo: 300,
          upLiked: true,
        ),
        (root) {
          final replies = [
            for (var index = 0; index < 25; index++)
              _comment(
                _replyTexts[index % _replyTexts.length],
                member: _members[index % _members.length],
                likes: (index * 37 + 11) % 180,
                minutesAgo: 290 - index * 10,
                root: root,
                parent: root,
                place: index,
              ),
          ];
          final answered = replies.firstWhere((reply) => reply.member.mid == _hong.mid);
          return [
            ...replies,
            _comment(
              '回复 @小红 :我也是这么觉得的',
              member: _nino,
              likes: 3,
              minutesAgo: 20,
              root: root,
              parent: answered.rpid,
              mentions: {_hong.name: _hong.mid},
            ),
            _comment('我也来回复一下', member: FakePageApi.accountMember, minutesAgo: 5, root: root, parent: root),
          ];
        },
      ),
      _comment('同一个作者的上一期 BV1GJ411x7h7 也很好看，强烈推荐', member: _ming, likes: 1890, minutesAgo: 1200, place: 3),
      _thread(
        _comment(
          '说一下我的看法：这一期的节奏比上一期好很多，开头三十秒就把主题交代清楚了，中间的资料整理也很扎实，看得出来花了很多时间。'
          '唯一的小遗憾是结尾有点仓促，最后那段总结如果能再展开一点就更好了。不过整体已经是今年看过最用心的视频之一了，期待下一期！[打call]',
          member: _early,
          likes: 1504,
          minutesAgo: 2000,
          place: 5,
        ),
        (root) => [
          _comment('说得好，结尾确实有点赶', member: _ming, likes: 40, minutesAgo: 1900, root: root, parent: root),
          _comment('同意楼主', member: _passer, likes: 12, minutesAgo: 1800, root: root, parent: root, place: 6),
          _comment('我也是这么想的[思考]', member: _kirito, likes: 25, minutesAgo: 1000, root: root, parent: root, place: 7),
          _comment('我也来回复一下', member: FakePageApi.accountMember, minutesAgo: 30, root: root, parent: root),
        ],
      ),
      _comment(
        '今天去现场拍的，分享给大家',
        member: _hong,
        likes: 987,
        minutesAgo: 90,
        place: 2,
        pictures: _pictures.take(3).toList(),
      ),
      _comment('好', member: _passer, likes: 860, minutesAgo: 45),
      _comment(
        '@小明 你上次说的就是这个吧，终于找到了',
        member: _nino,
        likes: 702,
        minutesAgo: 600,
        place: 4,
        mentions: {_ming.name: _ming.mid},
      ),
      _comment('1:02:33 的彩蛋有人发现吗？', member: _kirito, likes: 655, minutesAgo: 3000, place: 8),
      _comment('截图留念[doge]', member: _fish, likes: 540, minutesAgo: 150, place: 6, pictures: [_pictures[3]]),
      _comment('(｀・ω・´) 冲冲冲', member: _early, likes: 430, minutesAgo: 400),
      _comment('[小电视_笑][小电视_笑][小电视_笑]', member: _hoshino, likes: 401, minutesAgo: 75, place: 1),
      _comment('UP主的声音好好听', member: _hong, likes: 377, minutesAgo: 5000, place: 3),
      _comment('每次看都有新收获，收藏了', member: _ming, likes: 350, minutesAgo: 820),
      _comment('这期质量太高了，建议全站推荐', member: _fish, likes: 322, minutesAgo: 60, place: 7),
      _comment('有没有大佬讲讲 03:40 那里用的是什么技巧', member: _kirito, likes: 290, minutesAgo: 240, place: 2),
      _comment('求同款滤镜！', member: _nino, likes: 255, minutesAgo: 30, place: 5),
      _comment('第一次在这里评论，支持一下', member: FakePageApi.accountMember, likes: 231, minutesAgo: 10, place: 1),
      _comment('终于等到更新了[星星眼]', member: _passer, likes: 209, minutesAgo: 700, place: 8),
      _comment('看完了，去补前面的了', member: _early, likes: 188, minutesAgo: 15, place: 4),
      _comment('已经循环播放五遍了', member: _hoshino, likes: 160, minutesAgo: 1300, place: 3),
      _comment('这个系列我能看一百遍', member: _nino, likes: 120, minutesAgo: 500, place: 8),
      _comment('第二页的评论有人看吗[思考]', member: _fish, likes: 98, minutesAgo: 8),
      _comment('晚上十二点看到这个，越看越精神了', member: _hong, likes: 64, minutesAgo: 3600, place: 6),
      _comment('下一期什么时候出', member: _ming, likes: 41, minutesAgo: 2, place: 2),
      _comment('路过', member: _passer, likes: 9, minutesAgo: 1, place: 7),
      _comment('前排(°∀°)ﾉ', member: _kirito, likes: 2, minutesAgo: 4000, place: 5),
    ];
  }

  /// [root] with the replies [replies] makes for its rpid; the previews are the three most liked.
  Comment _thread(Comment root, List<Comment> Function(int root) replies) {
    final all = replies(root.rpid);
    threads[root.rpid] = all;
    final preview = FakePageApi._ordered(all, (a, b) => b.likes.compareTo(a.likes)).take(3).toList();
    return root.copyWith(replyCount: all.length, previewReplies: preview);
  }

  Comment _comment(
    String message, {
    required CommentMember member,
    int likes = 0,
    int minutesAgo = 60,
    int root = 0,
    int parent = 0,
    int place = 0,
    List<CommentPicture> pictures = const [],
    bool upLiked = false,
    Map<String, int> mentions = const {},
  }) => Comment(
    rpid: nextRpid++,
    mid: member.mid,
    root: root,
    parent: parent,
    ctime: now - minutesAgo * 60,
    likes: likes,
    member: member,
    message: message,
    runs: RichText.runs(message, emotes: _refs(message), mentions: mentions, links: const {}),
    pictures: pictures,
    location: _places[place % _places.length],
    upLiked: upLiked,
  );

  static Map<String, EmoteRef> _refs(String message) => {
    for (final package in emotes)
      if (!package.isText)
        for (final emote in package.emotes)
          if (message.contains(emote.token)) emote.token: EmoteRef(url: emote.url, size: emote.large ? 2 : 1),
  };
}
