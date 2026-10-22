import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/favourites_page.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/me/me_header.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/me/me_page.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/watch_later/watch_later_page.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/fake_login_gate.dart';
import 'me_page_support.dart';

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so no timer outlives the test.
Future<void> _toastGone(WidgetTester tester) => _settle(tester, 60);

Finder _key(String key) => find.byKey(ValueKey(key));

const _plain = MeProfile(mid: 7, name: '普通用户', face: '', level: 3, coins: 12.5, bcoin: 0);

void main() {
  testWidgets("a 大会员 reads as 87: the pink name, the pill, B币 and 硬币, the counts and the 会员 card", (tester) async {
    await showMe(tester);
    expect(find.text('KaiC5504'), findsOneWidget);
    expect(tester.widget<Text>(find.text('KaiC5504')).style?.color, MeTheme.vipName);
    expect(find.text('年度大会员'), findsOneWidget);
    expect(find.text('B币：2.3'), findsOneWidget);
    expect(find.text('硬币：878'), findsOneWidget);
    expect(find.bySemanticsLabel('LV5'), findsOneWidget);
    for (final (label, count) in [('动态', '0'), ('关注', '13'), ('粉丝', '0')]) {
      expect(find.text(label), findsOneWidget);
      expect(tester.getSemantics(_key('me-${_counts[label]}')).label, '$label $count');
    }
    expect(_key('me-vip-card'), findsOneWidget);
    expect(_key('me-vip-badge'), findsOneWidget);
    expect(_key('me-pendant'), findsOneWidget);
    expect(find.text('续订会员'), findsOneWidget);
    expect(find.text('更多独家内容'), findsOneWidget);
    expect(find.text('会员中心'), findsOneWidget);
    expect(tester.getRect(_key('me-vip-card')), const Rect.fromLTRB(12, 266, 428, 320));
  });

  testWidgets(
    'without 大会员 the name is plain, and no pill, badge, frame or card; the list starts where the card would',
    (tester) async {
      await showMe(tester, view: const MeShown(_plain, kaiCounts));
      expect(tester.widget<Text>(find.text('普通用户')).style?.color, MeTheme.name);
      expect(find.text('B币：0'), findsOneWidget);
      expect(find.text('硬币：12.5'), findsOneWidget);
      for (final key in ['me-vip-card', 'me-vip-label', 'me-vip-badge', 'me-pendant']) {
        expect(_key(key), findsNothing, reason: key);
      }
      expect(tester.getTopLeft(_key('me-list')).dy, 266);
    },
  );

  test('B币 and 硬币 drop a whole number\'s .0 and keep halves', () {
    expect(MeHeader.amount(878), '878');
    expect(MeHeader.amount(2.3), '2.3');
    expect(MeHeader.amount(878.5), '878.5');
    expect(MeHeader.amount(0.1 + 0.2), '0.3');
    expect(MeHeader.amount(2.999), '3');
  });

  testWidgets('counts past ten thousand read as 万', (tester) async {
    await showMe(tester, view: const MeShown(kaiProfile, MeCounts(dynamics: 3, following: 120, followers: 23456)));
    expect(find.text('2.3万'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('the avatar and 空间 › open the account\'s own space; the name opens nothing', (tester) async {
    await showMe(tester);
    await tester.tap(_key('me-name'));
    await _settle(tester);
    expect(find.byType(SpacePage), findsNothing);
    expect(find.text('即将推出'), findsNothing);

    await tester.tap(_key('me-avatar'));
    await _settle(tester);
    final space = tester.widget<SpacePage>(find.byType(SpacePage));
    expect(space.uploader.mid, 2233);
    expect(space.uploader.name, 'KaiC5504');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _settle(tester);
    expect(find.byType(SpacePage), findsNothing);

    await tester.tap(_key('me-space'));
    await _settle(tester);
    expect(tester.widget<SpacePage>(find.byType(SpacePage)).uploader.mid, 2233);
  });

  for (final key in [
    'me-cast',
    'me-scan',
    'me-outfit',
    'me-night',
    'me-edit',
    'me-dynamics',
    'me-following',
    'me-followers',
    'me-offline',
    'me-support',
    'me-listen',
  ]) {
    testWidgets('$key says 即将推出', (tester) async {
      await showMe(tester);
      await tester.tap(_key(key));
      await tester.pump();
      expect(find.text('即将推出'), findsOneWidget);
      await _toastGone(tester);
    });
  }

  for (final (key, page) in [
    ('me-history', WatchHistoryPage),
    ('me-favourites', FavouritesPage),
    ('me-later', WatchLaterPage),
  ]) {
    testWidgets('$key opens $page', (tester) async {
      await showMe(tester);
      await tester.tap(_key(key));
      await _settle(tester);
      expect(find.byType(page), findsOneWidget);
    });
  }

  testWidgets('设置 opens 设置 with the developer page passed on', (tester) async {
    Widget developer(BuildContext context) => const SizedBox();
    await showMe(tester, developerPage: developer);
    await tester.tap(_key('me-settings'));
    await _settle(tester);
    expect(tester.widget<SettingsPage>(find.byType(SettingsPage)).developerPage, developer);
  });

  testWidgets('the 会员 card and 会员中心 open the 会员 centre in the browser', (tester) async {
    final harness = await showMe(tester);
    await tester.tap(_key('me-vip-centre'));
    await tester.tap(find.text('更多独家内容'));
    await tester.pump();
    expect(harness.opened, [MePage.vipCentre, MePage.vipCentre]);
    expect(MePage.vipCentre.toString(), 'https://big.bilibili.com/mobile/home');
  });

  testWidgets('a link nothing could open says so', (tester) async {
    await showMe(tester, openSucceeds: false);
    await tester.tap(_key('me-vip-centre'));
    await tester.pump();
    expect(find.text('无法打开链接'), findsOneWidget);
    await _toastGone(tester);
  });

  testWidgets('logged out: the grey head and 点击登录, counts as -, no card; both ask for the login', (tester) async {
    final gate = FakeLoginGate();
    await showMe(tester, view: const MeLoggedOut(), loginGate: gate);
    expect(_key('me-avatar-blank'), findsOneWidget);
    expect(find.text('点击登录'), findsOneWidget);
    expect(find.textContaining('B币'), findsNothing);
    expect(find.text('空间'), findsNothing);
    expect(find.text('-'), findsNWidgets(3));
    expect(_key('me-vip-card'), findsNothing);
    expect(find.text('离线缓存'), findsOneWidget);
    expect(find.text('更多服务'), findsOneWidget);

    await tester.tap(_key('me-avatar'));
    await tester.pump();
    expect(gate.requests, 1);
    await tester.tap(_key('me-login'));
    await tester.pump();
    expect(gate.requests, 2);
  });

  for (final (name, view) in [('loading', const MeLoading()), ('failed', const MeFailed('网络不太好'))]) {
    testWidgets('$name: the header\'s layout with no name, counts as -, and nothing spinning over it', (tester) async {
      await showMe(tester, view: view);
      expect(_key('me-avatar-blank'), findsOneWidget);
      expect(_key('me-name'), findsNothing);
      expect(find.text('点击登录'), findsNothing);
      expect(find.text('-'), findsNWidgets(3));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(LoadingTv), findsNothing);
      await tester.tap(_key('me-avatar'));
      await _settle(tester);
      expect(find.byType(SpacePage), findsNothing);
    });
  }

  testWidgets('the page follows its model: a load landing shows the account', (tester) async {
    final harness = await showMe(tester, view: const MeLoading());
    expect(find.text('KaiC5504'), findsNothing);
    harness.model.view = const MeShown(kaiProfile, null);
    await tester.pump();
    expect(find.text('KaiC5504'), findsOneWidget);
    expect(find.text('-'), findsNWidgets(3), reason: 'the counts not in yet');
  });

  testWidgets('showing: at start when 我的 is the tab, and each time it becomes the tab', (tester) async {
    final harness = await showMe(tester, active: false);
    expect(harness.model.showings, 0);
    harness.active.value = true;
    await tester.pump();
    expect(harness.model.showings, 1);
    harness.active.value = false;
    await tester.pump();
    harness.active.value = true;
    await tester.pump();
    expect(harness.model.showings, 2);
  });

  testWidgets('a model made from AppScope when none is given', (tester) async {
    final harness = await showMe(tester);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: harness.services, child: child!),
        home: const MePage(active: true),
      ),
    );
    await tester.pump();
    expect(find.text('更多服务'), findsOneWidget);
  });

  testWidgets('the top row, header, counts and card stay put; the list scrolls under the card, cut at its bottom', (
    tester,
  ) async {
    await showMe(tester);
    final card = tester.getRect(_key('me-vip-card'));
    final name = tester.getRect(_key('me-name'));
    final viewport = tester.getRect(_key('me-list'));
    expect(viewport.top, card.bottom);
    final restTop = tester.getTopLeft(_key('me-offline')).dy;
    expect(restTop, card.bottom);

    final gesture = await tester.startGesture(tester.getCenter(_key('me-settings')));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final under = find.byKey(const ValueKey('me-offline'), skipOffstage: false);
    expect(tester.getTopLeft(under).dy, lessThan(card.bottom - 20), reason: 'under the card');
    expect(tester.getRect(_key('me-vip-card')), card);
    expect(tester.getRect(_key('me-name')), name);
    expect(tester.getRect(_key('me-cast')).center.dy, 84);
    expect(tester.widget<CustomScrollView>(_key('me-list')).clipBehavior, Clip.hardEdge, reason: 'cut at the card');
    await gesture.up();
    await _settle(tester);
    expect(tester.getTopLeft(_key('me-offline')).dy, restTop);
  });

  testWidgets('the pull refreshes the model and toasts what failed', (tester) async {
    final harness = await showMe(tester);
    harness.model.refreshAnswer = '网络不太好';
    await tester.drag(_key('me-list'), const Offset(0, 300));
    await _settle(tester, 10);
    expect(harness.model.refreshes, 1);
    expect(find.text('网络不太好'), findsOneWidget);
    await _toastGone(tester);
  });

  testWidgets('a pull that succeeds says nothing', (tester) async {
    final harness = await showMe(tester);
    await tester.drag(_key('me-list'), const Offset(0, 300));
    await _settle(tester, 10);
    expect(harness.model.refreshes, 1);
    expect(find.text('即将推出'), findsNothing);
    await _toastGone(tester);
  });

  testWidgets('every control answers an accessibility press, with a label', (tester) async {
    final handle = tester.ensureSemantics();
    await showMe(tester);
    for (final key in [
      'me-cast',
      'me-scan',
      'me-outfit',
      'me-night',
      'me-avatar',
      'me-edit',
      'me-space',
      'me-dynamics',
      'me-following',
      'me-followers',
      'me-vip-card',
      'me-vip-centre',
      'me-offline',
      'me-history',
      'me-favourites',
      'me-later',
      'me-support',
      'me-listen',
      'me-settings',
    ]) {
      final node = tester.getSemantics(_key(key));
      expect(node.label, isNotEmpty, reason: key);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: key);
    }
    handle.dispose();
  });

  testWidgets('logged out, the avatar and 点击登录 answer accessibility presses too', (tester) async {
    final handle = tester.ensureSemantics();
    final gate = FakeLoginGate();
    await showMe(tester, view: const MeLoggedOut(), loginGate: gate);
    tester.semantics.tap(find.semantics.byLabel('点击登录').first);
    await tester.pump();
    expect(gate.requests, 1);
    handle.dispose();
  });

  testWidgets('the status bar is dark over the white page', (tester) async {
    await showMe(tester);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(of: find.byType(MePage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).first,
    );
    expect(region.value, SystemUiOverlayStyle.dark);
  });

  testWidgets('text follows the 字体 chosen', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await showMe(tester, fonts: FontStore.memory()..select(FontChoice.system));
    for (final text in ['KaiC5504', '更多服务', '离线缓存', '续订会员', '动态']) {
      expect(tester.widget<Text>(find.text(text)).style?.fontFamily, BiliFonts.system, reason: text);
    }
  });
}

const _counts = {'动态': 'dynamics', '关注': 'following', '粉丝': 'followers'};
