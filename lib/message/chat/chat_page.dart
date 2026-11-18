import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../comments/comments_model.dart' show CommentsModel;
import '../../comments/emote_store.dart';
import '../../shared/loading_tv.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../space/space_route.dart';
import '../../space/uploader_tap.dart';
import 'chat_composer.dart';
import 'chat_emote_panel.dart';
import 'chat_glyphs.dart';
import 'chat_links.dart';
import 'chat_model.dart';
import 'chat_notice_card.dart';
import 'chat_rows.dart';
import 'chat_settings_bar.dart';

/// A 私信 session (202, 203), or a notice box's cards and bubbles (200, 201).
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.session, this.openWeb, this.openVideo});

  final ChatSession session;

  /// A web address; Safari unless a test watches it instead. False when nothing opened it.
  final Future<bool> Function(Uri uri)? openWeb;

  /// A video's address, opened in the app as a pasted link ([openVideoLink]) unless a test watches it instead.
  final Future<void> Function(BuildContext context, String link)? openVideo;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  ChatModel? _model;
  AppServices? _services;
  final _scroll = ScrollController();
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _emotes = false;
  List<EmotePackage>? _packages;
  bool _packagesFailed = false;
  bool _checkingOlder = false;

  ChatSession get _session => widget.session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    final services = _services = AppScope.of(context);
    final model = _model = ChatModel(
      api: services.messageApi,
      session: _session,
      selfMid: () => services.environment.mid,
    )..addListener(_modelChanged);
    services.follows.addListener(_followsChanged);
    _scroll.addListener(_nearTop);
    unawaited(_open(model, services));
    unawaited(model.loadSettings());
  }

  @override
  void dispose() {
    _services?.follows.removeListener(_followsChanged);
    _model
      ?..removeListener(_modelChanged)
      ..dispose();
    _scroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The first page acks the session up to its newest message.
  Future<void> _open(ChatModel model, AppServices services) async {
    final page = await model.start();
    if (page == null || !mounted) return;
    try {
      await services.messages.chatOpened(_acked(page.maxSeqno));
    } catch (error) {
      Logger.shared.warn(LogCategory.api, 'chat ack failed', {'error': '${error.runtimeType}'});
    }
  }

  ChatSession _acked(int seqno) {
    final session = _session;
    return ChatSession(
      talkerId: session.talkerId,
      sessionType: session.sessionType,
      name: session.name,
      face: session.face,
      lastText: session.lastText,
      time: session.time,
      unread: session.unread,
      ackSeqno: session.ackSeqno,
      maxSeqno: math.max(session.maxSeqno, seqno),
      top: session.top,
      box: session.box,
      vipPink: session.vipPink,
      bigVip: session.bigVip,
      verify: session.verify,
      pendant: session.pendant,
    );
  }

  void _modelChanged() {
    if (!mounted) return;
    setState(() {});
    // A short first page doesn't fill the screen, so no scroll would ever reach the top to ask for more.
    if (!_checkingOlder) {
      _checkingOlder = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkingOlder = false;
        if (mounted) _nearTop();
      });
    }
  }

  void _followsChanged() {
    final last = _services?.follows.last;
    if (last != null && last.mid == _session.talkerId) _model?.followChanged(last.following);
  }

  /// The list is reversed, so what lies past its end is the older messages above.
  void _nearTop() {
    final model = _model;
    if (model == null || !model.hasMore || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    if (position.extentAfter < MessageChatTheme.olderAhead) unawaited(model.loadOlder());
  }

  bool get _loggedOut => switch (_services?.environment.account) {
    LoggedOut() || LoginExpired() => true,
    _ => false,
  };

  /// True when there's an account to act as, after the login page if it took one. An account still being checked
  /// is asked first: sending under it would go out as nobody.
  Future<bool> _signedIn() async {
    final environment = _services!.environment;
    if (environment.account is AccountUnknown) {
      await environment.refreshAccount();
      if (!mounted) return false;
      if (environment.account is AccountUnknown) {
        showToast(context, '账号确认失败，请稍后重试');
        return false;
      }
    }
    if (!_loggedOut) return true;
    return _services!.loginGate.request(context);
  }

  void _failed(Object error) {
    if (!mounted) return;
    if (error is BiliError && error.needsLogin) {
      unawaited(_services!.loginGate.request(context));
    } else {
      showToast(context, CommentsModel.messageFor(error));
    }
  }

  Future<void> _togglePush() async {
    if (!await _signedIn() || !mounted) return;
    try {
      await _model!.togglePush();
    } on UnsupportedError {
      if (mounted) showToast(context, '暂未开放');
    } catch (error) {
      _failed(error);
    }
  }

  Future<void> _follow() async {
    if (!await _signedIn() || !mounted) return;
    try {
      await _model!.follow();
      _services?.follows.changed(_session.talkerId, following: true);
    } catch (error) {
      _failed(error);
    }
  }

  Future<void> _send(String typed) async {
    final text = typed.trim();
    if (text.isEmpty) return;
    if (!await _signedIn() || !mounted) return;
    _text.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      await _model!.send(text);
    } catch (error) {
      if (!mounted) return;
      _restore(text);
      _failed(error);
    }
  }

  /// Puts [failed] back in front of whatever was typed since, the caret where it was in that text.
  void _restore(String failed) {
    final now = _text.value;
    final selection = now.selection;
    final shift = failed.length;
    _text.value = TextEditingValue(
      text: failed + now.text,
      selection: selection.isValid
          ? selection.copyWith(baseOffset: selection.baseOffset + shift, extentOffset: selection.extentOffset + shift)
          : TextSelection.collapsed(offset: failed.length + now.text.length),
    );
  }

  /// The field keeps its focus either way: read-only under the panel, so its caret stays with no keyboard, and the
  /// keyboard comes back as it turns editable again.
  void _toggleEmotes() {
    setState(() => _emotes = !_emotes);
    if (_emotes && _packages == null) unawaited(_loadPackages());
    if (_focus.hasFocus) return;
    // Once the field has rebuilt read-only, or focus would bring the keyboard up under the panel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  Future<void> _loadPackages() async {
    setState(() => _packagesFailed = false);
    try {
      final packages = await EmoteCatalog.shared.load(_services!.pageApi);
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _packagesFailed = packages.isEmpty;
      });
    } catch (_) {
      // EmoteCatalog logs it.
      if (mounted) setState(() => _packagesFailed = true);
    }
  }

  void _pickEmote(Emote emote) {
    final value = _text.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, emote.token),
      selection: TextSelection.collapsed(offset: start + emote.token.length),
    );
    RecentEmotes.shared.record(emote);
  }

  void _dismiss() {
    _focus.unfocus();
    if (_emotes) setState(() => _emotes = false);
  }

  void _openLink(String address) => unawaited(
    openChatLink(
      context,
      address,
      openWeb: widget.openWeb ?? openInSafari,
      openVideo: widget.openVideo ?? openVideoLink,
    ),
  );

  void _openFace(ChatMessage message) =>
      unawaited(openSpace(context, UploaderRef(mid: message.senderMid, name: _session.name, face: _session.face)));

  @override
  Widget build(BuildContext context) {
    final model = _model!;
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom;
    final composer = model.isPerson;
    final settings = model.settings;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      // Pushed on a plain page route with no Material above it, words would otherwise take the app's fallback style.
      child: DefaultTextStyle(
        style: chatStyle(MessageChatTheme.bubbleText, MessageChatTheme.text),
        child: ColoredBox(
          color: MessageChatTheme.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: media.padding.top),
              _TitleRow(title: _session.box?.label ?? _session.name),
              if (model.showsBar && settings != null)
                ChatSettingsBar(
                  pushOn: settings.pushOn,
                  showPush: settings.showPush,
                  following: model.following,
                  onPush: () => unawaited(_togglePush()),
                  onFollow: () => unawaited(_follow()),
                ),
              Expanded(child: _body(model, bottom: composer ? 0 : safeBottom)),
              if (composer) ...[
                ChatComposer(
                  controller: _text,
                  focus: _focus,
                  showingEmotes: _emotes,
                  onPicture: () => showToast(context, '暂未开放'),
                  onToggleEmotes: _toggleEmotes,
                  onSend: (text) => unawaited(_send(text)),
                ),
                if (_emotes)
                  ChatEmotePanel(
                    packages: _packages,
                    recent: () => RecentEmotes.shared.list,
                    height: math.max(MessageChatTheme.emotePanel, safeBottom),
                    bottomInset: safeBottom,
                    onPick: _pickEmote,
                    onUnavailable: () => showToast(context, '暂未开放'),
                    onRetry: _packagesFailed ? () => unawaited(_loadPackages()) : null,
                  )
                else
                  SizedBox(
                    key: const ValueKey('chat-keyboard'),
                    height: math.max(media.viewInsets.bottom, safeBottom),
                    child: ColoredBox(color: MessageChatTheme.card),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ChatModel model, {required double bottom}) {
    if (model.messages.isEmpty) {
      if (model.loading) {
        return const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: LoadingTvTheme.stateTop),
            child: LoadingTvState(key: ValueKey('chat-loading')),
          ),
        );
      }
      if (model.error != null) {
        return _Retry(key: const ValueKey('chat-failed'), onTap: () => unawaited(_open(model, _services!)));
      }
    }
    final messages = model.messages;
    final older = model.loadingOlder || model.olderFailed;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismiss,
      child: Align(
        alignment: Alignment.topCenter,
        // Newest at the bottom, where the list starts; a chat shorter than the screen sits at its top (203).
        child: ListView.builder(
          key: const ValueKey('chat-list'),
          controller: _scroll,
          reverse: true,
          shrinkWrap: true,
          padding: EdgeInsets.only(top: MessageChatTheme.listTop, bottom: MessageChatTheme.listBottom + bottom),
          itemCount: messages.length + (older ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) return _olderRow(model);
            final at = messages.length - 1 - index;
            return _item(model, messages, at);
          },
        ),
      ),
    );
  }

  Widget _olderRow(ChatModel model) => SizedBox(
    height: MessageChatTheme.olderRow,
    child: Center(
      child: model.olderFailed
          ? _Retry(key: const ValueKey('chat-older-failed'), onTap: model.retryOlder)
          : const CupertinoActivityIndicator(key: ValueKey('chat-older-loading')),
    ),
  );

  Widget _item(ChatModel model, List<ChatMessage> messages, int at) {
    final message = messages[at];
    final first = at == 0;
    final stamped = first || !sameMinute(messages[at - 1].time, message.time);
    final card = message.kind == ChatMessageKind.notice;
    return Column(
      key: ValueKey('chat-item-${message.seqno}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stamped) ...[
          if (!first) const SizedBox(height: MessageChatTheme.timeGap),
          ChatTimeLine(time: message.time),
          const SizedBox(height: MessageChatTheme.rowGap),
        ] else
          SizedBox(height: card ? MessageChatTheme.cardGap : MessageChatTheme.rowGap),
        _row(model, message),
      ],
    );
  }

  Widget _row(ChatModel model, ChatMessage message) {
    final own = model.isOwn(message);
    switch (message.kind) {
      case ChatMessageKind.notice:
        return ChatNoticeCard(message: message, onLink: _openLink);
      case ChatMessageKind.tip:
        return ChatTip(text: message.text);
      case ChatMessageKind.withdrawn:
        return ChatTip(text: own ? '你撤回了一条消息' : '对方撤回了一条消息');
      case ChatMessageKind.other when message.text.isEmpty:
        return const SizedBox.shrink();
      case ChatMessageKind.text || ChatMessageKind.picture || ChatMessageKind.other:
        return ChatBubbleRow(
          message: message,
          own: own,
          box: _session.box,
          face: _session.face,
          onFace: () => _openFace(message),
          onLink: _openLink,
        );
    }
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    void back() => unawaited(Navigator.of(context).maybePop());
    void settings() => showToast(context, '暂未开放');
    return SizedBox(
      height: MessageChatTheme.barRow,
      child: Stack(
        children: [
          Positioned.fill(
            left: MessageChatTheme.titleSide,
            right: MessageChatTheme.titleSide,
            child: Center(
              child: Text(
                title,
                key: const ValueKey('chat-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: chatStyle(
                  MessageChatTheme.titleText,
                  MessageChatTheme.text,
                  weight: MessageChatTheme.titleWeight,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MessageChatTheme.backTarget,
            child: Semantics(
              button: true,
              label: '返回',
              onTap: back,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('chat-back'),
                behavior: HitTestBehavior.opaque,
                onTap: back,
                child: const CustomPaint(painter: ChatBackPainter()),
              ),
            ),
          ),
          Positioned(
            right: MessageChatTheme.gearCentreRight - MessageChatTheme.backTarget / 2,
            top: 0,
            bottom: 0,
            width: MessageChatTheme.backTarget,
            child: Semantics(
              button: true,
              label: '设置',
              onTap: settings,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('chat-settings'),
                behavior: HitTestBehavior.opaque,
                onTap: settings,
                child: Center(
                  child: ChatGlyph(
                    ChatArt.settings,
                    width: MessageChatTheme.gearWidth,
                    height: MessageChatTheme.gearHeight,
                    color: MessageChatTheme.dim,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '加载失败，点击重试',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: Text('加载失败，点击重试', style: chatStyle(MessageChatTheme.tipText, MessageChatTheme.grey))),
    ),
  );
}
