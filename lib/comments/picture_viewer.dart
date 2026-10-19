import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

/// A comment's pictures over the whole page: swipe between them, pinch to zoom, tap to close.
class PictureViewer extends StatefulWidget {
  const PictureViewer({super.key, required this.pictures, required this.initialIndex, required this.onClose});

  final List<CommentPicture> pictures;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<PictureViewer> createState() => _PictureViewerState();
}

class _PictureViewerState extends State<PictureViewer> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
