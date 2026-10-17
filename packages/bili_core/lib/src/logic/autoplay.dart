final class PlayItem {
  const PlayItem({required this.bvid, required this.cid});

  final String bvid;
  final int cid;

  @override
  bool operator ==(Object other) => other is PlayItem && other.bvid == bvid && other.cid == cid;

  @override
  int get hashCode => Object.hash(bvid, cid);

  @override
  String toString() => '$bvid/$cid';
}

enum LoopMode { single, list, none }

sealed class NextStep {
  const NextStep();

  static const NextStep replay = NextReplay();
  static const NextStep stop = NextStop();
  static NextStep play(PlayItem item) => NextPlay(item);
}

final class NextReplay extends NextStep {
  const NextReplay();

  @override
  bool operator ==(Object other) => other is NextReplay;

  @override
  int get hashCode => (NextReplay).hashCode;

  @override
  String toString() => 'replay';
}

final class NextPlay extends NextStep {
  const NextPlay(this.item);

  final PlayItem item;

  @override
  bool operator ==(Object other) => other is NextPlay && other.item == item;

  @override
  int get hashCode => item.hashCode;

  @override
  String toString() => 'play($item)';
}

final class NextStop extends NextStep {
  const NextStop();

  @override
  bool operator ==(Object other) => other is NextStop;

  @override
  int get hashCode => (NextStop).hashCode;

  @override
  String toString() => 'stop';
}

abstract final class Autoplay {
  /// `episodes` is every 合集 episode of every section, in order. A multi-part video sits in it once, under its first cid,
  /// so a later part is located by bvid when its own cid is not listed.
  static NextStep next({
    required PlayItem after,
    required List<PlayItem> parts,
    required List<PlayItem> episodes,
    required bool autoplay,
    required LoopMode loop,
  }) {
    final current = after;
    if (loop == LoopMode.single) return NextStep.replay;
    if (!autoplay && loop != LoopMode.list) return NextStep.stop;

    final siblings = parts.where((p) => p.bvid == current.bvid).toList();
    final i = siblings.indexWhere((p) => p.cid == current.cid);
    if (i >= 0 && i + 1 < siblings.length) return NextStep.play(siblings[i + 1]);

    var position = episodes.indexWhere((e) => e.cid == current.cid);
    if (position < 0) position = episodes.indexWhere((e) => e.bvid == current.bvid);
    if (position >= 0 && position + 1 < episodes.length) return NextStep.play(episodes[position + 1]);

    if (loop != LoopMode.list) return NextStep.stop;
    // Looping covers the collection the video belongs to, otherwise just its own parts.
    final first = position >= 0 ? episodes.firstOrNull : siblings.firstOrNull;
    if (first == null || first == current) return NextStep.replay;
    return NextStep.play(first);
  }
}
