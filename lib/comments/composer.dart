import 'package:flutter/widgets.dart';

import 'composer_model.dart';

/// The composer (14): a white sheet over the dimmed page that rides on the keyboard, with the field, ⤢ to make it
/// tall, 转到动态, the keyboard / emote switch, @, ⊕ and 发布, and the emote panel in the keyboard's place.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.model, required this.onClose});

  final ComposerModel model;

  /// A tap on the dimmed page, or a successful post.
  final VoidCallback onClose;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
