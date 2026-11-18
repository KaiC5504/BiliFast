import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../shared/toast.dart';
import 'message_routes.dart';
import 'session_row.dart' show messageStyle;

/// 一键已读's alert (211): true once 清除 is pressed; 取消 or a tap on the dim gives false.
Future<bool> confirmReadAll(BuildContext context) async =>
    await Navigator.of(context).push(_AlertRoute(reduceMotion: MediaQuery.disableAnimationsOf(context))) ?? false;

/// ⋮'s rows (212), top to bottom.
enum MessageSheetChoice {
  settings('消息设置'),
  contacts('通讯录'),
  fanClub('应援团消息助手'),
  harassment('防骚扰和互动人群设置'),
  community('社区中心'),
  system('系统通知'),
  service('服务通知'),
  creator('创作助手');

  const MessageSheetChoice(this.label);

  final String label;
}

/// ⋮ on 消息 (212): 消息设置 opens its page; 社区中心, 服务通知 and 创作助手 their sessions in [sessions] (暂无消息 while the
/// list has none), 系统通知 its own list; the rest say 暂未开放. [now] dates 系统通知's stand-in session.
Future<void> showMessageMoreSheet(
  BuildContext context, {
  required List<ChatSession> sessions,
  required DateTime now,
}) async {
  final choice = await Navigator.of(context).push(_SheetRoute(reduceMotion: MediaQuery.disableAnimationsOf(context)));
  if (choice == null || !context.mounted) return;
  NoticeBox? box;
  switch (choice) {
    case MessageSheetChoice.settings:
      unawaited(openMessageSettings(context));
      return;
    case MessageSheetChoice.contacts || MessageSheetChoice.fanClub || MessageSheetChoice.harassment:
      showToast(context, '暂未开放');
      return;
    case MessageSheetChoice.system:
      final session = ChatSession(
        talkerId: 0,
        box: NoticeBox.system,
        name: NoticeBox.system.label,
        face: '',
        lastText: '',
        time: now,
      );
      unawaited(openMessageChat(context, session));
      return;
    case MessageSheetChoice.community:
      box = NoticeBox.community;
    case MessageSheetChoice.service:
      box = NoticeBox.service;
    case MessageSheetChoice.creator:
      box = NoticeBox.creator;
  }
  for (final session in sessions) {
    if (session.box == box) {
      unawaited(openMessageChat(context, session));
      return;
    }
  }
  showToast(context, '暂无消息');
}

class _AlertRoute extends PopupRoute<bool> {
  _AlertRoute({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Color? get barrierColor => MessageTabTheme.alertDim;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '取消';

  @override
  Duration get transitionDuration => reduceMotion ? Duration.zero : MessageTabTheme.alertMotion;

  /// Centred between the status bar and the home indicator, as 211's.
  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => SafeArea(
    child: Center(
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: MessageTabTheme.alertStartScale, end: 1.0).animate(animation),
          child: _ReadAllAlert(
            onCancel: () => Navigator.of(context).pop(false),
            onConfirm: () => Navigator.of(context).pop(true),
          ),
        ),
      ),
    ),
  );
}

