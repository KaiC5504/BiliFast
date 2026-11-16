import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../player_ui/end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import '../../search/results/video_row.dart' show searchStyle;
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/actions/actions_model.dart' show ActionsModel;
import '../feed_model.dart' show feedLogFields;

/// 217's share targets, in its order. The row runs on past QQ off the screen; 217 shows no further.
enum HotShareTarget {
  facebook('Facebook'),
  x('X'),
  whatsApp('WhatsApp'),
  weChat('微信'),
  moments('朋友圈'),
  download('下载分享'),
  qq('QQ');

  const HotShareTarget(this.label);

  final String label;
}

const _notYet = '暂未开放';

/// What the sheet was closed with.
sealed class _Choice {
  const _Choice();
}

final class _Share extends _Choice {
  const _Share(this.target);

  final HotShareTarget target;
}

final class _WatchLater extends _Choice {
  const _WatchLater();
}

/// ⋮ on a 热门 row (217): 分享's targets, then 稍后再看, over the dimmed page and the bar. A target hands the video's
/// link to iOS's share sheet through [share] (tests pass their own: Windows freezes on it), 下载分享 isn't built, and
/// 稍后再看 adds the video; ×, the dim and back close it.
Future<void> showHotShareSheet(BuildContext context, PopularVideo video, {ShareLink share = shareThroughSystem}) async {
  final choice = await Navigator.of(context)
      .push(_ShareSheetRoute(reduceMotion: MediaQuery.disableAnimationsOf(context)));
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Share(target: HotShareTarget.download):
      showToast(context, _notYet);
    case _Share():
      await _share(context, video, share);
    case _WatchLater():
      await _watchLater(context, video);
  }
}

Future<void> _share(BuildContext context, PopularVideo video, ShareLink share) async {
  try {
    await share(Uri.parse('https://www.bilibili.com/video/${video.card.bvid}'));
  } catch (error) {
    Logger.shared.warn(LogCategory.ui, 'hot share failed', feedLogFields(error));
    if (context.mounted) showToast(context, '分享失败');
  }
}

/// Logged out it goes to the login page; an account still being checked tries, and goes there only if Bilibili
/// answers that it needs a login.
Future<void> _watchLater(BuildContext context, PopularVideo video) async {
  final services = AppScope.of(context);
  if (services.environment.account case LoggedOut() || LoginExpired()) {
    await services.loginGate.request(context);
    return;
  }
  try {
    await services.pageApi.addToWatchLater(aid: video.card.aid);
    if (context.mounted) showToast(context, '已添加至稍后再看');
  } catch (error) {
    Logger.shared.warn(LogCategory.ui, 'hot watch later failed', feedLogFields(error));
    if (!context.mounted) return;
    if (error is BiliError && error.needsLogin) {
      await services.loginGate.request(context);
    } else {
      showToast(context, ActionsModel.failureMessage(error));
    }
  }
}

