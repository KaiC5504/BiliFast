import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'landscape_chrome.dart' show fullScreenStrut, fullScreenText, latinSpacedFromChinese;
import 'player_notes.dart';

/// 274's notes at full screen's bottom left, the newest lowest; they stay whether the controls show or not, and take
/// no touches.
class PlayerNotesView extends StatelessWidget {
  const PlayerNotesView({super.key, required this.notes});

  final PlayerNotes notes;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    // Outside the chrome's DefaultTextStyle, so nothing ambient may leak in.
    final style = fullScreenText.merge(
      const TextStyle(fontSize: PlayerNotesTheme.text, fontWeight: FontWeight.normal, letterSpacing: 0, height: 1),
    );
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: notes,
        builder: (context, _) => Stack(
          children: [
            Positioned(
              left: insets.left + PlayerNotesTheme.left,
              right: insets.right,
              bottom: PlayerNotesTheme.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: PlayerNotesTheme.gap,
                children: [
                  for (final note in notes.shown)
                    DecoratedBox(
                      key: ValueKey('player-note-${note.id}'),
                      decoration: BoxDecoration(
                        color: PlayerNotesTheme.fill,
                        borderRadius: BorderRadius.circular(PlayerNotesTheme.radius),
                      ),
                      child: SizedBox(
                        height: PlayerNotesTheme.height,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: PlayerNotesTheme.inset),
                          child: Center(
                            widthFactor: 1,
                            child: Transform.translate(
                              offset: const Offset(0, PlayerNotesTheme.textDrop),
                              child: Text.rich(
                                latinSpacedFromChinese(note.text),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: style,
                                strutStyle: fullScreenStrut(style),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
