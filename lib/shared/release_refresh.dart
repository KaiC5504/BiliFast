import 'package:flutter/cupertino.dart';

import 'loading_tv.dart';
import 'theme.dart';

/// The pull to refresh every list uses: arms once pulled past [refreshTriggerPullDistance] but refreshes only when the
/// finger lets go, as everywhere in the official app (107). Drawn by [loadingTvRefreshIndicator] by default.
class ReleaseRefreshControl extends StatelessWidget {
  const ReleaseRefreshControl({
    super.key,
    required this.onRefresh,
    this.builder = loadingTvRefreshIndicator,
    this.refreshTriggerPullDistance = 100,
    this.refreshIndicatorExtent = LoadingTvTheme.size,
  });

  final RefreshCallback? onRefresh;
  final RefreshControlIndicatorBuilder? builder;
  final double refreshTriggerPullDistance;
  final double refreshIndicatorExtent;

  // Stub: Cupertino's control until the pull agent lands (it refreshes while still pulled).
  @override
  Widget build(BuildContext context) => CupertinoSliverRefreshControl(
    onRefresh: onRefresh,
    builder: builder,
    refreshTriggerPullDistance: refreshTriggerPullDistance,
    refreshIndicatorExtent: refreshIndicatorExtent,
  );
}
