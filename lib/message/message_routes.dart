import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import 'chat/chat_page.dart';
import 'feed/likes_page.dart';
import 'feed/new_fans_page.dart';
import 'feed/replies_page.dart';
import 'settings/message_settings_page.dart';
import 'settings/notice_picker_page.dart';

/// A 私信 session (202), or a notice box's (200, 201).
Future<void> openMessageChat(BuildContext context, ChatSession session) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => ChatPage(session: session)));

/// 回复与@ (197), on 全部 or @我.
Future<void> openReplies(BuildContext context, {bool mentions = false}) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => RepliesPage(mentions: mentions)));

/// 收到喜欢 (198).
Future<void> openLikes(BuildContext context) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const LikesPage()));

/// 新增粉丝 (199).
Future<void> openNewFans(BuildContext context) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const NewFansPage()));

/// 消息设置 (188).
Future<void> openMessageSettings(BuildContext context) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const MessageSettingsPage()));

/// A 消息提醒 picker (215, 216, 195), from 消息设置 and the gear on 回复与@ and 收到喜欢.
Future<void> openNoticePicker(BuildContext context, NoticeSettingKind kind) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => NoticePickerPage(kind: kind)));
