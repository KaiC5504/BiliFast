import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../app/route_observer.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/actions/actions_model.dart' show ActionsModel;
import '../../video/page_playback.dart' show RestoredPageRoute;
import '../../video/pip_keeper.dart';
import '../danmaku/live_send_input.dart';
import '../live_entry.dart';
import '../live_login.dart';
import '../player/live_player_controller.dart';
import '../player/live_player_panels.dart';
import '../player/live_player_view.dart';
import '../rank/live_rank_sheet.dart';
import 'chat/room_chat_list.dart';
import 'live_overlays.dart';
import 'live_room_model.dart';
import 'room_actions.dart';
import 'room_bottom_bar.dart';
import 'room_header.dart';
import 'room_more_sheet.dart';
import 'superchat/room_superchat.dart';

typedef LiveRoomModelFactory = LiveRoomModel Function(AppServices services, LiveRoomEntry entry);
typedef LivePlayerControllerFactory = LivePlayerController Function(AppServices services, LiveRoomModel room);

/// A room's model and player, which outlive its page while the small window plays it (as a video page's playback
/// does): [PipKeeper] keeps it, the restore button pushes the room back on it, ✕ or another video closes it.
class LiveRoomPlayback implements KeptPlayback {
  LiveRoomPlayback({required this.services, required this.entry, required this.model, required this.controller}) {
    controller
      ..keptAs = this
      ..addListener(_controllerChanged);
    _restores = controller.restoreRequests.listen((_) => restore());
  }

  final AppServices services;
  final LiveRoomEntry entry;
  final LiveRoomModel model;
  final LivePlayerController controller;
  StreamSubscription<void>? _restores;
  bool _pictureInPicture = false;
  bool _closed = false;

  bool get closed => _closed;

  @override
  bool get pipActive => !_closed && controller.pictureInPicture;

  @override
  String get bvid => 'live ${model.roomId}';

  @override
  void keep() {
    if (_closed) return;
    model.setShown(false);
    // The page is being disposed, with the tree locked; giving the orientation up notifies the page below.
    scheduleMicrotask(() {
      if (!_closed) controller.setKept(true);
    });
  }

  @override
  void returned() {
    if (_closed) return;
    controller.setKept(false);
  }

  @override
  bool pushPage() {
    final navigator = services.navigator.currentState;
    if (navigator == null || _closed) return false;
    unawaited(
      navigator.push(
        RestoredPageRoute<void>(
          builder: (_) => LiveRoomPage(entry: entry, playback: this),
        ),
      ),
    );
    return true;
  }

  /// The small window's restore button. Refused while kept, the window ends at once rather than waiting on a page
  /// that won't come.
  void restore() {
    final keeper = services.pipKeeper;
    if (!identical(keeper.kept, this) || keeper.restore(this)) return;
    Logger.shared.warn(LogCategory.ui, 'restore refused', {
      'bvid': bvid,
      'reason': _closed ? 'closed' : 'no navigator',
    });
    controller.refuseRestore();
  }

  /// Stops and frees the player and the model.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    controller.removeListener(_controllerChanged);
    unawaited(_restores?.cancel());
    // Just after: this can run inside the controller's own notification (the small window closing).
    scheduleMicrotask(() {
      controller.dispose();
      model.dispose();
    });
  }

  void _controllerChanged() {
    final active = controller.pictureInPicture;
    if (active == _pictureInPicture || _closed) return;
    _pictureInPicture = active;
    if (active) {
      services.pipKeeper.pipStarted(this);
    } else {
      services.pipKeeper.pipStopped(this);
    }
  }
}