class _ReadAllAlert extends StatelessWidget {
  const _ReadAllAlert({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    Widget line(String text, TextStyle style, double centre, double height) => Positioned(
      left: 0,
      right: 0,
      top: centre - height / 2,
      height: height,
      child: Center(
        child: Text(text, maxLines: 1, style: style, strutStyle: BiliFonts.strut(style)),
      ),
    );
    return Container(
      key: const ValueKey('message-read-all'),
      width: MessageTabTheme.alertWidth,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MessageTabTheme.alertFill,
        borderRadius: BorderRadius.circular(MessageTabTheme.alertRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MessageTabTheme.alertBody,
            child: Stack(
              children: [
                line(
                  '一键已读',
                  messageStyle(
                    MessageTabTheme.alertTitleText,
                    MessageTabTheme.alertTitle,
                    line: MessageTabTheme.alertTitleLine,
                    weight: MessageTabTheme.alertTitleWeight,
                  ),
                  MessageTabTheme.alertTitleCentre,
                  MessageTabTheme.alertTitleLine,
                ),
                line(
                  '是否清除全部新消息提醒？',
                  messageStyle(
                    MessageTabTheme.alertMessageText,
                    MessageTabTheme.alertMessage,
                    line: MessageTabTheme.alertMessageLine,
                  ),
                  MessageTabTheme.alertMessageCentre,
                  MessageTabTheme.alertMessageLine,
                ),
              ],
            ),
          ),
          SizedBox(
            height: MessageTabTheme.alertRule,
            child: ColoredBox(color: MessageTabTheme.alertRuleInk),
          ),
          SizedBox(
            height: MessageTabTheme.alertButton,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AlertButton(
                    label: '取消',
                    colour: MessageTabTheme.alertCancel,
                    shift: -MessageTabTheme.alertSpread / 2,
                    onTap: onCancel,
                  ),
                ),
                Expanded(
                  child: _AlertButton(
                    label: '清除',
                    colour: MessageTabTheme.alertAction,
                    shift: MessageTabTheme.alertSpread / 2,
                    onTap: onConfirm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertButton extends StatefulWidget {
  const _AlertButton({required this.label, required this.colour, required this.shift, required this.onTap});

  final String label;
  final Color colour;

  /// How far the word sits from its half's middle, outwards.
  final double shift;
  final VoidCallback onTap;

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    onTap: widget.onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('message-read-all-${widget.label}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: ColoredBox(
        color: _down ? MessageTabTheme.alertPressed : MessageTabTheme.alertFill,
        child: Center(
          child: Transform.translate(
            offset: Offset(widget.shift, 0),
            child: Text(
              widget.label,
              maxLines: 1,
              style: messageStyle(MessageTabTheme.alertButtonText, widget.colour, line: MessageTabTheme.alertButton),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SheetRoute extends PopupRoute<MessageSheetChoice> {
  _SheetRoute({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Color? get barrierColor => MessageTabTheme.sheetDim;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭';

  @override
  Duration get transitionDuration => reduceMotion ? Duration.zero : MessageTabTheme.sheetIn;

  @override
  Duration get reverseTransitionDuration => reduceMotion ? Duration.zero : MessageTabTheme.sheetOut;

  CurvedAnimation? _curve;

  @override
  Animation<double> createAnimation() => _curve = CurvedAnimation(
    parent: super.createAnimation(),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    const rows = MessageSheetChoice.values;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
        // The route lies outside the page's Material, whose text style the rows would otherwise miss.
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            key: const ValueKey('message-sheet'),
            decoration: BoxDecoration(
              color: MessageTabTheme.sheetFill,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(MessageTabTheme.sheetRadius)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: MessageTabTheme.grabberTop),
                  child: Center(
                    child: Container(
                      width: MessageTabTheme.grabberWidth,
                      height: MessageTabTheme.grabberHeight,
                      decoration: ShapeDecoration(color: MessageTabTheme.grabberInk, shape: const StadiumBorder()),
                    ),
                  ),
                ),
                const SizedBox(
                  height: MessageTabTheme.cardTop - MessageTabTheme.grabberTop - MessageTabTheme.grabberHeight,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MessageTabTheme.cardInset),
                  child: ColoredBox(
                    color: MessageTabTheme.card,
                    child: Column(
                      children: [
                        for (final (index, choice) in rows.indexed)
                          _SheetRow(
                            choice: choice,
                            last: index == rows.length - 1,
                            onTap: () => Navigator.of(context).pop(choice),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: MessageTabTheme.cardBottom + bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _SheetRow extends StatefulWidget {
  const _SheetRow({required this.choice, required this.last, required this.onTap});

  final MessageSheetChoice choice;
  final bool last;
  final VoidCallback onTap;

  @override
  State<_SheetRow> createState() => _SheetRowState();
}

class _SheetRowState extends State<_SheetRow> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final choice = widget.choice;
    final style = messageStyle(MessageTabTheme.sheetText, MessageTabTheme.sheetInk, line: MessageTabTheme.sheetRow);
    return Semantics(
      button: true,
      label: choice.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('message-sheet-${choice.name}'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: ColoredBox(
          color: _pressed ? MessageTabTheme.sheetPressed : MessageTabTheme.card,
          child: SizedBox(
            height: MessageTabTheme.sheetRow,
            child: Stack(
              children: [
                Positioned(
                  left: MessageTabTheme.sheetGlyphCentre - MessageTabTheme.sheetRow / 2,
                  top: 0,
                  bottom: 0,
                  width: MessageTabTheme.sheetRow,
                  child: Center(child: _SheetGlyph(choice)),
                ),
                Positioned(
                  left: MessageTabTheme.sheetTextLeft,
                  right: 0,
                  top: MessageTabTheme.sheetTextDrop,
                  height: MessageTabTheme.sheetRow,
                  child: Text(choice.label, maxLines: 1, style: style, strutStyle: BiliFonts.strut(style)),
                ),
                if (!widget.last)
                  Positioned(
                    left: MessageTabTheme.sheetTextLeft,
                    right: 0,
                    bottom: 0,
                    height: MessageTabTheme.sheetRule,
                    child: ColoredBox(color: MessageTabTheme.sheetRuleInk),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row's glyph at its ink's size: the APK's icon font's where it has one (cut at 3× to 212's width), else traced
/// on 212. Two sit off the column's middle as 212 has them.
class _SheetGlyph extends StatelessWidget {
  const _SheetGlyph(this.choice);

  final MessageSheetChoice choice;

  @override
  Widget build(BuildContext context) {
    final asset = switch (choice) {
      MessageSheetChoice.settings => 'settings',
      MessageSheetChoice.contacts => 'contacts',
      MessageSheetChoice.fanClub => 'fan_club',
      MessageSheetChoice.system => 'system',
      MessageSheetChoice.creator => 'creator',
      MessageSheetChoice.harassment || MessageSheetChoice.community || MessageSheetChoice.service => null,
    };
    final Widget glyph;
    if (asset != null) {
      glyph = Image.asset(
        'assets/images/message/tab_sheet_$asset.png',
        scale: 3,
        color: MessageTabTheme.sheetInk,
        excludeFromSemantics: true,
      );
    } else {
      final painter = _LineGlyphPainter(choice);
      glyph = CustomPaint(size: painter.box / 3, painter: painter);
    }
    final shift = switch (choice) {
      MessageSheetChoice.harassment => const Offset(MessageTabTheme.sheetHarassmentShift, 0),
      MessageSheetChoice.fanClub => const Offset(0, -MessageTabTheme.sheetFanClubRise),
      _ => null,
    };
    return shift == null ? glyph : Transform.translate(offset: shift, child: glyph);
  }
}

/// 212's glyphs the icon font lacks, in the screenshot's pixels from their ink's top left, 4 px strokes.
class _LineGlyphPainter extends CustomPainter {
  const _LineGlyphPainter(this.choice);

  final MessageSheetChoice choice;

  Size get box => switch (choice) {
    MessageSheetChoice.harassment => const Size(49, 53),
    MessageSheetChoice.community => const Size(52, 48),
    _ => const Size(46, 46),
  };

  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / box.width);
    final ink = Paint()
      ..color = MessageTabTheme.sheetInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (choice) {
      case MessageSheetChoice.harassment:
        _harassment(canvas, ink);
      case MessageSheetChoice.community:
        _community(canvas, ink);
      default:
        _service(canvas, ink);
    }
    canvas.restore();
  }

  /// A shield cut away at its bottom right for a smiling person.
  static void _harassment(Canvas canvas, Paint ink) {
    canvas.drawPath(
      _rounded(const [
        Offset(20.5, 47.5),
        Offset(2, 30),
        Offset(2, 10),
        Offset(22.5, 2),
        Offset(42, 10),
        Offset(42, 22),
      ], 5),
      ink,
    );
    // The head's ring opens at the bottom into the shoulders.
    const head = Offset(37.5, 36);
    const radius = 8.0;
    const from = 115 * math.pi / 180;
    const sweep = 310 * math.pi / 180;
    final neck = head + Offset.fromDirection(from, radius);
    canvas
      ..drawPath(
        Path()
          ..moveTo(28.5, 51.5)
          ..quadraticBezierTo(30.5, 45.5, neck.dx, neck.dy)
          ..arcTo(Rect.fromCircle(center: head, radius: radius), from, sweep, false)
          ..quadraticBezierTo(44.5, 45.5, 46.5, 51.5),
        ink,
      )
      ..drawPath(
        Path()
          ..moveTo(33.25, 37)
          ..arcToPoint(const Offset(42.75, 37), radius: const Radius.circular(4.75), clockwise: false)
          ..close(),
        Paint()..color = MessageTabTheme.sheetInk,
      );
  }

  /// A bubble with two lines and a tail, over the corner of a second one up and to the right.
  static void _community(Canvas canvas, Paint ink) {
    final tail = Path()
      ..moveTo(11.5, 40)
      ..lineTo(19.5, 40)
      ..lineTo(13.5, 46.5)
      ..close();
    canvas
      ..drawPath(
        _rounded(const [Offset(13, 6), Offset(13, 2.5), Offset(48.5, 2.5), Offset(48.5, 32.5), Offset(44, 32.5)], 4),
        ink,
      )
      ..drawRRect(RRect.fromLTRBR(2, 13, 37, 40, const Radius.circular(6)), ink)
      ..drawPath(
        tail,
        Paint()
          ..color = MessageTabTheme.sheetInk
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      )
      ..drawPath(tail, Paint()..color = MessageTabTheme.sheetInk);
    final line = Paint()
      ..color = MessageTabTheme.sheetInk
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(11, 22.3), const Offset(30, 22.3), line)
      ..drawLine(const Offset(10.5, 30.8), const Offset(20, 30.8), line);
  }

  /// Three rounded squares and a diamond where the fourth would be.
  static void _service(Canvas canvas, Paint ink) {
    const corner = Radius.circular(3.5);
    for (final (left, top) in [(2.5, 2.5), (2.5, 26.5), (26.5, 26.5)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, 17, 17), corner), ink);
    }
    canvas
      ..save()
      ..translate(34.5, 10.25)
      ..rotate(math.pi / 4)
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 13, height: 13), const Radius.circular(3)),
        ink,
      )
      ..restore();
  }

  /// [points] joined by lines, each corner rounded by [radius].
  static Path _rounded(List<Offset> points, double radius) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final corner = points[i];
      final into = points[i - 1] - corner;
      final out = points[i + 1] - corner;
      final start = corner + into / into.distance * math.min(radius, into.distance / 2);
      final end = corner + out / out.distance * math.min(radius, out.distance / 2);
      path
        ..lineTo(start.dx, start.dy)
        ..quadraticBezierTo(corner.dx, corner.dy, end.dx, end.dy);
    }
    return path..lineTo(points.last.dx, points.last.dy);
  }

  @override
  bool shouldRepaint(_LineGlyphPainter oldDelegate) => oldDelegate.choice != choice;
}
