import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show AdaptiveTextSelectionToolbar, InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../comments/field_strut.dart';
import '../../shared/theme.dart';
import 'chat_glyphs.dart';
import 'chat_rows.dart' show chatStyle;

/// A chat's composer (202, 218, 219): the picture button, 发个消息聊聊呗, and the face that swaps the keyboard for the
/// emote panel (the pink keyboard, or a tap on the field, swaps it back). Return sends.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.focus,
    required this.showingEmotes,
    required this.onPicture,
    required this.onToggleEmotes,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool showingEmotes;
  final VoidCallback onPicture;
  final VoidCallback onToggleEmotes;
  final ValueChanged<String> onSend;

  /// iOS's own edit menu: its Paste reads the clipboard without the "Allow Paste" alert Flutter's toolbar brings up.
  static Widget _editMenu(BuildContext context, EditableTextState state) => SystemContextMenu.isSupported(context)
      ? SystemContextMenu.editableText(editableTextState: state)
      : AdaptiveTextSelectionToolbar.editableText(editableTextState: state);

  /// Flutter draws an iOS caret 2 pt taller than it is asked for.
  static double get _caretHeight => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => MessageChatTheme.caretHeight - 2,
    _ => MessageChatTheme.caretHeight,
  };

  @override
  Widget build(BuildContext context) {
    final style = chatStyle(MessageChatTheme.fieldText, MessageChatTheme.text);
    final hint = style.copyWith(color: MessageChatTheme.grey);
    final strut = fieldStrut(context, style);
    return ColoredBox(
      key: const ValueKey('chat-composer'),
      color: MessageChatTheme.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: MessageChatTheme.composerHeight),
        child: Row(
          children: [
            _Tool(
              key: const ValueKey('chat-picture'),
              label: '图片',
              onTap: onPicture,
              trailing: false,
              child: const ChatGlyph(
                ChatArt.picture,
                width: MessageChatTheme.toolWidth,
                height: MessageChatTheme.pictureGlyphHeight,
                color: MessageChatTheme.dim,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: (MessageChatTheme.composerHeight - MessageChatTheme.fieldHeight) / 2,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: MessageChatTheme.fieldHeight),
                  alignment: Alignment.centerLeft,
                  decoration: const ShapeDecoration(color: MessageChatTheme.fieldFill, shape: StadiumBorder()),
                  child: Material(
                    type: MaterialType.transparency,
                    child: TextField(
                      key: const ValueKey('chat-field'),
                      controller: controller,
                      focusNode: focus,
                      minLines: 1,
                      maxLines: MessageChatTheme.fieldMaxLines,
                      // The keyboard's plain ⏎ (218), not 发送; the return it types sends instead of breaking the line.
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      inputFormatters: [_ReturnSends(onSend)],
                      keyboardAppearance: Brightness.light,
                      // Under the emote panel the field keeps its caret with no keyboard (219).
                      readOnly: showingEmotes,
                      showCursor: true,
                      onTap: showingEmotes ? onToggleEmotes : null,
                      cursorColor: MessageChatTheme.cursor,
                      cursorWidth: MessageChatTheme.caretWidth,
                      cursorHeight: _caretHeight,
                      cursorRadius: Radius.zero,
                      contextMenuBuilder: _editMenu,
                      style: style,
                      strutStyle: strut,
                      onSubmitted: onSend,
                      // Keeps the keyboard up after a send.
                      onEditingComplete: () {},
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: MessageChatTheme.fieldPadding,
                          vertical: MessageChatTheme.fieldTextTop,
                        ),
                        hintText: '发个消息聊聊呗',
                        hintStyle: hint,
                        hintMaxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Tool(
              key: const ValueKey('chat-emotes'),
              label: showingEmotes ? '键盘' : '表情',
              onTap: onToggleEmotes,
              trailing: true,
              child: showingEmotes
                  ? const ChatGlyph(
                      ChatArt.keyboard,
                      width: MessageChatTheme.toolWidth,
                      height: MessageChatTheme.keyboardGlyphHeight,
                      color: MessageChatTheme.keyboardInk,
                    )
                  : const ChatGlyph(
                      ChatArt.emote,
                      width: MessageChatTheme.toolWidth,
                      height: MessageChatTheme.emoteGlyphHeight,
                      color: MessageChatTheme.dim,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Takes a return typed at the caret back out and sends what was there; a pasted text keeps its line breaks.
class _ReturnSends extends TextInputFormatter {
  _ReturnSends(this.onSend);

  final ValueChanged<String> onSend;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final old = oldValue.text;
    final selection = oldValue.selection;
    final start = selection.isValid ? selection.start : old.length;
    final end = selection.isValid ? selection.end : old.length;
    if (newValue.text != old.replaceRange(start, end, '\n')) return newValue;
    // Not from inside the formatter: the send clears the field it is formatting.
    scheduleMicrotask(() => onSend(old));
    return oldValue;
  }
}

/// A glyph [MessageChatTheme.toolInset] from the screen's edge, its cell reaching the field.
class _Tool extends StatelessWidget {
  const _Tool({super.key, required this.label, required this.onTap, required this.trailing, required this.child});

  final String label;
  final VoidCallback onTap;
  final bool trailing;
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
        width: MessageChatTheme.fieldInset,
        height: MessageChatTheme.composerHeight,
        child: Padding(
          padding: EdgeInsets.only(
            left: trailing ? 0 : MessageChatTheme.toolInset,
            right: trailing ? MessageChatTheme.toolInset : 0,
          ),
          child: Align(alignment: trailing ? Alignment.centerRight : Alignment.centerLeft, child: child),
        ),
      ),
    ),
  );
}
