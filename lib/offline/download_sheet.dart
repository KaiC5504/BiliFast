import 'package:bili_core/logic.dart' show QualityNames;
import 'package:flutter/widgets.dart';

import '../app/app_scope.dart';
import '../player_ui/player_ui.dart';
import '../shared/theme.dart';
import 'offline_library.dart';
import 'offline_models.dart';
import 'offline_size.dart';
import 'pages/offline_list_page.dart';
import 'sheet/download_entries.dart';
import 'sheet/download_rows.dart';
import 'sheet/quality_picker.dart';
import 'sheet/sheet_art.dart';

/// 缓存 (141, 144, 153, 154): 画质 with its picker (142), the part or the 合集's videos with each one's state, 缓存全部,
/// 查看缓存 and the space line.
class DownloadSheet extends StatefulWidget {
  const DownloadSheet({super.key, required this.ui, required this.toast, required this.close, this.cover});

  final PlayerUi ui;
  final void Function(String message) toast;
  final VoidCallback close;

  /// Puts a layer over the whole page (画质's picker dims the player too), or takes it off with null.
  final ValueChanged<Widget?>? cover;

  /// 已使用 78.6M / 剩余 74.4G: the sheet drops the B that 离线缓存 writes (144); nothing used, or unknown, is - (141).
  static String space(int? bytes) =>
      bytes == null || bytes <= 0 ? '-' : formatBytes(bytes).replaceFirst(RegExp(r'B$'), '');

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  int? _quality;
  final _current = GlobalKey();
  var _revealed = false;

  OfflineLibrary? get _library => context.getInheritedWidgetOfExactType<AppScope>()?.services.offline;

