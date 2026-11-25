import 'package:bili_core/api.dart' show Chapter;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'landscape_chrome.dart' show fullScreenStrut, fullScreenText;

/// 273's chapters along the screen's bottom under the 章节 panel: each title centred on its stretch of the video, a
/// rule where each but the first starts, over a light band. The stretches share the whole width it is given.
class ChapterStrip extends StatelessWidget {
  const ChapterStrip({super.key, required this.chapters, required this.duration});

  final List<Chapter> chapters;
  final ValueListenable<double> duration;

  @override
  Widget build(BuildContext context) {
    // Outside the chrome's DefaultTextStyle, so nothing ambient may leak in.
    final style = fullScreenText.merge(
      const TextStyle(
        fontSize: ChapterStripTheme.titleText,
        fontWeight: ChapterStripTheme.titleWeight,
        letterSpacing: 0,
        height: 1,
      ),
    );
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: duration,
        builder: (context, total, _) {
          if (total <= 0) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double x(double seconds) => width * (seconds / total).clamp(0.0, 1.0);
              return SizedBox(
                key: const ValueKey('chapter-strip'),
                height: ChapterStripTheme.height,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [ChapterStripTheme.fillClear, ChapterStripTheme.fill],
                            stops: [0, ChapterStripTheme.solidFrom],
                          ),
                        ),
                      ),
                    ),
                    for (final chapter in chapters) ...[
                      if (chapter.from > 0 && chapter.from < total)
                        Positioned(
                          key: ValueKey('chapter-strip-rule-${chapter.from}'),
                          left: x(chapter.from) - ChapterStripTheme.rule / 2,
                          width: ChapterStripTheme.rule,
                          top: 0,
                          bottom: 0,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  ChapterStripTheme.ruleClear,
                                  ChapterStripTheme.ruleInk,
                                  ChapterStripTheme.ruleClear,
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (chapter.title.isNotEmpty && x(chapter.to) - x(chapter.from) > ChapterStripTheme.titlePad * 2)
                        Positioned(
                          left: x(chapter.from) + ChapterStripTheme.titlePad,
                          width: x(chapter.to) - x(chapter.from) - ChapterStripTheme.titlePad * 2,
                          bottom: ChapterStripTheme.titleCentre - ChapterStripTheme.titleText,
                          height: ChapterStripTheme.titleText * 2,
                          child: Center(
                            child: Text(
                              chapter.title,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                              strutStyle: fullScreenStrut(style),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
