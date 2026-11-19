import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_parts.dart';
import 'package:bilifast/dynamic/follow_tab/follow_top.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'follow_fixtures.dart';

/// Made up: a live face whose answer carries no room, so it opens the face sheet as any other face does.
const _roomless = DynamicLiveUp(mid: 201, name: '晚星直播', face: '');
const _withRoom = DynamicLiveUp(mid: 202, name: '月下直播', face: '', roomId: 30002);

Finder _sheetFaces() => find.byKey(const ValueKey('face-sheet-faces'));
Finder _pointer() => find.byKey(const ValueKey('face-sheet-pointer'));

/// The face [key] in the sheet's own row.
Rect _sheetFace(WidgetTester tester, String key) => tester.getRect(
  find.descendant(
    of: find.descendant(of: _sheetFaces(), matching: find.byKey(ValueKey(key))),
    matching: find.byType(ClipOval),
  ),
);

Future<void> _openLive(WidgetTester tester, FakeDynamicApi api) async {
  await showShell(tester, api: api);
  await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('follow-live-${_roomless.mid}')));
  await settle(tester, 12);
  expect(find.text('${_roomless.name}的动态'), findsOneWidget);
}

void main() {
  setUp(() => FollowPosts.cardOverride = (item, inline) => SizedBox(height: 300, child: Text('post ${item.id}')));
  tearDown(() => FollowPosts.cardOverride = null);

  testWidgets('a live face without a room points the sheet at its own slot, before the line', (tester) async {
    await _openLive(
      tester,
      FakeDynamicApi(posts: posts(3, mid: 201), upList: faces, liveUps: const [_withRoom, _roomless]),
    );
    final face = _sheetFace(tester, 'follow-live-${_roomless.mid}');
    expect(tester.getRect(_pointer()).center.dx, moreOrLessEquals(face.center.dx, epsilon: 0.01));
    expect(
      tester.getRect(_pointer()).center.dx,
      lessThan(tester.getRect(find.descendant(of: _sheetFaces(), matching: find.byKey(const ValueKey('follow-live-rule')))).left),
    );

    await tester.tap(find.descendant(of: _sheetFaces(), matching: find.byKey(const ValueKey('follow-face-103'))));
    await settle(tester, 12);
    expect(
      tester.getRect(_pointer()).center.dx,
      moreOrLessEquals(_sheetFace(tester, 'follow-face-103').center.dx, epsilon: 0.01),
      reason: 'past the line, the others keep theirs',
    );
  });

  testWidgets('with every face live there is still a pointer, under the chosen one', (tester) async {
    await _openLive(tester, FakeDynamicApi(posts: posts(3, mid: 201), liveUps: const [_withRoom, _roomless]));
    expect(find.descendant(of: _sheetFaces(), matching: find.byKey(const ValueKey('follow-live-rule'))), findsNothing);
    expect(_pointer(), findsOneWidget);
    expect(
      tester.getRect(_pointer()).center.dx,
      moreOrLessEquals(_sheetFace(tester, 'follow-live-${_roomless.mid}').center.dx, epsilon: 0.01),
    );
  });

  test('a face\'s centre across the row: live ones first, then the 16 pt of the line before the rest', () {
    const live = [_withRoom, _roomless];
    expect(FollowFacesRow.centreOf(202, faces, live), DynamicFeedTheme.facePitch / 2);
    expect(FollowFacesRow.centreOf(201, faces, live), DynamicFeedTheme.facePitch * 1.5);
    expect(FollowFacesRow.centreOf(101, faces, live), 2 * 74 + 16 + 37);
    expect(FollowFacesRow.centreOf(101, faces, const []), 37);
    expect(FollowFacesRow.centreOf(999, faces, live), isNull);
  });
}
