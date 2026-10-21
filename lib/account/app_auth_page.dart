import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../shared/loading_tv.dart';
import '../shared/theme.dart';

/// Bilibili's confirm page for the app token's TV code, for when the confirm call is refused: the user taps its 确认,
/// and [TokenAppAuth] polls while the page is up and closes it once the token comes. Pops false when closed by hand.
class AppAuthPage extends StatelessWidget {
  const AppAuthPage({super.key, required this.url, required this.cookies});

  final Uri url;

  /// The account's cookies, put in the web view's store before the page loads, so it opens signed in even when the
  /// login came over from the Swift app rather than through the login page.
  final Map<String, String> cookies;

  static Route<bool> route(Uri url, Map<String, String> cookies) => MaterialPageRoute<bool>(
    fullscreenDialog: true,
    builder: (_) => AppAuthPage(url: url, cookies: cookies),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppAuthTheme.page,
    appBar: AppBar(
      backgroundColor: AppAuthTheme.bar,
      surfaceTintColor: AppAuthTheme.bar,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: _CloseButton(onTap: () => Navigator.of(context).pop(false)),
      title: Text('授权官方接口', style: AppAuthTheme.titleStyle),
    ),
    body: Platform.isIOS
        ? _ConfirmWeb(url: url, cookies: cookies)
        : Center(
            child: Text('请在手机上授权', key: const ValueKey('app-auth-on-phone'), style: AppAuthTheme.messageStyle),
          ),
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '关闭',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('app-auth-close'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.square(
        dimension: AppAuthTheme.closeTarget,
        child: Icon(Icons.close, size: AppAuthTheme.closeIcon, color: AppAuthTheme.close),
      ),
    ),
  );
}

class _ConfirmWeb extends StatefulWidget {
  const _ConfirmWeb({required this.url, required this.cookies});

  final Uri url;
  final Map<String, String> cookies;

  @override
  State<_ConfirmWeb> createState() => _ConfirmWebState();
}

class _ConfirmWebState extends State<_ConfirmWeb> {
  final _web = WebViewController();
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _allow,
          onPageStarted: (_) => _setLoading(true),
          onPageFinished: (_) => _setLoading(false),
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            Logger.shared.warn(LogCategory.ui, 'app auth page failed', {'code': error.errorCode});
            _setLoading(false);
          },
        ),
      );
    } catch (error) {
      Logger.shared.error(LogCategory.ui, 'app auth web view setup failed', {'error': '${error.runtimeType}'});
    }
    await _setCookies();
    try {
      await _web.loadRequest(widget.url);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'app auth page load failed', {'error': '${error.runtimeType}'});
      _setLoading(false);
    }
  }

  Future<void> _setCookies() async {
    final store = WebViewCookieManager();
    var failed = 0;
    for (final MapEntry(:key, :value) in widget.cookies.entries) {
      try {
        await store.setCookie(WebViewCookie(name: key, value: value, domain: '.bilibili.com'));
      } catch (_) {
        failed += 1;
      }
    }
    if (failed > 0) Logger.shared.warn(LogCategory.ui, 'app auth cookies not set', {'count': failed});
  }

  /// The page may try to open the Bilibili app (bilibili://), which would only fail.
  NavigationDecision _allow(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final scheme = Uri.tryParse(request.url)?.scheme;
    return scheme == 'https' || scheme == 'http' || scheme == 'about'
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  void _setLoading(bool loading) {
    if (mounted && _loading != loading) setState(() => _loading = loading);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      WebViewWidget(controller: _web),
      if (_loading) const ColoredBox(color: AppAuthTheme.page, child: Center(child: LoadingTvState())),
    ],
  );
}
