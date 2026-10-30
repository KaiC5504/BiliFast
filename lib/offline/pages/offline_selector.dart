import 'package:flutter/widgets.dart';

import '../offline_library.dart';

/// Builds from what [select] reads off [library], and again only when a change makes it answer something new (by ==):
/// the library calls its listeners about once a second in all while anything downloads, and a row whose part didn't
/// move stays as it is.
class LibrarySelector<T> extends StatefulWidget {
  const LibrarySelector({super.key, required this.library, required this.select, required this.builder, this.equals});

  final OfflineLibrary library;
  final T Function(OfflineLibrary library) select;
  final Widget Function(BuildContext context, T value) builder;

  /// In place of ==, for a list.
  final bool Function(T a, T b)? equals;

  @override
  State<LibrarySelector<T>> createState() => _LibrarySelectorState<T>();
}

class _LibrarySelectorState<T> extends State<LibrarySelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.library);
    widget.library.addListener(_changed);
  }

  @override
  void didUpdateWidget(LibrarySelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      oldWidget.library.removeListener(_changed);
      widget.library.addListener(_changed);
    }
    _value = widget.select(widget.library);
  }

  @override
  void dispose() {
    widget.library.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.select(widget.library);
    final same = widget.equals?.call(next, _value) ?? next == _value;
    if (!same) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
