import 'package:flutter/widgets.dart';

/// Tells a page when another page covers it and when that page leaves. A menu, sheet or dialog over the page is no
/// cover: the observer reports a push or pop only between two page routes. The app's navigator registers it.
final pageRoutes = RouteObserver<PageRoute<dynamic>>();
