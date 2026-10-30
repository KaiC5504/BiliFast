import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/app_scope.dart';
import '../../app/swipe_back_route.dart';
import '../../shared/theme.dart';
import '../../skin/skin.dart';
import '../offline_library.dart';
import '../offline_models.dart';
import 'downloading_page.dart';
import 'offline_bar.dart';
import 'offline_group_page.dart';
import 'offline_page_kit.dart';
import 'offline_rows.dart';
import 'offline_selector.dart';
import 'offline_shelf.dart';

/// 离线缓存 (143, 145, 155, 157), from 我的's and the avatar page's shortcut and the 缓存 sheet's 查看缓存.
Future<void> openOfflineList(BuildContext context) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const OfflineListPage()));

typedef _T = OfflineListTheme;

/// 离线缓存: 正在缓存's one stacked row (it opens 正在缓存), then 已缓存视频: 合集s and multi-part videos as one row each
/// (they open their page, 156), every other part on its own (it plays, 158). 🔍 searches the finished parts (151); ☰
/// is edit mode over the rows (no screenshot; 149's). Opening it clears 查看缓存's dot.
class OfflineListPage extends StatefulWidget {
  const OfflineListPage({super.key, this.library, this.skin, this.openItem});

  /// [AppScope]'s by default.
  final OfflineLibrary? library;
  final ValueListenable<Skin?>? skin;
  final OfflineOpener? openItem;

  static const emptyMessage = '还没有缓存的视频';
  static const noResults = '没有找到相关的缓存';

  @override
  State<OfflineListPage> createState() => _OfflineListPageState();
}

class _OfflineListPageState extends State<OfflineListPage> with OfflineEditing {
  OfflineLibrary? _library;
  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false;
  String _query = '';

  @override
  OfflineLibrary get library => _library!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_library != null) return;
    final library = _library = widget.library ?? AppScope.of(context).offline;
    // Both tell the library's listeners at once, and the page is still building.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      library.markSeen();
      unawaited(library.refreshFreeSpace());
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Map<String, List<int>> selectable() => _rows(OfflineShelf.of(library));

  static Map<String, List<int>> _rows(OfflineShelf shelf) => {
    if (shelf.queued.isNotEmpty) 'queue': shelf.queued,
    for (final entry in shelf.done) entry.key: entry.cids,
  };

  void _back() {
    if (closeEditLayer()) return;
    if (_searching) {
      _cancelSearch();
    }
  }

  void _startSearch() {
    if (editing) return;
    setState(() => _searching = true);
  }

  void _cancelSearch() {
    _focus.unfocus();
    _field.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  void _queryChanged(String text) => setState(() => _query = text);

  void _clearQuery() {
    _field.clear();
    setState(() => _query = '');
  }

  void _open(OfflineItem item) {
    _focus.unfocus();
    (widget.openItem ?? openItemPage)(context, item);
  }

  void _openQueue() => unawaited(
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        builder: (_) => DownloadingPage(library: widget.library, skin: widget.skin),
      ),
    ),
  );

  void _openGroup(GroupEntry entry) => unawaited(
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        builder: (_) => OfflineGroupPage(
          group: entry.group,
          title: entry.title,
          library: widget.library,
          skin: widget.skin,
          openItem: widget.openItem,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => offlineScaffold(
    skin: widget.skin ?? AppScope.of(context).skin,
    canPop: !editing && !_searching,
    onBack: _back,
    builder: (look) => LibrarySelector<OfflineShelf>(
      library: library,
      select: OfflineShelf.of,
      builder: (context, shelf) {
        pruneSelection();
        final Widget bar;
        final Widget body;
        if (_searching) {
          bar = OfflineSearchBar(
            look: look,
            field: _field,
            focus: _focus,
            onChanged: _queryChanged,
            onClear: _clearQuery,
            onCancel: _cancelSearch,
          );
          body = _results();
        } else {
          bar = OfflineBar(
            look: look,
            title: '离线缓存',
            onBack: () => unawaited(Navigator.of(context).maybePop()),
            onSearch: _startSearch,
            onEdit: shelf.done.isEmpty ? null : startEdit,
            onDone: editing ? endEdit : null,
          );
          body = _shelf(shelf);
        }
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar,
                Expanded(child: body),
                if (editing) editBar() else if (!_searching) SpaceFooter(library: library),
              ],
            ),
            if (confirming) confirmLayer(),
          ],
        );
      },
    ),
  );

  Widget _shelf(OfflineShelf shelf) {
    if (shelf.isEmpty) return const OfflineEmptyNote(OfflineListPage.emptyMessage);
    final queued = shelf.queued;
    final done = shelf.done;
    return offlineScroll(context, key: const ValueKey('offline-list'), [
      if (queued.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('正在缓存')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: _T.row,
            child: ListenableBuilder(
              listenable: selection,
              builder: (context, _) => QueueStackRow(
                library: library,
                cids: queued,
                editing: editing,
                chosen: selection.contains('queue'),
                onTap: editing ? () => toggle('queue', queued) : _openQueue,
              ),
            ),
          ),
        ),
      ],
      if (done.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('已缓存视频')),
        SliverFixedExtentList.builder(
          itemExtent: _T.row,
          itemCount: done.length,
          itemBuilder: (context, index) => _entry(done[index], divider: index < done.length - 1),
        ),
      ],
    ]);
  }

  Widget _entry(ShelfEntry entry, {required bool divider}) => ListenableBuilder(
    key: ValueKey('offline-entry-${entry.key}'),
    listenable: selection,
    builder: (context, _) {
      final chosen = selection.contains(entry.key);
      return switch (entry) {
        SingleEntry(:final cid) => DoneRow(
          library: library,
          cid: cid,
          editing: editing,
          chosen: chosen,
          divider: divider,
          onTap: editing ? (_) => toggle(entry.key, entry.cids) : _open,
        ),
        GroupEntry() => GroupRow(
          library: library,
          entry: entry,
          editing: editing,
          chosen: chosen,
          divider: divider,
          onTap: editing ? () => toggle(entry.key, entry.cids) : () => _openGroup(entry),
        ),
      };
    },
  );

  /// 151: nothing until there are words; then the finished parts they find, each on its own.
  Widget _results() {
    if (_query.trim().isEmpty) return const SizedBox.expand(key: ValueKey('offline-search-blank'));
    return LibrarySelector<List<int>>(
      library: library,
      select: (library) => searchFinished(library, _query),
      equals: listEquals,
      builder: (context, cids) {
        if (cids.isEmpty) return const OfflineEmptyNote(OfflineListPage.noResults);
        return offlineScroll(context, key: const ValueKey('offline-results'), [
          SliverFixedExtentList.builder(
            itemExtent: _T.row,
            itemCount: cids.length,
            itemBuilder: (context, index) => DoneRow(
              key: ValueKey('offline-result-${cids[index]}'),
              library: library,
              cid: cids[index],
              editing: false,
              chosen: false,
              divider: index < cids.length - 1,
              onTap: _open,
            ),
          ),
        ]);
      },
    );
  }
}
