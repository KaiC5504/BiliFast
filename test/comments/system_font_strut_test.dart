import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/comment_row.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/comments/composer.dart';
import 'package:bilifast/comments/emote_panel.dart';
import 'package:bilifast/comments/mention_picker.dart';
import 'package:bilifast/comments/picture_attach.dart';
import 'package:bilifast/comments/rich_text_view.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stand_in_fonts.dart';
import 'comments_tab_test.dart' show FakeComments, Replies;
import 'composer_test.dart' show FakeComposerModel;

const _phone = Size(440, 956);
const _emoteUrl = 'https://i0.hdslb.com/bfs/emote/a.png';

/// The app's theme under the system font, so Chinese falls back to the PingFang stand-in as on the phone.
Future<void> _show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: BiliFonts.family,
        fontFamilyFallback: BiliFonts.fallback,
        textTheme: BiliFonts.untracked,
      ),
      home: MediaQuery(
        data: const MediaQueryData(size: _phone, padding: EdgeInsets.only(bottom: 34)),
        child: Material(
          color: BiliColors.card,
          child: PrimaryScrollController(
            controller: ScrollController(),
            child: PlayerReserve(height: 0, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// A laid-out box's first baseline, read outside its parent's layout as the intrinsics checks do.
double _baseline(RenderBox box) {
  RenderObject.debugCheckingIntrinsics = true;
  try {
    return box.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true)!;
  } finally {
    RenderObject.debugCheckingIntrinsics = false;
  }
}

/// A line of only Chinese in [style]: its height and baseline.
({double height, double baseline}) _chineseLine(TextStyle? style, TextScaler scaler, TextHeightBehavior? behavior) {
  final painter = TextPainter(
    text: TextSpan(text: '设置', style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    textHeightBehavior: behavior,
  )..layout();
  final line = (height: painter.height, baseline: painter.computeDistanceToActualBaseline(TextBaseline.alphabetic));
  painter.dispose();
  return line;
}

/// Where each line starts, from where a point at the left edge stops hitting the line above: a forced strut sets the
/// lines' boxes, which the glyph boxes don't show.
List<double> _lineTops(double height, int Function(double y) lineAt) {
  final tops = [0.0];
  var line = lineAt(0);
  for (var probe = 1.0; probe < height; probe++) {
    final next = lineAt(probe);
    if (next == line) continue;
    var above = probe - 1, below = probe;
    for (var i = 0; i < 40; i++) {
      final middle = (above + below) / 2;
      lineAt(middle) == line ? above = middle : below = middle;
    }
    tops.add(below);
    line = next;
  }
  return tops;
}

void _expectLines(double baseline, List<double> tops, ({double height, double baseline}) chinese, int? lines) {
  expect(baseline, closeTo(chinese.baseline, 0.01));
  expect(tops.length, lines ?? greaterThan(1));
  for (final (i, top) in tops.indexed) {
    expect(top, closeTo(i * chinese.height, 0.01), reason: 'line $i');
  }
}

/// [text]'s paragraph mixes Latin and Chinese, and every line of it sits as a Chinese-only line in its style would:
/// the same baseline and the same pitch. [lines] null means more than one.
void _expectChineseLines(WidgetTester tester, Finder text, {int? lines = 1}) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final plain = paragraph.text.toPlainText();
  expect(plain, matches(RegExp('[A-Za-z0-9]')), reason: 'the text mixes scripts');
  expect(plain, matches(RegExp('[\u3040-\u30ff\u4e00-\u9fff]')), reason: 'the text mixes scripts');
  final tops = _lineTops(paragraph.size.height, (y) => paragraph.getPositionForOffset(Offset(0, y)).offset);
  _expectLines(
    _baseline(paragraph),
    tops,
    _chineseLine(paragraph.text.style, paragraph.textScaler, paragraph.textHeightBehavior),
    lines,
  );
}

/// The same for a text field's typed text.
void _expectChineseField(WidgetTester tester, Finder field, {int? lines = 1}) {
  final editable = tester
      .state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)))
      .renderEditable;
  final chinese = _chineseLine(editable.text!.style, editable.textScaler, editable.textHeightBehavior);
  expect(editable.preferredLineHeight, closeTo(chinese.height, 0.01));
  final tops = _lineTops(
    editable.size.height,
    (y) => editable.getPositionForPoint(editable.localToGlobal(Offset(0, y))).offset,
  );
  _expectLines(_baseline(editable), tops, chinese, lines);
}

