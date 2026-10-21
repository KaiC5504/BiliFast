import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import '../playback/overlay_stats.dart';
import '../player/bili_player.dart';
import '../shared/theme.dart';

/// The official player's wait (65, 66): the pink TV, looping, centred in the box it is given, over 正在缓冲..., which
/// gains the download speed once the engine has measured one. It takes no touches. Reduce Motion holds the TV still,
/// and it stops while its ticker is muted (a covered page).
class PlayerLoading extends StatefulWidget {
  const PlayerLoading({super.key, this.stats});

  /// The playback's stats; null (no session yet) shows no speed.
  final ValueListenable<OverlayStats>? stats;

  static const asset = 'assets/lottie/player_loading_tv.json';
  static const message = '正在缓冲...';

  /// Parses the Lottie into the package's shared cache ahead of the first video, which would otherwise draw nothing
  /// for its first frames.
  static Future<void> precache() => AssetLottie(asset).load();

  /// `正在缓冲... 69.33 KB/s`, or the message alone until the engine reports (never, in direct mode). The official app
  /// shows 0.00 KB/s too, so a measured zero still reads.
  static String line(OverlayStats? stats) => switch (speed(stats)) {
    final speed? => '$message $speed',
    null => message,
  };

  /// KB/s to two decimals, as the official app writes it; past 1024 KB/s its format is unseen, so MB/s alike.
  static String? speed(OverlayStats? stats) {
    if (stats?.engine == null) return null;
    final kilobytes = stats!.downloadBps / 1024;
    final shown = kilobytes.toStringAsFixed(2);
    if (double.parse(shown) < 1024) return '$shown KB/s';
    return '${(kilobytes / 1024).toStringAsFixed(2)} MB/s';
  }

  @override
  State<PlayerLoading> createState() => _PlayerLoadingState();
}

class _PlayerLoadingState extends State<PlayerLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _run();
  }

  void _loaded(LottieComposition composition) {
    _loop.duration = composition.duration;
    _run();
  }

  void _run() {
    if (_loop.duration == null) return;
    if (_still) {
      _loop
        ..stop()
        ..value = 0;
    } else if (!_loop.isAnimating) {
      unawaited(_loop.repeat());
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: PlayerLoadingTheme.text,
      color: PlayerLoadingTheme.ink,
      letterSpacing: 0,
      decoration: TextDecoration.none,
    );
    final strut = BiliFonts.strutOf(context, style);
    Widget text(OverlayStats? stats) => Text(
      PlayerLoading.line(stats),
      key: const ValueKey('player-loading-text'),
      style: style,
      strutStyle: strut,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
    final stats = widget.stats;
    return IgnorePointer(
      child: CustomMultiChildLayout(
        delegate: _Layout(),
        children: [
          LayoutId(
            id: _Slot.tv,
            child: Lottie.asset(
              PlayerLoading.asset,
              controller: _loop,
              onLoaded: _loaded,
              width: PlayerLoadingTheme.tvSize,
              height: PlayerLoadingTheme.tvSize,
            ),
          ),
          LayoutId(
            id: _Slot.text,
            child: stats == null
                ? text(null)
                : ValueListenableBuilder(valueListenable: stats, builder: (context, stats, _) => text(stats)),
          ),
        ],
      ),
    );
  }
}

enum _Slot { tv, text }

/// The TV's centre on the box's, as in both recordings; the line hangs below it, centred, whatever its width.
class _Layout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    const tv = PlayerLoadingTheme.tvSize;
    layoutChild(_Slot.tv, BoxConstraints.tight(const Size.square(tv)));
    final text = layoutChild(_Slot.text, const BoxConstraints());
    final centre = size.center(Offset.zero);
    positionChild(_Slot.tv, centre - const Offset(tv / 2, tv / 2));
    positionChild(_Slot.text, Offset(centre.dx - text.width / 2, centre.dy + tv / 2 + PlayerLoadingTheme.gap));
  }

  @override
  bool shouldRelayout(_Layout oldDelegate) => false;
}

/// Whether the player has waited for data longer than [grace] while meant to be playing. A wait shorter than it (a
/// seek inside the buffer, a hiccup) shows nothing, so the TV doesn't flash on every quick seek.
final class PlayerWait extends ChangeNotifier implements ValueListenable<bool> {
  PlayerWait(this._status, {this.grace = PlayerLoadingTheme.grace}) {
    _status.addListener(_update);
    _update();
  }

  final ValueListenable<PlayerStatus> _status;
  final Duration grace;
  Timer? _timer;
  bool _waited = false;
  bool _active = true;

  @override
  bool get value => _waited;

  /// False while the page is covered or gone: nothing shows, and a wait starts over when it is shown again.
  set active(bool value) {
    if (value == _active) return;
    _active = value;
    _update();
  }

  void _update() {
    if (!_active || _status.value != PlayerStatus.buffering) {
      _timer?.cancel();
      _timer = null;
      _set(false);
      return;
    }
    if (_waited || _timer != null) return;
    _timer = Timer(grace, () {
      _timer = null;
      _set(true);
    });
  }

  void _set(bool waited) {
    if (waited == _waited) return;
    _waited = waited;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _status.removeListener(_update);
    super.dispose();
  }
}
