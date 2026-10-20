import 'dart:async';

import 'package:bili_core/api.dart' show BiliError, MentionCandidate;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/comments/mention_picker.dart';
import 'package:bilifast/shared/remote_image.dart' show DefaultAvatar;
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';

/// No face addresses, so the avatars stay grey and nothing is fetched.
const recent = [
  MentionCandidate(mid: 1, name: '星宇动漫社'),
  MentionCandidate(mid: 2, name: 'Bilibili官方'),
  MentionCandidate(mid: 3, name: '老番茄'),
];

/// Answers each search from [answers] when given, or holds it until the test completes it.
class Rig {
  final queries = <String>[];
  final picked = <MentionCandidate>[];
  var closed = 0;
  final pending = <String, Completer<List<MentionCandidate>>>{};
  Map<String, Object>? answers;

  Future<List<MentionCandidate>> search(String query) {
    queries.add(query);
    final answer = answers?[query];
    if (answer is List<MentionCandidate>) return Future.value(answer);
    if (answer != null) return Future.error(answer);
    return (pending[query] = Completer()).future;
  }
}

Future<Rig> mount(WidgetTester tester, {Map<String, Object>? answers}) async {
  final rig = Rig()..answers = answers;
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 440,
          height: 600,
          child: MentionPicker(search: rig.search, onPick: rig.picked.add, onClose: () => rig.closed++),
        ),
      ),
    ),
  );
  await tester.pump();
  return rig;
}

Color? colourOf(WidgetTester tester, String name, String part) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate((widget) => widget is RichText && widget.text.toPlainText() == name),
  );
  Color? found;
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text == part) found = span.style?.color;
    return true;
  });
  return found;
}

