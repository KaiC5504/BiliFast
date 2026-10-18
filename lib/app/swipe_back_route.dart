import 'package:flutter/cupertino.dart';

/// Flutter's own Cupertino page route: back is a swipe from the left edge only. The iOS 26 swipe from anywhere in
/// the content went back by accident too often (KaiC, 2026-10-19), so it is gone.
class SwipeBackPageRoute<T> extends CupertinoPageRoute<T> {
  SwipeBackPageRoute({required super.builder, super.settings});
}
