import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../app/form_factor.dart';

/// The device's [FormFactor] at launch on iOS. The engine can start Dart before the view has been laid out, when its
/// size is still zero, so the screen's size stands in; failing both, the first metrics with a size, up to [wait].
Future<FormFactor> launchFormFactor(WidgetsBinding binding, {Duration wait = const Duration(seconds: 1)}) async {
  final dispatcher = binding.platformDispatcher;
  final view = dispatcher.implicitView ?? (dispatcher.views.isEmpty ? null : dispatcher.views.first);
  if (view == null) return FormFactor.phone;
  if (!view.physicalSize.isEmpty) return FormFactor.fromView(view);
  final screen = _screen(view);
  if (screen != null) return screen;
  final sized = Completer<FormFactor>();
  final observer = _SizeObserver(view, sized);
  binding.addObserver(observer);
  try {
    return await sized.future.timeout(wait, onTimeout: () => FormFactor.phone);
  } finally {
    binding.removeObserver(observer);
  }
}

FormFactor? _screen(ui.FlutterView view) {
  final ui.Display display;
  try {
    display = view.display;
  } on Object {
    return null;
  }
  if (display.size.isEmpty || display.devicePixelRatio <= 0) return null;
  final shortest = (display.size / display.devicePixelRatio).shortestSide;
  return shortest >= FormFactor.padShortestSide ? FormFactor.pad : FormFactor.phone;
}

class _SizeObserver with WidgetsBindingObserver {
  _SizeObserver(this.view, this.sized);

  final ui.FlutterView view;
  final Completer<FormFactor> sized;

  @override
  void didChangeMetrics() {
    if (sized.isCompleted || view.physicalSize.isEmpty) return;
    sized.complete(FormFactor.fromView(view));
  }
}
