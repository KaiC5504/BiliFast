import 'package:bili_core/api.dart' show SpaceVideo;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/uploader_sheet_grid.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../video/intro/bars_ink.dart';

const _video = SpaceVideo(aid: 2, bvid: 'BV1sheet0002', title: '演示视频 第2期', cover: '', duration: 39);

void main() {
  testWidgets('the playing card\'s mark keeps its 8.4 × 10 box, 2 in from the title\'s start and 6 before its text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 208,
            child: UploaderVideoCard(video: _video, playing: true, onOpen: () {}),
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.getRect(find.byKey(const ValueKey('uploader-sheet-playing')));
    final title = tester.getRect(find.byKey(const ValueKey('uploader-sheet-title-BV1sheet0002')));
    expect(box.size, UploaderSheetTheme.barsBox);
    expect(box.left, title.left + UploaderSheetTheme.barsLead);
    expect(tester.getRect(find.byType(PlayingBars)), box);
    expect(tester.widget<PlayingBars>(find.byType(PlayingBars)).color, UploaderSheetTheme.barsInk);
  });

  testWidgets('its bars are 1.5 wide and 3.6 apart, centred in the box, in the sheet\'s pink', (tester) async {
    const boundary = ValueKey('boundary');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: Padding(padding: EdgeInsets.all(2), child: PlayingMark()),
          ),
        ),
      ),
    );
    await tester.pump();

    final bars = await barsIn(tester, find.byKey(boundary));
    expect(bars, hasLength(3));
    // The test's 2 pt margin, then the mark's lead and drop, to the box's centre.
    final centre =
        const Offset(2 + UploaderSheetTheme.barsLead, 2 + UploaderSheetTheme.barsDrop * 2) +
        UploaderSheetTheme.barsBox.center(Offset.zero);
    expect(bars[0].x, closeTo(centre.dx - UploaderSheetTheme.barPitch, 0.05));
    expect(bars[1].x, closeTo(centre.dx, 0.05));
    expect(bars[2].x, closeTo(centre.dx + UploaderSheetTheme.barPitch, 0.05));
    for (final bar in bars) {
      expect(bar.width, closeTo(1.5, 0.1));
      expect(bar.y, closeTo(centre.dy, 0.05));
      expect(bar.ink, UploaderSheetTheme.barsInk);
    }
  });
}
