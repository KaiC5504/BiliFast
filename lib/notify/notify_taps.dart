import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../app/app_environment.dart';
import '../account/login_gate.dart';
import '../app/app_scope.dart';
import '../dynamic/post/post_route.dart';
import '../video/video_route.dart';
import 'notify_host.dart';

/// Opens what a tapped notification names, and logs the background checks NotifyHost.swift ran since the last launch.
/// A tap closes the sheets and dialogs on top and opens its page over the page under them, as a pasted link does; only
/// a video page there is replaced, since video pages never stack. Logged out, a tap opens nothing.
class NotifyTaps {
  NotifyTaps({
    required this.host,
    required this.navigator,
    Logger? logger,
    @visibleForTesting this.pages = const NotifyPages(),
    @visibleForTesting this.accountWait = const Duration(seconds: 10),
    @visibleForTesting DateTime Function()? now,
  }) : _logger = logger ?? Logger.shared,
       _now = now ?? DateTime.now;

  final NotifyHost host;
  final GlobalKey<NavigatorState> navigator;
  final NotifyPages pages;

  /// How long a tap waits for an account check still out (a cold start's) before it opens nothing.
  final Duration accountWait;

  final Logger _logger;
  final DateTime Function() _now;
  bool _started = false;

  /// Counts the taps, so one still waiting on the account gives way to a later one.
  int _taps = 0;

  /// Once the first page shows.
  void start() {
    if (_started) return;
    _started = true;
    _afterFirstPage();
  }

  /// As `--play=` waits for 首页: called before runApp, so the frame that built the navigator's first page is awaited.
  void _afterFirstPage() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_services == null) {
      _afterFirstPage();
    } else {
      unawaited(_listen());
    }
  });

  AppServices? get _services => navigator.currentContext?.getInheritedWidgetOfExactType<AppScope>()?.services;

  Future<void> _listen() async {
    // Before the launch route is asked: asking tells NotifyHost.swift to send later taps straight here.
    host.onTap = (route) => unawaited(_open(route));
    try {
      final launch = await host.takeLaunchRoute();
      if (launch != null) unawaited(_open(launch));
    } catch (error) {
      _logger.warn(LogCategory.app, 'notify launch route failed', {'error': '${error.runtimeType}'});
    }
    try {
      final trips = await host.takeTrips();
      final now = _now();
      for (final trip in trips) {
        _logger.info(LogCategory.app, 'notify trip', {
          'outcome': trip.outcome,
          'calls': trip.calls,
          'posted': trip.posted,
          'ageMinutes': now.difference(trip.at).inMinutes,
        });
      }
    } catch (error) {
      _logger.warn(LogCategory.app, 'notify trips failed', {'error': '${error.runtimeType}'});
    }
  }

  Future<void> _open(NotifyRoute route) async {
    final tap = ++_taps;
    final kind = switch (route) {
      NotifyVideo(commentRoot: null) => 'video',
      NotifyVideo() => 'comment',
      NotifyDynamicPost() => 'post',
      NotifyApp() => 'app',
    };
    if (route is NotifyApp) {
      _logger.info(LogCategory.app, 'notify open', {'kind': kind});
      return;
    }
    final environment = _services?.environment;
    if (environment == null) {
      _logger.warn(LogCategory.app, 'notify not opened', {'kind': kind, 'reason': 'no page'});
      return;
    }
    // A cold start's tap arrives before the launch's account check answers; this waits on that one.
    if (environment.account is AccountUnknown) {
      await environment.refreshAccount().timeout(accountWait, onTimeout: () => false);
      if (tap != _taps) return;
    }
    final navigator = this.navigator.currentState;
    if (environment.account is! LoggedIn || navigator == null) {
      _logger.info(LogCategory.app, 'notify not opened', {
        'kind': kind,
        'reason': switch (environment.account) {
          _ when navigator == null => 'no page',
          AccountUnknown() => 'account unknown',
          _ => 'logged out',
        },
      });
      return;
    }
    _logger.info(LogCategory.app, 'notify open', {'kind': kind});
    _show(navigator, route);
  }

  void _show(NavigatorState navigator, NotifyRoute route) {
    final top = _closePopups(navigator);
    // A login finishing removes its own page, which would leave a page pushed over it next to the video page under
    // it; the tap waits until the login has gone, then opens as any other.
    if (top is ModalRoute<Object?> && top.settings.name == LoginPageGate.routeSettings.name) {
      unawaited(
        top.popped.then((_) => WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open(route)))),
      );
      return;
    }
    switch (route) {
      case NotifyVideo(:final bvid, :final commentRoot, :final comment):
        final video = VideoRoute(
          bvid: bvid,
          comment: commentRoot == null ? null : CommentFocus(root: commentRoot, reply: comment),
        );
        if (top is! ModalRoute<Object?> || !isVideoPageRoute(top)) {
          unawaited(pages.openVideo(navigator.context, video));
        } else if (top.subtreeContext case final shown?) {
          unawaited(pages.replaceVideo(shown, video));
        } else {
          // Pushed this frame (a tap just before), so nothing in it is built to replace it from, nor shown yet.
          navigator.removeRoute(top);
          unawaited(pages.openVideo(navigator.context, video));
        }
      case NotifyDynamicPost(:final id, :final toComments):
        unawaited(pages.openPost(navigator.context, id: id, toComments: toComments));
      case NotifyApp():
        break;
    }
  }

  /// Pops the sheets and dialogs on top and returns the page route then showing. Over a video page they would
  /// otherwise get the new page over them, with the old page still under both.
  Route<dynamic>? _closePopups(NavigatorState navigator) {
    Route<dynamic>? top;
    // The navigator names its top route no other way: each route the predicate turns down is popped.
    navigator.popUntil((route) {
      top = route;
      return route is! PopupRoute;
    });
    return top;
  }
}

/// The pages a tap opens; tests stand in for the video page, which needs a player.
class NotifyPages {
  const NotifyPages();

  Future<void> openVideo(BuildContext context, VideoRoute route) => openVideoPage(context, route);

  Future<void> replaceVideo(BuildContext context, VideoRoute route) => replaceVideoPage(context, route);

  Future<void> openPost(BuildContext context, {required String id, required bool toComments}) =>
      openDynamicPost(context, id: id, toComments: toComments);
}
