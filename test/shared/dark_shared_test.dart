import 'package:bilifast/app/appearance.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/shared/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared pieces in 深色模式: each takes its night colours, and a change of mode while it shows redraws it.
void main() {
  Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Material(color: BiliColors.pageGrey, child: Center(child: child))),
  );

  BoxDecoration decorationOf(WidgetTester tester, Finder finder) =>
      tester.widget<DecoratedBox>(finder).decoration as BoxDecoration;

  Color inkOf(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color!;

  testWidgets("the toast keeps its black at night: white words on a box a shade off the page's black", (tester) async {
    BiliTheme.dark = true;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return ColoredBox(color: BiliColors.pageGrey);
          },
        ),
      ),
    );
    showToast(context, '已复制');
    await tester.pump(const Duration(milliseconds: 200));
    final box = tester.widget<Container>(find.byKey(const ValueKey('toast'))).decoration! as BoxDecoration;
    expect(box.color, BiliColors.toastFill);
    expect(inkOf(tester, '已复制'), const Color(0xFFFFFFFF));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets("a menu's glass, rows and pressed highlight at night", (tester) async {
    BiliTheme.dark = true;
    await mount(
      tester,
      GlassPanel(
        width: 200,
        child: MenuRow(title: '稍后再看', icon: Icons.schedule, onTap: () {}),
      ),
    );
    final glass = find.descendant(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox)).first;
    final decoration = decorationOf(tester, glass);
    expect(decoration.color, const Color(0xB8242628));
    expect((decoration.border! as Border).top.color, const Color(0x1FFFFFFF));
    expect(inkOf(tester, '稍后再看'), const Color(0xFFE7E9EB));

    final press = await tester.startGesture(tester.getCenter(find.text('稍后再看')));
    await tester.pump();
    final highlight = find.descendant(of: find.byType(PressHighlight), matching: find.byType(DecoratedBox)).first;
    expect(decorationOf(tester, highlight).color, const Color(0x14FFFFFF));
    await press.up();
  });

  testWidgets('by day the same menu keeps its light glass and dark highlight', (tester) async {
    await mount(
      tester,
      GlassPanel(
        width: 200,
        child: MenuRow(title: '稍后再看', icon: Icons.schedule, onTap: () {}),
      ),
    );
    final glass = find.descendant(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox)).first;
    expect(decorationOf(tester, glass).color, const Color(0xB8FFFFFF));
    final press = await tester.startGesture(tester.getCenter(find.text('稍后再看')));
    await tester.pump();
    final highlight = find.descendant(of: find.byType(PressHighlight), matching: find.byType(DecoratedBox)).first;
    expect(decorationOf(tester, highlight).color, const Color(0x14000000));
    await press.up();
  });

  testWidgets("the cover placeholder and the default face turn dark, and back, as the mode changes", (tester) async {
    final model = AppearanceModel.memory();
    await tester.pumpWidget(
      AppearanceRedraw(
        model: model,
        builder: (_) => const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              SizedBox(width: 100, height: 60, child: CoverPlaceholder()),
              SizedBox(width: 40, height: 40, child: DefaultAvatar()),
            ],
          ),
        ),
      ),
    );
    Color fill() => tester.widget<ColoredBox>(find.byType(ColoredBox).first).color;
    expect(fill(), const Color(0xFFDEDFE1));
    expect(find.byType(ColorFiltered), findsNothing);

    await model.toggle();
    await tester.pump();
    expect(fill(), const Color(0xFF2F3134));
    final filter = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
    expect(filter.colorFilter, const ColorFilter.matrix(CoverPlaceholderTheme.nightFace));
    expect(find.byKey(const ValueKey('default-avatar')), findsOneWidget);

    await model.toggle();
    await tester.pump();
    expect(fill(), const Color(0xFFDEDFE1));
    expect(find.byType(ColorFiltered), findsNothing);
  });

  test("the default face's night matrix lands its ground and TV on the placeholder's night greys", () {
    int channel(int value, int row) {
      final m = CoverPlaceholderTheme.nightFace;
      return (m[row * 5 + row] * value + m[row * 5 + 4]).round();
    }

    // E5E8EF and B0B9C0, the asset's ground and TV.
    expect([channel(0xE5, 0), channel(0xE8, 1), channel(0xEF, 2)], [0x2F, 0x31, 0x34]);
    expect([channel(0xB0, 0), channel(0xB9, 1), channel(0xC0, 2)], [0x46, 0x49, 0x4D]);
  });

  test("the light sheets' frames on Ga12 at night", () {
    BiliTheme.dark = true;
    expect(PanelFrame.of(PlayerPanel.more).sheetColor, const Color(0xFF202123));
    expect(PanelFrame.of(PlayerPanel.danmakuSettings).sheetColor, const Color(0xFF202123));
    expect(PanelFrame.of(PlayerPanel.episodes).sheetColor, const Color(0xFF202123));
    expect(BiliColors.sheetCloseFill, const Color(0xFF2F3134));
    expect(BiliColors.sheetGrabber, const Color(0xFF46494D));
    expect(BiliColors.sheetCloseGlyph, const Color(0xFFA2A7AE));
    BiliTheme.dark = false;
    expect(PanelFrame.of(PlayerPanel.more).sheetColor, const Color(0xFFF6F7F8));
    expect(PanelFrame.of(PlayerPanel.danmakuSettings).sheetColor, const Color(0xFFF6F7F8));
    expect(PanelFrame.of(PlayerPanel.episodes).sheetColor, const Color(0xFFFFFFFF));
  });

  test('what draws over the video is the same in both modes', () {
    final day = [BiliColors.videoPink, DanmakuSendTheme.darkBar, DanmakuSendTheme.darkField, DanmakuListTheme.liked];
    BiliTheme.dark = true;
    expect([BiliColors.videoPink, DanmakuSendTheme.darkBar, DanmakuSendTheme.darkField, DanmakuListTheme.liked], day);
    expect(BlockWordsTheme.fieldInk, const Color(0xFF18191C));
  });
}
