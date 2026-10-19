import 'dart:math' as math;

import 'package:bili_core/logic.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../history/watch_history_page.dart';
import '../player_ui/portrait_controls.dart';
import '../settings/settings_page.dart';
import '../shared/menu.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/video_route.dart';
import 'feed_card.dart';
import 'recent_store.dart';
import 'recents_page.dart';

/// What the avatar opens (49): back, the one tab 最近 (49's 看视频 and 听视频 are left out), ⚙ for 设置, the four
/// shortcuts, and the last few of 最近打开 in a white card. The account, logging in and out, and 开发者 are in 设置.
class AvatarPage extends StatelessWidget {
  const AvatarPage({super.key, this.developerPage});

  /// Builds the developer page (dev builds), for 设置 to offer.
  final WidgetBuilder? developerPage;

  void _push(BuildContext context, WidgetBuilder builder) =>
      Navigator.of(context).push(SwipeBackPageRoute<void>(builder: builder));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    void soon() => showToast(context, '即将推出');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AvatarPageTheme.background,
        body: Column(
          children: [
            SizedBox(height: top),
            _Bar(onSettings: () => _push(context, (_) => const SettingsPage())),
            SizedBox(
              height: AvatarPageTheme.shortcutsHeight,
              child: Row(
                children: [
                  _Shortcut(key: const ValueKey('avatar-offline'), label: '离线缓存', glyph: _Glyph.offline, onTap: soon),
                  _Shortcut(
                    key: const ValueKey('avatar-history'),
                    label: '历史记录',
                    glyph: _Glyph.history,
                    onTap: () => _push(context, (_) => const WatchHistoryPage()),
                  ),
                  _Shortcut(key: const ValueKey('avatar-favourites'), label: '我的收藏', glyph: _Glyph.star, onTap: soon),
                  _Shortcut(key: const ValueKey('avatar-later'), label: '稍后再看', glyph: _Glyph.later, onTap: soon),
                ],
              ),
            ),
            Expanded(child: _RecentCard(onAll: () => _push(context, (_) => const RecentsPage()))),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    const half = AvatarPageTheme.tapTarget / 2;
    return SizedBox(
      height: AvatarPageTheme.barHeight,
      child: Stack(
        children: [
          Positioned(
            left: AvatarPageTheme.backLeft + BiliMetrics.backGlyphWidth / 2 - half,
            top: 0,
            width: AvatarPageTheme.tapTarget,
            height: AvatarPageTheme.tapTarget,
            child: _Tap(
              key: const ValueKey('avatar-back'),
              label: '返回',
              onTap: () => Navigator.of(context).maybePop(),
              child: const BackGlyph(color: AvatarPageTheme.barIcon, shadow: false),
            ),
          ),
          Positioned(
            left: AvatarPageTheme.tabCentreX - AvatarPageTheme.tapTarget,
            width: AvatarPageTheme.tapTarget * 2,
            top: 0,
            bottom: 0,
            child: Semantics(
              header: true,
              selected: true,
              child: Center(
                child: Text(
                  '最近',
                  style: TextStyle(
                    fontFamily: BiliFonts.family,
                    fontSize: AvatarPageTheme.tabText,
                    fontWeight: FontWeight.w600,
                    color: BiliColors.pink,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: AvatarPageTheme.tabCentreX - AvatarPageTheme.tabUnderlineWidth / 2,
            top: AvatarPageTheme.tabUnderlineTop,
            width: AvatarPageTheme.tabUnderlineWidth,
            height: AvatarPageTheme.tabUnderlineHeight,
            child: const DecoratedBox(
              decoration: ShapeDecoration(color: BiliColors.pink, shape: StadiumBorder()),
            ),
          ),
          Positioned(
            left: AvatarPageTheme.gearCentreX - half,
            top: 0,
            width: AvatarPageTheme.tapTarget,
            height: AvatarPageTheme.tapTarget,
            child: _Tap(
              key: const ValueKey('avatar-settings'),
              label: '设置',
              onTap: onSettings,
              child: const CustomPaint(size: Size.square(AvatarPageTheme.gearBox), painter: _GearPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

/// A glyph button that fades while pressed, as iOS bar buttons do.
class _Tap extends StatelessWidget {
  const _Tap({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(AvatarPageTheme.tapTarget),
      child: Center(child: child),
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({super.key, required this.label, required this.glyph, required this.onTap});

  final String label;
  final _Glyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: CupertinoButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: AvatarPageTheme.shortcutIconCentre - AvatarPageTheme.shortcutIconBox / 2,
                child: CustomPaint(
                  size: const Size.square(AvatarPageTheme.shortcutIconBox),
                  painter: _ShortcutPainter(glyph),
                ),
              ),
              Positioned(
                top: 0,
                height: AvatarPageTheme.shortcutLabelCentre * 2,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: BiliFonts.family,
                      fontSize: AvatarPageTheme.shortcutText,
                      color: BiliColors.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 最近在看的视频: the newest few of 最近打开, with 全部 for the whole list.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.onAll});

  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final recents = AppScope.of(context).recents;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AvatarPageTheme.cardRadius)),
      child: ColoredBox(
        color: BiliColors.card,
        child: ListenableBuilder(
          listenable: recents,
          builder: (context, _) {
            final items = recents.items.take(AvatarPageTheme.shown).toList();
            final now = recents.now();
            return ListView(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              children: [
                _Header(onAll: onAll),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AvatarPageTheme.rowExtent / 2),
                    child: Center(
                      child: Text(
                        '还没有打开过视频',
                        style: TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.secondaryText),
                      ),
                    ),
                  ),
                for (final item in items)
                  _RecentRow(
                    key: ValueKey('avatar-recent-${item.id}'),
                    item: item,
                    now: now,
                    onRemove: () => recents.remove(item),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onAll});

  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AvatarPageTheme.headerHeight,
    child: Stack(
      children: [
        Positioned(
          left: BiliMetrics.gutter,
          top: 0,
          height: AvatarPageTheme.headerCentre * 2,
          child: Center(
            child: Text(
              '最近在看的视频',
              style: TextStyle(
                fontFamily: BiliFonts.family,
                fontSize: AvatarPageTheme.headerText,
                fontWeight: FontWeight.w500,
                color: BiliColors.text,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: AvatarPageTheme.headerCentre - AvatarPageTheme.tapTarget / 2,
          height: AvatarPageTheme.tapTarget,
          child: Semantics(
            container: true,
            button: true,
            label: '全部',
            excludeSemantics: true,
            onTap: onAll,
            child: CupertinoButton(
              key: const ValueKey('avatar-all'),
              onPressed: onAll,
              padding: const EdgeInsets.only(left: BiliMetrics.gutter, right: AvatarPageTheme.allRight),
              minimumSize: const Size.square(AvatarPageTheme.tapTarget),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '全部',
                    style: TextStyle(
                      fontFamily: BiliFonts.family,
                      fontSize: AvatarPageTheme.allText,
                      color: BiliColors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: AvatarPageTheme.allChevronGap),
                  const CustomPaint(
                    size: Size(AvatarPageTheme.allChevronWidth, AvatarPageTheme.allChevronHeight),
                    painter: _ChevronPainter(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// One of 49's rows: the cover with its duration and progress, two lines of title, when it was opened, and ✕.
class _RecentRow extends StatelessWidget {
  const _RecentRow({super.key, required this.item, required this.now, required this.onRemove});

  final RecentVideo item;
  final DateTime now;
  final VoidCallback onRemove;

  void _open(BuildContext context) =>
      openVideoPage(context, VideoRoute(bvid: item.bvid, cid: item.cid, title: item.title, cover: item.cover));

  @override
  Widget build(BuildContext context) {
    const coverTop = AvatarPageTheme.rowCoverTop;
    const coverBottom = coverTop + AvatarPageTheme.coverHeight;
    final cover = item.cover;
    final progress = item.progress;
    final duration = item.duration;
    final openedAt = item.openedAt;
    return SizedBox(
      height: AvatarPageTheme.rowExtent,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              container: true,
              button: true,
              label: item.title,
              excludeSemantics: true,
              onTap: () => _open(context),
              child: PressHighlight(onTap: () => _open(context), child: const SizedBox.expand()),
            ),
          ),
          Positioned(
            left: BiliMetrics.gutter,
            top: coverTop,
            width: AvatarPageTheme.coverWidth,
            height: AvatarPageTheme.coverHeight,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AvatarPageTheme.coverRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null && cover.isNotEmpty)
                      RemoteImage(cover, size: const Size(AvatarPageTheme.coverWidth, AvatarPageTheme.coverHeight))
                    else
                      const ColoredBox(color: BiliColors.pageGrey),
                    if (duration > 0)
                      Positioned(
                        right: AvatarPageTheme.durationInset,
                        bottom: AvatarPageTheme.durationInset,
                        height: AvatarPageTheme.durationHeight,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: AvatarPageTheme.durationPad),
                          decoration: BoxDecoration(
                            color: AvatarPageTheme.durationFill,
                            borderRadius: BorderRadius.circular(AvatarPageTheme.durationRadius),
                          ),
                          child: Text(
                            FeedCardView.duration(duration),
                            style: TextStyle(
                              fontFamily: BiliFonts.family,
                              fontSize: AvatarPageTheme.durationText,
                              height: 1,
                              color: BiliColors.onCover,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    if (progress != null && progress > 0 && duration > 0)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        height: AvatarPageTheme.progressHeight,
                        width: AvatarPageTheme.coverWidth * math.min(1, progress / duration),
                        child: const ColoredBox(key: ValueKey('avatar-recent-progress'), color: BiliColors.pink),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: AvatarPageTheme.textLeft,
            right: BiliMetrics.gutter,
            top: coverTop - AvatarPageTheme.titleLift,
            child: IgnorePointer(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: BiliFonts.family,
                  fontSize: AvatarPageTheme.titleText,
                  height: AvatarPageTheme.titleLine / AvatarPageTheme.titleText,
                  color: BiliColors.text,
                ),
              ),
            ),
          ),
          if (openedAt != null)
            Positioned(
              left: AvatarPageTheme.textLeft,
              right: AvatarPageTheme.removeCentreFromRight + AvatarPageTheme.tapTarget / 2,
              bottom: AvatarPageTheme.rowExtent - coverBottom - AvatarPageTheme.timeDrop,
              child: IgnorePointer(
                child: Text(
                  '${TimeFormat.relative(openedAt, now: now)}播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: BiliFonts.family,
                    fontSize: AvatarPageTheme.timeText,
                    color: BiliColors.secondaryText,
                  ),
                ),
              ),
            ),
          Positioned(
            right: AvatarPageTheme.removeCentreFromRight - AvatarPageTheme.tapTarget / 2,
            top: coverTop + AvatarPageTheme.removeCentreBelowCover - AvatarPageTheme.tapTarget / 2,
            width: AvatarPageTheme.tapTarget,
            height: AvatarPageTheme.tapTarget,
            child: Semantics(
              container: true,
              button: true,
              label: '移除',
              excludeSemantics: true,
              onTap: onRemove,
              child: GestureDetector(
                key: ValueKey('avatar-remove-${item.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: const Center(
                  child: CustomPaint(size: Size.square(AvatarPageTheme.removeGlyph), painter: _CrossPainter()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Paint _stroke(double width, Color color) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color;

/// 49's ⚙: a hexagon standing on a point, with rounded corners, around a small ring.
class _GearPainter extends CustomPainter {
  const _GearPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final corners = [
      for (var i = 0; i < 6; i++)
        centre + Offset.fromDirection(-math.pi / 2 + i * math.pi / 3, AvatarPageTheme.gearRadius),
    ];
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final corner = corners[i];
      final before = corners[(i + 5) % 6];
      final after = corners[(i + 1) % 6];
      final into = corner + (before - corner) / (before - corner).distance * AvatarPageTheme.gearCorner;
      final out = corner + (after - corner) / (after - corner).distance * AvatarPageTheme.gearCorner;
      if (i == 0) {
        path.moveTo(into.dx, into.dy);
      } else {
        path.lineTo(into.dx, into.dy);
      }
      path.quadraticBezierTo(corner.dx, corner.dy, out.dx, out.dy);
    }
    path.close();
    final paint = _stroke(AvatarPageTheme.gearStroke, AvatarPageTheme.barIcon);
    canvas
      ..drawPath(path, paint)
      ..drawCircle(centre, AvatarPageTheme.gearHole, paint);
  }

  @override
  bool shouldRepaint(_GearPainter oldDelegate) => false;
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = AvatarPageTheme.allChevronStroke / 2;
    final path = Path()
      ..moveTo(inset, inset)
      ..lineTo(size.width - inset, size.height / 2)
      ..lineTo(inset, size.height - inset);
    canvas.drawPath(path, _stroke(AvatarPageTheme.allChevronStroke, BiliColors.secondaryText));
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => false;
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _stroke(AvatarPageTheme.removeStroke, AvatarPageTheme.remove);
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => false;
}

enum _Glyph { offline, history, star, later }

/// 49's four line icons, drawn on a 32 pt box from the screenshot.
class _ShortcutPainter extends CustomPainter {
  const _ShortcutPainter(this.glyph);

  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / AvatarPageTheme.shortcutIconBox);
    final paint = _stroke(AvatarPageTheme.shortcutStroke, BiliColors.text);
    switch (glyph) {
      case _Glyph.offline:
        const corner = Radius.circular(3);
        final folder = Path()
          ..moveTo(5.6, 10.3)
          ..arcToPoint(const Offset(8.6, 7.3), radius: corner)
          ..lineTo(13.2, 7.3)
          ..lineTo(15.8, 10.8)
          ..lineTo(23.3, 10.8)
          ..arcToPoint(const Offset(26.3, 13.8), radius: corner)
          ..lineTo(26.3, 21.6)
          ..arcToPoint(const Offset(23.3, 24.6), radius: corner)
          ..lineTo(8.6, 24.6)
          ..arcToPoint(const Offset(5.6, 21.6), radius: corner)
          ..close();
        final arrow = Path()
          ..moveTo(16, 14.6)
          ..lineTo(16, 20.2)
          ..moveTo(12.9, 17.3)
          ..lineTo(16, 20.4)
          ..lineTo(19.1, 17.3);
        canvas
          ..drawPath(folder, paint)
          ..drawLine(const Offset(19.2, 7.3), const Offset(24.2, 7.3), paint)
          ..drawPath(arrow, paint);
      case _Glyph.history:
        _circleArrow(canvas, paint, centre: const Offset(17.5, 16), onRight: false);
        canvas.drawPath(
          Path()
            ..moveTo(17.5, 10.8)
            ..lineTo(17.5, 15.8)
            ..lineTo(22.6, 15.8),
          paint,
        );
      case _Glyph.star:
        const centre = Offset(16, 16.6);
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final radius = i.isEven ? 11.2 : 6.3;
          final point = centre + Offset.fromDirection(-math.pi / 2 + i * math.pi / 5, radius);
          if (i == 0) {
            star.moveTo(point.dx, point.dy);
          } else {
            star.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(star..close(), paint);
      case _Glyph.later:
        _circleArrow(canvas, paint, centre: const Offset(15.2, 16), onRight: true);
        canvas.drawPath(
          Path()
            ..moveTo(13.2, 13.4)
            ..lineTo(17.5, 16.05)
            ..lineTo(13.2, 18.7)
            ..close(),
          paint..strokeWidth = AvatarPageTheme.shortcutStroke * 0.85,
        );
    }
  }

  /// A ring with a short gap beside its arrowhead, which points down: 历史记录's on the left, 稍后再看's on the right.
  void _circleArrow(Canvas canvas, Paint paint, {required Offset centre, required bool onRight}) {
    const radius = 10.2;
    const gap = 15 * math.pi / 180;
    const tip = 8 * math.pi / 180;
    final end = onRight ? tip : math.pi - tip;
    final start = onRight ? end + gap : end;
    canvas.drawArc(Rect.fromCircle(center: centre, radius: radius), start, 2 * math.pi - gap, false, paint);
    final head = centre + Offset.fromDirection(end, radius);
    const arm = 3.4;
    canvas.drawPath(
      Path()
        ..moveTo(head.dx - arm, head.dy - arm)
        ..lineTo(head.dx, head.dy)
        ..lineTo(head.dx + arm, head.dy - arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShortcutPainter oldDelegate) => oldDelegate.glyph != glyph;
}
