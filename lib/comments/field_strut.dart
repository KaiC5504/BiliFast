import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// What a TextField draws [style] over: the theme's input style, not the inherited default.
TextStyle fieldStyle(BuildContext context, TextStyle style) {
  final theme = Theme.of(context);
  return (theme.useMaterial3 ? theme.textTheme.bodyLarge! : theme.textTheme.titleMedium!).merge(style);
}

/// [BiliFonts.strut] for a TextField's [style]. Without it the field forces a strut from its own style, SF's line
/// under the system font, where its Chinese should sit on PingFang's.
StrutStyle? fieldStrut(BuildContext context, TextStyle style) => BiliFonts.strut(fieldStyle(context, style));
