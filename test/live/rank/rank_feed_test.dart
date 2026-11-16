import 'package:bili_core/api.dart';
import 'package:bilifast/live/rank/live_rank_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rank_support.dart';

LiveRankPage _page(Iterable<int> uids, {int firstRank = 1, bool hasMore = true}) => LiveRankPage(
  entries: [for (final (index, uid) in uids.indexed) LiveRankEntry(rank: firstRank + index, user: viewer(uid))],
  hasMore: hasMore,
);

void main() {
  test("a next page overlapping the last (ranks moved) drops the repeats and keeps paging", () async {
    final pages = {
      1: _page([for (var uid = 1; uid <= 20; uid++) uid]),
      // Three viewers slid down a page between the calls.
      2: _page([for (var uid = 18; uid <= 30; uid++) uid], firstRank: 21),
      3: _page([for (var uid = 31; uid <= 35; uid++) uid], firstRank: 34, hasMore: false),
    };
    final asked = <int>[];
    final feed = RankFeed<LiveRankPage>(
      name: 'audience',
      load: (page) async {
        asked.add(page);
        return pages[page]!;
      },
      entries: (answer) => answer.entries,
      hasMore: (answer) => answer.hasMore,
    );
    addTearDown(feed.dispose);

    Future<void> landed() => Future<void>.delayed(Duration.zero);

    feed.start();
    await landed();
    expect(feed.entries, hasLength(20));

    feed.loadMore();
    await landed();
    expect([for (final entry in feed.entries) entry.user.uid], [for (var uid = 1; uid <= 30; uid++) uid]);
    // uid 18 keeps the rank it was first shown with.
    expect(feed.entries[17].rank, 18);
    expect(feed.canLoadMore, isTrue);

    feed.loadMore();
    await landed();
    expect(asked, [1, 2, 3]);
    expect([for (final entry in feed.entries) entry.user.uid], [for (var uid = 1; uid <= 35; uid++) uid]);
    expect(feed.exhausted, isTrue);
    feed.loadMore();
    await landed();
    expect(asked, [1, 2, 3]);
  });
}