/// A room (207-209, 221-233): its header, the player, the chat and the bottom bar in portrait; the full-screen player
/// in landscape; the overlays over both.
class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({super.key, required this.entry, this.playback, this.createModel, this.createController});

  final LiveRoomEntry entry;

  /// The room the small window's restore button brought back; a fresh one when it was closed meanwhile.
  final LiveRoomPlayback? playback;

  /// Tests' model and player in place of the real ones.
  @visibleForTesting
  final LiveRoomModelFactory? createModel;
  @visibleForTesting
  final LivePlayerControllerFactory? createController;

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> with RouteAware {
  AppServices? _services;
  late final LiveRoomPlayback _playback;
  late final LiveRoomModel _model;
  late final LivePlayerController _controller;
  int _endsToasted = 0;
  final _overlays = LiveOverlays();

  /// 229's sheet over the open 醒目留言 card.
  final _superChatMenu = ValueNotifier(false);
  late final AppLifecycleListener _lifecycle;
  PageRoute<dynamic>? _route;
  bool _covered = false;
  bool _away = false;
  StreamSubscription<Object>? _writeFailures;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _appStateChanged);
    _overlays.addListener(_overlayChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null) {
      final services = _services = AppScope.of(context);
      final brought = widget.playback;
      final playback = _playback = brought != null && !brought.closed ? brought : _newPlayback(services);
      _model = playback.model;
      _controller = playback.controller;
      // A restored room's ends from before this page were the small window's.
      _endsToasted = _model.endedNotices.value;
      _model.endedNotices.addListener(_toastEnded);
      _writeFailures = _model.writeFailures.listen((error) {
        if (mounted) roomWriteFailed(context, error, login: _requestLogin);
      });
      _model.setShown(true);
      unawaited(_model.start());
      unawaited(_controller.start());
      // After this frame's build: a kept playback let go notifies the keeper's listeners, which can't rebuild mid-build.
      scheduleMicrotask(() {
        if (mounted) services.pipKeeper.pageShown(playback, opened: true);
      });
    }
    // Only another page covers the room: the sheets and the login page's dialog route are no cover.
    if (ModalRoute.of(context) case final PageRoute<dynamic> route when route != _route) {
      pageRoutes.unsubscribe(this);
      _route = route;
      pageRoutes.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    pageRoutes.unsubscribe(this);
    _lifecycle.dispose();
    _overlays
      ..removeListener(_overlayChanged)
      ..dispose();
    _superChatMenu.dispose();
    _model.endedNotices.removeListener(_toastEnded);
    unawaited(_writeFailures?.cancel());
    _services?.pipKeeper.pageRemoved(_playback);
    super.dispose();
  }

  LiveRoomPlayback _newPlayback(AppServices services) {
    final model =
        widget.createModel?.call(services, widget.entry) ??
        LiveRoomModel(
          api: services.liveApi,
          entry: widget.entry,
          loggedIn: () => services.environment.account is LoggedIn,
          viewer: () => LiveUser(
            uid: services.environment.mid ?? 0,
            name: switch (services.environment.account) {
              LoggedIn(:final name) => name,
              _ => '',
            },
            face: services.environment.face ?? '',
          ),
        );
    final controller =
        widget.createController?.call(services, model) ?? LivePlayerController(room: model, services: services);
    return LiveRoomPlayback(services: services, entry: widget.entry, model: model, controller: controller);
  }

  /// One 直播已结束 for each end the model counts; one while covered waits until the room shows again.
  void _toastEnded() {
    final ends = _model.endedNotices.value;
    if (ends <= _endsToasted || !mounted || _covered) return;
    _endsToasted = ends;
    showToast(context, '直播已结束');
  }

  void _overlayChanged() {
    if (_overlays.value != LiveOverlay.superChat) _superChatMenu.value = false;
  }

  /// The socket closes while the app is away; the player keeps its own background rules (后台听视频, the small window).
  void _appStateChanged(AppLifecycleState state) {
    final away = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
      AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached => true,
    };
    if (away == _away) return;
    _away = away;
    _model.setShown(!_covered && !_away);
  }

  @override
  void didPushNext() {
    if (_covered) return;
    _covered = true;
    _model.setShown(false);
    _controller.setCovered(true);
  }

  @override
  void didPopNext() {
    if (!_covered) return;
    _covered = false;
    _model.setShown(!_away);
    _controller.setCovered(false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toastEnded());
  }

  /// The header's and full screen's ‹: through [_popInvoked], so an overlay closes first and full screen turns upright.
  void _back() => unawaited(Navigator.of(context).maybePop());

  bool _wide(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  void _popInvoked(bool didPop, Object? _) {
    if (didPop) return;
    if (_superChatMenu.value) {
      _superChatMenu.value = false;
    } else if (_overlays.close()) {
      return;
    } else if (!_controller.back() && _wide(context)) {
      // Sideways with the turn not the room's (another page had it): still upright, never out of the room.
      unawaited(_controller.setFullScreen(false));
    }
  }

  static const _turnLimit = Duration(seconds: 3);
  static const _turnPoll = Duration(milliseconds: 20);

  /// The rotation's animation, which runs on after the screen has its upright size.
  static const _turnSettle = Duration(milliseconds: 400);
  bool _askingLogin = false;

  /// Every logged-out action in the room (关注, sending, 点赞) and every answer that wants a login, as the video page's:
  /// the overlays go, full screen turns upright, and the login page goes up once the turn is over, with the phone's
  /// turning off until it closes.
  Future<bool> _requestLogin() async {
    final services = _services;
    if (_askingLogin || services == null || _covered || !mounted) return false;
    _askingLogin = true;
    try {
      _superChatMenu.value = false;
      _overlays.close();
      var turning = _controller.back();
      if (!turning && _wide(context)) {
        turning = true;
        unawaited(_controller.setFullScreen(false));
      }
      if (turning) {
        var waited = Duration.zero;
        while (mounted && _wide(context) && waited < _turnLimit) {
          await Future<void>.delayed(_turnPoll);
          waited += _turnPoll;
        }
        if (mounted) await Future<void>.delayed(_turnSettle);
      }
      if (!mounted || _covered) return false;
      _controller.holdTurns(true);
      try {
        return await services.loginGate.request(context);
      } finally {
        if (mounted) _controller.holdTurns(false);
      }
    } finally {
      _askingLogin = false;
    }
  }

  @override
  Widget build(BuildContext context) => LiveLoginScope(
    request: _requestLogin,
    child: ListenableBuilder(
      listenable: Listenable.merge([_overlays, _controller, _superChatMenu]),
      builder: (context, _) {
        final wide = _wide(context);
        return PopScope<Object?>(
          canPop: _overlays.value == LiveOverlay.none && !_superChatMenu.value && !_controller.fullScreen && !wide,
          onPopInvokedWithResult: _popInvoked,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            // The inputs and panels need a Material above them; the room draws its own fills.
            child: Material(
              key: const ValueKey('live-room-page'),
              type: MaterialType.transparency,
              child: wide ? _fullScreen() : _portrait(context),
            ),
          ),
        );
      },
    ),
  );

  Widget _fullScreen() {
    final overlay = switch (_overlays.value) {
      LiveOverlay.more => LiveMorePanel(controller: _controller, room: _model, overlays: _overlays),
      LiveOverlay.quality => LiveQualityPicker(
        controller: _controller,
        room: _model,
        overlays: _overlays,
        landscape: true,
      ),
      LiveOverlay.danmakuSettings => LiveDanmakuSettingsPanel(
        controller: _controller,
        overlays: _overlays,
        landscape: true,
      ),
      LiveOverlay.rank => LiveRankSheet(room: _model, overlays: _overlays, landscape: true),
      LiveOverlay.send => LiveSendInput(
        room: _model,
        overlays: _overlays,
        landscape: true,
        startOnEmotes: _overlays.sendOnEmotes,
      ),
      LiveOverlay.superChat || LiveOverlay.none => null,
    };
    if (_overlays.value == LiveOverlay.superChat) {
      // Full screen draws no 醒目留言 card; left open, back would close something no one sees.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _overlays.value != LiveOverlay.superChat) return;
        _superChatMenu.value = false;
        _overlays.close();
      });
    }
    return ColoredBox(
      key: const ValueKey('live-room-full-screen'),
      color: BiliColors.videoBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: LivePlayerView(
              controller: _controller,
              room: _model,
              overlays: _overlays,
              fullScreen: true,
              onBack: _back,
            ),
          ),
          if (overlay != null) Positioned.fill(child: overlay),
        ],
      ),
    );
  }

  Widget _portrait(BuildContext context) {
    final services = _services!;
    final padding = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final boxTop = padding.top + LiveRoomTheme.boxTop;
    final boxBottom = boxTop + width / BiliMetrics.videoAspect;
    final ownFace = roomLoggedOut(services) ? '' : services.meProfile.kept?.view.profile.face ?? '';
    return ValueListenableBuilder<List<LiveSuperChat>>(
      valueListenable: _model.superChats,
      builder: (context, superChats, _) {
        final stripTop = boxBottom + LiveRoomTheme.stripGap;
        final stripBottom = stripTop + LiveRoomTheme.stripHeight;
        final chatTop = superChats.isEmpty ? boxBottom : stripBottom;
        final open = _overlays.value;
        LiveSuperChat? card;
        if (open == LiveOverlay.superChat) {
          card = superChats.where((sc) => sc.id == _overlays.superChatId).firstOrNull;
          // Its time ran out, or it was taken down.
          if (card == null) WidgetsBinding.instance.addPostFrameCallback((_) => _overlays.close());
        }
        return ColoredBox(
          color: LiveRoomTheme.page,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: padding.top + LiveRoomTheme.headerTop,
                height: LiveRoomTheme.capsuleHeight,
                child: RoomHeader(room: _model, overlays: _overlays, onBack: _back),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: padding.top + LiveRoomTheme.chipsTop,
                height: LiveRoomTheme.chipHeight,
                child: RoomChips(room: _model),
              ),
              Positioned(
                left: 0,
                top: boxTop,
                width: width,
                height: boxBottom - boxTop,
                // The box (its picture, controls and flying danmaku) and the chat change at their own pace; each keeps
                // its own layer so neither repaints the other or the header.
                child: RepaintBoundary(
                  child: LivePlayerView(
                    controller: _controller,
                    room: _model,
                    overlays: _overlays,
                    fullScreen: false,
                    onBack: _back,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: chatTop,
                bottom: padding.bottom + LiveRoomTheme.barHeight + LiveRoomTheme.chatBottomGap,
                child: RepaintBoundary(child: RoomChatList(chat: _model.chat, now: _model.now)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: padding.bottom,
                height: LiveRoomTheme.barHeight,
                child: RoomBottomBar(overlays: _overlays, ownFace: ownFace),
              ),
              if (card != null)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('live-sc-dim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _overlays.close,
                    child: const ColoredBox(color: LiveRoomTheme.dim),
                  ),
                ),
              if (superChats.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: stripTop,
                  height: LiveRoomTheme.stripHeight,
                  child: RoomSuperChatStrip(
                    superChats: superChats,
                    now: _model.now,
                    selected: card?.id,
                    onOpen: _overlays.openSuperChat,
                  ),
                ),
              if (card != null)
                Positioned(
                  left: LiveRoomTheme.cardSide,
                  right: LiveRoomTheme.cardSide,
                  top: stripBottom + LiveRoomTheme.cardBelowStrip,
                  child: RoomSuperChatCard(superChat: card, onMore: () => _superChatMenu.value = true),
                ),
              if (card != null && _superChatMenu.value)
                Positioned.fill(
                  child: RoomSuperChatActions(
                    onManage: () => toastNotYet(context),
                    onReport: () => toastNotYet(context),
                    onCancel: () => _superChatMenu.value = false,
                  ),
                ),
              if (_portraitOverlay(context, open) case final overlay?) Positioned.fill(child: overlay),
            ],
          ),
        );
      },
    );
  }

  Widget? _portraitOverlay(BuildContext context, LiveOverlay open) => switch (open) {
    LiveOverlay.more => RoomMoreSheet(
      onShare: (_) {
        _overlays.close();
        unawaited(_controller.share(context));
      },
      onItem: (item) => _moreItem(context, item),
      onClose: _overlays.close,
    ),
    LiveOverlay.quality => LiveQualityPicker(
      controller: _controller,
      room: _model,
      overlays: _overlays,
      landscape: false,
    ),
    LiveOverlay.danmakuSettings => LiveDanmakuSettingsPanel(
      controller: _controller,
      overlays: _overlays,
      landscape: false,
    ),
    LiveOverlay.rank => LiveRankSheet(room: _model, overlays: _overlays, landscape: false),
    LiveOverlay.send => LiveSendInput(
      room: _model,
      overlays: _overlays,
      landscape: false,
      startOnEmotes: _overlays.sendOnEmotes,
    ),
    LiveOverlay.superChat || LiveOverlay.none => null,
  };

  void _moreItem(BuildContext context, RoomMoreItem item) {
    switch (item) {
      case RoomMoreItem.pictureInPicture:
        _overlays.close();
        unawaited(_controller.startPictureInPicture());
      case RoomMoreItem.danmakuSettings:
        _overlays.open(LiveOverlay.danmakuSettings);
      case RoomMoreItem.quality:
        _overlays.open(LiveOverlay.quality);
      case RoomMoreItem.playSettings ||
          RoomMoreItem.boost ||
          RoomMoreItem.spending ||
          RoomMoreItem.effects ||
          RoomMoreItem.cast ||
          RoomMoreItem.report ||
          RoomMoreItem.feedback ||
          RoomMoreItem.audioOnly ||
          RoomMoreItem.colourVision ||
          RoomMoreItem.desktop:
        toastNotYet(context);
    }
  }
}

/// A room write that failed after its control let go (点赞's gathered send): one that needs a login opens [login], the
/// room's own way to the login page; any other toasts.
void roomWriteFailed(BuildContext context, Object error, {required Future<bool> Function() login}) {
  if (!context.mounted) return;
  if (liveNeedsLogin(error)) {
    unawaited(login());
  } else {
    showToast(context, ActionsModel.failureMessage(error));
  }
}
