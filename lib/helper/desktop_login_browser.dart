import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens the account desktop-login URL in an in-app WebView when supported,
/// otherwise in the system browser.
class DesktopLoginBrowser {
  const DesktopLoginBrowser._();

  static bool get canUseInAppWebView =>
      macOS && WebViewPlatform.instance != null;

  /// Clears stale account.proton.me session data from the shared WebView store.
  ///
  /// Prevents desktop fork login from reusing an account session whose token
  /// lacks Meet scopes ("Access token does not have sufficient scope").
  static Future<void> clearAccountWebViewData() async {
    if (!canUseInAppWebView) return;

    try {
      final hadCookies = await WebViewCookieManager().clearCookies();
      logger.d(
        'Desktop login WebView cookies cleared (hadCookies: $hadCookies)',
      );
    } catch (e, st) {
      logger.w('Desktop login WebView cookie clear failed: $e', stackTrace: st);
    }
  }

  static Future<void> openExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open sign-in page');
    }
  }
}
