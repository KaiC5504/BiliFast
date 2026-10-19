import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comment_badges.dart';
import 'package:bilifast/comments/comment_callbacks.dart';
import 'package:bilifast/comments/comment_row.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/comments/rich_text_view.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the reactions the row asks for; [own] stands in for the logged-in viewer's comments.
class _Model extends CommentsModel {
  _Model({this.own = false, super.upMid = 99})
    : super(
        aid: 1,
        api: FakePageApi(),
        drafts: CommentDrafts(),
        isLoggedIn: () => true,
        accountMid: () => 5,
        requestLogin: () {},
        toast: (_) {},
      );

  final bool own;
  final likes = <int>[];
  final hates = <int>[];

  @override
  bool isOwn(Comment comment) => own;

  @override
  Future<void> toggleLike(Comment comment) async => likes.add(comment.rpid);

  @override
  Future<void> toggleHate(Comment comment) async => hates.add(comment.rpid);
}

class _Calls {
  final replies = <(ReplyTarget, bool)>[];
  final threads = <int>[];
  final pictures = <(List<CommentPicture>, int)>[];
  final deletes = <int>[];

  void seek(int seconds) {}
  void openVideo(String id) {}

  late final callbacks = CommentCallbacks(
    reply: (target, emotes) => replies.add((target, emotes)),
    openThread: (root) => threads.add(root.rpid),
    viewPictures: (pictures, index) => this.pictures.add((pictures, index)),
    confirmDelete: (comment) => deletes.add(comment.rpid),
    seek: seek,
    openVideo: openVideo,
  );
}

int _ago(Duration elapsed) => DateTime.now().subtract(elapsed).millisecondsSinceEpoch ~/ 1000;

Comment _comment({
  int rpid = 1,
  int root = 0,
  int mid = 2,
  String name = '殇泪丶丿',
  int level = 6,
  bool vip = false,
  String? pendant,
  String? card,
  String? cardNumber,
  String? cardColour,
  String message = '拳头的规则',
  int likes = 0,
  int action = 0,
  int replyCount = 0,
  List<Comment> previews = const [],
  List<CommentPicture> pictures = const [],
  bool pinned = false,
  bool upLiked = false,
  String? location = '湖北',
}) => Comment(
  rpid: rpid,
  root: root,
  mid: mid,
  ctime: _ago(const Duration(hours: 1, minutes: 5)),
  likes: likes,
  action: action,
  replyCount: replyCount,
  location: location,
  member: CommentMember(
    mid: mid,
    name: name,
    level: level,
    isVip: vip,
    pendant: pendant,
    fanCardImage: card,
    fanCardNumber: cardNumber,
    fanCardColor: cardColour,
  ),
  message: message,
  pictures: pictures,
  isPinned: pinned,
  upLiked: upLiked,
  previewReplies: previews,
);

