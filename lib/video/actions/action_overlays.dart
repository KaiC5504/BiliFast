import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../../player_ui/end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import '../../shared/toast.dart';
import 'coin_dialog.dart';
import 'favourite_sheet.dart';
import 'unfollow_confirm.dart';
import 'video_actions.dart';

/// What [ActionOverlays] has up (the prompt it took), so the page's back closes it before anything else.
class ActionOverlayController extends ValueNotifier<ActionPrompt?> {
  ActionOverlayController() : super(null);

  void close() => value = null;
}

/// Puts up what the actions ask for, over the whole page in every presentation: the coin dialog, the favourites sheet,
/// the unfollow confirm, or the system share sheet (counted once it closes). Lets touches through when nothing is up.
class ActionOverlays extends StatefulWidget {
  const ActionOverlays({
    super.key,
    required this.actions,
    required this.controller,
    required this.landscape,
    required this.shareLink,
    this.share = shareThroughSystem,
  });

  /// Null until the video's detail arrives.
  final VideoActions? actions;
  final ActionOverlayController controller;
  final bool landscape;
  final Uri? shareLink;
  final ShareLink share;

  @override
  State<ActionOverlays> createState() => _ActionOverlaysState();
}

class _ActionOverlaysState extends State<ActionOverlays> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// What shows: the open overlay, or the one going away after a close.
  ActionPrompt? _shown;

  /// The actions the overlay on screen belongs to, and the prompt's when it is taken: a new video's actions may
  /// arrive while it is still up.
  VideoActions? _owner;
  FavouriteFolders? _folders;

  @override
  void initState() {
    super.initState();
    widget.actions?.addListener(_actionsChanged);
    widget.controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _actionsChanged();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _motion
      ..duration = still ? Duration.zero : const Duration(milliseconds: 300)
      ..reverseDuration = still ? Duration.zero : const Duration(milliseconds: 220);
  }

  @override
  void didUpdateWidget(ActionOverlays oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    if (!identical(oldWidget.actions, widget.actions)) {
      oldWidget.actions?.removeListener(_actionsChanged);
      widget.actions?.addListener(_actionsChanged);
      // What is up belongs to the video before.
      if (_owner != null && !identical(_owner, widget.actions)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !identical(_owner, widget.actions)) widget.controller.close();
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _actionsChanged();
      });
    }
  }

  @override
  void dispose() {
    widget.actions?.removeListener(_actionsChanged);
    widget.controller.removeListener(_controllerChanged);
    _folders?.dispose();
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _actionsChanged() {
    final actions = widget.actions;
    final prompt = actions?.prompt;
    if (actions == null || prompt == null) return;
    // At the limit there is nothing to choose: coin() only says 已投满 (as BiliNative's page).
    if (prompt == ActionPrompt.coin && actions.maxCoins <= 0) {
      actions.clearPrompt();
      unawaited(actions.coin(1, alsoLike: false));
      return;
    }
    _owner = actions;
    if (prompt == ActionPrompt.favourites) {
      _replaceFolders(actions.openFolders());
      if (_shown != null) setState(() {});
    }
    widget.controller.value = prompt;
    actions.clearPrompt();
    if (prompt == ActionPrompt.share) unawaited(_share(actions));
  }

  void _controllerChanged() {
    final next = widget.controller.value;
    if (next == null || next == ActionPrompt.share) {
      _close();
      return;
    }
    final owner = _owner ?? widget.actions;
    if (owner == null) return;
    _owner = owner;
    if (next == ActionPrompt.favourites && _folders == null) _replaceFolders(owner.openFolders());
    final wasShown = _shown != null;
    setState(() => _shown = next);
    // Taken again while going away: it turns around where it is.
    _motion.forward(from: wasShown ? null : 0);
  }

  void _replaceFolders(FavouriteFolders folders) {
    final previous = _folders;
    _folders = folders;
    if (previous != null && !identical(previous, folders)) _disposeAfterFrame(previous);
  }

  void _disposeAfterFrame(FavouriteFolders folders) {
    WidgetsBinding.instance.addPostFrameCallback((_) => folders.dispose());
  }

  void _close() {
    if (_shown == null) return;
    setState(() {});
    _motion.reverse().whenCompleteOrCancel(() {
      if (!mounted || !_motion.isDismissed) return;
      final value = widget.controller.value;
      if (value != null && value == _shown) return;
      final folders = _folders;
      setState(() {
        _shown = null;
        _owner = null;
        _folders = null;
      });
      if (folders != null) _disposeAfterFrame(folders);
    });
  }

  /// Closes [prompt]'s overlay, unless another has taken its place since.
  void _closeIf(ActionPrompt prompt) {
    if (widget.controller.value == prompt) widget.controller.close();
  }

  Future<void> _share(VideoActions actions) async {
    final link = widget.shareLink;
    if (link == null) {
      _toast('视频还没有加载完');
      _closeIf(ActionPrompt.share);
      return;
    }
    try {
      await widget.share(link);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'share failed', {'error': '${error.runtimeType}'});
      _toast('分享失败');
      _closeIf(ActionPrompt.share);
      return;
    }
    unawaited(actions.shared());
    _closeIf(ActionPrompt.share);
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final owner = _owner;
    if (shown == null || owner == null) return const SizedBox.shrink();
    final open = widget.controller.value == shown;
    final Widget child = switch (shown) {
      ActionPrompt.coin => FadeTransition(
        opacity: _curve,
        child: CoinDialog(actions: owner, onClose: () => _closeIf(ActionPrompt.coin)),
      ),
      ActionPrompt.favourites => FavouriteSheet(
        folders: _folders!,
        dark: widget.landscape,
        motion: _curve,
        onClose: () => _closeIf(ActionPrompt.favourites),
      ),
      ActionPrompt.unfollow => UnfollowConfirm(
        motion: _curve,
        onConfirm: () {
          unawaited(owner.toggleFollow());
          _closeIf(ActionPrompt.unfollow);
        },
        onCancel: () => _closeIf(ActionPrompt.unfollow),
      ),
      ActionPrompt.share => const SizedBox.shrink(),
    };
    return IgnorePointer(
      key: const ValueKey('action-overlay'),
      ignoring: !open,
      child: ExcludeSemantics(
        excluding: !open,
        // Up, it is modal: VoiceOver reads only it, not the page under it.
        child: BlockSemantics(blocking: open, child: child),
      ),
    );
  }
}
