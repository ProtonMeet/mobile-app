import 'package:meet/helper/extension/platform.extension.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens the account desktop-login URL in an in-app WebView when supported,
/// otherwise in the system browser.
class DesktopLoginBrowser {
  const DesktopLoginBrowser._();

  static bool get canUseInAppWebView =>
      macOS && WebViewPlatform.instance != null;

  static Future<void> openExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open sign-in page');
    }
  }
}