Future<void> _mount(WidgetTester tester, Widget row, {bool reduceMotion = false}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: const Size(440, 956), disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          key: UniqueKey(),
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (context, _, _) => Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(child: SizedBox(width: 440, child: row)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

CommentRow _row(
  Comment comment,
  _Model model,
  _Calls calls, {
  Comment? thread,
  bool replies = true,
  bool divider = true,
}) => CommentRow(
  comment: comment,
  model: model,
  callbacks: calls.callbacks,
  thread: thread,
  showsReplies: replies,
  showsDivider: divider,
);

Color? _colour(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// The paragraph [CommentText] lays its runs out in, whatever it wraps it in.
RenderParagraph _paragraph(WidgetTester tester, Finder text) {
  RenderParagraph? find(RenderObject node) {
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((child) => found ??= find(child));
    return found;
  }

  return find(tester.renderObject(text))!;
}

void main() {
  group('name and badges', () {
    testWidgets('a 大会员 name is pink, anyone else\'s grey', (tester) async {
      await _mount(tester, _row(_comment(vip: true), _Model(), _Calls()));
      expect(_colour(tester, '殇泪丶丿'), CommentRowTheme.vipName);

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(_colour(tester, '殇泪丶丿'), CommentRowTheme.name);
    });

    testWidgets('the LV badge reads its level, kept to LV0-LV6, 5 after the name', (tester) async {
      await _mount(tester, _row(_comment(level: 4), _Model(), _Calls()));
      expect(find.bySemanticsLabel('LV4'), findsOneWidget);
      final badge = _rect(tester, find.byType(LevelBadge));
      expect(badge.width, closeTo(CommentRowTheme.levelWidth, 0.01));
      expect(badge.height, closeTo(CommentRowTheme.levelHeight, 0.01));
      expect(badge.left - _rect(tester, find.text('殇泪丶丿')).right, closeTo(CommentRowTheme.badgeGap, 0.01));

      await _mount(tester, _row(_comment(level: 9), _Model(), _Calls()));
      expect(find.bySemanticsLabel('LV6'), findsOneWidget);
    });

    testWidgets('UP marks the uploader\'s own comment only', (tester) async {
      await _mount(tester, _row(_comment(mid: 99), _Model(), _Calls()));
      expect(find.byType(UpBadge), findsOneWidget);

      await _mount(tester, _row(_comment(mid: 3), _Model(), _Calls()));
      expect(find.byType(UpBadge), findsNothing);

      await _mount(tester, _row(_comment(mid: 0), _Model(upMid: 0), _Calls()));
      expect(find.byType(UpBadge), findsNothing, reason: 'an unknown uploader is nobody');
    });

    testWidgets('置顶 leads a pinned comment\'s text', (tester) async {
      await _mount(tester, _row(_comment(pinned: true), _Model(), _Calls()));
      expect(find.text('置顶'), findsOneWidget);
      expect(tester.widget<CommentText>(find.byType(CommentText)).leading, isA<WidgetSpan>());

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.text('置顶'), findsNothing);
      expect(tester.widget<CommentText>(find.byType(CommentText)).leading, isNull);
    });

    testWidgets('UP主觉得很赞 shows under the meta line in the list only', (tester) async {
      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls()));
      expect(find.text('UP主觉得很赞'), findsOneWidget);

      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls(), replies: false));
      expect(find.text('UP主觉得很赞'), findsNothing);
    });
  });

  group('avatar', () {
    testWidgets('a pendant shrinks the face to 24 inside a 42 frame on the same centre', (tester) async {
      await _mount(tester, _row(_comment(pendant: 'https://i0.hdslb.com/bfs/garb/p.png'), _Model(), _Calls()));
      final avatar = _rect(tester, find.byType(CommentAvatar));
      expect(avatar.topLeft, const Offset(12, CommentRowTheme.avatarTop));
      expect(avatar.width, closeTo(30, 0.01));
      expect(avatar.height, closeTo(30, 0.01));
      final frame = _rect(tester, find.byKey(const ValueKey('comment-pendant')));
      expect(frame.width, closeTo(42, 0.01));
      expect((frame.center - avatar.center).distance, closeTo(0, 0.01));
      final face = _rect(tester, find.descendant(of: find.byType(CommentAvatar), matching: find.byType(ClipOval)));
      expect(face.width, closeTo(24, 0.01));

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.byKey(const ValueKey('comment-pendant')), findsNothing);
      final plain = _rect(tester, find.descendant(of: find.byType(CommentAvatar), matching: find.byType(ClipOval)));
      expect(plain.width, closeTo(30, 0.01));
    });

    testWidgets('大会员 get the pink 大 at the avatar\'s lower right', (tester) async {
      await _mount(tester, _row(_comment(vip: true), _Model(), _Calls()));
      final avatar = _rect(tester, find.byType(CommentAvatar));
      final mark = _rect(tester, find.byKey(const ValueKey('comment-vip')));
      expect(mark.width, closeTo(CommentRowTheme.vipMark + 2 * CommentRowTheme.vipMarkRing, 0.01));
      expect(avatar.right - mark.right, closeTo(CommentRowTheme.vipMarkRight - CommentRowTheme.vipMarkRing, 0.01));
      expect(avatar.bottom - mark.bottom, closeTo(CommentRowTheme.vipMarkBottom - CommentRowTheme.vipMarkRing, 0.01));

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.byKey(const ValueKey('comment-vip')), findsNothing);
    });

    testWidgets('a tap on the avatar asks nothing of the page', (tester) async {
      final calls = _Calls();
      await _mount(tester, _row(_comment(), _Model(), calls));
      await tester.tap(find.byType(CommentAvatar));
      expect(calls.replies, isEmpty);
      expect(calls.threads, isEmpty);
    });
  });

  group('fan card', () {
    testWidgets('the number sits 31 into the card, in the card\'s colour or the gold one', (tester) async {
      await _mount(
        tester,
        _row(
          _comment(card: 'https://i0.hdslb.com/bfs/garb/c.png', cardNumber: '017949', cardColour: '#f35543'),
          _Model(),
          _Calls(),
        ),
      );
      final number = tester.widget<FanNumber>(find.byType(FanNumber));
      expect(number.number, '017949');
      expect(number.color, const Color(0xFFF35543));
      final card = _rect(tester, find.byType(FanCard));
      expect(card.left, 440 - CommentRowTheme.fanCardLeft);
      expect(card.top, CommentRowTheme.fanCardTop);
      expect(_rect(tester, find.byType(FanNumber)).left - card.left, CommentRowTheme.fanNumberLead);

      await _mount(
        tester,
        _row(_comment(card: 'https://i0.hdslb.com/bfs/garb/c.png', cardNumber: '1'), _Model(), _Calls()),
      );
      expect(tester.widget<FanNumber>(find.byType(FanNumber)).color, CommentRowTheme.fanNumber);

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.byType(FanCard), findsNothing);
    });

    testWidgets('a long name stops short of the card', (tester) async {
      final long = '名' * 40;
      await _mount(tester, _row(_comment(name: long, card: 'https://i0.hdslb.com/bfs/garb/c.png'), _Model(), _Calls()));
      expect(
        _rect(tester, find.byType(LevelBadge)).right,
        lessThanOrEqualTo(440 - CommentRowTheme.fanCardLeft - CommentRowTheme.fanCardClearance),
      );
    });
  });

  group('text', () {
    testWidgets('timestamps and video ids in the text go to the page', (tester) async {
      final calls = _Calls();
      await _mount(tester, _row(_comment(message: '看 1:23 和 BV1xx411c7mD'), _Model(), calls));
      final text = tester.widget<CommentText>(find.byType(CommentText));
      expect(text.onSeek, calls.callbacks.seek);
      expect(text.onOpenVideo, calls.callbacks.openVideo);
      expect(text.style.fontSize, CommentRowTheme.textText);
      expect(text.style.color, CommentRowTheme.text);
    });

    testWidgets('a reply\'s 回复 @name : shows the name as a mention', (tester) async {
      await _mount(tester, _row(_comment(root: 9, message: '回复 @Wormkids :没人看的'), _Model(), _Calls()));
      final text = tester.widget<CommentText>(find.byType(CommentText));
      expect(text.marksReplyTarget, isTrue);
      expect(markingReplyTarget(text.runs), const [
        RichRun.text('回复 '),
        RichRun.mention(name: 'Wormkids', mid: 0),
        RichRun.text(' :没人看的'),
      ]);
    });
  });

  group('pictures', () {
    testWidgets('one picture: tall ones 162 wide cut at 3:4, wide ones 240 no flatter than 16:9', (tester) async {
      Size single(double width, double height, {bool compact = false}) => CommentPictures.single(
        CommentPicture(url: 'a', width: width, height: height),
        compact: compact,
      );
      expect(single(1000, 3000), const Size(162, 216));
      expect(single(1000, 1200), const Size(162, 194.4));
      expect(single(1000, 1000), const Size(162, 162));
      expect(single(1600, 900), const Size(240, 135));
      expect(single(3000, 500), const Size(240, 135));
      expect(single(0, 0), const Size(162, 162), reason: 'no size known');
      expect(single(1000, 3000, compact: true), const Size(135, 180));
      expect(single(1600, 900, compact: true), const Size(200, 112.5));
    });

    testWidgets('评论详情 shows the single picture smaller (13)', (tester) async {
      const picture = CommentPicture(url: 'https://i0.hdslb.com/bfs/a.png', width: 1000, height: 3000);
      await _mount(tester, _row(_comment(pictures: const [picture]), _Model(), _Calls()));
      expect(_rect(tester, find.byKey(const ValueKey('comment-picture-0'))).size, const Size(162, 216));
      expect(_rect(tester, find.byKey(const ValueKey('comment-picture-0'))).topLeft, const Offset(56, 200 / 3));

      await _mount(tester, _row(_comment(pictures: const [picture]), _Model(), _Calls(), replies: false));
      expect(_rect(tester, find.byKey(const ValueKey('comment-picture-0'))).size, const Size(135, 180));
    });

    testWidgets('two side by side, four in two rows, others in rows of three', (tester) async {
      Future<List<Rect>> grid(int count) async {
        final pictures = [for (var i = 0; i < count; i++) CommentPicture(url: 'p$i', width: 10, height: 10)];
        await _mount(tester, _row(_comment(pictures: pictures), _Model(), _Calls()));
        return [for (var i = 0; i < count; i++) _rect(tester, find.byKey(ValueKey('comment-picture-$i')))];
      }

      const column = 440 - 56 - 12.0;
      const spacing = CommentRowTheme.pictureSpacing;
      const third = (column - spacing * 2) / 3;

      final two = await grid(2);
      expect(two[0].width, closeTo((column - spacing) / 2, 0.01));
      expect(two[1].top, two[0].top);

      final four = await grid(4);
      expect(four[0].width, closeTo(third, 0.01));
      expect(four[1].top, four[0].top);
      expect(four[2].left, four[0].left);
      expect(four[2].top, closeTo(four[0].bottom + spacing, 0.01));

      final nine = await grid(9);
      expect(nine[2].top, nine[0].top);
      expect(nine[3].left, nine[0].left);
      expect(nine[8].right, closeTo(56 + column, 0.01));
    });

    testWidgets('a tap opens the viewer at that picture', (tester) async {
      final calls = _Calls();
      final pictures = [for (var i = 0; i < 3; i++) CommentPicture(url: 'p$i', width: 10, height: 10)];
      await _mount(tester, _row(_comment(pictures: pictures), _Model(), calls));
      await tester.tap(find.byKey(const ValueKey('comment-picture-1')));
      expect(calls.pictures.single.$1, pictures);
      expect(calls.pictures.single.$2, 1);
    });

    test('pictures load scaled from Bilibili\'s image servers', () {
      expect(
        CommentPictures.thumbnail('https://i0.hdslb.com/bfs/new_dyn/a.png', width: 480),
        'https://i0.hdslb.com/bfs/new_dyn/a.png@480w.webp',
      );
      expect(
        CommentPictures.thumbnail('//i0.hdslb.com/bfs/new_dyn/a.png', width: 480),
        'https://i0.hdslb.com/bfs/new_dyn/a.png@480w.webp',
      );
      expect(
        CommentPictures.thumbnail('https://i0.hdslb.com/bfs/a.png@1e_1c.webp', width: 480),
        'https://i0.hdslb.com/bfs/a.png@1e_1c.webp',
      );
      expect(CommentPictures.thumbnail('https://example.com/a.png', width: 480), 'https://example.com/a.png');
    });
  });

  group('meta line', () {
    testWidgets('time and place, then 回复, as on 10', (tester) async {
      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.text('1小时前 湖北'), findsOneWidget);
      expect(_colour(tester, '1小时前 湖北'), CommentRowTheme.meta);
      expect(_colour(tester, '回复'), CommentRowTheme.action);

      await _mount(tester, _row(_comment(location: null), _Model(), _Calls()));
      expect(find.text('1小时前'), findsOneWidget);
    });

    testWidgets('回复 answers the comment, or inside a thread the reply under its root', (tester) async {
      final calls = _Calls();
      final root = _comment(rpid: 1);
      await _mount(tester, _row(root, _Model(), calls));
      await tester.tap(find.byKey(const ValueKey('comment-reply')));
      expect(calls.replies.last, (ReplyToComment(root), false));

      final reply = _comment(rpid: 7, root: 1);
      await _mount(tester, _row(reply, _Model(), calls, thread: root, replies: false));
      await tester.tap(find.byKey(const ValueKey('comment-reply')));
      expect(calls.replies.last, (ReplyInThread(root: root, reply: reply), false));

      await _mount(tester, _row(root, _Model(), calls, thread: root, replies: false));
      await tester.tap(find.byKey(const ValueKey('comment-reply')));
      expect(calls.replies.last, (ReplyToComment(root), false), reason: 'the thread\'s own root');
    });

    testWidgets('👍 and 👎 go to the model', (tester) async {
      final model = _Model();
      await _mount(tester, _row(_comment(rpid: 4), model, _Calls()));
      await tester.tap(find.byKey(const ValueKey('comment-like')));
      await tester.tap(find.byKey(const ValueKey('comment-dislike')));
      expect(model.likes, [4]);
      expect(model.hates, [4]);
    });

    testWidgets('a liked comment\'s 👍 and count are pink and solid; a disliked one\'s 👎 solid', (tester) async {
      await _mount(tester, _row(_comment(likes: 60, action: 1), _Model(), _Calls()));
      final like = tester.widget<CommentThumb>(
        find.descendant(of: find.byKey(const ValueKey('comment-like')), matching: find.byType(CommentThumb)),
      );
      expect(like.solid, isTrue);
      expect(like.color, CommentRowTheme.liked);
      expect(_colour(tester, '60'), CommentRowTheme.liked);

      await _mount(tester, _row(_comment(likes: 60, action: 2), _Model(), _Calls()));
      final hate = tester.widget<CommentThumb>(
        find.descendant(of: find.byKey(const ValueKey('comment-dislike')), matching: find.byType(CommentThumb)),
      );
      expect(hate.solid, isTrue);
      expect(hate.down, isTrue);
      expect(_colour(tester, '60'), CommentRowTheme.action);
    });

    testWidgets('the count ends 73.7 from the right edge, 👎 and ⋮ at their places (10)', (tester) async {
      await _mount(tester, _row(_comment(likes: 12000), _Model(), _Calls()));
      expect(find.text('1.2万'), findsOneWidget);
      expect(_rect(tester, find.text('1.2万')).right, closeTo(440 - CommentRowTheme.likeTrailing, 0.01));
      final thumbs = find.byType(CommentThumb);
      expect(_rect(tester, thumbs.at(1)).center.dx, closeTo(440 - CommentRowTheme.dislikeCentre, 0.01));
      expect(_rect(tester, find.byKey(const ValueKey('comment-more'))).center.dx, 440 - CommentRowTheme.moreCentre);

      await _mount(tester, _row(_comment(likes: 0), _Model(), _Calls()));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('👍 swells once as it turns pink, not with Reduce Motion', (tester) async {
      Future<double> scaleAfterLiking({required bool reduceMotion}) async {
        final model = _Model();
        final comment = ValueNotifier(_comment());
        addTearDown(comment.dispose);
        await _mount(
          tester,
          ValueListenableBuilder(
            valueListenable: comment,
            builder: (context, value, _) => _row(value, model, _Calls()),
          ),
          reduceMotion: reduceMotion,
        );
        comment.value = _comment(action: 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final scale = tester
            .widget<ScaleTransition>(
              find.descendant(of: find.byKey(const ValueKey('comment-like')), matching: find.byType(ScaleTransition)),
            )
            .scale
            .value;
        await tester.pumpAndSettle();
        return scale;
      }

      expect(await scaleAfterLiking(reduceMotion: false), greaterThan(1.05));
      expect(await scaleAfterLiking(reduceMotion: true), 1);
    });

    testWidgets('⋮ → 复制 copies the text and says so', (tester) async {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String?);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _mount(tester, _row(_comment(message: '拳头的规则'), _Model(), _Calls()));
      await tester.tap(find.byKey(const ValueKey('comment-more')));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsNothing, reason: 'not the viewer\'s comment');
      await tester.tap(find.text('复制'));
      await tester.pump();
      expect(copied, ['拳头的规则']);
      expect(find.text('已复制'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('⋮ → 删除 on the viewer\'s own comment asks the page to confirm', (tester) async {
      final calls = _Calls();
      await _mount(tester, _row(_comment(rpid: 6), _Model(own: true), calls));
      await tester.tap(find.byKey(const ValueKey('comment-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(calls.deletes, [6]);
      expect(find.text('复制'), findsNothing, reason: 'the menu closed');
    });

    testWidgets('a long press on the text opens the same menu', (tester) async {
      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      await tester.longPress(find.byType(CommentText));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
    });
  });

  group('replies box', () {
    Comment reply(int rpid, String name, String text, {int likes = 0}) => Comment(
      rpid: rpid,
      root: 1,
      likes: likes,
      member: CommentMember(mid: rpid, name: name),
      message: text,
    );

    testWidgets('共N条回复 alone is a 36 pt box 54 from the left; a tap opens the thread', (tester) async {
      final calls = _Calls();
      await _mount(tester, _row(_comment(replyCount: 12), _Model(), calls));
      expect(find.text('共12条回复'), findsOneWidget);
      expect(_colour(tester, '共12条回复'), CommentRowTheme.moreLink);
      final box = _rect(tester, find.byKey(const ValueKey('comment-replies')));
      expect(box.left, CommentRowTheme.boxLeading);
      expect(box.right, 440 - CommentRowTheme.gutter);
      expect(box.height, CommentRowTheme.moreSlot);
      await tester.tap(find.byKey(const ValueKey('comment-replies')));
      expect(calls.threads, [1]);
    });

    testWidgets('up to two previews as "name: text", the name grey', (tester) async {
      await _mount(
        tester,
        _row(
          _comment(replyCount: 28, previews: [reply(2, '甲', '第一条'), reply(3, '乙', '第二条'), reply(4, '丙', '第三条')]),
          _Model(),
          _Calls(),
        ),
      );
      final texts = tester.widgetList<CommentText>(find.byType(CommentText)).skip(1).toList();
      expect(texts, hasLength(2));
      final leading = texts.first.leading! as TextSpan;
      expect(leading.toPlainText(), '甲: ');
      expect((leading.children!.first as TextSpan).style?.color, CommentRowTheme.previewName);
      expect(texts.first.maxLines, 2);
      expect(texts.first.style.color, CommentRowTheme.preview);
    });

    testWidgets('a preview\'s likes follow its text; a long one is cut short for them, the first line kept whole', (
      tester,
    ) async {
      await _mount(
        tester,
        _row(_comment(replyCount: 3, previews: [reply(2, '甲', '短', likes: 51)]), _Model(), _Calls()),
      );
      final text = _paragraph(tester, find.byType(CommentText).last);
      expect(_rect(tester, find.text('51')).left, greaterThan(text.localToGlobal(Offset.zero).dx + text.size.width));
      expect(text.size.width, lessThan(100));

      await _mount(
        tester,
        _row(_comment(replyCount: 3, previews: [reply(2, '甲', '很长的回复' * 20, likes: 51)]), _Model(), _Calls()),
      );
      final box = _rect(tester, find.byKey(const ValueKey('comment-replies')));
      final long = _paragraph(tester, find.byType(CommentText).last);
      expect(long.size.width, greaterThan(box.width - 2 * CommentRowTheme.boxPadding - 20));
      expect(_rect(tester, find.text('51')).right, lessThanOrEqualTo(box.right - CommentRowTheme.boxPadding));
    });

    testWidgets('no box in a thread, nor without replies', (tester) async {
      await _mount(tester, _row(_comment(replyCount: 12), _Model(), _Calls(), replies: false));
      expect(find.byKey(const ValueKey('comment-replies')), findsNothing);

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.byKey(const ValueKey('comment-replies')), findsNothing);
    });
  });

  group('layout', () {
    testWidgets('a one-line comment is 99.7 tall with its hairline from 54 at the bottom (13)', (tester) async {
      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      final row = _rect(tester, find.byType(CommentRow));
      expect(row.height, closeTo(CommentRowTheme.textMinBottom + 24 + 9, 0.01));
      final divider = _rect(tester, find.byKey(const ValueKey('comment-divider')));
      expect(divider, Rect.fromLTRB(54, row.bottom - CommentRowTheme.divider, 440, row.bottom));
      expect(_rect(tester, find.byType(CommentAvatar)).topLeft, const Offset(12, CommentRowTheme.avatarTop));

      await _mount(tester, _row(_comment(), _Model(), _Calls(), divider: false));
      expect(find.byKey(const ValueKey('comment-divider')), findsNothing);
      expect(_rect(tester, find.byType(CommentRow)).height, closeTo(row.height, 0.01));
    });

    testWidgets('longer text pushes the meta line down a line at a time', (tester) async {
      await _mount(tester, _row(_comment(message: '字' * 60), _Model(), _Calls()));
      final paragraph = _paragraph(tester, find.byType(CommentText));
      final lines = paragraph.size.height / CommentRowTheme.textLine;
      expect(lines, greaterThan(2));
      expect(
        _rect(tester, find.byType(CommentRow)).height,
        closeTo(CommentRowTheme.textTop + lines * CommentRowTheme.textLine + 24 + 9, 0.01),
      );
    });
  });

  group('accessibility', () {
    testWidgets('every control is a labelled button', (tester) async {
      final handle = tester.ensureSemantics();
      await _mount(
        tester,
        _row(
          _comment(likes: 60, replyCount: 12, pictures: const [CommentPicture(url: 'a', width: 10, height: 10)]),
          _Model(),
          _Calls(),
        ),
      );
      for (final label in ['回复', '点赞 60', '点踩', '更多', '共12条回复', '图片 1']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(label: label, isButton: true, hasTapAction: true),
          reason: label,
        );
      }
      handle.dispose();
    });

    testWidgets('a liked 👍 and a disliked 👎 read as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await _mount(tester, _row(_comment(likes: 1, action: 1), _Model(), _Calls()));
      expect(
        tester.getSemantics(find.bySemanticsLabel('点赞 1')),
        isSemantics(label: '点赞 1', isButton: true, hasTapAction: true, isSelected: true),
      );
      handle.dispose();
    });
  });
}
