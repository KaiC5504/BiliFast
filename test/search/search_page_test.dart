import 'dart:async';

import 'package:bili_core/api.dart' hide SearchPage;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/results/result_more_sheet.dart';
import 'package:bilifast/search/results/results_view.dart';
import 'package:bilifast/search/search_glyphs.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_home_view.dart';
import 'package:bilifast/search/search_model.dart';
import 'package:bilifast/search/search_page.dart';
import 'package:bilifast/search/suggestion_list.dart';
import 'package:bilifast/settings/settings_confirm.dart';
import 'package:bilifast/video/link_opener.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

const _link = 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2';

const _video = SearchVideo(
  aid: 1,
  bvid: 'BV1xx411c7mD',
  title: HighlightedText([HighlightRun('一个'), HighlightRun('视频', highlighted: true)]),
  author: '作者',
  mid: 2,
  cover: 'https://i0.hdslb.com/bfs/archive/cover.jpg',
  play: 10,
  danmaku: 1,
  duration: 60,
  published: null,
);

const _user = SearchUser(mid: 4242, name: '某人', face: '', fans: 1, videos: 1, level: 3, sign: '');

/// Takes every link it is given, holding it while [gate] is set, and reads it as busy meanwhile.
class _FakeOpener extends LinkOpener {
  final opened = <String>[];
  Completer<void>? gate;

  @override
  Future<bool> open(BuildContext context, String text) async {
    opened.add(text);
    busy.value = true;
    await gate?.future;
    busy.value = false;
    return true;
  }
}

