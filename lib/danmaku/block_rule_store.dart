import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../video/page_api.dart';

/// The account's 弹幕屏蔽词 (BiliNative `BlockRuleStore.swift`), shared by every page: fetched from the server and
/// kept for 10 minutes, added to and deleted from there, so the official app sees the same list.
// Contracts stub: slice 5's block-words agent writes it.
class BlockRuleStore extends ChangeNotifier {
  BlockRuleStore({
    required PageApi api,
    required bool Function() isLoggedIn,
    DateTime Function()? now,
    Logger? logger,
  });

  List<BlockRule> get rules => const [];

  bool get loading => false;

  /// Asks the server unless the list is younger than 10 minutes; [force] (同步) always asks.
  Future<void> refresh({bool force = false}) async {}

  /// The message to show, or null once it is added.
  Future<String?> add(BlockRuleKind kind, String filter) async => '暂不可用';

  /// The message to show, or null once it is gone.
  Future<String?> remove(BlockRule rule) async => '暂不可用';
}