  void _revealCurrent() {
    if (_revealed) return;
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current.currentContext case final current? when mounted) {
        Scrollable.ensureVisible(current, alignment: 0.5);
      }
    });
  }

  int? _selected() {
    final qualities = downloadQualities(widget.ui.session);
    final chosen = _quality;
    if (chosen != null && qualities.options.any((option) => option.id == chosen)) return chosen;
    return qualities.best;
  }

  int? _estimate(int? quality, int seconds) {
    final dash = widget.ui.session.dash;
    if (dash == null || quality == null) return null;
    return estimateBytes(dash, quality: quality, seconds: seconds, codecOrder: [widget.ui.session.codec]);
  }

  Future<void> _queue(OfflineLibrary library, List<DownloadEntry> entries, int? quality) async {
    final parts = [
      for (final entry in entries)
        if (library.item(entry.cid) == null) entry.request,
    ];
    if (parts.isEmpty) return;
    await library.enqueue(parts, quality: quality);
  }

  void _tap(OfflineLibrary library, DownloadEntry entry, int? quality) {
    final item = library.item(entry.cid);
    if (item == null) {
      _queue(library, [entry], quality);
      return;
    }
    switch (item.state) {
      case OfflineState.paused || OfflineState.failed:
        library.resume(entry.cid);
      case OfflineState.waiting || OfflineState.downloading || OfflineState.done:
        break;
    }
  }

  void _openPicker(int? selected) {
    final cover = widget.cover;
    if (cover == null) return;
    final session = widget.ui.session;
    final seconds = session.part?.duration ?? session.duration.value.round();
    final options = downloadQualities(session).options;
    cover(
      QualityPicker(
        options: options,
        selected: selected,
        sizes: {for (final option in options) option.id: ?_estimate(option.id, seconds)},
        onPick: (quality) {
          if (mounted) setState(() => _quality = quality);
        },
        dismissed: () => cover(null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    if (library == null) return const SizedBox.shrink();
    // Landscape's side panel scrolls its content; 缓存 is portrait only and closes there (PanelLayer).
    return LayoutBuilder(
      builder: (context, constraints) => !constraints.hasBoundedHeight
          ? const SizedBox.shrink()
          : ListenableBuilder(listenable: library, builder: (context, _) => _sheet(context, library)),
    );
  }

  Widget _sheet(BuildContext context, OfflineLibrary library) {
    final session = widget.ui.session;
    final entries = downloadEntries(session);
    final quality = _selected();
    final collection = entries.any((entry) => entry.cover != null);
    if (collection) _revealCurrent();
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          name: quality == null
              ? '-'
              : QualityNames.full(
                  qn: quality,
                  serverText: session.qualities.where((option) => option.id == quality).firstOrNull?.name,
                ),
          onTap: widget.cover == null || quality == null ? null : () => _openPicker(quality),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey('download-list'),
            primary: false,
            padding: EdgeInsets.only(
              left: DownloadSheetTheme.cardInset,
              right: DownloadSheetTheme.cardInset,
              bottom: collection ? 0 : DownloadSheetTheme.rowGap,
            ),
            children: [
              for (final (index, entry) in entries.indexed) ...[
                if (index > 0) const SizedBox(height: DownloadSheetTheme.rowGap),
                DownloadRow(
                  key: entry.current ? _current : ValueKey(entry.cid),
                  entry: entry,
                  item: library.item(entry.cid),
                  estimate: _estimate(quality, entry.request.duration),
                  onTap: () => _tap(library, entry, quality),
                ),
              ],
              if (collection)
                const SizedBox(
                  height: DownloadSheetTheme.footerCentre + DownloadSheetTheme.footerBottom,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: DownloadSheetTheme.footerCentre - _line / 2,
                        height: _line,
                        child: Center(child: Text('内容到底啦', style: _footer)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _Bar(
          bottom: bottom,
          unseen: library.unseen,
          used: library.usedBytes,
          free: library.freeBytes,
          queueAll: () => _queue(library, entries, quality),
          openList: () => openOfflineList(context),
        ),
      ],
    );
  }

  static const _footer = TextStyle(fontSize: BiliMetrics.sheetFooterText, color: BiliColors.sheetHint);
}

/// A box a line of the sheet's small text is centred in.
const _line = 24.0;

/// 画质, the chosen quality's name and ⌄; a tap opens the picker.
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  static const _label = TextStyle(fontSize: DownloadSheetTheme.headerText, color: DownloadSheetTheme.grey);
  static const _name = TextStyle(fontSize: DownloadSheetTheme.headerText, color: BiliColors.text);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: DownloadSheetTheme.listTop,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          top: DownloadSheetTheme.headerCentre - BiliMetrics.panelHitBox / 2,
          height: BiliMetrics.panelHitBox,
          child: SheetTap(
            key: const ValueKey('download-quality'),
            label: '画质 $name',
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DownloadSheetTheme.cardInset),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('画质', style: _label, strutStyle: BiliFonts.strutOf(context, _label)),
                  const SizedBox(width: DownloadSheetTheme.headerGap),
                  Text(name, style: _name, strutStyle: BiliFonts.strutOf(context, _name)),
                  const SizedBox(width: DownloadSheetTheme.headerChevronGap),
                  const CustomPaint(
                    size: Size(DownloadSheetTheme.headerChevronWidth, DownloadSheetTheme.headerChevronHeight),
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

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const half = 0.6;
    canvas.drawPath(
      Path()
        ..moveTo(half, half)
        ..lineTo(size.width / 2, size.height - half)
        ..lineTo(size.width - half, half),
      Paint()
        ..color = BiliColors.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = half * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => false;
}

/// The white bar (141): 缓存全部 | 查看缓存 (its red dot while something is new) over 已使用 X / 剩余 Y.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.bottom,
    required this.unseen,
    required this.used,
    required this.free,
    required this.queueAll,
    required this.openList,
  });

  final double bottom;
  final bool unseen;
  final int used;
  final int? free;
  final VoidCallback queueAll;
  final VoidCallback openList;

  static const _button = TextStyle(fontSize: DownloadSheetTheme.barButtonText, color: BiliColors.text);
  static const _label = TextStyle(fontSize: DownloadSheetTheme.barSpaceText, color: BiliColors.secondaryText);
  static const _value = TextStyle(fontSize: DownloadSheetTheme.barSpaceText, color: BiliColors.text);

  Widget _half(BuildContext context, String key, String title, VoidCallback onTap, {bool dot = false}) => Expanded(
    child: SheetTap(
      key: ValueKey(key),
      label: dot ? '$title，有新内容' : title,
      onTap: onTap,
      child: SizedBox(
        height: DownloadSheetTheme.barButtonCentre * 2,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(title, style: _button, strutStyle: BiliFonts.strutOf(context, _button)),
              if (dot)
                Positioned(
                  key: const ValueKey('download-unseen'),
                  right: -(DownloadSheetTheme.dotSize / 2 + DownloadSheetTheme.dotRing),
                  top: -DownloadSheetTheme.dotLift - DownloadSheetTheme.dotRing,
                  child: Container(
                    width: DownloadSheetTheme.dotSize + DownloadSheetTheme.dotRing * 2,
                    height: DownloadSheetTheme.dotSize + DownloadSheetTheme.dotRing * 2,
                    decoration: BoxDecoration(
                      color: DownloadSheetTheme.dot,
                      shape: BoxShape.circle,
                      border: Border.all(color: DownloadSheetTheme.card, width: DownloadSheetTheme.dotRing),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final space = Text.rich(
      key: const ValueKey('download-space'),
      TextSpan(
        children: [
          const TextSpan(text: '已使用 ', style: _label),
          TextSpan(text: DownloadSheet.space(used), style: _value),
          const TextSpan(text: ' / ', style: _label),
          const TextSpan(text: '剩余 ', style: _label),
          TextSpan(text: DownloadSheet.space(free), style: _value),
        ],
      ),
      strutStyle: BiliFonts.strutOf(context, _label),
    );
    return Container(
      height: DownloadSheetTheme.barHeight + bottom,
      decoration: const BoxDecoration(
        color: DownloadSheetTheme.card,
        border: Border(
          top: BorderSide(color: DownloadSheetTheme.hairline, width: BiliMetrics.panelHairline),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: DownloadSheetTheme.barButtonCentre * 2,
            child: Row(
              children: [
                _half(context, 'download-all', '缓存全部', queueAll),
                Container(
                  width: BiliMetrics.panelHairline,
                  height: DownloadSheetTheme.barDivider,
                  color: DownloadSheetTheme.hairline,
                ),
                _half(context, 'download-open-list', '查看缓存', openList, dot: unseen),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: DownloadSheetTheme.barSpaceCentre - _line / 2,
            height: _line,
            child: Center(child: space),
          ),
        ],
      ),
    );
  }
}
