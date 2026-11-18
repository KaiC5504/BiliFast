import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../history/history_glyphs.dart' show HistoryMorePainter;
import '../../search/results/video_row.dart' show SearchFormat, dotted, searchStyle;
import '../../shared/menu.dart' show PressHighlight;
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../space/uploader_tap.dart';

/// How 热门's rows word their plays and dates (204): "183.1万播放 · 昨天 11:20", "23小时前", "2天前".
abstract final class HotFormat {
  /// The calendar days back that read N天前; before them [SearchFormat.date]'s 昨天 HH:mm, after them its M月D日.
  static const daysAgo = 3;

  /// [SearchFormat.date], with 2 to [daysAgo] calendar days back as N天前; '' when unknown.
  static String date(DateTime? published, {required DateTime now, Duration? utcOffset}) {
    if (published == null) return '';
    if (now.difference(published) >= const Duration(days: 1)) {
      final days = _calendarDays(published, now, utcOffset);
      if (days >= 2 && days <= daysAgo) return '$days天前';
    }
    return SearchFormat.date(published, now: now, utcOffset: utcOffset);
  }

  static int _calendarDays(DateTime then, DateTime now, Duration? utcOffset) {
    DateTime day(DateTime instant) {
      final wall = instant.toUtc().add(utcOffset ?? instant.toLocal().timeZoneOffset);
      return DateTime.utc(wall.year, wall.month, wall.day);
    }

    return day(now).difference(day(then)).inDays;
  }

  /// The ▷ line: the plays and the date, the date left out when unknown.
  static String plays(PopularVideo video, {required DateTime now, Duration? utcOffset}) {
    final count = '${SearchFormat.count(video.card.views)}播放';
    final when = date(video.published, now: now, utcOffset: utcOffset);
    return when.isEmpty ? count : '$count · $when';
  }
}

/// A 热门 row (204): the cover with its length, the title in two lines, the uploader (whose space a tap on the name
/// opens), the plays and the date, ⋮, and the line under it all.
class HotRow extends StatelessWidget {
  const HotRow({super.key, required this.video, required this.now, required this.onOpen, required this.onMore});

  final PopularVideo video;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  static const height = HotListTheme.rowHeight;

  static const _coverBottom = HotListTheme.coverTop + HotListTheme.coverHeight;
  static const _metaRight = HotListTheme.moreCentreRight + HotListTheme.moreTarget / 2;
  static const _upTop = _coverBottom - HotListTheme.upCentreAbove - HotListTheme.metaLine / 2;
  static const _playsTop = _coverBottom - HotListTheme.playsCentreAbove - HotListTheme.metaLine / 2;

  @override
  Widget build(BuildContext context) {
    final card = video.card;
    final titleStyle = searchStyle(HotListTheme.titleText, HotListTheme.titleInk, line: HotListTheme.titleLine);
    final plays = HotFormat.plays(video, now: now);
    final length = card.duration > 0 ? '，${SearchFormat.duration(card.duration)}' : '';
    final uploader = card.ownerMid > 0 && card.ownerName.isNotEmpty;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              label: '${card.title}，${card.ownerName}$length，$plays',
              onTap: onOpen,
              excludeSemantics: true,
              child: PressHighlight(
                key: ValueKey('hot-row-${card.bvid}'),
                onTap: onOpen,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: HotListTheme.gutter,
            top: HotListTheme.coverTop,
            width: HotListTheme.coverWidth,
            height: HotListTheme.coverHeight,
            child: IgnorePointer(child: _Cover(card: card)),
          ),
          Positioned(
            left: HotListTheme.titleLeft,
            right: HotListTheme.titleRight,
            top: HotListTheme.coverTop + HotListTheme.titleTop,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Text(
                  card.title,
                  key: ValueKey('hot-title-${card.bvid}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                  strutStyle: BiliFonts.strut(titleStyle),
                ),
              ),
            ),
          ),
          Positioned(
            left: HotListTheme.metaLeft,
            right: _metaRight,
            top: _upTop - HotListTheme.uploaderSlopAbove,
            child: Align(
              alignment: Alignment.topLeft,
              child: uploader
                  ? _Uploader(card: card)
                  : IgnorePointer(
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.only(top: HotListTheme.uploaderSlopAbove),
                          child: _MetaLine(icon: _upIcon, text: card.ownerName),
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            left: HotListTheme.metaLeft,
            right: _metaRight,
            top: _playsTop,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: _MetaLine(key: ValueKey('hot-plays-${card.bvid}'), icon: _playIcon, text: plays),
              ),
            ),
          ),
          Positioned(
            right: HotListTheme.moreCentreRight - HotListTheme.moreTarget / 2,
            width: HotListTheme.moreTarget,
            top: _coverBottom - HotListTheme.playsCentreAbove - HotListTheme.moreTarget / 2,
            height: HotListTheme.moreTarget,
            child: Semantics(
              button: true,
              label: '更多操作',
              onTap: onMore,
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('hot-more-${card.bvid}'),
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: const CustomPaint(painter: HistoryMorePainter()),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: HotListTheme.hairlineTop,
            height: HotListTheme.hairline,
            child: ColoredBox(color: HotListTheme.hairlineInk),
          ),
        ],
      ),
    );
  }
}

