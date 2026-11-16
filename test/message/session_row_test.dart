import 'package:bili_core/api.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/message/notice_box_icon.dart';
import 'package:bilifast/message/session_row.dart';
import 'package:bilifast/search/results/user_row.dart' show VerifiedBoltPainter;
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 16, 9, 55);

ChatSession _person({
  int talkerId = 7,
  String name = '演示用户',
  String lastText = '[自动回复] 谢谢关注',
  DateTime? time,
  int unread = 0,
  bool vipPink = false,
  bool bigVip = false,
  DynamicVerify verify = DynamicVerify.none,
  String pendant = '',
}) => ChatSession(
  talkerId: talkerId,
  name: name,
  face: '',
  lastText: lastText,
  time: time ?? DateTime(2026, 11, 12, 8),
  unread: unread,
  vipPink: vipPink,
  bigVip: bigVip,
  verify: verify,
  pendant: pendant,
);

ChatSession _box(NoticeBox box, {int unread = 0}) => ChatSession(
  talkerId: 100 + box.index,
  box: box,
  name: box.label,
  face: '',
  lastText: '演示通知',
  time: DateTime(2026, 11, 13, 9),
  unread: unread,
);

Finder _key(String key) => find.byKey(ValueKey(key));

void _near(Offset actual, Offset expected) {
  expect(actual.dx, moreOrLessEquals(expected.dx, epsilon: 1e-6));
  expect(actual.dy, moreOrLessEquals(expected.dy, epsilon: 1e-6));
}

