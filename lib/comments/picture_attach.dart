import 'package:flutter/widgets.dart';

import 'composer_model.dart';

/// The composer's ⊕: up to [limit] pictures from the photo library, without asking for library access. Empty when
/// the viewer cancels.
Future<List<PickedPicture>> pickPictures({required int limit}) async => const [];

/// The picked pictures under the composer's field, each with a ✕ that takes it out.
class AttachedPictures extends StatelessWidget {
  const AttachedPictures({super.key, required this.pictures, required this.onRemove});

  final List<PickedPicture> pictures;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
