/// The website's QR login (`passport.bilibili.com/x/passport-login/web/qrcode/*`), which the Windows build uses:
/// the code is scanned and confirmed in the official app.
library;

/// A fresh code: [url] is what the QR draws, [key] what the poll asks about. Bilibili lets a code live 180 s.
final class WebLoginQr {
  const WebLoginQr({required this.url, required this.key});

  final String url;
  final String key;
}

/// One poll's answer.
sealed class WebLoginPoll {
  const WebLoginPoll();
}

/// 86101 (not scanned yet) or 86090 ([scanned], waiting for 确认 in the app).
final class WebLoginWaiting extends WebLoginPoll {
  const WebLoginWaiting({required this.scanned});

  final bool scanned;
}

/// 86038: the code ran out; a new one has to be asked for.
final class WebLoginExpired extends WebLoginPoll {
  const WebLoginExpired();
}

/// 0: logged in. [cookies] are the session's (SESSDATA, bili_jct, DedeUserID, DedeUserID__ckMd5, sid), read off the
/// answer's `url`. Never log them.
final class WebLoginDone extends WebLoginPoll {
  const WebLoginDone(this.cookies);

  final Map<String, String> cookies;
}
