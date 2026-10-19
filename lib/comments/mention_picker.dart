import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

/// The composer's @: the people the viewer follows, searchable by name; a tap picks one.
class MentionPicker extends StatefulWidget {
  const MentionPicker({super.key, required this.search, required this.onPick, required this.onClose});

  /// An empty query lists the most recently followed.
  final Future<List<MentionCandidate>> Function(String query) search;
  final ValueChanged<MentionCandidate> onPick;
  final VoidCallback onClose;

  @override
  State<MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<MentionPicker> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
