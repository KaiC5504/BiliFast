import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/app_scope.dart';
import '../../shared/theme.dart';
import '../../skin/skin.dart';
import '../offline_library.dart';
import '../offline_models.dart';
import 'offline_bar.dart';
import 'offline_page_kit.dart';
import 'offline_rows.dart';
import 'offline_selector.dart';
import 'offline_shelf.dart';

typedef _T = OfflineListTheme;

/// A 合集's page (156), or a multi-part video's (no screenshot, the same with each part by its name): its finished
/// parts, each playing on a tap; ☰ is edit mode. Once its last part is deleted it closes.
class OfflineGroupPage extends StatefulWidget {
  const OfflineGroupPage({super.key, required this.group, required this.title, this.library, this.skin, this.openItem});

  final ShelfGroup group;
  final String title;

  /// [AppScope]'s by default.
  final OfflineLibrary? library;
  final ValueListenable<Skin?>? skin;
  final OfflineOpener? openItem;

  @override
  State<OfflineGroupPage> createState() => _OfflineGroupPageState();
}

class _OfflineGroupPageState extends State<OfflineGroupPage> with OfflineEditing {
  OfflineLibrary? _library;
  bool _closing = false;

  @override
  OfflineLibrary get library => _library!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _library ??= widget.library ?? AppScope.of(context).offline;
  }

  List<int> _parts(OfflineLibrary library) => [for (final item in groupParts(library.items, widget.group)) item.cid];

  @override
  Map<String, List<int>> selectable() => {
    for (final cid in _parts(library)) '$cid': [cid],
  };

  String? _partTitle(OfflineItem item) =>
      widget.group.bvid == null ? null : item.request.partTitle ?? 'P${item.request.page}';

  void _close() {
    if (_closing) return;
    _closing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(Navigator.of(context).maybePop());
    });
  }

  @override
  Widget build(BuildContext context) => offlineScaffold(
    skin: widget.skin ?? AppScope.of(context).skin,
    canPop: !editing,
    onBack: closeEditLayer,
    builder: (look) => LibrarySelector<List<int>>(
      library: library,
      select: _parts,
      equals: listEquals,
      builder: (context, parts) {
        pruneSelection();
        if (parts.isEmpty) _close();
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OfflineBar(
                  look: look,
                  title: widget.title,
                  onBack: () => unawaited(Navigator.of(context).maybePop()),
                  onEdit: parts.isEmpty ? null : startEdit,
                  onDone: editing ? endEdit : null,
                ),
                Expanded(
                  child: offlineScroll(context, key: const ValueKey('offline-group'), [
                    SliverFixedExtentList.builder(
                      itemExtent: _T.row,
                      itemCount: parts.length,
                      itemBuilder: (context, index) {
                        final cid = parts[index];
                        return ListenableBuilder(
                          key: ValueKey('offline-part-$cid'),
                          listenable: selection,
                          builder: (context, _) => DoneRow(
                            library: library,
                            cid: cid,
                            editing: editing,
                            chosen: selection.contains('$cid'),
                            divider: index < parts.length - 1,
                            titleOf: widget.group.bvid == null ? null : (item) => _partTitle(item)!,
                            onTap: editing
                                ? (_) => toggle('$cid', [cid])
                                : (item) => (widget.openItem ?? openItemPage)(context, item),
                          ),
                        );
                      },
                    ),
                  ]),
                ),
                if (editing) editBar() else SpaceFooter(library: library, centre: _T.folderFooterCentre),
              ],
            ),
            if (confirming) confirmLayer(),
          ],
        );
      },
    ),
  );
}