void main() {
  late FakeSearchApi api;
  late SearchHistoryStore history;
  late _FakeOpener opener;
  late List<VideoRoute> videos;
  late List<Uri> spaces;

  /// What opening an uploader's space answers.
  late Future<bool> Function() spaceAnswer;
  final navigator = GlobalKey<NavigatorState>();

  setUp(() {
    api = FakeSearchApi(
      defaultWord: '接口默认词',
      hotWords: const [HotWord(keyword: 'hot-1', showName: '热词一号')],
      discovery: const [DiscoveryWord(keyword: 'found-1', showName: '发现一号')],
      suggest: (term) => [SearchSuggestion(keyword: '$term联动', text: HighlightedText.plain('$term联动'))],
      videos: const [_video],
      users: const [_user],
    );
    history = SearchHistoryStore.memory();
    opener = _FakeOpener();
    videos = [];
    spaces = [];
    spaceAnswer = () async => true;
  });

  tearDown(() => opener.dispose());

  /// The page pushed over a home screen, at the iPhone's size.
  Future<void> show(WidgetTester tester, {String? placeholder = '默认词', FakeSearchApi? searchApi}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      searchApi: searchApi ?? api,
      searchHistory: history,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const Text('home'),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => SearchPage(
            placeholder: placeholder,
            linkOpener: opener,
            openVideo: (context, route) => videos.add(route),
            openSpace: (link) {
              spaces.add(link);
              return spaceAnswer();
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  Finder field() => key('search-field');
  String fieldText(WidgetTester tester) => tester.widget<TextField>(field()).controller!.text;
  bool keyboardUp(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;
  SearchModel model(WidgetTester tester) => tester.widget<SearchHomeView>(find.byType(SearchHomeView)).model;

  /// Types [text] a character at a time, as the keyboard does.
  Future<void> type(WidgetTester tester, String text) async {
    for (var i = 1; i <= text.length; i++) {
      await tester.enterText(field(), text.substring(0, i));
    }
    await settle(tester);
  }

  testWidgets('the page opens with the keyboard up and the default word in grey', (tester) async {
    await show(tester);
    expect(keyboardUp(tester), isTrue);
    expect(find.text('默认词'), findsOneWidget);
    expect(find.byType(SearchHomeView), findsOneWidget);
    expect(find.text('热词一号'), findsOneWidget);
    expect(api.calls, containsAll(['hotWords', 'discovery']));
    final input = tester.widget<TextField>(field());
    expect(input.textInputAction, TextInputAction.search);
    expect(input.autofocus, isTrue);
  });

  testWidgets('without a default word from home, the page asks for one', (tester) async {
    await show(tester, placeholder: null);
    expect(find.text('接口默认词'), findsOneWidget);
  });

  testWidgets('搜索 with the field empty searches the grey word', (tester) async {
    await show(tester);
    await tester.tap(key('search-submit'));
    await settle(tester);
    expect(fieldText(tester), '默认词');
    expect(find.byType(ResultsView), findsOneWidget);
    expect(history.words, ['默认词']);
    expect(api.calls, contains('videos 默认词 1'));
    expect(keyboardUp(tester), isFalse);
  });

  testWidgets('the keyboard\'s search key with the field empty and no grey word does nothing', (tester) async {
    await show(tester, placeholder: null, searchApi: FakeSearchApi());
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.byType(SearchHomeView), findsOneWidget);
    expect(history.words, isEmpty);
  });

  testWidgets('a typed word shows suggestions, and the keyboard\'s search key searches it', (tester) async {
    await show(tester);
    await type(tester, '猫猫');
    expect(find.byType(SuggestionList), findsOneWidget);
    expect(find.text('猫猫联动'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.byType(ResultsView), findsOneWidget);
    expect(fieldText(tester), '猫猫');
    expect(keyboardUp(tester), isFalse);
    expect(api.calls, contains('videos 猫猫 1'));
    expect(opener.opened, isEmpty);
  });

  testWidgets('a typed link opens its video on 搜索, with no search', (tester) async {
    await show(tester);
    await type(tester, 'BV1GJ411x7h7');
    expect(opener.opened, isEmpty, reason: 'typing opens nothing until 搜索');
    await tester.tap(key('search-submit'));
    await settle(tester);
    expect(opener.opened, ['BV1GJ411x7h7']);
    expect(api.calls.where((call) => call.startsWith('videos')), isEmpty);
    expect(history.words, isEmpty);
    expect(fieldText(tester), isEmpty, reason: 'the link was taken');
    expect(find.byType(SearchHomeView), findsOneWidget);
  });

  testWidgets('a pasted link opens at once, with the spinner while it resolves', (tester) async {
    await show(tester);
    opener.gate = Completer<void>();
    await tester.enterText(field(), _link);
    await tester.pump();
    expect(opener.opened, [_link]);
    expect(key('search-opening'), findsOneWidget);
    expect(keyboardUp(tester), isFalse);
    expect(tester.widget<TextField>(field()).enabled, isFalse);

    opener.gate!.complete();
    await settle(tester);
    expect(key('search-opening'), findsNothing);
    expect(fieldText(tester), isEmpty);
    expect(api.calls.where((call) => call.startsWith('suggestions')), isEmpty);
  });

  testWidgets('pasted words that are no link go to the suggestions', (tester) async {
    await show(tester);
    await tester.enterText(field(), '一段文字');
    await settle(tester);
    expect(opener.opened, isEmpty);
    expect(find.byType(SuggestionList), findsOneWidget);
  });

  testWidgets('a suggestion searches its keyword', (tester) async {
    await show(tester);
    await type(tester, '狗');
    await tester.tap(key('search-suggestion-狗联动'));
    await settle(tester);
    expect(fieldText(tester), '狗联动');
    expect(api.calls, contains('videos 狗联动 1'));
  });

  testWidgets('a 热搜 word, a history chip and a 搜索发现 cell each search', (tester) async {
    history.add('旧词');
    await show(tester);
    await tester.tap(find.text('热词一号'));
    await settle(tester);
    expect(fieldText(tester), 'hot-1');
    expect(find.byType(ResultsView), findsOneWidget);

    await tester.tap(key('search-clear'));
    await settle(tester);
    await tester.tap(key('search-history-旧词'));
    await settle(tester);
    expect(fieldText(tester), '旧词');

    await tester.tap(key('search-clear'));
    await settle(tester);
    await tester.tap(key('search-discovery-found-1'));
    await settle(tester);
    expect(fieldText(tester), 'found-1');
    expect(api.calls.where((call) => call.startsWith('videos')), ['videos hot-1 1', 'videos 旧词 1', 'videos found-1 1']);
  });

  testWidgets('ⓧ shows only with text, and clears back to the empty page with the keyboard up', (tester) async {
    await show(tester);
    expect(key('search-clear'), findsNothing);
    await type(tester, '猫');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(keyboardUp(tester), isFalse);
    await tester.tap(key('search-clear'));
    await settle(tester);
    expect(fieldText(tester), isEmpty);
    expect(find.byType(SearchHomeView), findsOneWidget);
    expect(keyboardUp(tester), isTrue);
    expect(key('search-clear'), findsNothing);
  });

  /// Lets a toast run out, so its timer is not left pending.
  Future<void> toastGone(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  ValueNotifier<bool> filterOpen(WidgetTester tester) =>
      tester.widget<ResultsView>(find.byType(ResultsView)).filterOpen!;

  Future<void> showResults(WidgetTester tester) async {
    await show(tester);
    await type(tester, '猫');
    await tester.tap(key('search-submit'));
    await settle(tester);
    expect(find.byType(ResultsView), findsOneWidget);
  }

  group('the field reads as a link only when it is one', () {
    for (final text in ['AV1', 'av1 编码', '4K AV1', 'av1234', 'BV1 教程', 'bilibili 会员']) {
      test('"$text" searches', () => expect(isSearchFieldLink(text), isFalse));
    }
    for (final text in [
      'av170001',
      ' AV170001 ',
      'BV1GJ411x7h7',
      '看这个 BV1GJ411x7h7 好看',
      'https://www.bilibili.com/video/av170001',
      'www.bilibili.com/video/BV1GJ411x7h7?p=2',
      '【标题】 https://b23.tv/abc123',
      'https://b23.tv/abc123',
    ]) {
      test('"$text" opens', () => expect(isSearchFieldLink(text), isTrue));
    }
    test('a URL with no video in it searches', () {
      expect(isSearchFieldLink('https://space.bilibili.com/42'), isFalse);
    });
  });

  for (final text in ['AV1', 'av1 编码', '4K AV1']) {
    testWidgets('"$text" searches on 搜索 and when pasted, opening nothing', (tester) async {
      await show(tester);
      await tester.enterText(field(), text);
      await settle(tester);
      expect(opener.opened, isEmpty, reason: 'pasted');
      expect(find.byType(SuggestionList), findsOneWidget);
      await tester.tap(key('search-submit'));
      await settle(tester);
      expect(opener.opened, isEmpty);
      expect(api.calls, contains('videos ${text.trim()} 1'));
      expect(history.words, [text]);
    });
  }

  testWidgets('a bare av id typed opens its video on 搜索', (tester) async {
    await show(tester);
    await type(tester, 'av170001');
    await tester.tap(key('search-submit'));
    await settle(tester);
    expect(opener.opened, ['av170001']);
    expect(history.words, isEmpty);
  });

  testWidgets("the field's rim is drawn over it: the magnifier, the word and ⓧ sit where 52 and 55 have them", (
    tester,
  ) async {
    await show(tester);
    await type(tester, '猫');
    final magnifier = tester.getRect(
      find.descendant(
        of: find.byType(SearchPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is SearchGlyphIcon && widget.glyph == SearchGlyph.magnifier,
        ),
      ),
    );
    expect(magnifier.left, closeTo(38 + 35 / 3, 0.01));
    expect(magnifier.width, closeTo(12.33, 0.01));
    expect(tester.getRect(find.byType(EditableText)).left, closeTo(68, 0.01));
    final clear = tester.getRect(find.descendant(of: key('search-clear'), matching: find.byType(SearchGlyphIcon)));
    expect(clear.center.dx, closeTo(358, 0.01));
    expect(clear.width, closeTo(40 / 3, 0.01));
  });

  testWidgets('back, ‹ and the left-edge swipe close 筛选 before the page', (tester) async {
    await showResults(tester);
    final open = filterOpen(tester);

    open.value = true;
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(open.value, isFalse);
    expect(find.byType(SearchPage), findsOneWidget);

    open.value = true;
    await settle(tester);
    await tester.tap(key('search-back'));
    await settle(tester);
    expect(open.value, isFalse, reason: '‹ closes 筛选 first');
    expect(find.byType(SearchPage), findsOneWidget);

    open.value = true;
    await settle(tester);
    expect(key('search-filter-edge'), findsOneWidget);
    await tester.dragFrom(const Offset(4, 600), const Offset(160, 0));
    await settle(tester);
    expect(open.value, isFalse, reason: 'the edge swipe closes 筛选 first');
    expect(find.byType(SearchPage), findsOneWidget);
    expect(key('search-filter-edge'), findsNothing);

    await tester.tap(key('search-back'));
    await settle(tester);
    expect(find.byType(SearchPage), findsNothing, reason: 'with 筛选 closed, ‹ leaves');
  });

  testWidgets('going back to typing leaves 筛选 closed', (tester) async {
    await showResults(tester);
    final open = filterOpen(tester);
    open.value = true;
    await settle(tester);
    await tester.tap(field());
    await settle(tester);
    expect(find.byType(SuggestionList), findsOneWidget);
    expect(open.value, isFalse);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(SearchPage), findsNothing, reason: 'nothing holds back');
  });

  for (final spot in ['magnifier', 'padding']) {
    testWidgets('a tap on the $spot over results goes back to typing too', (tester) async {
      await showResults(tester);
      final field = tester.getRect(find.byType(EditableText));
      final at = spot == 'magnifier'
          ? tester.getCenter(
              find.byWidgetPredicate((widget) => widget is SearchGlyphIcon && widget.glyph == SearchGlyph.magnifier),
            )
          : Offset(42, field.center.dy);
      await tester.tapAt(at);
      await settle(tester);
      expect(find.byType(SuggestionList), findsOneWidget);
      expect(keyboardUp(tester), isTrue);
      expect(fieldText(tester), '猫');
    });
  }

  testWidgets("an uploader's space that can't open says 无法打开", (tester) async {
    await showResults(tester);
    spaceAnswer = () async => false;
    tester.widget<ResultsView>(find.byType(ResultsView)).onOpenUser(_user);
    await tester.pump();
    await tester.pump();
    expect(find.text('无法打开'), findsOneWidget);
    await toastGone(tester);

    spaceAnswer = () async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    tester.widget<ResultsView>(find.byType(ResultsView)).onOpenUser(_user);
    await tester.pump();
    await tester.pump();
    expect(find.text('无法打开'), findsOneWidget);
    await toastGone(tester);
    expect(spaces, hasLength(2));
  });

  testWidgets('tapping the field over results goes back to the suggestions for its text', (tester) async {
    await show(tester);
    await type(tester, '猫');
    await tester.tap(key('search-submit'));
    await settle(tester);
    expect(find.byType(ResultsView), findsOneWidget);
    await tester.tap(field());
    await settle(tester);
    expect(find.byType(SuggestionList), findsOneWidget);
    expect(fieldText(tester), '猫');
    expect(keyboardUp(tester), isTrue);
  });

  testWidgets('a result video opens its page; a result uploader opens their space', (tester) async {
    await show(tester);
    await tester.tap(key('search-submit'));
    await settle(tester);
    final results = tester.widget<ResultsView>(find.byType(ResultsView));
    results.onOpenVideo(_video);
    expect(videos.single.bvid, 'BV1xx411c7mD');
    expect(videos.single.title, '一个视频');
    expect(videos.single.cover, 'https://i0.hdslb.com/bfs/archive/cover.jpg');
    results.onOpenUser(_user);
    expect(spaces, [Uri.parse('https://space.bilibili.com/4242')]);
    await tester.pump();
    expect(find.text('无法打开'), findsNothing);
  });

  testWidgets('⋮ shows the sheet in the page; back closes it before the page', (tester) async {
    await show(tester);
    await tester.tap(key('search-submit'));
    await settle(tester);
    tester.widget<ResultsView>(find.byType(ResultsView)).onMore(_video);
    await settle(tester);
    final sheet = find.byType(ResultMoreSheet);
    expect(sheet, findsOneWidget);
    expect(tester.widget<ResultMoreSheet>(sheet).video, same(_video));
    expect(
      find.ancestor(of: sheet, matching: find.byType(SearchPage)),
      findsOneWidget,
      reason: 'not a route',
    );

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(sheet, findsNothing);
    expect(find.byType(SearchPage), findsOneWidget);

    tester.widget<ResultsView>(find.byType(ResultsView)).onMore(_video);
    await settle(tester);
    await tester.tap(key('search-back'));
    await settle(tester);
    expect(sheet, findsNothing, reason: '‹ closes the sheet first too');
    expect(find.byType(SearchPage), findsOneWidget);

    tester.widget<ResultsView>(find.byType(ResultsView)).onMore(_video);
    await settle(tester);
    tester.widget<ResultMoreSheet>(sheet).onClose();
    await settle(tester);
    expect(sheet, findsNothing);
  });

  testWidgets('🗑 asks 清空搜索历史？: 取消 keeps it, 清空 clears it', (tester) async {
    history
      ..add('旧词一')
      ..add('旧词二');
    await show(tester);
    await tester.tap(key('search-history-clear'));
    await settle(tester);
    expect(find.byType(SettingsConfirm), findsOneWidget);
    expect(find.text('清空搜索历史？'), findsOneWidget);
    expect(keyboardUp(tester), isFalse);

    await tester.tap(find.byKey(const ValueKey('settings-confirm-取消')));
    await settle(tester);
    expect(find.byType(SettingsConfirm), findsNothing);
    expect(history.words, hasLength(2));

    await tester.tap(key('search-history-clear'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(SettingsConfirm), findsNothing, reason: 'back closes the alert first');
    expect(find.byType(SearchPage), findsOneWidget);
    expect(history.words, hasLength(2));

    await tester.tap(key('search-history-clear'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings-confirm-清空')));
    await settle(tester);
    expect(history.words, isEmpty);
    expect(find.text('搜索历史'), findsNothing);
    expect(find.byType(SettingsConfirm), findsNothing);
  });

  testWidgets('‹ pops the page', (tester) async {
    await show(tester);
    await tester.tap(key('search-back'));
    await settle(tester);
    expect(find.byType(SearchPage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the model leaves with the page', (tester) async {
    await show(tester);
    final searchModel = model(tester);
    await tester.tap(key('search-back'));
    await settle(tester);
    expect(() => searchModel.addListener(() {}), throwsFlutterError);
  });

  testWidgets('‹, ⓧ and 搜索 answer accessibility presses', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester);
    await tester.enterText(field(), '猫');
    await settle(tester);
    tester.semantics.tap(find.semantics.byLabel('清空'));
    await settle(tester);
    expect(fieldText(tester), isEmpty);
    tester.semantics.tap(find.semantics.byLabel('搜索'));
    await settle(tester);
    expect(fieldText(tester), '默认词');
    tester.semantics.tap(find.semantics.byLabel('返回'));
    await settle(tester);
    expect(find.byType(SearchPage), findsNothing);
    handle.dispose();
  });

  testWidgets("on iOS the field's edit menu is the system's, whose Paste asks nothing", (tester) async {
    tester.platformDispatcher.supportsShowingSystemContextMenu = true;
    addTearDown(tester.platformDispatcher.resetSupportsShowingSystemContextMenu);
    await show(tester);
    expect(await editMenu(tester), isA<SystemContextMenu>());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets("elsewhere the field's edit menu is Flutter's own", (tester) async {
    await show(tester);
    expect(await editMenu(tester), isA<AdaptiveTextSelectionToolbar>());
  });
}

/// Lets the model's calls answer and the route's push run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// What the field shows as its edit menu once focused.
Future<Widget> editMenu(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('search-field'));
  final editable = find.descendant(of: field, matching: find.byType(EditableText));
  final state = tester.state<EditableTextState>(editable);
  return tester.widget<TextField>(field).contextMenuBuilder!(tester.element(editable), state);
}
