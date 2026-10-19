import 'dart:ui' show Tristate;

import 'package:bili_core/api.dart';
import 'package:bilifast/comments/emote_panel.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const width = 440.0;
const height = 304.0;
const inset = 34.0;

List<Emote> small(String prefix, int count) => [
  for (var i = 0; i < count; i++) Emote(token: '[$prefix$i]', url: 'https://i0.hdslb.com/$prefix$i.png', large: false),
];

final faces = EmotePackage(
  id: 1,
  name: '小黄脸',
  icon: 'https://i0.hdslb.com/icon.png',
  isText: false,
  emotes: small('e', 20),
);
final tv = EmotePackage(id: 2, name: '小电视', icon: 'https://i0.hdslb.com/tv.png', isText: false, emotes: small('tv', 3));
const words = EmotePackage(
  id: 3,
  name: '颜文字',
  icon: '',
  isText: true,
  emotes: [
    Emote(token: '(⌒▽⌒)', url: '', large: false),
    Emote(token: '（￣▽￣）', url: '', large: false),
    Emote(token: '(=・ω・=)', url: '', large: false),
    Emote(token: '(｀・ω・´)', url: '', large: false),
  ],
);
final big = EmotePackage(
  id: 4,
  name: '热词',
  icon: 'https://i0.hdslb.com/hot.png',
  isText: false,
  emotes: [for (var i = 0; i < 5; i++) Emote(token: '[热$i]', url: 'https://i0.hdslb.com/hot$i.gif', large: true)],
);

class Rig {
  final picked = <String>[];
  int retries = 0;
}

Future<Rig> pumpPanel(
  WidgetTester tester, {
  List<EmotePackage>? packages,
  List<Emote> recent = const [],
  bool failed = false,
}) async {
  tester.view.physicalSize = const Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = Rig();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: EmotePanel(
            packages: packages,
            recent: recent,
            height: height,
            bottomInset: inset,
            onPick: (emote) => rig.picked.add(emote.token),
            onRetry: failed ? () => rig.retries++ : null,
          ),
        ),
      ),
    ),
  );
  return rig;
}

Rect cell(WidgetTester tester, String token) => tester.getRect(find.bySemanticsLabel(token));

Rect picture(WidgetTester tester, String token) =>
    tester.getRect(find.descendant(of: find.bySemanticsLabel(token), matching: find.byType(RemoteImage)));

bool selected(WidgetTester tester, int id) =>
    tester.getSemantics(find.byKey(ValueKey('emote-tab-$id'))).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  testWidgets('a spinner while the packages load', (tester) async {
    await pumpPanel(tester);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('表情加载失败，点击重试'), findsNothing);
  });

  testWidgets('a failure says so, and a tap asks again', (tester) async {
    final rig = await pumpPanel(tester, failed: true);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    await tester.tap(find.text('表情加载失败，点击重试'));
    expect(rig.retries, 1);
  });

  testWidgets('the grid, the tab bar and the home indicator\'s strip share the height', (tester) async {
    await pumpPanel(tester, packages: [faces]);
    final panel = tester.getRect(find.byType(EmotePanel));
    expect(panel.height, height);
    final tab = tester.getRect(find.byKey(const ValueKey('emote-tab-1')));
    expect(tab.size, const Size(ComposerTheme.tabWidth, ComposerTheme.tabHeight));
    expect(tab.left, 0);
    expect(tab.top, height - inset - ComposerTheme.tabHeight);
  });

  testWidgets('the first package: 最近使用, then 所有表情, seven to a row at 14\'s places', (tester) async {
    await pumpPanel(tester, packages: [faces, tv], recent: [faces.emotes[5]]);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('所有表情'), findsOneWidget);

    // 14: the recent emote is centred at (34, 64.7) under the panel's top; the grid's first row at 151.7, 62 apart.
    final recent = find.bySemanticsLabel('[e5]').first;
    final recentPicture = tester.getRect(find.descendant(of: recent, matching: find.byType(RemoteImage)));
    expect(recentPicture.size, const Size.square(ComposerTheme.emote));
    expect(recentPicture.center, const Offset(34, 65));

    final first = picture(tester, '[e0]');
    expect(first.center, const Offset(34, 152));
    expect(picture(tester, '[e1]').center.dx, 96);
    expect(picture(tester, '[e6]').center.dx, 406);
    expect(picture(tester, '[e7]').center, const Offset(34, 214));
    expect(cell(tester, '[e0]').width, (width - 2 * ComposerTheme.gridSide) / ComposerTheme.columns);
  });

  testWidgets('another package has no 最近使用, and its tab turns grey', (tester) async {
    await pumpPanel(tester, packages: [faces, tv], recent: [faces.emotes[5]]);
    expect(selected(tester, 1), isTrue);
    await tester.tap(find.bySemanticsLabel('小电视'));
    await tester.pump();
    expect(selected(tester, 1), isFalse);
    expect(selected(tester, 2), isTrue);
    expect(find.text('最近使用'), findsNothing);
    expect(find.bySemanticsLabel('[tv0]'), findsOneWidget);
    expect(find.bySemanticsLabel('[e0]'), findsNothing);
    final tab = tester.widget<Container>(
      find.descendant(of: find.byKey(const ValueKey('emote-tab-2')), matching: find.byType(Container)),
    );
    expect(tab.color, ComposerTheme.tabSelected);
  });

  testWidgets('a text package: kaomoji cells three to a row, its tab the first kaomoji', (tester) async {
    await pumpPanel(tester, packages: [faces, words]);
    expect(
      find.descendant(of: find.byKey(const ValueKey('emote-tab-3')), matching: find.text('(⌒▽⌒)')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('颜文字'));
    await tester.pump();
    expect(find.text('（￣▽￣）'), findsOneWidget);
    final first = cell(tester, '(⌒▽⌒)');
    expect(first.width, closeTo((width - 2 * ComposerTheme.gridSide) / ComposerTheme.textColumns, 0.01));
    expect(first.height, ComposerTheme.textRow);
    expect(cell(tester, '(｀・ω・´)').top, first.bottom);
  });

  testWidgets('a package of large emotes: four to a row', (tester) async {
    await pumpPanel(tester, packages: [faces, big]);
    await tester.tap(find.bySemanticsLabel('热词'));
    await tester.pump();
    final first = cell(tester, '[热0]');
    expect(first.width, closeTo((width - 2 * ComposerTheme.gridSide) / ComposerTheme.largeColumns, 0.01));
    expect(first.height, ComposerTheme.largeRow);
    expect(picture(tester, '[热0]').size, const Size.square(ComposerTheme.largeEmote));
    expect(cell(tester, '[热4]').top, first.bottom);
  });

  testWidgets('a tap picks the emote; each is a button named by its token', (tester) async {
    final rig = await pumpPanel(tester, packages: [faces], recent: [faces.emotes[3]]);
    await tester.tap(find.bySemanticsLabel('[e2]'));
    await tester.tap(find.bySemanticsLabel('[e3]').first);
    expect(rig.picked, ['[e2]', '[e3]']);
    final node = tester.getSemantics(find.bySemanticsLabel('[e2]'));
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
  });
}
