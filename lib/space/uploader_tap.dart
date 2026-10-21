import 'dart:async';

import 'package:flutter/widgets.dart';

import 'space_route.dart';

/// An uploader as the place showing them knows them, so what opens can draw the face and name before its call
/// answers.
@immutable
final class UploaderRef {
  const UploaderRef({required this.mid, this.name, this.face});

  final int mid;
  final String? name;
  final String? face;
}

/// Where a tap on an uploader's face or name goes. A video page puts one over its body, so its uploader row and staff
/// open the uploader sheet (62); without one it's the space. Comments go straight to the space everywhere (75).
class UploaderTap extends InheritedWidget {
  const UploaderTap({super.key, required this.open, required super.child});

  final void Function(UploaderRef uploader) open;

  static void Function(UploaderRef uploader)? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UploaderTap>()?.open;

  @override
  bool updateShouldNotify(UploaderTap oldWidget) => open != oldWidget.open;
}

/// The uploader row's and staff's tap: the page's sheet when it has one, the space otherwise.
void openUploader(BuildContext context, UploaderRef uploader) {
  if (UploaderTap.maybeOf(context) case final open?) {
    open(uploader);
  } else {
    unawaited(openSpace(context, uploader));
  }
}