class _ShareSheetRoute extends PopupRoute<_Choice> {
  _ShareSheetRoute({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Color? get barrierColor => HotListTheme.sheetDim;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭';

  @override
  Duration get transitionDuration => reduceMotion ? Duration.zero : HotListTheme.sheetIn;

  @override
  Duration get reverseTransitionDuration => reduceMotion ? Duration.zero : HotListTheme.sheetOut;

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
    void pick(_Choice choice) => Navigator.of(context).pop(choice);
    const titleLine = HotListTheme.sheetTitleText * 1.4;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
        // The route sits outside the page's Material, whose text style the words would otherwise miss.
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            key: const ValueKey('hot-share-sheet'),
            height: HotListTheme.sheetHeight + bottom,
            decoration: const BoxDecoration(
              color: HotListTheme.sheetFill,
              borderRadius: BorderRadius.vertical(top: Radius.circular(HotListTheme.sheetRadius)),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: HotListTheme.sheetTitleLeft,
                  top: HotListTheme.sheetTitleCentre - titleLine / 2,
                  height: titleLine,
                  child: Semantics(
                    header: true,
                    child: Text(
                      '分享',
                      maxLines: 1,
                      style: searchStyle(
                        HotListTheme.sheetTitleText,
                        HotListTheme.sheetInk,
                        line: titleLine,
                        weight: HotListTheme.sheetTitleWeight,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: HotListTheme.closeCentreRight - HotListTheme.closeTarget / 2,
                  top: HotListTheme.sheetTitleCentre - HotListTheme.closeTarget / 2,
                  width: HotListTheme.closeTarget,
                  height: HotListTheme.closeTarget,
                  child: Semantics(
                    button: true,
                    label: '关闭',
                    onTap: () => Navigator.of(context).pop(),
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const ValueKey('hot-share-close'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: const CustomPaint(painter: _ClosePainter()),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: HotListTheme.targetIconTop,
                  height: _Target.height,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: HotListTheme.targetsLeft),
                    children: [
                      for (final target in HotShareTarget.values)
                        _Target(
                          key: ValueKey('hot-share-${target.name}'),
                          label: target.label,
                          icon: _icon(target),
                          onTap: () => pick(_Share(target)),
                        ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  top: HotListTheme.ruleTop,
                  height: HotListTheme.rule,
                  child: ColoredBox(color: HotListTheme.ruleInk),
                ),
                Positioned(
                  left: HotListTheme.targetsLeft,
                  top: HotListTheme.laterTop,
                  child: _Target(
                    key: const ValueKey('hot-share-watch-later'),
                    label: '稍后再看',
                    icon: Image.asset(
                      'assets/images/home/hot_share_watch_later.png',
                      width: HotListTheme.targetIcon,
                      height: HotListTheme.targetIcon,
                      excludeFromSemantics: true,
                    ),
                    onTap: () => pick(const _WatchLater()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _icon(HotShareTarget target) {
    final asset = switch (target) {
      HotShareTarget.weChat => 'hot_share_wechat',
      HotShareTarget.moments => 'hot_share_moments',
      HotShareTarget.download => 'hot_share_download',
      HotShareTarget.qq => 'hot_share_qq',
      HotShareTarget.facebook || HotShareTarget.x || HotShareTarget.whatsApp => null,
    };
    if (asset == null) {
      return SizedBox.square(
        dimension: HotListTheme.targetIcon,
        child: CustomPaint(painter: _BrandPainter(target)),
      );
    }
    return Image.asset(
      'assets/images/home/$asset.png',
      width: HotListTheme.targetIcon,
      height: HotListTheme.targetIcon,
      excludeFromSemantics: true,
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

/// A target: its 44 icon at the top of a 66 wide slot, its name centred under it.
class _Target extends StatelessWidget {
  const _Target({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  static const _line = 17.0;
  static const height = HotListTheme.targetIcon / 2 + HotListTheme.targetLabelBelow + _line / 2;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: HotListTheme.targetWidth,
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: HotListTheme.targetIcon,
              child: Center(child: icon),
            ),
            Positioned(
              left: -HotListTheme.targetsLeft,
              right: -HotListTheme.targetsLeft,
              top: HotListTheme.targetIcon / 2 + HotListTheme.targetLabelBelow - _line / 2,
              height: _line,
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: searchStyle(HotListTheme.targetText, HotListTheme.sheetInk, line: _line),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// ×, centred in its target.
class _ClosePainter extends CustomPainter {
  const _ClosePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = HotListTheme.closeStroke;
    // Round caps reach past the ends along the diagonal; pulled in so the ink is the 12 square.
    const reach = HotListTheme.closeSize / 2 - stroke / 2 / math.sqrt2;
    final centre = size.center(Offset.zero);
    final paint = Paint()
      ..color = HotListTheme.sheetInk
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(centre.translate(-reach, -reach), centre.translate(reach, reach), paint)
      ..drawLine(centre.translate(reach, -reach), centre.translate(-reach, reach), paint);
  }

  @override
  bool shouldRepaint(_ClosePainter oldDelegate) => false;
}

/// Facebook's, X's and WhatsApp's marks on their circles, which the APK doesn't carry: drawn on a 44 grid measured
/// off 217.
class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.target);

  final HotShareTarget target;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 44);
    final circle = Path()..addOval(const Rect.fromLTWH(0, 0, 44, 44));
    final mark = Paint()..color = HotListTheme.brandMark;
    switch (target) {
      case HotShareTarget.facebook:
        canvas
          ..clipPath(circle)
          ..drawPath(circle, Paint()..color = HotListTheme.facebookFill)
          ..drawPath(
            Path()
              ..moveTo(18.73, 45)
              ..lineTo(18.73, 16)
              ..arcToPoint(const Offset(25, 9.17), radius: const Radius.circular(6.4))
              ..lineTo(31.67, 9.17)
              ..lineTo(31.67, 14.93)
              ..lineTo(27.4, 14.93)
              ..arcToPoint(const Offset(25.17, 17.1), radius: const Radius.circular(2.2), clockwise: false)
              ..lineTo(25.17, 45)
              ..close(),
            mark,
          )
          ..drawPath(_polygon(const [(13.33, 21.83), (31.33, 21.83), (30.73, 28.17), (13.33, 28.17)]), mark);
      case HotShareTarget.x:
        canvas
          ..drawPath(circle, Paint()..color = HotListTheme.xFill)
          ..drawPath(_polygon(const [(9.83, 10.73), (17.5, 10.73), (34.33, 33.27), (26.67, 33.27)]), mark)
          ..drawPath(
            _polygon(const [(14.17, 13), (16.5, 13), (30, 30.83), (27.5, 30.83)]),
            Paint()..color = HotListTheme.xFill,
          )
          ..drawPath(_polygon(const [(28.83, 10.73), (32.93, 10.73), (14.17, 33.27), (10.07, 33.27)]), mark);
      case HotShareTarget.whatsApp:
        const centre = Offset(21.75, 21.7);
        const radius = 11.78;
        final ring = Paint()
          ..color = HotListTheme.brandMark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.55
          ..strokeJoin = StrokeJoin.miter;
        Offset on(double degrees) =>
            centre + Offset(math.cos(degrees * math.pi / 180), math.sin(degrees * math.pi / 180)) * radius;
        // The bubble: the ring the long way round from the lower left, its tail pointing down-left in the gap.
        final bubble = Path()
          ..moveTo(on(115).dx, on(115).dy)
          ..lineTo(10.6, 33.2)
          ..lineTo(on(155).dx, on(155).dy)
          ..arcTo(Rect.fromCircle(center: centre, radius: radius), 155 * math.pi / 180, 320 * math.pi / 180, false)
          ..close();
        canvas
          ..drawPath(circle, Paint()..color = HotListTheme.whatsAppFill)
          ..drawPath(bubble, ring)
          ..drawPath(
            Path()
              ..moveTo(17.4, 19.5)
              ..quadraticBezierTo(17.6, 25.4, 25.6, 26.5),
            Paint()
              ..color = HotListTheme.brandMark
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..strokeCap = StrokeCap.round,
          );
        _earpiece(canvas, const Offset(17.6, 18), const Size(4.2, 5.6), mark);
        _earpiece(canvas, const Offset(26.9, 25.9), const Size(5.6, 4.2), mark);
      case HotShareTarget.weChat || HotShareTarget.moments || HotShareTarget.download || HotShareTarget.qq:
        break;
    }
    canvas.restore();
  }

  static Path _polygon(List<(double, double)> points) {
    final path = Path()..moveTo(points.first.$1, points.first.$2);
    for (final (x, y) in points.skip(1)) {
      path.lineTo(x, y);
    }
    return path..close();
  }

  /// One end of the handset: a short rounded bar, tilted as 217's.
  static void _earpiece(Canvas canvas, Offset centre, Size size, Paint paint) {
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(-0.25)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height),
          Radius.circular(math.min(size.width, size.height) / 2),
        ),
        paint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) => oldDelegate.target != target;
}
