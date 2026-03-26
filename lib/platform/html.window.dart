// avoid import 'package:web/web.dart' for non-web target or will raise error
export 'html.window.nonweb.dart' if (dart.library.html) 'html.window.web.dart';