const _upIcon = 'assets/images/card/up_badge.png';
const _playIcon = 'assets/images/home/hot_play_counts.png';

// Half the gap down to the ▷ line, so that line stays the row's.
const _slopBelow = (HotListTheme.upCentreAbove - HotListTheme.playsCentreAbove - HotListTheme.metaLine) / 2;

/// The UP line as one target, as wide as the drawn name: the uploader's space.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.card});

  final VideoCard card;

  @override
  Widget build(BuildContext context) {
    void open() => openUploader(
      context,
      UploaderRef(mid: card.ownerMid, name: card.ownerName, face: card.ownerFace.isEmpty ? null : card.ownerFace),
    );
    return Semantics(
      button: true,
      label: card.ownerName,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('hot-uploader-${card.bvid}'),
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.only(top: HotListTheme.uploaderSlopAbove, bottom: _slopBelow),
          child: _MetaLine(icon: _upIcon, text: card.ownerName),
        ),
      ),
    );
  }
}

/// An icon and one line of grey words after it, as wide as they are drawn.
class _MetaLine extends StatelessWidget {
  const _MetaLine({super.key, required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = searchStyle(HotListTheme.metaText, HotListTheme.metaInk, line: HotListTheme.metaLine);
    return SizedBox(
      height: HotListTheme.metaLine,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            icon,
            width: HotListTheme.metaIconWidth,
            height: HotListTheme.metaIconHeight,
            color: HotListTheme.metaInk,
            colorBlendMode: BlendMode.srcIn,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: HotListTheme.metaIconGap),
          Flexible(
            child: Text.rich(
              dotted(text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
              strutStyle: BiliFonts.strut(style),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.card});

  final VideoCard card;

  @override
  Widget build(BuildContext context) {
    final style = searchStyle(HotListTheme.durationText, HotListTheme.durationInk, line: HotListTheme.durationHeight);
    return ClipRRect(
      borderRadius: BorderRadius.circular(HotListTheme.coverRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (card.cover.isEmpty)
            ColoredBox(key: const ValueKey('hot-cover-placeholder'), color: HotListTheme.coverPlaceholder)
          else
            RemoteImage(card.cover, size: const Size(HotListTheme.coverWidth, HotListTheme.coverHeight), cover: true),
          if (card.duration > 0)
            Positioned(
              right: HotListTheme.durationRight,
              bottom: HotListTheme.durationBottom,
              height: HotListTheme.durationHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: HotListTheme.durationFill,
                  borderRadius: BorderRadius.circular(HotListTheme.durationRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: HotListTheme.durationPadX),
                  child: Center(widthFactor: 1, child: Text(SearchFormat.duration(card.duration), style: style)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
