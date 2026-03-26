import 'package:web/web.dart' as web;

bool isWindowsFocused() {
  return web.document.hasFocus();
}

void preventGoPrevPage() {
  /// add new history so user will not go back
  web.window.history.pushState(null, '', web.window.location.href);
  web.window.onPopState.listen((event) {
    /// push a new history to counteract back page
    web.window.history.pushState(null, '', web.window.location.href);
  });
}
