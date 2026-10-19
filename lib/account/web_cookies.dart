import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The login web view's cookie store (`WKWebsiteDataStore.default()`, which `webview_flutter`'s WKWebView uses). The
/// package can clear it but not read it, and Bilibili's SESSDATA is HttpOnly, so the page's own script can't see it
/// either; `WebCookies.swift` reads it.
abstract interface class WebCookies {
  factory WebCookies.platform() => Platform.isIOS ? ChannelWebCookies() : const NoWebCookies();

  /// Every cookie on a bilibili.com domain, name → value.
  Future<Map<String, String>> bilibili();

  /// Removes the bilibili.com cookies, so the login page starts signed out.
  Future<void> clearBilibili();

  /// Removes everything the web view stored (logout).
  Future<void> clearAll();
}

class ChannelWebCookies implements WebCookies {
  ChannelWebCookies([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('bilifast/web_cookies');

  // ignore: unused_field
  final MethodChannel _channel;

  @override
  Future<Map<String, String>> bilibili() => throw UnimplementedError('slice 8: login');

  @override
  Future<void> clearBilibili() => throw UnimplementedError('slice 8: login');

  @override
  Future<void> clearAll() => throw UnimplementedError('slice 8: login');
}

/// The PC: no web view, nothing stored.
class NoWebCookies implements WebCookies {
  const NoWebCookies();

  @override
  Future<Map<String, String>> bilibili() async => const {};

  @override
  Future<void> clearBilibili() async {}

  @override
  Future<void> clearAll() async {}
}
