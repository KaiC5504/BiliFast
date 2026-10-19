import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator, CupertinoButton;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../shared/theme.dart';
import 'web_cookies.dart';

/// 登录: Bilibili's own login page in a web view (BiliNative `LoginView.swift`); on the PC, a note to log in on the
/// phone. Pops true once the account is logged in.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LoginTheme.page,
    appBar: AppBar(
      backgroundColor: LoginTheme.bar,
      surfaceTintColor: LoginTheme.bar,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: _CloseButton(onTap: () => Navigator.of(context).pop(false)),
      title: Text('登录', style: LoginTheme.titleStyle),
    ),
    body: Platform.isIOS
        ? _WebLogin(
            environment: AppScope.of(context).environment,
            onLoggedIn: () => Navigator.of(context).pop(true),
          )
        : Center(
            child: Text('请在手机上登录', key: const ValueKey('login-on-phone'), style: LoginTheme.messageStyle),
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
      key: const ValueKey('login-close'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.square(
        dimension: LoginTheme.closeTarget,
        child: Icon(Icons.close, size: LoginTheme.closeIcon, color: LoginTheme.close),
      ),
    ),
  );
}

/// Bilibili's page, with the account taken from its cookies once it logs in.
class _WebLogin extends StatefulWidget {
  const _WebLogin({required this.environment, required this.onLoggedIn});

  final AppEnvironment environment;
  final VoidCallback onLoggedIn;

  @override
  State<_WebLogin> createState() => _WebLoginState();
}

class _WebLoginState extends State<_WebLogin> {
  static final _loginPage = Uri.parse('https://passport.bilibili.com/login');

  /// NSURLErrorCancelled (a load another one replaced) and WebKit's 102 (a load handed elsewhere).
  static const _ignoredErrors = {-999, 102};

  final _web = WebViewController();
  late final _watcher = LoginWatcher(
    cookies: widget.environment.webCookies,
    onSession: (cookies) => unawaited(_signIn(cookies)),
  );
  var _loading = true;
  String? _loadError;
  var _signingIn = false;

  /// The cookies of a login that didn't take, kept for 重试.
  Map<String, String>? _rejected;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _allow,
          onPageStarted: (_) => _setLoading(true),
          onPageFinished: _finished,
          onUrlChange: (_) => unawaited(_watcher.check()),
          onWebResourceError: _failed,
        ),
      );
    } catch (error) {
      Logger.shared.error(LogCategory.ui, 'login web view setup failed', {'error': '$error'});
    }
    await _start();
  }

  /// A SESSDATA left from an expired login would count as a fresh login at once (LoginView.swift :65-84), so the
  /// page loads only after the old bilibili.com cookies are gone.
  Future<void> _start() async {
    try {
      await widget.environment.webCookies.clearBilibili();
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'login cookies not cleared', {'error': '$error'});
    }
    if (!mounted) return;
    _watcher.start();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _web.loadRequest(_loginPage);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'login page load failed', {'error': '$error'});
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '页面加载失败';
        });
      }
    }
  }

  /// Pages that try to open the Bilibili app (bilibili://) would only fail with an unsupported URL.
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

  void _finished(String url) {
    // The query of Bilibili's cross-domain hops carries the session, so only the host and path are logged.
    final page = Uri.tryParse(url);
    Logger.shared.info(LogCategory.ui, 'login page', {'host': page?.host ?? '', 'path': page?.path ?? ''});
    _setLoading(false);
    unawaited(_watcher.check());
  }

  void _failed(WebResourceError error) {
    if (error.isForMainFrame == false || _ignoredErrors.contains(error.errorCode)) return;
    Logger.shared.warn(LogCategory.ui, 'login page failed', {'code': error.errorCode});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = error.description.isEmpty ? '页面加载失败' : error.description;
    });
  }

  Future<void> _signIn(Map<String, String> cookies) async {
    setState(() {
      _signingIn = true;
      _rejected = null;
    });
    final loggedIn = await widget.environment.didLogin(cookies);
    if (!mounted) return;
    if (loggedIn) {
      widget.onLoggedIn();
      return;
    }
    setState(() {
      _signingIn = false;
      _rejected = cookies;
    });
  }

  /// A check that couldn't reach Bilibili asks again with the same cookies; cookies Bilibili turned down need a
  /// fresh login on a cleared page.
  void _retrySignIn() {
    final cookies = _rejected;
    if (cookies == null) return;
    if (widget.environment.accountCheckFailed) {
      unawaited(_signIn(cookies));
      return;
    }
    setState(() => _rejected = null);
    unawaited(_start());
  }

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    final Widget? cover = _signingIn
        ? const CupertinoActivityIndicator(key: ValueKey('login-signing-in'), radius: LoginTheme.spinnerRadius)
        : _rejected != null
        ? _Retry(message: '登录失败', onRetry: _retrySignIn)
        : error != null
        ? _Retry(message: error, onRetry: () => unawaited(_load()))
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _web),
        if (cover != null)
          ColoredBox(color: LoginTheme.page, child: Center(child: cover))
        else if (_loading)
          const Center(child: CupertinoActivityIndicator(radius: LoginTheme.spinnerRadius)),
      ],
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(LoginTheme.inset),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center, style: LoginTheme.messageStyle),
        const SizedBox(height: LoginTheme.gap),
        CupertinoButton(
          onPressed: onRetry,
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(LoginTheme.retryHeight),
          child: Container(
            height: LoginTheme.retryHeight,
            padding: const EdgeInsets.symmetric(horizontal: LoginTheme.retryPadX),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(shape: StadiumBorder(side: BorderSide(color: LoginTheme.retry))),
            child: Text('重试', style: LoginTheme.retryStyle),
          ),
        ),
      ],
    ),
  );
}

/// Watches the web view's cookie store for Bilibili's SESSDATA and hands over every bilibili.com cookie the first
/// time a non-empty one is there. BiliNative observed `WKHTTPCookieStore`; webview_flutter has no such hook, so this
/// reads on every page finish and URL change and once a second in between.
class LoginWatcher {
  LoginWatcher({required this.cookies, required this.onSession, this.interval = const Duration(seconds: 1)});

  final WebCookies cookies;
  final void Function(Map<String, String> cookies) onSession;
  final Duration interval;
  Timer? _timer;
  bool _watching = false;
  bool _reading = false;

  /// Also after a login Bilibili turned down, once the page is cleared again.
  void start() {
    _watching = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  Future<void> check() async {
    if (!_watching || _reading) return;
    _reading = true;
    final Map<String, String> found;
    try {
      found = await cookies.bilibili();
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'login cookies unreadable', {'error': '$error'});
      return;
    } finally {
      _reading = false;
    }
    final session = found['SESSDATA'];
    if (!_watching || session == null || session.isEmpty) return;
    _stop();
    Logger.shared.info(LogCategory.ui, 'login cookies', {'count': found.length});
    onSession(found);
  }

  void dispose() => _stop();

  void _stop() {
    _watching = false;
    _timer?.cancel();
    _timer = null;
  }
}
