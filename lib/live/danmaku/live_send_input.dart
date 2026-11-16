import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show AdaptiveTextSelectionToolbar, InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../comments/field_strut.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_emote_panel.dart';
import 'live_recent_emotes.dart';
import 'live_send_glyphs.dart';

/// The 弹幕 input over the keyboard: 226 and its emote panel 227 in portrait, 223 in full screen. Closes through
/// [overlays] once sent or dismissed.
///
/// It takes the whole screen it is given, with the keyboard's inset still in its MediaQuery: a tap above the panel
/// closes it. Emotes whose text is bracketed ([dog]) go into the field, as 227's ⌫ shows; the others are sent at once.
class LiveSendInput extends StatefulWidget {
  const LiveSendInput({super.key, required this.room, required this.overlays, required this.landscape});

  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  State<LiveSendInput> createState() => _LiveSendInputState();
}

class _LiveSendInputState extends State<LiveSendInput> {
  /// One call per room for as long as the room is open; a failure or an empty answer is asked again next time.
  static final _packagesOf = Expando<Future<List<LiveEmotePackage>>>();

  static final _token = RegExp(r'\[[^\[\]]{1,16}\]$');

  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _emotes = false;
  bool _sending = false;
  bool _sendingEmote = false;
  List<LiveEmotePackage>? _packages;
  bool _packagesFailed = false;
  LiveRecentEmotes? _recents;