void main() {
  late List<ChatSession> taps;

  setUp(() => taps = []);

  Future<void> show(WidgetTester tester, List<ChatSession> sessions, {bool counts = true}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              for (final session in sessions)
                SessionRow(session: session, now: _now, counts: counts, onTap: () => taps.add(session)),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a person: 71 tall, the 40 pt face, the name and date on one line, the last message under, the hairline '
      'from the text', (tester) async {
    await show(tester, [_person()]);
    final row = tester.getRect(_key('message-session-7'));
    expect(row, const Rect.fromLTWH(0, 0, 440, MessageTabTheme.row));
    final face = tester.getRect(find.byType(SessionFace));
    expect(face, Rect.fromLTWH(MessageTabTheme.faceLeft, (71 - 40) / 2, 40, 40));
    expect(find.descendant(of: find.byType(SessionFace), matching: find.byType(RemoteImage)), findsOneWidget);
    expect(find.byType(NoticeBoxIcon), findsNothing);
    expect(find.text('演示用户'), findsOneWidget);
    expect(find.text('11月12日'), findsOneWidget);
    expect(find.text('[自动回复] 谢谢关注'), findsOneWidget);
    expect(tester.getTopLeft(_key('message-session-name-7')).dx, MessageTabTheme.textLeft);
    expect(tester.getTopRight(_key('message-session-date-7')).dx, 440 - MessageTabTheme.dateRight);
    expect(
      tester.getCenter(_key('message-session-name-7')).dy,
      moreOrLessEquals(MessageTabTheme.nameCentre, epsilon: 0.01),
    );
    expect(
      tester.getCenter(_key('message-session-text-7')).dy,
      moreOrLessEquals(MessageTabTheme.lastCentre, epsilon: 0.01),
    );
    // 196's ink middles (登录操作通知's for the last message), a third of a point under the lines' boxes.
    expect(MessageTabTheme.nameCentre + 1 / 3, moreOrLessEquals(25.17, epsilon: 0.01));
    expect(MessageTabTheme.lastCentre + 1 / 3, moreOrLessEquals(48.17, epsilon: 0.01));
    final hairline = tester.getRect(
      find.descendant(
        of: _key('message-session-7'),
        matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == MessageTabTheme.hairlineInk),
      ),
    );
    expect(hairline, Rect.fromLTRB(MessageTabTheme.textLeft, 71 - MessageTabTheme.hairline, 440, 71));
    expect(tester.widget<Text>(_key('message-session-name-7')).style?.color, MessageTabTheme.name);
    expect(tester.widget<Text>(_key('message-session-text-7')).style?.color, MessageTabTheme.last);
    expect(tester.widget<Text>(_key('message-session-text-7')).maxLines, 1);
    expect(tester.widget<Text>(_key('message-session-text-7')).overflow, TextOverflow.ellipsis);
  });

  testWidgets('dates go by noticeDate: 刚刚, hours, days, then the month and day, the year before this one', (
    tester,
  ) async {
    await show(tester, [
      _person(talkerId: 1, time: _now.subtract(const Duration(seconds: 20))),
      _person(talkerId: 2, time: _now.subtract(const Duration(hours: 5))),
      _person(talkerId: 3, time: _now.subtract(const Duration(days: 3))),
      _person(talkerId: 4, time: DateTime(2025, 12, 31, 9)),
    ]);
    expect(find.text('刚刚'), findsOneWidget);
    expect(find.text('5小时前'), findsOneWidget);
    expect(find.text('3天前'), findsOneWidget);
    expect(find.text('2025年12月31日'), findsOneWidget);
  });

  testWidgets('大会员 draws the name pink and the 大 badge on the face\'s bottom right', (tester) async {
    await show(tester, [_person(vipPink: true, bigVip: true)]);
    expect(tester.widget<Text>(_key('message-session-name-7')).style?.color, MessageTabTheme.vipName);
    final face = tester.getRect(find.byType(SessionFace));
    final badge = tester.getRect(_key('message-session-vip-7'));
    const ring = MessageTabTheme.badgeRing;
    expect(badge.size, const Size.square(MessageTabTheme.badge + ring * 2));
    _near(badge.bottomRight - const Offset(ring, ring), face.bottomRight);
    final big = find.descendant(of: _key('message-session-vip-7'), matching: find.text('大'));
    expect(big, findsOneWidget);
    expect(tester.widget<Text>(big).style?.fontWeight, MessageTabTheme.vipWeight);
    expect(_key('message-session-verified-7'), findsNothing);
  });

  testWidgets('the verify bolt in its colour, in place of 大 when both; none without either', (tester) async {
    await show(tester, [
      _person(talkerId: 1, verify: DynamicVerify.personal, bigVip: true),
      _person(talkerId: 2, verify: DynamicVerify.organisation),
      _person(talkerId: 3),
    ]);
    Color bolt(int id) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(of: _key('message-session-verified-$id'), matching: find.byType(CustomPaint)),
                    )
                    .painter!
                as VerifiedBoltPainter)
            .color;
    expect(bolt(1), MessageTabTheme.badgePerson);
    expect(bolt(2), MessageTabTheme.badgeOrganisation);
    expect(_key('message-session-vip-1'), findsNothing);
    expect(_key('message-session-verified-3'), findsNothing);
    expect(_key('message-session-vip-3'), findsNothing);
  });

  testWidgets('a pendant shrinks the face to 36 in a frame 1.75 times that on the same centre', (tester) async {
    await show(tester, [_person(pendant: 'https://i0.hdslb.com/bfs/garb/demo.png', bigVip: true)]);
    final box = tester.getRect(find.byType(SessionFace));
    final face = tester.getRect(find.descendant(of: find.byType(SessionFace), matching: find.byType(ClipOval)));
    expect(face.width, moreOrLessEquals(MessageTabTheme.pendantFace));
    expect(face.height, moreOrLessEquals(MessageTabTheme.pendantFace));
    _near(face.center, box.center);
    final frame = tester.getRect(_key('message-session-pendant-7'));
    expect(frame.width, moreOrLessEquals(MessageTabTheme.pendantFace * MessageTabTheme.pendantScale));
    expect(frame.height, moreOrLessEquals(frame.width));
    _near(frame.center, box.center);
    final badge = tester.getRect(_key('message-session-vip-7'));
    _near(badge.bottomRight - const Offset(MessageTabTheme.badgeRing, MessageTabTheme.badgeRing), face.bottomRight);
  });

  testWidgets('each notice box draws its own face in place of a picture', (tester) async {
    await show(tester, [for (final box in NoticeBox.values) _box(box)]);
    for (final box in NoticeBox.values) {
      final icon = find.descendant(of: _key('message-session-${box.name}'), matching: find.byType(NoticeBoxIcon));
      expect(icon, findsOneWidget, reason: box.label);
      expect(tester.widget<NoticeBoxIcon>(icon).box, box);
      expect(tester.getSize(icon), const Size.square(MessageTabTheme.face));
      expect(find.text(box.label), findsOneWidget);
    }
    expect(find.byType(SessionFace), findsNothing);
    Iterable<Image> images(NoticeBox box) => tester.widgetList<Image>(
      find.descendant(of: _key('message-session-${box.name}'), matching: find.byType(Image)),
    );
    Iterable<String> assets(NoticeBox box) => images(box).map((image) => (image.image as AssetImage).assetName);
    expect(assets(NoticeBox.system), ['assets/images/message/tab_box_system.png']);
    expect(assets(NoticeBox.creator), ['assets/images/message/tab_box_creator.png']);
    expect(assets(NoticeBox.service), isEmpty, reason: 'drawn');
    expect(assets(NoticeBox.community), isEmpty, reason: 'drawn');

    // No screenshot shows 系统通知's or 创作助手's face: the APK's own blue ones are drawn as they are.
    Iterable<Color?> discs(NoticeBox box) => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: _key('message-session-${box.name}'), matching: find.byType(DecoratedBox)),
        )
        .map((box) => (box.decoration as BoxDecoration).color);
    for (final box in [NoticeBox.system, NoticeBox.creator]) {
      expect(images(box).single.color, isNull, reason: box.label);
      expect(discs(box), isNot(contains(MessageTabTheme.boxFill)), reason: box.label);
    }
    expect(discs(NoticeBox.service), contains(MessageTabTheme.boxFill));
  });

  testWidgets('an unread count on the face\'s top right, 99+ past 99; none at 0 or with 消息提醒 off', (tester) async {
    await show(tester, [
      _person(talkerId: 1, unread: 7),
      _person(talkerId: 2, unread: 120),
      _person(talkerId: 3),
      _box(NoticeBox.service, unread: 2),
    ]);
    expect(find.descendant(of: _key('message-session-count-1'), matching: find.text('7')), findsOneWidget);
    expect(find.descendant(of: _key('message-session-count-2'), matching: find.text('99+')), findsOneWidget);
    expect(_key('message-session-count-3'), findsNothing);
    expect(_key('message-session-count-service'), findsOneWidget);
    final face = tester.getRect(find.descendant(of: _key('message-session-1'), matching: find.byType(SessionFace)));
    final count = tester.getCenter(_key('message-session-count-1'));
    expect(count.dx, moreOrLessEquals(face.right - MessageTabTheme.countFaceInset, epsilon: 0.01));
    expect(count.dy, moreOrLessEquals(face.top + MessageTabTheme.countFaceInset, epsilon: 0.01));
    expect(
      tester.getSize(_key('message-session-count-1')).height,
      MessageTabTheme.count + 2 * MessageTabTheme.countRing,
    );

    await show(tester, [_person(talkerId: 1, unread: 7)], counts: false);
    expect(find.byType(TabCount), findsNothing);
  });

  testWidgets('a tap, or VoiceOver\'s press, opens the session; the row reads its name and count', (tester) async {
    final semantics = tester.ensureSemantics();
    final sessions = [_person(talkerId: 1, unread: 3), _box(NoticeBox.community)];
    await show(tester, sessions);
    await tester.tap(_key('message-session-1'));
    await tester.tap(_key('message-session-community'));
    expect(taps, sessions);

    final node = tester.getSemantics(_key('message-session-1'));
    expect(node, isSemantics(label: '演示用户', value: '3条未读', isButton: true, hasTapAction: true));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(taps, [...sessions, sessions.first]);
    semantics.dispose();
  });
}
