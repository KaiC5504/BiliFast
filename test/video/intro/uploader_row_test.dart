import 'package:bili_core/api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/uploader_row.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';

/// No face addresses, so the avatars stay grey and nothing is fetched.
VideoDetail _detail({List<StaffMember> staff = const []}) => VideoDetail(
  bvid: 'BV1xx411c7mD',
  aid: 1,
  title: '恭喜你，终于触发了B站大保底！',
  cover: '',
  pubdate: 0,
  duration: 100,
  desc: '',
  descParts: const [],
  copyright: 0,
  owner: const VideoOwner(mid: 7, name: '视频里的名字', face: ''),
  stat: VideoStat.zero,
  pages: const [],
  season: null,
  staff: staff,
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

UploaderCard _card({bool isVip = false, bool following = false, OfficialKind official = OfficialKind.none}) =>
    UploaderCard(
      mid: 7,
      name: '星宇动漫社',
      face: '',
      fans: 475000,
      videos: 410,
      isVip: isVip,
      following: following,
      official: official,
    );

Future<void> _mount(WidgetTester tester, UploaderRow row) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(440, 956)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 440, child: row),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _colour(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

void main() {
  testWidgets('a 大会员 name is pink and anyone else\'s grey', (tester) async {
    await _mount(tester, UploaderRow(detail: _detail(), card: _card(isVip: true)));
    expect(_colour(tester, '星宇动漫社'), BiliColors.pink);

    await _mount(tester, UploaderRow(detail: _detail(), card: _card()));
    expect(_colour(tester, '星宇动漫社'), IntroTheme.name);
  });

  testWidgets('粉丝 and 视频 come with the card; until then the name is the video\'s owner', (tester) async {
    await _mount(tester, UploaderRow(detail: _detail()));
    expect(find.text('视频里的名字'), findsOneWidget);
    expect(find.textContaining('粉丝'), findsNothing);

    await _mount(tester, UploaderRow(detail: _detail(), card: _card()));
    expect(find.text('星宇动漫社'), findsOneWidget);
    expect(find.text('47.5万粉丝  410视频'), findsOneWidget);
  });

  testWidgets('with the system font, digits meeting 粉丝 and 视频 stand a little apart, as PingFang sets them', (
    tester,
  ) async {
    List<String> spaced() {
      final text = tester.renderObject<RenderParagraph>(find.text('47.5万粉丝  410视频')).text;
      final apart = <String>[];
      text.visitChildren((span) {
        if (span is TextSpan && span.style?.letterSpacing == IntroTheme.fansHanGap) apart.add(span.text!);
        return true;
      });
      return apart;
    }

    await _mount(tester, UploaderRow(detail: _detail(), card: _card()));
    expect(spaced(), isEmpty, reason: 'MiSans has its own nudge');

    final family = BiliFonts.family;
    addTearDown(() => BiliFonts.family = family);
    BiliFonts.family = null;
    await _mount(tester, UploaderRow(detail: _detail(), card: _card()));
    expect(spaced(), ['5', '0']);
  });

  testWidgets('the name stays put when the counts arrive', (tester) async {
    await _mount(tester, UploaderRow(detail: _detail()));
    final before = tester.getTopLeft(find.text('视频里的名字'));

    await _mount(tester, UploaderRow(detail: _detail(), card: _card()));
    expect(tester.getTopLeft(find.text('星宇动漫社')), before);
  });

  testWidgets('the badge is yellow for a person, blue for an organisation, and absent otherwise', (tester) async {
    Color? badge() {
      final found = find.byType(VerifiedBadge);
      return found.evaluate().isEmpty ? null : tester.widget<VerifiedBadge>(found).color;
    }

    await _mount(
      tester,
      UploaderRow(
        detail: _detail(),
        card: _card(official: OfficialKind.person),
      ),
    );
    expect(badge(), IntroTheme.badgePerson);

    await _mount(
      tester,
      UploaderRow(
        detail: _detail(),
        card: _card(official: OfficialKind.organisation),
      ),
    );
    expect(badge(), IntroTheme.badgeOrganisation);

    await _mount(tester, UploaderRow(detail: _detail(), card: _card()));
    expect(badge(), isNull);

    await _mount(tester, UploaderRow(detail: _detail()));
    expect(badge(), isNull);
  });

  testWidgets('the badge sits on the avatar\'s lower right', (tester) async {
    await _mount(
      tester,
      UploaderRow(
        detail: _detail(),
        card: _card(official: OfficialKind.person),
      ),
    );
    final badge = tester.getRect(find.byType(VerifiedBadge));
    // The 10 pt disc ends where the 30 pt avatar does, 12 in and 12 down, inside its 1 pt ring.
    expect(badge.right, BiliMetrics.gutter + IntroTheme.avatar + IntroTheme.badgeRing);
    expect(badge.bottom, IntroTheme.uploaderTop + IntroTheme.avatar + IntroTheme.badgeRing);
  });

  testWidgets('关注 follows through the actions and turns to 已关注 when they change', (tester) async {
    final actions = FakeVideoActions();
    addTearDown(actions.dispose);
    await _mount(tester, UploaderRow(detail: _detail(), card: _card(), actions: actions));
    expect(find.text('关注'), findsOneWidget);

    await tester.tap(find.text('关注'));
    expect(actions.calls, ['tapFollow']);

    actions
      ..following = true
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
    expect(find.text('关注'), findsNothing);

    await tester.tap(find.text('已关注'));
    expect(actions.calls, ['tapFollow', 'tapFollow']);
  });

  testWidgets('the actions decide 关注 over the card', (tester) async {
    final actions = FakeVideoActions(following: false);
    addTearDown(actions.dispose);
    await _mount(tester, UploaderRow(detail: _detail(), card: _card(following: true), actions: actions));
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('before the actions exist the pill shows the card\'s state and a tap does nothing', (tester) async {
    await _mount(tester, UploaderRow(detail: _detail(), card: _card(following: true)));
    expect(find.text('已关注'), findsOneWidget);
    await tester.tap(find.text('已关注'));
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);

    await _mount(tester, UploaderRow(detail: _detail()));
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('关注 presses through accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = FakeVideoActions();
    addTearDown(actions.dispose);
    await _mount(tester, UploaderRow(detail: _detail(), card: _card(), actions: actions));

    tester.semantics.tap(find.semantics.byLabel('关注'));
    expect(actions.calls, ['tapFollow']);
    semantics.dispose();
  });

  testWidgets('a 联合投稿 shows each member with the role, and 关注 stays', (tester) async {
    final actions = FakeVideoActions();
    addTearDown(actions.dispose);
    const staff = [
      StaffMember(mid: 1, title: 'UP主', name: '不科学', face: ''),
      StaffMember(mid: 2, title: '参演', name: '後藤の独', face: ''),
      StaffMember(mid: 3, title: '剪辑', name: '学姐圆', face: ''),
    ];
    await _mount(
      tester,
      UploaderRow(
        detail: _detail(staff: staff),
        card: _card(),
        actions: actions,
      ),
    );

    for (final member in staff) {
      expect(find.text(member.name), findsOneWidget);
      expect(find.text(member.title), findsOneWidget);
    }
    expect(find.text('星宇动漫社'), findsNothing);
    expect(find.textContaining('粉丝'), findsNothing);
    // Side by side, in the order Bilibili gives.
    expect(tester.getCenter(find.text('不科学')).dx, lessThan(tester.getCenter(find.text('後藤の独')).dx));
    expect(tester.getCenter(find.text('後藤の独')).dy, tester.getCenter(find.text('学姐圆')).dy);

    await tester.tap(find.text('关注'));
    expect(actions.calls, ['tapFollow']);
  });

  testWidgets('a lone staff member is just the uploader', (tester) async {
    await _mount(
      tester,
      UploaderRow(
        detail: _detail(
          staff: const [StaffMember(mid: 7, title: 'UP主', name: '星宇动漫社', face: '')],
        ),
        card: _card(),
      ),
    );
    expect(find.text('UP主'), findsNothing);
    expect(find.text('47.5万粉丝  410视频'), findsOneWidget);
  });
}