Comment _comment({
  int rpid = 1,
  String name = 'KaiC5504老番茄',
  String message = '拳头的规则',
  int likes = 0,
  int replyCount = 0,
  List<Comment> previews = const [],
  bool upLiked = false,
}) => Comment(
  rpid: rpid,
  mid: rpid * 10,
  ctime: DateTime.now().subtract(const Duration(hours: 1, minutes: 5)).millisecondsSinceEpoch ~/ 1000,
  likes: likes,
  replyCount: replyCount,
  location: '湖北',
  member: CommentMember(mid: rpid * 10, name: name),
  message: message,
  upLiked: upLiked,
  previewReplies: previews,
);

CommentsModel _model() => CommentsModel(
  aid: 1,
  upMid: 2,
  api: FakePageApi(),
  drafts: CommentDrafts(),
  isLoggedIn: () => true,
  accountMid: () => 3,
  requestLogin: () {},
  toast: (_) {},
);

Widget _row(Comment comment, {bool replies = true}) => Align(
  alignment: Alignment.topLeft,
  child: SingleChildScrollView(
    child: SizedBox(
      width: 440,
      child: CommentRow(comment: comment, model: _model(), callbacks: Replies().callbacks, showsReplies: replies),
    ),
  ),
);

void main() {
  setUp(() {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
  });

  testWidgets('a comment mixing Latin and Chinese keeps the Chinese line, wrapped or not', (tester) async {
    await tester.runAsync(loadSystemFontStandIns);
    await _show(tester, _row(_comment(message: 'KaiC 说 iPhone 17 Pro Max 上的 4K HDR 很好看，' * 3)));
    _expectChineseLines(
      tester,
      find.descendant(of: find.byType(CommentText), matching: find.byType(RichText)),
      lines: null,
    );
    await _show(tester, _row(_comment(message: 'Bilibili 2233 好耶')));
    _expectChineseLines(tester, find.descendant(of: find.byType(CommentText), matching: find.byType(RichText)));
  });

  group('a comment with an emote keeps its own lines, so the emote\'s line still grows', () {
    const style = TextStyle(fontSize: 15, height: 25 / 15, leadingDistribution: TextLeadingDistribution.even);
    Finder paragraph() => find.descendant(of: find.byType(CommentText), matching: find.byType(RichText));
    Future<void> show(WidgetTester tester, List<RichRun> runs) => _show(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 372,
          child: CommentText(runs: runs, style: style.copyWith(fontFamily: BiliFonts.family)),
        ),
      ),
    );

    testWidgets('2 pt below its text', (tester) async {
      await tester.runAsync(loadSystemFontStandIns);
      await show(tester, const [RichRun.text('重打了')]);
      final plain = tester.getSize(paragraph()).height;
      expect(plain, closeTo(25, 0.01));
      await show(tester, const [RichRun.text('重打了'), RichRun.emote(token: '[无语]', url: _emoteUrl, size: 1)]);
      expect(tester.getSize(paragraph()).height, closeTo(plain + CommentTextTheme.emoteLineGrowth, 0.01));
      expect(tester.renderObject<RenderParagraph>(paragraph()).strutStyle, isNull);
    });

    testWidgets('only that line', (tester) async {
      await tester.runAsync(loadSystemFontStandIns);
      final line = '回溯' * 10;
      List<double> tops() {
        final text = tester.renderObject<RenderParagraph>(paragraph());
        return _lineTops(text.size.height, (y) => text.getPositionForOffset(Offset(0, y)).offset);
      }

      await show(tester, [RichRun.text('$line\n$line\n$line')]);
      final plain = tops();
      expect(plain, [for (final top in [0, 25, 50]) closeTo(top, 0.01)]);
      await show(tester, [
        RichRun.text('$line\n$line'),
        const RichRun.emote(token: '[无语]', url: _emoteUrl, size: 1),
        RichRun.text('\n$line'),
      ]);
      expect(tops(), [for (final top in [0, 25, 52]) closeTo(top, 0.01)]);
      expect(tester.getSize(paragraph()).height, closeTo(75 + CommentTextTheme.emoteLineGrowth, 0.01));
    });
  });

  testWidgets('the row\'s name, time, likes, UP主觉得很赞, 共N条回复 and reply previews keep the Chinese line', (
    tester,
  ) async {
    await tester.runAsync(loadSystemFontStandIns);
    final preview = _comment(
      rpid: 2,
      name: 'Windows98es',
      message: '回复 KaiC：iPhone 上 4K 播放没有问题，HDR 也正常，' * 2,
      likes: 23000,
    );
    await _show(tester, _row(_comment(likes: 12000, replyCount: 12, previews: [preview], upLiked: true)));
    _expectChineseLines(tester, find.text('KaiC5504老番茄'));
    _expectChineseLines(tester, find.text('1小时前 湖北'));
    _expectChineseLines(tester, find.text('1.2万'));
    _expectChineseLines(tester, find.text('UP主觉得很赞'));
    _expectChineseLines(tester, find.text('共12条回复'));
    _expectChineseLines(
      tester,
      find.descendant(of: find.byType(CommentText).last, matching: find.byType(RichText)),
      lines: 2,
    );
    _expectChineseLines(tester, find.text('2.3万'));

    await _show(tester, _row(_comment(upLiked: true), replies: false));
    _expectChineseLines(tester, find.text('UP主觉得很赞'));
  });

  testWidgets('the sort header, the footer\'s reason, a closed section and the write bar keep the Chinese line', (
    tester,
  ) async {
    await tester.runAsync(loadSystemFontStandIns);
    await _show(tester, CommentSortHeader(title: '相关回复共12条', sort: CommentSort.time, onChange: (_) {}));
    _expectChineseLines(tester, find.text('相关回复共12条'));

    await _show(
      tester,
      CommentListFooter(loading: false, error: 'HTTP 412：请求被拦截', isEnd: false, isEmpty: false, onRetry: () {}),
    );
    _expectChineseLines(tester, find.text('HTTP 412：请求被拦截'));

    final closed = FakeComments(closedValue: 'UP主已关闭评论区');
    addTearDown(closed.dispose);
    await _show(tester, CommentsTab(model: closed, callbacks: Replies().callbacks));
    _expectChineseLines(tester, find.text('UP主已关闭评论区'));

    await _show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: CommentWriteBar(onWrite: (_) {}, prompt: 'UP主说：发条评论吧 2233'),
      ),
    );
    _expectChineseLines(tester, find.text('UP主说：发条评论吧 2233'));
  });

  testWidgets('the composer\'s typed text and its reply hint keep the Chinese line', (tester) async {
    await tester.runAsync(loadSystemFontStandIns);
    final model = FakeComposerModel(hint: '回复 KaiC5504 :');
    addTearDown(model.dispose);
    await _show(tester, Composer(model: model, onClose: () {}, pick: ({required limit}) async => const PicturePick([])));
    final hint = find.text('回复 KaiC5504 :');
    _expectChineseLines(tester, hint);
    final hintBaseline =
        tester.getTopLeft(hint).dy +
        _baseline(tester.renderObject<RenderParagraph>(hint));

    final field = find.byKey(const ValueKey('composer-field'));
    await tester.enterText(field, 'KaiC 说 iPhone 17 上 4K 很好看，');
    await tester.pump();
    _expectChineseField(tester, field);
    final editable = tester.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));
    final typedBaseline =
        editable.renderEditable.localToGlobal(Offset.zero).dy +
        _baseline(editable.renderEditable);
    expect(typedBaseline, closeTo(hintBaseline, 0.01), reason: 'the hint sits where the typed text does');

    await tester.enterText(field, 'KaiC 说 iPhone 17 Pro Max 上的 4K HDR 很好看，' * 3);
    await tester.pump();
    _expectChineseField(tester, field, lines: null);
  });

  testWidgets('the @ picker\'s search and names keep the Chinese line', (tester) async {
    await tester.runAsync(loadSystemFontStandIns);
    await _show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 440,
          height: 600,
          child: MentionPicker(
            search: (_) async => const [MentionCandidate(mid: 2, name: 'Bilibili官方')],
            onPick: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    _expectChineseLines(tester, find.text('Bilibili官方', findRichText: true));
    final field = find.byKey(const ValueKey('mention-search'));
    await tester.enterText(field, 'KaiC 老番茄');
    await tester.pump();
    _expectChineseField(tester, field);
  });

  testWidgets('颜文字 in the emote panel and on its tab keep the Chinese line', (tester) async {
    await tester.runAsync(loadSystemFontStandIns);
    const words = EmotePackage(
      id: 3,
      name: '颜文字',
      icon: '',
      isText: true,
      emotes: [Emote(token: 'ヾ(≧▽≦*)o', url: '', large: false), Emote(token: '(=・ω・=)', url: '', large: false)],
    );
    await _show(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 440,
          child: EmotePanel(packages: const [words], recent: const [], height: 304, bottomInset: 34, onPick: (_) {}),
        ),
      ),
    );
    final cells = find.text('ヾ(≧▽≦*)o');
    expect(cells, findsNWidgets(2), reason: 'the cell and the tab');
    _expectChineseLines(tester, cells.first);
    _expectChineseLines(tester, cells.last);
  });
}
