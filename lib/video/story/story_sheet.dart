import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../page_details.dart' show PageTab;

/// Where 竖屏's 简介/评论 sheet rests: closed (plain 竖屏), half (264) or full (266).
enum SheetStop { closed, half, full }

/// 竖屏's 简介/评论 sheet (264-271): where it is, which tab it shows, and the drags that move it. [position] runs from
/// 0 (closed) through 1 (half) to 2 (full), following the finger between the stops and animating to them.
class StorySheetController extends ChangeNotifier {
  StorySheetController({required TickerProvider vsync});

  final _position = ValueNotifier<double>(0);
  SheetStop _stop = SheetStop.closed;
  PageTab _tab = PageTab.comments;

  /// Changes every frame the sheet moves; [topFor] turns it into the sheet's top edge.
  ValueListenable<double> get position => _position;

  /// The stop the sheet rests at, or is heading for.
  SheetStop get stop => _stop;

  /// Open, moving or under the finger: 竖屏's own controls and swipe stand aside.
  bool get isOpen => _stop != SheetStop.closed || _position.value > 0;

  PageTab get tab => _tab;

  void selectTab(PageTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// From 竖屏: up to half on [tab] (评论 from the column's button, 简介 from the title).
  void open(PageTab tab) {
    _tab = tab;
    _settle(SheetStop.half);
  }

  void close() => _settle(SheetStop.closed);

  /// The ⌃⌄ / ✕ button: half and full.
  void toggle() => _settle(_stop == SheetStop.full ? SheetStop.half : SheetStop.full);

  void dragStart() {}

  /// The finger moved [delta] points, down positive, on a screen [screenHeight] tall.
  void dragUpdate(double delta, double screenHeight) {}

  /// The finger lifted at [velocity] points a second, down positive.
  void dragEnd(double velocity, double screenHeight) {}

  void _settle(SheetStop stop) {
    _stop = stop;
    _position.value = stop.index.toDouble();
    notifyListeners();
  }

  /// The sheet's top edge for [position] on a screen [screenHeight] tall.
  static double topFor(double position, double screenHeight) => position <= 1
      ? lerpDouble(screenHeight, StorySheetTheme.halfTop, position.clamp(0, 1))!
      : lerpDouble(StorySheetTheme.halfTop, StorySheetTheme.fullTop, (position - 1).clamp(0, 1))!;

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }
}
