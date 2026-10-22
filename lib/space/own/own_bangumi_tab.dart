import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../space_api.dart';
import 'own_tab_cards.dart';
import 'own_tab_paging.dart';

/// 追番 (117): three posters a row with the title and progress over each, paged, ending in 再怎么找也没有啦. 番剧 isn't
/// built, so a poster says so.
class OwnBangumiSliver extends StatefulWidget {
  const OwnBangumiSliver({super.key, required this.mid});

  final int mid;

  static const endMessage = '再怎么找也没有啦';

  @override
  State<OwnBangumiSliver> createState() => _OwnBangumiSliverState();
}

class _OwnBangumiSliverState extends State<OwnBangumiSliver> with OwnPaging<OwnBangumiSliver, SpaceBangumiCard> {
  late SpaceApi _api;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _api = AppScope.of(context).spaceApi;
    restartPaging();
  }

  @override
  void didUpdateWidget(OwnBangumiSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mid != widget.mid) restartPaging();
  }

  @override
  String get pagingName => 'own bangumi';

  @override
  Object idOf(SpaceBangumiCard item) => item.seasonId;

  @override
  Future<OwnPage<SpaceBangumiCard>> fetchPage(int page) async {
    final answer = await _api.bangumi(widget.mid, page: page);
    return (items: answer.items, hasMore: answer.hasMore);
  }

  @override
  Widget build(BuildContext context) {
    final posters = items;
    final rows = (posters.length + 2) ~/ 3;
    final end = ownStyle(OwnSpaceTabsTheme.endText, OwnSpaceTabsTheme.endInk, line: OwnSpaceTabsTheme.endLine);
    const endTop = OwnSpaceTabsTheme.endCentre - OwnSpaceTabsTheme.endLine / 2;
    return DecoratedSliver(
      decoration: const BoxDecoration(color: OwnSpaceTabsTheme.greyPage),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (posters.isEmpty && (!loaded || failed))
            SliverToBoxAdapter(
              child: OwnFirstLoad(keyPrefix: 'own-bangumi', failed: failed, onRetry: retryPaging),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                OwnSpaceTabsTheme.gutter,
                OwnSpaceTabsTheme.bangumiTop,
                OwnSpaceTabsTheme.gutter,
                0,
              ),
              sliver: SliverList.separated(
                itemCount: rows,
                separatorBuilder: (context, index) => const SizedBox(height: OwnSpaceTabsTheme.posterGap),
                itemBuilder: (context, row) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = row * 3; i < row * 3 + 3; i++) ...[
                      if (i > row * 3) const SizedBox(width: OwnSpaceTabsTheme.posterGap),
                      Expanded(
                        child: i < posters.length
                            ? OwnPoster(
                                key: ValueKey('own-bangumi-${posters[i].seasonId}'),
                                bangumi: posters[i],
                                onTap: () => showToast(context, '暂未开放'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: loading || failed
                  ? OwnPagingFooter(keyPrefix: 'own-bangumi', failed: failed, onRetry: retryPaging)
                  : !hasMore
                  ? Padding(
                      padding: const EdgeInsets.only(top: endTop, bottom: OwnSpaceTabsTheme.endBottom),
                      child: Text(
                        OwnBangumiSliver.endMessage,
                        key: const ValueKey('own-bangumi-end'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: end,
                        strutStyle: BiliFonts.strut(end),
                      ),
                    )
                  : const SizedBox(height: endTop + OwnSpaceTabsTheme.endLine + OwnSpaceTabsTheme.endBottom),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
          const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
