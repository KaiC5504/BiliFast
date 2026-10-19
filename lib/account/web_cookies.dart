import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The login web view's cookie store (`WKWebsiteDataStore.default()`, which `webview_flutter`'s WKWebView uses).
/// Bilibili's SESSDATA is HttpOnly, so the page's own script can't see it. `WebViewCookieManager` could read it, but
/// its clear removes cookies only, and logout must also drop the web view's other stored data, so one native channel
/// (`WebCookies.swift`) does the read, the bilibili.com clear and the full clear.
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

  final MethodChannel _channel;

  @override
  Future<Map<String, String>> bilibili() async =>
      {...?await _channel.invokeMapMethod<String, String>('bilibili')};

  @override
  Future<void> clearBilibili() => _channel.invokeMethod<void>('clearBilibili');

  @override
  Future<void> clearAll() => _channel.invokeMethod<void>('clearAll');
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
