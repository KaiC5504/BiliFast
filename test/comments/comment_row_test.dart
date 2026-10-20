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
  });

  group('UP主觉得很赞', () {
    Finder thumb() =>
        find.byWidgetPredicate((widget) => widget is CommentThumb && widget.width == CommentRowTheme.upLikedIcon);
    Finder chip() => find.byKey(const ValueKey('comment-up-liked'));
    Rect metaLine(WidgetTester tester) => _rect(tester, find.byKey(const ValueKey('comment-like')));

    void systemFont() {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      BiliFonts.family = BiliFonts.system;
    }

    testWidgets('in the list: a thumb and grey text in 18 under the meta line, no box', (tester) async {
      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls()));
      expect(thumb(), findsOneWidget);
      expect(chip(), findsNothing);
      expect(_colour(tester, 'UP主觉得很赞'), CommentRowTheme.upLiked);
      final row = _rect(tester, find.byType(CommentRow));
      expect(row.bottom - metaLine(tester).bottom, closeTo(CommentRowTheme.upLikedHeight + 9, 0.01));
    });

    testWidgets('in a thread: 10 pt #757575 in a #F4F4F4 box 16 tall and 2 round, 9.5 under the meta line at the '
        'text\'s left, 13/3 either side of the text (font-check 04)', (tester) async {
      systemFont();
      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls(), replies: false, divider: false));
      expect(thumb(), findsNothing);
      final box = _rect(tester, chip());
      final text = _rect(tester, find.text('UP主觉得很赞'));
      expect(box.left, CommentRowTheme.textLeading);
      expect(box.top - metaLine(tester).bottom, closeTo(9.5, 0.01));
      expect(box.height, closeTo(16, 0.01));
      expect(box.width, closeTo(text.width + 26 / 3, 0.01));
      expect(text.left - box.left, closeTo(13 / 3, 0.01));
      expect(text.center.dy, closeTo(box.center.dy, 0.01));
      final decoration = tester.widget<DecoratedBox>(chip()).decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFF4F4F4));
      expect(decoration.borderRadius, const BorderRadius.all(Radius.circular(2)));
      final style = tester.renderObject<RenderParagraph>(find.text('UP主觉得很赞')).text.style!;
      expect(style.color, const Color(0xFF757575));
      expect(style.fontSize, 10);
      expect(style.letterSpacing, 0.4);
      expect(style.fontFamily, BiliFonts.system);
    });

    testWidgets('the root\'s band starts 8 under the box; a reply\'s hairline does too', (tester) async {
      systemFont();
      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls(), replies: false, divider: false));
      expect(_rect(tester, find.byType(CommentRow)).bottom - _rect(tester, chip()).bottom, closeTo(8, 0.01));

      final root = _comment(rpid: 9);
      await _mount(tester, _row(_comment(root: 9, upLiked: true), _Model(), _Calls(), thread: root, replies: false));
      final divider = _rect(tester, find.byKey(const ValueKey('comment-divider')));
      expect(divider.top - _rect(tester, chip()).bottom, closeTo(8, 0.01));
      expect(divider.bottom, _rect(tester, find.byType(CommentRow)).bottom);
    });

    testWidgets('the box moves the root\'s band 26 lower: 20 under the meta text without it, 46 with it (13, '
        'font-check 04)', (tester) async {
      systemFont();
      double band(WidgetTester tester) => _rect(tester, find.byType(CommentRow)).bottom - metaLine(tester).bottom;
      await _mount(tester, _row(_comment(), _Model(), _Calls(), replies: false, divider: false));
      final without = band(tester);
      expect(without, closeTo(7.5, 0.01), reason: 'the system font\'s meta text sits 0.5 above the line\'s centre');
      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls(), replies: false, divider: false));
      expect(band(tester) - without, closeTo(26, 0.01));
    });

    testWidgets('MiSans keeps the root\'s band a hairline\'s room under the meta line, and its lower meta text puts '
        'the box 11.2 under the line', (tester) async {
      await _mount(tester, _row(_comment(), _Model(), _Calls(), replies: false, divider: false));
      expect(_rect(tester, find.byType(CommentRow)).bottom - metaLine(tester).bottom, closeTo(9, 0.01));

      await _mount(tester, _row(_comment(upLiked: true), _Model(), _Calls(), replies: false, divider: false));
      final box = _rect(tester, chip());
      expect(box.top - metaLine(tester).bottom, closeTo(11.2, 0.01));
      expect(_rect(tester, find.byType(CommentRow)).bottom - box.bottom, closeTo(8, 0.01));
    });

    testWidgets('nothing under a comment the uploader didn\'t like, in the list or a thread', (tester) async {
      for (final replies in [true, false]) {
        await _mount(tester, _row(_comment(), _Model(), _Calls(), replies: replies, divider: replies));
        expect(find.text('UP主觉得很赞'), findsNothing);
        expect(chip(), findsNothing);
        expect(thumb(), findsNothing);
      }
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

    testWidgets('a reply\'s 回复 @name : reads 回复 name: with the name grey, as on font-check 04', (tester) async {
      await _mount(tester, _row(_comment(root: 9, message: '回复 @Wormkids :没人看的'), _Model(), _Calls()));
      final text = tester.widget<CommentText>(find.byType(CommentText));
      expect(text.marksReplyTarget, isTrue);
      expect(find.text('回复 Wormkids: 没人看的', findRichText: true), findsOneWidget);
      final spans = <TextSpan>[];
      _paragraph(tester, find.byType(CommentText)).text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      final name = spans.singleWhere((span) => span.text == 'Wormkids');
      expect(name.style?.color, CommentTextTheme.replyTarget);
      expect(name.recognizer, isNull);
      expect(spans.where((span) => span.text!.contains('@')), isEmpty);
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

    testWidgets('the count ends 73 from the right edge, 👎 and ⋮ at their places (10)', (tester) async {
      await _mount(tester, _row(_comment(likes: 12000), _Model(), _Calls()));
      expect(find.text('1.2万'), findsOneWidget);
      expect(_rect(tester, find.text('1.2万')).right, closeTo(440 - CommentRowTheme.likeTrailing, 0.01));
      final thumbs = find.byType(CommentThumb);
      expect(_rect(tester, thumbs.at(1)).center.dx, closeTo(440 - CommentRowTheme.dislikeCentre, 0.01));
      expect(_rect(tester, find.byKey(const ValueKey('comment-more'))).center.dx, 440 - CommentRowTheme.moreCentre);

      await _mount(tester, _row(_comment(likes: 0), _Model(), _Calls()));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('⋮ centres the line 16 below the pictures; 👍 sits 2 px above it and 👎 2 px below (font-check 04)', (
      tester,
    ) async {
      final pictures = [for (var i = 0; i < 3; i++) CommentPicture(url: 'p$i', width: 10, height: 10)];
      await _mount(tester, _row(_comment(likes: 513, pictures: pictures), _Model(), _Calls(), replies: false));
      final bottom = _rect(tester, find.byKey(const ValueKey('comment-picture-0'))).bottom;
      final more = _rect(tester, find.byKey(const ValueKey('comment-more'))).center.dy;
      expect(more - bottom, closeTo(16, 0.01));
      final like = _rect(
        tester,
        find.descendant(of: find.byKey(const ValueKey('comment-like')), matching: find.byType(CommentThumb)),
      );
      final hate = _rect(
        tester,
        find.descendant(of: find.byKey(const ValueKey('comment-dislike')), matching: find.byType(CommentThumb)),
      );
      expect(like.center.dy - bottom, closeTo(46 / 3, 0.01));
      expect(hate.center.dy - more, closeTo(2 / 3, 0.01));
      expect(
        _rect(tester, find.text('513')).center.dy,
        closeTo(more + CommentRowTheme.metaDrop, 0.01),
        reason: 'the count stays on the line',
      );
    });

    testWidgets('⋮\'s dots are 6.4 px across and 13 px apart (font-check 04, 13)', (tester) async {
      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      final dots = tester.widget<CustomPaint>(
        find.descendant(of: find.byKey(const ValueKey('comment-more')), matching: find.byType(CustomPaint)),
      );
      expect(dots.size.width, closeTo(6.4 / 3, 1e-9));
      expect(dots.size.height, closeTo((6.4 + 26) / 3, 1e-9));
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

    testWidgets('a long press on the text opens the same menu with a selection tick', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      await tester.longPress(find.byType(CommentText));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('a long comment\'s menu opens at the finger and stays on screen', (tester) async {
      // Scrolled so the text's top is far above the screen, as under the player.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(440, 956), padding: EdgeInsets.only(top: 62, bottom: 34)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (context, _, _) => OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: Transform.translate(
                    offset: const Offset(0, -2000),
                    child: SizedBox(width: 440, child: _row(_comment(message: '字' * 6000), _Model(), _Calls())),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPressAt(const Offset(200, 300));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byKey(const ValueKey('comment-copy')));
      expect(menu.top, greaterThan(300));
      expect(menu.top, lessThan(400));

      await tester.tapAt(const Offset(20, 900));
      await tester.pumpAndSettle();
      await tester.longPressAt(const Offset(200, 940));
      await tester.pumpAndSettle();
      final low = tester.getRect(find.byKey(const ValueKey('comment-copy')));
      expect(low.bottom, lessThanOrEqualTo(956 - 34));
      expect(low.top, greaterThanOrEqualTo(62));
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

    testWidgets('previews stack with no gap: lines 23 apart, the next preview 18.75 down, 共N条回复 26 below '
        '(differences 12)', (tester) async {
      await _mount(
        tester,
        _row(
          _comment(replyCount: 15, previews: [reply(2, '甲', '字' * 30, likes: 66), reply(3, '乙', '短', likes: 18)]),
          _Model(),
          _Calls(),
        ),
      );
      final box = _rect(tester, find.byKey(const ValueKey('comment-replies')));
      final texts = find.byType(CommentText);
      final first = _paragraph(tester, texts.at(1));
      final second = _paragraph(tester, texts.at(2));
      final firstTop = first.localToGlobal(Offset.zero).dy;
      final secondTop = second.localToGlobal(Offset.zero).dy;
      const half = CommentRowTheme.previewLine / 2;
      expect(first.size.height, CommentRowTheme.previewLine * 2);
      expect(firstTop + half - box.top, closeTo(16.67, 0.01));
      expect(secondTop + half - (firstTop + first.size.height - half), closeTo(18.75, 0.01));
      final more = _rect(tester, find.text('共15条回复'));
      expect(more.center.dy - (secondTop + half), closeTo(26, 0.01));
      expect(box.bottom - more.center.dy, closeTo(CommentRowTheme.moreSlot / 2, 0.01));
      expect(
        _rect(tester, find.text('66')).center.dy,
        closeTo(firstTop + first.size.height - half + CommentRowTheme.metaDrop, 0.5),
      );
    });

    testWidgets('a preview cut short stands 7 taller below its last line (12), with likes or without', (tester) async {
      for (final likes in [51, 0]) {
        await _mount(
          tester,
          _row(_comment(replyCount: 28, previews: [reply(2, '甲', '很长的回复' * 20, likes: likes)]), _Model(), _Calls()),
        );
        final text = _paragraph(tester, find.byType(CommentText).last);
        final lastLine = text.localToGlobal(Offset.zero).dy + text.size.height - CommentRowTheme.previewLine / 2;
        expect(_rect(tester, find.text('共28条回复')).center.dy - lastLine, closeTo(33, 0.01), reason: 'likes $likes');
      }
    });

    testWidgets('no box in a thread, nor without replies', (tester) async {
      await _mount(tester, _row(_comment(replyCount: 12), _Model(), _Calls(), replies: false));
      expect(find.byKey(const ValueKey('comment-replies')), findsNothing);

      await _mount(tester, _row(_comment(), _Model(), _Calls()));
      expect(find.byKey(const ValueKey('comment-replies')), findsNothing);
    });
  });

  group('layout', () {
    testWidgets(
      'the system font starts the text 1.4 lower and the box 1.75 and the hairline 0.83 higher; MiSans keeps the places from 10',
      (tester) async {
        final saved = BiliFonts.family;
        addTearDown(() => BiliFonts.family = saved);
        final comment = _comment(replyCount: 3);
        BiliFonts.family = BiliFonts.miSans;
        await _mount(tester, _row(comment, _Model(), _Calls()));
        final textMiSans = _rect(tester, find.byType(CommentText)).top;
        final boxMiSans = _rect(tester, find.byKey(const ValueKey('comment-replies'))).top;
        expect(textMiSans, closeTo(CommentRowTheme.textFirstCentre - CommentRowTheme.textLine / 2, 0.01));

        BiliFonts.family = BiliFonts.system;
        await _mount(tester, _row(comment, _Model(), _Calls()));
        expect(_rect(tester, find.byType(CommentText)).top - textMiSans, closeTo(1.4, 0.01));
        // A one-line comment keeps its meta line where it was, so only the box's own gap moves it.
        expect(_rect(tester, find.byKey(const ValueKey('comment-replies'))).top - boxMiSans, closeTo(-1.75, 0.01));

        BiliFonts.family = BiliFonts.miSans;
        await _mount(tester, _row(_comment(), _Model(), _Calls()));
        final heightMiSans = _rect(tester, find.byType(CommentRow)).height;
        BiliFonts.family = BiliFonts.system;
        await _mount(tester, _row(_comment(), _Model(), _Calls()));
        // 20 below the meta text, which sits 0.5 above the line's centre: 7.5 under the line against MiSans's 8.33.
        expect(_rect(tester, find.byType(CommentRow)).height - heightMiSans, closeTo(7.5 - (61 / 3 - 12), 0.01));
      },
    );

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

    testWidgets('a liked 👍 and a disliked 👎 read as selected, and not otherwise', (tester) async {
      final handle = tester.ensureSemantics();
      Matcher reads(String label, {required bool selected}) =>
          isSemantics(label: label, isButton: true, hasTapAction: true, hasSelectedState: true, isSelected: selected);

      await _mount(tester, _row(_comment(likes: 1, action: 1), _Model(), _Calls()));
      expect(tester.getSemantics(find.bySemanticsLabel('点赞 1')), reads('点赞 1', selected: true));
      expect(tester.getSemantics(find.bySemanticsLabel('点踩')), reads('点踩', selected: false));

      await _mount(tester, _row(_comment(likes: 1, action: 2), _Model(), _Calls()));
      expect(tester.getSemantics(find.bySemanticsLabel('点赞 1')), reads('点赞 1', selected: false));
      expect(tester.getSemantics(find.bySemanticsLabel('点踩')), reads('点踩', selected: true));
      handle.dispose();
    });
  });
}
