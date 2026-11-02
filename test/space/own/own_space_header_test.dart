import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comment_badges.dart' show DecorImage;
import 'package:bilifast/friends/friends_route.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/own/own_banner_video.dart';
import 'package:bilifast/space/own/own_space_banner.dart';
import 'package:bilifast/space/own/own_space_glyphs.dart';
import 'package:bilifast/space/own/own_space_header.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _banner = 'https://i0.hdslb.com/bfs/garb/made-up/banner.png';
const _icon = 'https://i0.hdslb.com/bfs/garb/made-up/collection-icon.png';

SpaceProfile _profile({
  OwnSpace own = const OwnSpace(),
  List<SpaceTagLine> tags = const [SpaceTagLine(text: 'IP属地：澳大利亚')],
}) => SpaceProfile(
  mid: 1,
  name: '测试账号',
  face: '',
  level: 5,
  vip: true,
  fans: 0,
  following: 14,
  likes: 0,
  tagLines: tags,
  own: own,
);

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));

  /// The header alone, at the iPhone's width, its 粉丝 / 关注 taps kept in [friends].
  Future<void> show(
    WidgetTester tester,
    SpaceProfile profile, {
    List<FriendsTab>? friends,
    ValueNotifier<bool>? muted,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 956)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              child: OwnSpaceHeader(
                profile: profile,
                onSoon: () {},
                onFriends: (tab) => friends?.add(tab),
                bannerMuted: muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('an animated banner', () {
    const video = 'https://i0.hdslb.com/bfs/garb/made-up/banner.mp4';
    const animated = OwnSpace(
      banner: _banner,
      bannerVideo: video,
      bannerSize: (width: 1080, height: 1618),
      bannerAlignY: -1,
    );

    testWidgets('opens muted; its button turns the sound on and off', (tester) async {
      final muted = ValueNotifier(true);
      addTearDown(muted.dispose);
      await show(tester, _profile(own: animated), muted: muted);
      expect(key('own-space-sound-off'), findsOneWidget);
      final button = tester.getRect(key('own-space-sound-off'));
      expect(button.size, const Size.square(OwnSpaceTheme.soundSize));
      expect(button.center, offsetMoreOrLessEquals(Offset(417, OwnSpaceTheme.bannerHeight - 63)));
      await tester.tap(key('own-space-sound'));
      await tester.pump();
      expect(muted.value, isFalse);
      expect(key('own-space-sound-on'), findsOneWidget);
      await tester.tap(key('own-space-sound'));
      await tester.pump();
      expect(muted.value, isTrue);
      expect(key('own-space-sound-off'), findsOneWidget);
    });

    testWidgets('the button answers an accessibility press', (tester) async {
      final semantics = tester.ensureSemantics();
      final muted = ValueNotifier(true);
      addTearDown(muted.dispose);
      await show(tester, _profile(own: animated), muted: muted);
      tester.semantics.tap(find.semantics.byLabel('声音'));
      await tester.pump();
      expect(muted.value, isFalse);
      semantics.dispose();
    });

    testWidgets('a silent one has no button, nor a still one', (tester) async {
      final muted = ValueNotifier(true);
      addTearDown(muted.dispose);
      await show(
        tester,
        _profile(
          own: const OwnSpace(banner: _banner, bannerVideo: video, bannerSilent: true),
        ),
        muted: muted,
      );
      expect(key('own-space-sound'), findsNothing);
      await show(
        tester,
        _profile(own: const OwnSpace(banner: _banner)),
        muted: muted,
      );
      expect(key('own-space-sound'), findsNothing);
    });

    testWidgets('the still shows under it, cut as the video is', (tester) async {
      await show(tester, _profile(own: animated));
      expect(find.byType(OwnBannerVideo), findsOneWidget);
      final still = tester.widget<DecorImage>(
        find.descendant(of: key('own-space-banner'), matching: find.byType(DecorImage)),
      );
      expect(still.alignment, const Alignment(0, -1));
    });
  });

  group('the banner', () {
    testWidgets('is asked whole at the screen\'s width and cut about the answer\'s crop', (tester) async {
      await show(tester, _profile(own: const OwnSpace(banner: _banner, bannerAlignY: -0.75)));
      final picture = tester.widget<DecorImage>(
        find.descendant(of: key('own-space-banner'), matching: find.byType(DecorImage)),
      );
      expect(picture.fit, BoxFit.cover);
      expect(picture.alignment, const Alignment(0, -0.75));
      expect(picture.url, 'https://i1.hdslb.com/bfs/garb/made-up/banner.png@480w.webp');
      expect(picture.url, isNot(contains('_1c')), reason: 'a sized ask is cut about the middle by the CDN');
    });

    test('its address steps the width by 60 px, as the app\'s other pictures', () {
      expect(OwnSpaceBanner.address(_banner, 1320), endsWith('@1320w.webp'));
      expect(OwnSpaceBanner.address(_banner, 1179), endsWith('@1200w.webp'));
      expect(OwnSpaceBanner.address(_banner, double.nan), endsWith('@1320w.webp'));
    });

    testWidgets('without a crop it is cut about the middle', (tester) async {
      await show(tester, _profile(own: const OwnSpace(banner: _banner)));
      final picture = tester.widget<DecorImage>(
        find.descendant(of: key('own-space-banner'), matching: find.byType(DecorImage)),
      );
      expect(picture.alignment, Alignment.center);
    });

    /// A picture 100 wide and 300 tall, white down to 100 and black below: cover-fit across 440 it is 1320 tall, so
    /// only a crop near its top puts white behind the status bar.
    Future<ui.Image> whiteTop() {
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, 100, 300), Paint()..color = const Color(0xFF000000))
        ..drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = const Color(0xFFFFFFFF));
      return recorder.endRecording().toImage(100, 300);
    }

    testWidgets('the status bar is measured on the crop the banner draws', (tester) async {
      final results = (await tester.runAsync(() async {
        final image = await whiteTop();
        final top = await ownBannerLuminance(image, width: 440, alignY: -1);
        final middle = await ownBannerLuminance(image, width: 440, alignY: 0);
        final bottom = await ownBannerLuminance(image, width: 440, alignY: 1);
        image.dispose();
        return (top, middle, bottom);
      }))!;
      expect(results.$1, closeTo(1, 0.01), reason: 'the top: white');
      expect(results.$2, closeTo(0, 0.01), reason: 'the middle: black');
      expect(results.$3, closeTo(0, 0.01), reason: 'the bottom: black');
    });
  });

  group('the label', () {
    testWidgets('draws the collectible\'s picture before the title when it has one', (tester) async {
      await show(
        tester,
        _profile(
          own: const OwnSpace(
            bannerLabel: SpaceBannerLabel(title: '测试收藏集', subtitle: 'CD.013149', icon: _icon),
          ),
        ),
      );
      final icon = tester.getRect(key('own-space-label-icon'));
      final title = tester.getRect(key('own-space-label-title'));
      expect(icon.size, const Size.square(OwnSpaceTheme.labelBadge));
      expect(title.left - icon.right, closeTo(OwnSpaceTheme.labelBadgeGap, 0.01));
      expect(icon.center.dy, closeTo(title.center.dy, 0.01));
      expect(title.right, closeTo(440 - OwnSpaceTheme.labelTitleRight, 0.01));
      final picture = tester.widget<DecorImage>(
        find.descendant(of: key('own-space-label-icon'), matching: find.byType(DecorImage)),
      );
      expect(picture.url, _icon);
    });

    testWidgets('without a picture the title alone keeps its place', (tester) async {
      await show(
        tester,
        _profile(
          own: const OwnSpace(bannerLabel: SpaceBannerLabel(title: '测试收藏集')),
        ),
      );
      expect(key('own-space-label-icon'), findsNothing);
      expect(tester.getRect(key('own-space-label-title')).right, closeTo(440 - OwnSpaceTheme.labelTitleRight, 0.01));
      expect(
        tester.getCenter(key('own-space-label-title')).dy,
        closeTo(OwnSpaceTheme.bannerHeight - OwnSpaceTheme.labelTitleRise, 0.01),
      );
    });

    testWidgets('CD.013149 is drawn in block letters, not set as type', (tester) async {
      await show(
        tester,
        _profile(
          own: const OwnSpace(
            bannerLabel: SpaceBannerLabel(title: '测试收藏集', subtitle: 'CD.013149'),
          ),
        ),
      );
      expect(find.byType(OwnLabelNumber), findsOneWidget);
      expect(find.text('CD.013149'), findsNothing);
    });

    test('every capital and digit has a block letter; lower case and other marks are set as type', () {
      expect(OwnLabelNumber.draws('CD.013149'), isTrue);
      expect(OwnLabelNumber.draws('NO.000067'), isTrue);
      expect(OwnLabelNumber.draws('ABCDEFGHIJKLMNOPQRSTUVWXYZ.0123456789'), isTrue);
      expect(OwnLabelNumber.draws('No.000067'), isFalse);
      expect(OwnLabelNumber.draws('NO-1'), isFalse);
      expect(OwnLabelNumber.draws(''), isFalse);
    });

    testWidgets('D is a block with its right corners cut and a hollow', (tester) async {
      const scale = 12.0;
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: ValueKey('number'),
              child: OwnLabelNumber(text: 'D', color: Color(0xFF000000)),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(key('number'));
      final (pixels, width) = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: scale);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
        final width = image.width;
        image.dispose();
        return (bytes, width);
      }))!;
      bool inked(double x, double y) =>
          pixels.getUint8((((y * scale).round()) * width + (x * scale).round()) * 4 + 3) > 128;
      const w = OwnSpaceTheme.labelNumberWidth;
      const h = OwnSpaceTheme.labelNumberHeight;
      const stroke = OwnSpaceTheme.labelNumberWeight;
      expect(inked(stroke / 2, h / 2), isTrue, reason: 'the left stem');
      expect(inked(w / 2, stroke / 2), isTrue, reason: 'the top bar');
      expect(inked(w - stroke / 2, h / 2), isTrue, reason: 'the right stem');
      expect(inked(w / 2, h - stroke / 2), isTrue, reason: 'the bottom bar');
      expect(inked(w / 2, h / 2), isFalse, reason: 'the hollow');
      expect(inked(w - 0.3, 0.3), isFalse, reason: 'the top right corner, cut');
      expect(inked(w - 0.3, h - 0.3), isFalse, reason: 'the bottom right corner, cut');
      expect(inked(0.3, 0.3), isTrue, reason: 'the top left corner, square');
    });
  });

  group('the face', () {
    testWidgets('draws the 大 when the own answer gives it', (tester) async {
      await show(tester, _profile(own: const OwnSpace(vipBadge: true, pendant: 'https://i0.hdslb.com/bfs/garb/p.png')));
      expect(key('own-space-vip-badge'), findsOneWidget);
      final face = tester.getRect(key('own-space-face'));
      final badge = tester.getRect(key('own-space-vip-badge'));
      expect(badge.center - face.center, offsetMoreOrLessEquals(OwnSpaceTheme.vipPendantShift));
    });

    testWidgets('draws no 大 when it doesn\'t', (tester) async {
      await show(tester, _profile());
      expect(key('own-space-vip-badge'), findsNothing);
    });
  });

  group('the tag row', () {
    testWidgets('leaves out 添加学校信息, keeping the rest', (tester) async {
      final profile = _profile(
        tags: const [
          SpaceTagLine(text: 'IP属地：澳大利亚'),
          SpaceTagLine(text: '添加学校信息', link: true, schoolPrompt: true),
        ],
      );
      await show(tester, profile);
      expect(find.text('IP属地：澳大利亚'), findsOneWidget);
      expect(find.text('添加学校信息'), findsNothing);
      expect(OwnSpaceHeader.heightOf(profile), OwnSpaceHeader.heightOf(_profile()));
    });

    testWidgets('with only the prompt there is no row', (tester) async {
      final profile = _profile(tags: const [SpaceTagLine(text: '添加学校信息', link: true, schoolPrompt: true)]);
      await show(tester, profile);
      expect(find.text('添加学校信息'), findsNothing);
      expect(OwnSpaceHeader.heightOf(profile), OwnSpaceHeader.heightOf(_profile(tags: const [])));
    });
  });

  group('the counts', () {
    testWidgets('粉丝 and 关注 open 我的好友 on their tab; 获赞 opens nothing', (tester) async {
      final friends = <FriendsTab>[];
      await show(tester, _profile(), friends: friends);
      await tester.tap(key('own-space-fans'));
      await tester.tap(key('own-space-following'));
      await tester.tap(key('own-space-likes'));
      expect(friends, [FriendsTab.fans, FriendsTab.following]);
    });

    testWidgets('they answer an accessibility press as buttons', (tester) async {
      final friends = <FriendsTab>[];
      final semantics = tester.ensureSemantics();
      await show(tester, _profile(), friends: friends);
      expect(tester.getSemantics(key('own-space-fans')), isSemantics(isButton: true, label: '0粉丝'));
      tester.semantics.tap(find.semantics.byLabel('14关注'));
      tester.semantics.tap(find.semantics.byLabel('0粉丝'));
      expect(friends, [FriendsTab.following, FriendsTab.fans]);
      semantics.dispose();
    });
  });

  group('the 大会员 label', () {
    testWidgets('is drawn tall enough that its pill is 24\'s', (tester) async {
      await show(
        tester,
        const SpaceProfile(
          mid: 1,
          name: '测试账号',
          face: '',
          vip: true,
          vipLabel: 'https://i1.hdslb.com/bfs/vip/made-up/label.png',
          own: OwnSpace(),
        ),
      );
      final label = tester.widget<Image>(key('own-space-vip-label'));
      expect(label.height, closeTo(58.67 / 3, 0.01));
      expect(label.image, isA<StoredNetworkImage>());
    });
  });
}