  bool get _canSend => !_sending && _text.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text.addListener(_textChanged);
    unawaited(_loadPackages());
    _recents = LiveRecentEmotes.loaded;
    if (_recents == null) {
      unawaited(
        LiveRecentEmotes.shared().then((store) {
          if (mounted) setState(() => _recents = store);
        }),
      );
    }
  }

  @override
  void dispose() {
    _text
      ..removeListener(_textChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _hadText = false;

  void _textChanged() {
    final has = _text.text.trim().isNotEmpty;
    if (has == _hadText) return;
    _hadText = has;
    setState(() {});
  }

  Future<void> _loadPackages() async {
    final room = widget.room;
    final asked = _packagesOf[room] ??= room.api.emotes(room.roomId);
    if (_packagesFailed) setState(() => _packagesFailed = false);
    try {
      final packages = await asked;
      if (packages.isEmpty && identical(_packagesOf[room], asked)) _packagesOf[room] = null;
      if (mounted) setState(() => _packages = packages);
    } catch (error) {
      if (identical(_packagesOf[room], asked)) _packagesOf[room] = null;
      Logger.shared.warn(LogCategory.api, 'live emotes failed', {'error': _reason(error)});
      if (mounted) setState(() => _packagesFailed = true);
    }
  }

  static String _reason(Object error) => error is BiliError ? error.userMessage : '${error.runtimeType}';

  /// The recently used ones this room has, then its first package's, as many as the band holds.
  List<LiveEmote> _bandEmotes() {
    final room = [for (final package in _packages ?? const <LiveEmotePackage>[]) ...package.emotes];
    final band = <LiveEmote>[];
    void add(LiveEmote emote) {
      if (band.length >= LiveSendTheme.recentCount) return;
      if (band.any((shown) => LiveRecentEmotes.sameEmote(shown, emote))) return;
      band.add(emote);
    }

    for (final recent in _recents?.list ?? const <LiveEmote>[]) {
      for (final emote in room) {
        if (LiveRecentEmotes.sameEmote(emote, recent)) {
          add(emote);
          break;
        }
      }
    }
    for (final emote in _packages?.firstOrNull?.emotes ?? const <LiveEmote>[]) {
      add(emote);
    }
    return band;
  }

  /// The field keeps its focus either way: read-only under the panel, so its caret stays with no keyboard, and the
  /// keyboard comes back as it turns editable again.
  void _toggleEmotes() {
    setState(() => _emotes = !_emotes);
    if (_emotes && _packages == null && _packagesFailed) unawaited(_loadPackages());
    if (_focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  void _unavailable() => showToast(context, '暂未开放');

  void _pick(LiveEmote emote) {
    if (insertsAsText(emote)) {
      if (_insert(emote.text)) _recents?.record(emote);
    } else {
      unawaited(_sendEmote(emote));
    }
  }

  /// Puts [token] at the caret unless the field would pass its limit.
  bool _insert(String token) {
    final value = _text.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, token);
    if (next.characters.length > LiveSendTheme.maxLength) return false;
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    return true;
  }

  /// ⌫: an emote's whole [token] before the caret, else one character.
  void _delete() {
    final value = _text.value;
    final selection = value.selection;
    final end = selection.isValid ? selection.end : value.text.length;
    var start = selection.isValid ? selection.start : end;
    if (start == end) {
      final before = value.text.substring(0, end);
      if (before.isEmpty) return;
      final token = _token.firstMatch(before);
      start = token != null ? token.start : end - before.characters.last.length;
    }
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }

  Future<bool> _loginFirst() async {
    if (widget.room.loggedIn()) return false;
    await AppScope.of(context).loginGate.request(context);
    return true;
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    if (await _loginFirst()) return;
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      await widget.room.send(text);
      if (!mounted) return;
      _text.clear();
      widget.overlays.close();
    } catch (error) {
      if (mounted) await _failed(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendEmote(LiveEmote emote) async {
    if (_sendingEmote) return;
    if (await _loginFirst()) return;
    if (!mounted) return;
    _sendingEmote = true;
    try {
      await widget.room.sendEmote(emote);
      _recents?.record(emote);
    } catch (error) {
      if (mounted) await _failed(error);
    } finally {
      _sendingEmote = false;
    }
  }

  Future<void> _failed(Object error) async {
    if (error is BiliError && error.needsLogin) {
      await AppScope.of(context).loginGate.request(context);
      return;
    }
    showToast(context, failureMessage(error));
  }

  @override
  Widget build(BuildContext context) {
    final landscape = widget.landscape;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final below = _emotes
        ? LiveEmotePanel(
            packages: _packages,
            height: landscape ? LiveSendTheme.emotePanelLandscape : LiveSendTheme.emotePanelHeight,
            onPick: _pick,
            onDelete: _delete,
            failed: _packagesFailed,
            onRetry: _packagesFailed ? () => unawaited(_loadPackages()) : null,
          )
        : SizedBox(key: const ValueKey('live-send-keyboard'), height: keyboard);
    return Stack(
      key: const ValueKey('live-send-input'),
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('live-send-outside'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.overlays.close,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // Taps beside the pill pass through to close the input; the panel's fill takes its own.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: landscape ? LiveSendTheme.pillLeftLandscape : LiveSendTheme.pillLeft,
                  bottom: LiveSendTheme.pillGap,
                ),
                child: _SuperChatPill(onTap: _unavailable),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: LiveSendTheme.panelFill,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(LiveSendTheme.panelRadius)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: LiveSendTheme.fieldTop),
                    landscape ? _landscapeRow() : _portraitRow(),
                    SizedBox(
                      height: _emotes ? LiveSendTheme.bandHeightPanel : LiveSendTheme.bandHeight,
                      child: landscape ? _landscapeBand() : _portraitBand(),
                    ),
                  ],
                ),
              ),
              below,
            ],
          ),
        ),
      ],
    );
  }

  Widget _portraitRow() => SizedBox(
    height: LiveSendTheme.fieldHeight,
    child: Row(
      children: [
        const SizedBox(width: LiveSendTheme.fieldSide),
        Expanded(child: _field()),
        const SizedBox(width: LiveSendTheme.sendGap),
        _sendButton(),
        const SizedBox(width: LiveSendTheme.fieldSide),
      ],
    ),
  );

  Widget _landscapeRow() => SizedBox(
    height: LiveSendTheme.fieldHeight,
    child: Row(
      children: [
        const SizedBox(width: LiveSendTheme.landscapeSide),
        Expanded(child: _field()),
        const SizedBox(width: LiveSendTheme.landscapeGlyphGap),
        ..._glyphs(LiveSendTheme.landscapeGlyphCell),
        const SizedBox(width: LiveSendTheme.landscapeSendGap),
        _sendButton(),
        const SizedBox(width: LiveSendTheme.landscapeSide),
      ],
    ),
  );

  Widget _portraitBand() => Row(
    children: [
      Expanded(child: _emoteRow(left: LiveSendTheme.emoteLeft)),
      ..._glyphs(LiveSendTheme.glyphCell),
    ],
  );

  Widget _landscapeBand() => Padding(
    padding: const EdgeInsets.only(right: LiveSendTheme.landscapeEmoteRight),
    child: _emoteRow(left: LiveSendTheme.landscapeEmoteLeft),
  );

  /// The band's emotes from [left] (the first one's edge), fading out at the band's end.
  Widget _emoteRow({required double left}) {
    final emotes = _bandEmotes();
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = rect.width <= 0 ? 0.0 : (LiveSendTheme.emoteFade / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          colors: const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 1 - fade, 1],
        ).createShader(rect);
      },
      child: ListView.builder(
        key: const ValueKey('live-send-band'),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: left - (LiveSendTheme.emoteStep - LiveSendTheme.emoteSize) / 2),
        itemExtent: LiveSendTheme.emoteStep,
        itemCount: emotes.length,
        itemBuilder: (context, index) => LiveEmoteButton(
          emote: emotes[index],
          size: LiveSendTheme.emoteSize,
          onTap: _pick,
          keyPrefix: 'live-recent',
        ),
      ),
    );
  }

  List<Widget> _glyphs(double cell) => [
    _Glyph(
      key: const ValueKey('live-send-translate'),
      label: '翻译',
      width: cell,
      onTap: _unavailable,
      child: Image.asset(
        'assets/images/live/send_translate.png',
        width: LiveSendTheme.translateWidth,
        height: LiveSendTheme.translateHeight,
        color: LiveSendTheme.glyph,
      ),
    ),
    _Glyph(
      key: const ValueKey('live-send-face'),
      label: _emotes ? '键盘' : '表情',
      width: cell,
      onTap: _toggleEmotes,
      child: LiveFaceGlyph(color: _emotes ? LiveSendTheme.glyphOn : LiveSendTheme.glyph),
    ),
    _Glyph(
      key: const ValueKey('live-send-style'),
      label: '弹幕样式',
      width: cell,
      onTap: _unavailable,
      child: Image.asset(
        'assets/images/live/send_style.png',
        width: LiveSendTheme.styleSize,
        height: LiveSendTheme.styleSize,
        color: LiveSendTheme.glyph,
      ),
    ),
  ];

  /// iOS's own edit menu: its Paste reads the clipboard without the "Allow Paste" alert Flutter's toolbar brings up.
  static Widget _editMenu(BuildContext context, EditableTextState state) => SystemContextMenu.isSupported(context)
      ? SystemContextMenu.editableText(editableTextState: state)
      : AdaptiveTextSelectionToolbar.editableText(editableTextState: state);

  /// Flutter draws an iOS caret 2 pt taller than it is asked for.
  static double get _caretHeight => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => LiveSendTheme.caretHeight - 2,
    _ => LiveSendTheme.caretHeight,
  };

  Widget _field() {
    final style = sendStyle(LiveSendTheme.fieldText, LiveSendTheme.fieldInk);
    return Container(
      height: LiveSendTheme.fieldHeight,
      alignment: Alignment.centerLeft,
      decoration: const ShapeDecoration(color: LiveSendTheme.fieldFill, shape: StadiumBorder()),
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          key: const ValueKey('live-send-field'),
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          maxLines: 1,
          readOnly: _emotes,
          showCursor: true,
          onTap: _emotes ? _toggleEmotes : null,
          inputFormatters: [LengthLimitingTextInputFormatter(LiveSendTheme.maxLength)],
          textInputAction: TextInputAction.send,
          keyboardAppearance: Brightness.dark,
          cursorColor: LiveSendTheme.cursor,
          cursorWidth: LiveSendTheme.caretWidth,
          cursorHeight: _caretHeight,
          cursorRadius: Radius.zero,
          contextMenuBuilder: _editMenu,
          style: style,
          strutStyle: fieldStrut(context, style),
          onSubmitted: (_) => unawaited(_send()),
          // Keeps the keyboard up after a failed send.
          onEditingComplete: () {},
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: LiveSendTheme.fieldPadding),
            hintText: '弹幕支持下～',
            hintStyle: style.copyWith(color: LiveSendTheme.placeholder),
            hintMaxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _sendButton() {
    final enabled = _canSend;
    void tap() => unawaited(_send());
    return Semantics(
      button: true,
      enabled: enabled,
      label: '发送',
      onTap: enabled ? tap : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('live-send-button'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? tap : null,
        child: Container(
          width: LiveSendTheme.sendWidth,
          height: LiveSendTheme.fieldHeight,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: enabled ? LiveSendTheme.sendFill : LiveSendTheme.sendFillEmpty,
            shape: const StadiumBorder(),
          ),
          child: Text('发送', style: sendStyle(LiveSendTheme.sendText, LiveSendTheme.sendInk)),
        ),
      ),
    );
  }
}

