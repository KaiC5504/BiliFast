import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart';

import '../app/app_scope.dart';
import '../home/feed_model.dart' show requestFailureMessage;
import '../home/recent_store.dart';
import '../playback/playback_controller.dart' show resolveVideoLink;
import '../shared/toast.dart';
import 'video_route.dart';

/// Opens a pasted or typed link's video page (port of HomeView.swift's open): resolves the link, asks for the part
/// when it names none of several, adds it to 最近打开 and pushes the page. [busy] is true while the link resolves.
class LinkOpener {
  LinkOpener({this.onPushed, this.openPage});

  /// Gets each pushed page's future, for home's account recheck once the page is closed.
  final void Function(Future<void> pushed)? onPushed;

  /// Pushes the video page; [openVideoPage] unless a test watches it instead.
  final Future<void> Function(BuildContext context, VideoRoute route)? openPage;

  final busy = ValueNotifier(false);

  /// The page that owns this opener can leave while a link still resolves; nothing is written to [busy] after that.
  bool _disposed = false;

  void _setBusy(bool value) {
    if (!_disposed) busy.value = value;
  }

  /// False when [text] is no link, after a toast saying so; true once the link was taken, whether it opened or not.
  Future<bool> open(BuildContext context, String text) async {
    if (busy.value) return true;
    final link = LinkParser.parse(text);
    if (link == null) {
      showToast(context, BiliError.invalidLink.userMessage);
      return false;
    }
    final services = AppScope.of(context);
    _setBusy(true);
    try {
      VideoDetail? resolved;
      final (view, pageNumber) = await resolveVideoLink(
        services.environment.client,
        link,
        onDetail: (d) => resolved = d,
      );
      if (!context.mounted) return true;
      Logger.shared.info(LogCategory.ui, 'open', {'bvid': view.bvid, 'pages': view.pages.length});
      // Handed to the page so its open asks for nothing again and keeps the 合集.
      final detail = resolved?.bvid == view.bvid ? resolved : null;
      final match = view.pages.where((page) => page.page == pageNumber).firstOrNull;
      if (match != null) {
        _go(context, view, match, detail);
      } else if (view.pages.length > 1) {
        // The spinner would otherwise wait behind the sheet for as long as it is up.
        _setBusy(false);
        await _choosePart(context, view, detail);
      } else if (view.pages.firstOrNull case final first?) {
        _go(context, view, first, detail);
      } else {
        showToast(context, '该视频没有可播放的分P');
      }
    } catch (error) {
      // Not '$error': a failure can carry the pasted link.
      Logger.shared.warn(LogCategory.ui, 'open failed', {
        'error': switch (error) {
          BiliAPIError(:final code) => 'api $code',
          BiliHTTPError(:final status) => 'http $status',
          _ => '${error.runtimeType}',
        },
      });
      if (context.mounted) showToast(context, requestFailureMessage(error, fallback: '打开视频失败，请稍后重试'));
    } finally {
      _setBusy(false);
    }
    return true;
  }

  Future<void> _choosePart(BuildContext context, VideoView view, VideoDetail? detail) async {
    final page = await showCupertinoModalPopup<VideoPage>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择分P'),
        message: Text(view.title),
        actions: [
          for (final page in view.pages)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(page),
              child: Text('P${page.page} ${page.part}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      ),
    );
    if (page != null && context.mounted) _go(context, view, page, detail);
  }

  void _go(BuildContext context, VideoView view, VideoPage page, VideoDetail? detail) {
    AppScope.of(context).recents.add(
      RecentVideo(
        bvid: view.bvid,
        cid: page.cid,
        title: view.title,
        part: page.part,
        page: page.page,
        pageCount: view.pages.length,
        cover: detail?.cover,
        duration: page.duration,
      ),
    );
    final route = VideoRoute(bvid: view.bvid, cid: page.cid, title: view.title, view: view, detail: detail);
    final pushed = (openPage ?? openVideoPage)(context, route);
    final onPushed = this.onPushed;
    if (onPushed != null) {
      onPushed(pushed);
    } else {
      unawaited(pushed);
    }
  }

  void dispose() {
    _disposed = true;
    busy.dispose();
  }
}
