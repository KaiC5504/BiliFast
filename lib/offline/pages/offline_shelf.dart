import 'package:flutter/foundation.dart';

import '../offline_library.dart';
import '../offline_models.dart';

/// One line of 已缓存视频: a part on its own, or a 合集's or a multi-part video's finished parts under one row (155).
@immutable
sealed class ShelfEntry {
  const ShelfEntry();

  /// Every part the line stands for, in the order its page lists them.
  List<int> get cids;

  /// Steady across rebuilds, for the row's key and the selection.
  String get key;
}

final class SingleEntry extends ShelfEntry {
  const SingleEntry(this.cid);

  final int cid;

  @override
  List<int> get cids => [cid];

  @override
  String get key => 'p$cid';

  @override
  bool operator ==(Object other) => other is SingleEntry && other.cid == cid;

  @override
  int get hashCode => cid.hashCode;
}

final class GroupEntry extends ShelfEntry {
  const GroupEntry({required this.group, required this.title, required this.cids});

  final ShelfGroup group;
  final String title;

  @override
  final List<int> cids;

  @override
  String get key => group.key;

  @override
  bool operator ==(Object other) =>
      other is GroupEntry && other.group == group && other.title == title && listEquals(other.cids, cids);

  @override
  int get hashCode => Object.hash(group, title, Object.hashAll(cids));
}

/// What a group gathers: a 合集 by its id, or a video's parts by its BV.
@immutable
final class ShelfGroup {
  const ShelfGroup.collection(int this.collection) : bvid = null;
  const ShelfGroup.video(String this.bvid) : collection = null;

  final int? collection;
  final String? bvid;

  String get key => collection != null ? 'c$collection' : 'v$bvid';

  bool holds(OfflineRequest request) =>
      collection != null ? request.collection?.id == collection : request.collection == null && request.bvid == bvid;

  @override
  bool operator ==(Object other) => other is ShelfGroup && other.collection == collection && other.bvid == bvid;

  @override
  int get hashCode => Object.hash(collection, bvid);
}

/// The shape of 离线缓存: the unfinished parts in the order they were queued, and 已缓存视频's lines newest first. Equal
/// shelves draw the same rows, so progress alone never rebuilds the page.
@immutable
final class OfflineShelf {
  const OfflineShelf({required this.queued, required this.done});

  static const empty = OfflineShelf(queued: [], done: []);

  final List<int> queued;
  final List<ShelfEntry> done;

  bool get isEmpty => queued.isEmpty && done.isEmpty;

  /// A 合集's parts share a line; so do two or more finished parts of one video outside a 合集. A line sits where its
  /// newest part was added.
  static OfflineShelf of(OfflineLibrary library) {
    final items = library.items;
    final queued = [
      for (final item in items.reversed)
        if (!item.isDone) item.cid,
    ];
    final finished = [
      for (final item in items)
        if (item.isDone) item,
    ];
    final partsOf = <String, int>{};
    for (final item in finished) {
      if (item.request.collection == null) partsOf.update(item.request.bvid, (n) => n + 1, ifAbsent: () => 1);
    }
    final done = <ShelfEntry>[];
    final seen = <ShelfGroup>{};
    for (final item in finished) {
      final request = item.request;
      final collection = request.collection;
      final ShelfGroup group;
      if (collection != null) {
        group = ShelfGroup.collection(collection.id);
      } else if ((partsOf[request.bvid] ?? 0) > 1) {
        group = ShelfGroup.video(request.bvid);
      } else {
        done.add(SingleEntry(item.cid));
        continue;
      }
      if (!seen.add(group)) continue;
      done.add(
        GroupEntry(
          group: group,
          title: collection?.title ?? request.title,
          cids: [for (final part in groupParts(finished, group)) part.cid],
        ),
      );
    }
    return OfflineShelf(queued: queued, done: done);
  }

  @override
  bool operator ==(Object other) =>
      other is OfflineShelf && listEquals(other.queued, queued) && listEquals(other.done, done);

  @override
  int get hashCode => Object.hash(Object.hashAll(queued), Object.hashAll(done));
}

/// A group's finished parts as its page lists them: a 合集's in the order they were added (156), a video's by part.
List<OfflineItem> groupParts(Iterable<OfflineItem> items, ShelfGroup group) {
  final parts = [
    for (final item in items)
      if (item.isDone && group.holds(item.request)) item,
  ];
  if (group.collection != null) {
    parts.sort((a, b) => a.addedAt.compareTo(b.addedAt));
  } else {
    parts.sort((a, b) => a.request.page.compareTo(b.request.page));
  }
  return parts;
}

/// The finished parts whose title, part title or uploader holds [query] (ignoring case), newest first.
List<int> searchFinished(OfflineLibrary library, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  bool holds(String? text) => text != null && text.toLowerCase().contains(needle);
  return [
    for (final item in library.items)
      if (item.isDone && (holds(item.request.title) || holds(item.request.partTitle) || holds(item.request.ownerName)))
        item.cid,
  ];
}