/// What a failed send toasts: Bilibili's own words for its refusals (发送频率过快), never an address.
String failureMessage(Object error) => switch (error) {
  BiliAPIError(code: -352 || -412) => error.userMessage,
  BiliAPIError(:final message) when message.isNotEmpty => message,
  BiliError() => error.userMessage,
  _ => '发送失败，请稍后重试',
};

class _Glyph extends StatelessWidget {
  const _Glyph({super.key, required this.label, required this.width, required this.onTap, required this.child});

  final String label;
  final double width;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Center(child: child),
      ),
    ),
  );
}

class _SuperChatPill extends StatelessWidget {
  const _SuperChatPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '醒目留言',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('live-send-sc'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: LiveSendTheme.pillHeight,
        padding: const EdgeInsets.only(left: LiveSendTheme.pillPadLeft, right: LiveSendTheme.pillPadRight),
        decoration: const ShapeDecoration(
          color: LiveSendTheme.pillFill,
          shape: StadiumBorder(
            side: BorderSide(color: LiveSendTheme.pillLine, width: LiveSendTheme.pillLineWidth),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LiveScMark(),
            const SizedBox(width: LiveSendTheme.pillTextGap),
            Text('醒目留言', style: sendStyle(LiveSendTheme.pillText, LiveSendTheme.pillInk)),
          ],
        ),
      ),
    ),
  );
}