void main() {
  late MemorySink sink;

  setUp(() {
    sink = MemorySink();
    Logger.shared.add(sink);
  });

  tearDown(() => Logger.shared.remove(sink));

  testWidgets('opens on the most recently followed, with a spinner until they come', (tester) async {
    final rig = await mount(tester);
    expect(rig.queries, ['']);
    expect(find.byKey(const ValueKey('mention-loading')), findsOneWidget);
    expect(find.text('选择好友'), findsOneWidget);
    expect(find.text('搜索我的关注'), findsOneWidget);

    rig.pending['']!.complete(recent);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mention-loading')), findsNothing);
    expect(find.text('最近关注'), findsOneWidget);
    for (final who in recent) {
      expect(find.text(who.name), findsOneWidget);
    }
  });

  testWidgets('searches 300 ms after typing stops, only for the last text, trimmed', (tester) async {
    final rig = await mount(
      tester,
      answers: {
        '': recent,
        '番茄': [recent[2]],
      },
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('mention-search')), '番');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('mention-search')), ' 番茄 ');
    await tester.pump(const Duration(milliseconds: 299));
    expect(rig.queries, ['']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(rig.queries, ['', '番茄']);

    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('老番茄'), findsOneWidget);
    expect(find.text('星宇动漫社'), findsNothing);
    expect(colourOf(tester, '老番茄', '番茄'), MentionTheme.match);
    expect(colourOf(tester, '老番茄', '老'), isNull);
  });

  testWidgets('a match is found whatever its case', (tester) async {
    final rig = await mount(
      tester,
      answers: {
        '': recent,
        'bili': [recent[1]],
      },
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('mention-search')), 'bili');
    await tester.pumpAndSettle(MentionTheme.debounce);
    expect(rig.queries.last, 'bili');
    expect(colourOf(tester, 'Bilibili官方', 'Bili'), MentionTheme.match);
    expect(colourOf(tester, 'Bilibili官方', 'bili'), MentionTheme.match);
    expect(colourOf(tester, 'Bilibili官方', '官方'), isNull);
  });

  testWidgets('a newer search wins over an older answer that arrives late', (tester) async {
    final rig = await mount(tester);
    await tester.enterText(find.byKey(const ValueKey('mention-search')), '甲');
    await tester.pump(MentionTheme.debounce);
    expect(rig.queries, ['', '甲']);

    rig.pending['甲']!.complete(const [MentionCandidate(mid: 9, name: '甲')]);
    await tester.pumpAndSettle();
    rig.pending['']!.complete(recent);
    await tester.pumpAndSettle();
    expect(find.text('甲'), findsWidgets);
    expect(find.text('星宇动漫社'), findsNothing);
    expect(find.text('搜索结果'), findsOneWidget);
  });

  testWidgets('a search over a shown list keeps it, with a spinner in the field', (tester) async {
    final rig = await mount(tester, answers: {'': recent});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mention-searching')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('mention-search')), '老');
    await tester.pump(MentionTheme.debounce);
    await tester.pump();
    expect(find.byKey(const ValueKey('mention-searching')), findsOneWidget);
    expect(find.text('星宇动漫社'), findsOneWidget);

    rig.pending['老']!.complete([recent[2]]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mention-searching')), findsNothing);
    expect(find.text('星宇动漫社'), findsNothing);
  });

  testWidgets('a tap on someone picks them, by touch or by accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await mount(tester, answers: {'': recent});
    await tester.pumpAndSettle();

    await tester.tap(find.text('老番茄'));
    expect(rig.picked, [recent[2]]);

    expect(find.bySemanticsLabel('星宇动漫社'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('星宇动漫社'));
    expect(rig.picked, [recent[2], recent[0]]);
    semantics.dispose();
  });

  testWidgets('✕ closes, by touch or by accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await mount(tester, answers: {'': recent});
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-close')));
    expect(rig.closed, 1);
    tester.semantics.tap(find.semantics.byLabel('关闭'));
    expect(rig.closed, 2);
    expect(rig.picked, isEmpty);
    semantics.dispose();
  });

  testWidgets('no one to show says so, differently for the list and a search', (tester) async {
    await mount(tester, answers: {'': const <MentionCandidate>[], '无人': const <MentionCandidate>[]});
    await tester.pumpAndSettle();
    expect(find.text('还没有关注任何人'), findsOneWidget);
    expect(find.text('最近关注'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('mention-search')), '无人');
    await tester.pumpAndSettle(MentionTheme.debounce);
    expect(find.text('没有找到相关的人'), findsOneWidget);
    expect(find.text('还没有关注任何人'), findsNothing);
  });

  testWidgets('a failure is logged and offers a retry of the same search', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await mount(tester, answers: {'': recent, '甲': const BiliError.http(412)});
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('mention-search')), '甲');
    await tester.pumpAndSettle(MentionTheme.debounce);
    expect(find.text('加载失败，点击重试'), findsOneWidget);
    expect(find.text('星宇动漫社'), findsNothing);
    final event = sink.events.singleWhere((event) => event.msg == 'mention search failed');
    expect(event.level, LogLevel.warn);
    expect(event.encode(), isNot(contains('甲')));

    rig.answers!['甲'] = const [MentionCandidate(mid: 9, name: '甲乙')];
    tester.semantics.tap(find.semantics.byLabel('加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(rig.queries, ['', '甲', '甲']);
    expect(find.text('加载失败，点击重试'), findsNothing);
    expect(find.text('甲乙'), findsOneWidget);

    rig.answers!['甲'] = const BiliError.http(412);
    await tester.enterText(find.byKey(const ValueKey('mention-search')), '甲 ');
    await tester.pumpAndSettle(MentionTheme.debounce);
    await tester.tap(find.text('加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(rig.queries, ['', '甲', '甲', '甲', '甲']);
    semantics.dispose();
  });

  testWidgets('the clear button empties the field and lists the recent ones at once', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await mount(
      tester,
      answers: {
        '': recent,
        '老': [recent[2]],
      },
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mention-clear')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('mention-search')), '老');
    await tester.pumpAndSettle(MentionTheme.debounce);
    expect(find.byKey(const ValueKey('mention-clear')), findsOneWidget);

    tester.semantics.tap(find.semantics.byLabel('清除'));
    await tester.pump();
    expect(rig.queries, ['', '老', '']);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mention-search'))).controller!.text, '');
    await tester.pumpAndSettle();
    expect(find.text('最近关注'), findsOneWidget);
    expect(find.text('星宇动漫社'), findsOneWidget);
    expect(find.byKey(const ValueKey('mention-clear')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a search pending when the picker closes is dropped quietly', (tester) async {
    final rig = await mount(tester);
    await tester.enterText(find.byKey(const ValueKey('mention-search')), '甲');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(MentionTheme.debounce);
    expect(rig.queries, ['']);
    rig.pending['']!.complete(recent);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows hold a round 40 pt avatar and the name, 60 pt tall', (tester) async {
    await mount(tester, answers: {'': recent});
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byKey(const ValueKey('mention-1')));
    expect(row.height, MentionTheme.rowHeight);
    final avatar = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('mention-1')), matching: find.byType(ClipOval)),
    );
    expect(avatar.size, const Size.square(MentionTheme.avatar));
    expect(avatar.left - row.left, MentionTheme.gutter);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });

  testWidgets('an avatar with no face, still loading or failed shows Bilibili\'s default face', (tester) async {
    await mount(
      tester,
      answers: {
        '': const [
          MentionCandidate(mid: 1, name: '没有头像'),
          MentionCandidate(mid: 2, name: '有头像', face: 'https://i0.hdslb.com/bfs/face/a.jpg'),
        ],
      },
    );
    await tester.pump();
    for (final mid in [1, 2]) {
      final images = tester.widgetList<Image>(
        find.descendant(of: find.byKey(ValueKey('mention-$mid')), matching: find.byType(Image)),
      );
      expect(
        images.map((image) => image.image).whereType<AssetImage>().map((asset) => asset.assetName),
        [DefaultAvatar.asset],
        reason: 'row $mid',
      );
    }
  });

  testWidgets('under the system font, its words fall back to PingFang SC', (tester) async {
    Future<void> show() async {
      await mount(tester, answers: {'': recent});
      await tester.pumpAndSettle();
    }

    await expectSystemFallback(tester, show, find.text('最近关注'));
    await expectSystemFallback(tester, show, find.text('老番茄'));
  });
}
