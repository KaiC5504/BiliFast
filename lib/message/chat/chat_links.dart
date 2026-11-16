import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../comments/rich_text_view.dart' show spaceMid;
import '../../shared/toast.dart';
import '../../space/space_route.dart';
import '../../space/uploader_tap.dart';
import '../../video/link_opener.dart';

/// Where a chat's link goes.
sealed class ChatLinkTarget {
  const ChatLinkTarget();
}

/// A video, opened in the app as a pasted link would be.
final class ChatVideoTarget extends ChatLinkTarget {
  const ChatVideoTarget(this.link);

  /// What [LinkOpener] reads: the address, or `av<aid>` / the BV id from an app link.
  final String link;
}

final class ChatSpaceTarget extends ChatLinkTarget {
  const ChatSpaceTarget(this.mid);

  final int mid;
}

/// Anything else on the web, in Safari.
final class ChatWebTarget extends ChatLinkTarget {
  const ChatWebTarget(this.uri);

  final Uri uri;
}

/// An app link the app has no page for (`bilibili://…` 装扮, 会员购 …).
final class ChatUnknownTarget extends ChatLinkTarget {
  const ChatUnknownTarget();
}

const _bilibiliHosts = ['bilibili.com', 'b23.tv', 'bili2233.cn'];

bool _onBilibili(String host) => _bilibiliHosts.any((known) => host == known || host.endsWith('.$known'));

/// A video or space address on Bilibili opens in the app; other web addresses in Safari; `bilibili://video/…` and
/// `bilibili://space/…` in the app, and other app links nowhere.
ChatLinkTarget chatLinkTarget(String address) {
  final uri = Uri.tryParse(address.trim());
  if (uri == null) return const ChatUnknownTarget();
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    final host = uri.host.toLowerCase();
    if (_onBilibili(host)) {
      if (spaceMid(uri) case final mid?) return ChatSpaceTarget(mid);
      // Short links can lead anywhere, so only an address naming its video opens one.
      if (LinkParser.parse(address) case BvidLink() || AidLink()) return ChatVideoTarget(address);
    }
    return ChatWebTarget(uri);
  }
  if (scheme == 'bilibili') {
    final first = uri.pathSegments.where((segment) => segment.isNotEmpty).firstOrNull ?? '';
    switch (uri.host.toLowerCase()) {
      case 'video':
        if (int.tryParse(first) case final aid? when aid > 0) return ChatVideoTarget('av$aid');
        if (LinkParser.parse(first) is BvidLink) return ChatVideoTarget(first);
      case 'space':
        if (int.tryParse(first) case final mid? when mid > 0) return ChatSpaceTarget(mid);
    }
  }
  return const ChatUnknownTarget();
}

Future<bool> openInSafari(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> openVideoLink(BuildContext context, String link) async {
  final opener = LinkOpener();
  try {
    await opener.open(context, link);
  } finally {
    opener.dispose();
  }
}

/// Opens [address] where [chatLinkTarget] says; what can't be opened toasts.
Future<void> openChatLink(
  BuildContext context,
  String address, {
  required Future<bool> Function(Uri uri) openWeb,
  required Future<void> Function(BuildContext context, String link) openVideo,
}) async {
  switch (chatLinkTarget(address)) {
    case ChatVideoTarget(:final link):
      await openVideo(context, link);
    case ChatSpaceTarget(:final mid):
      await openSpace(context, UploaderRef(mid: mid));
    case ChatWebTarget(:final uri):
      var opened = false;
      try {
        opened = await openWeb(uri);
      } catch (error) {
        Logger.shared.warn(LogCategory.ui, 'chat link not opened', {'error': '${error.runtimeType}'});
      }
      if (!opened && context.mounted) showToast(context, '无法打开链接');
    case ChatUnknownTarget():
      showToast(context, '暂未开放');
  }
}
