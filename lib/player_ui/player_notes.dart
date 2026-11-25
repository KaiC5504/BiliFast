import 'dart:async';

import 'package:flutter/foundation.dart';

import '../shared/theme.dart';

/// One of a player's notes at the bottom left (live: 208's 已开启弹幕, 210's 切换中，请稍候 and 已成功切换至…; a video:
/// 274's Hi-Res无损音质开启中，请稍候 and 已开启).
@immutable
final class PlayerNote {
  const PlayerNote(this.id, this.text);

  final int id;
  final String text;
}

/// The notes showing, oldest first; each goes after [LivePlayerTheme.noteShown], and at most two stand at once.
class PlayerNotes extends ChangeNotifier {
  PlayerNotes({this.shownFor = LivePlayerTheme.noteShown});

  final Duration shownFor;
  final _shown = <PlayerNote>[];
  final _timers = <int, Timer>{};
  int _next = 0;
  bool _disposed = false;

  List<PlayerNote> get shown => List.unmodifiable(_shown);

  void add(String text) {
    if (_disposed) return;
    final notice = PlayerNote(_next++, text);
    _shown.add(notice);
    while (_shown.length > 2) {
      _timers.remove(_shown.removeAt(0).id)?.cancel();
    }
    _timers[notice.id] = Timer(shownFor, () {
      _timers.remove(notice.id);
      _shown.removeWhere((shown) => shown.id == notice.id);
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
