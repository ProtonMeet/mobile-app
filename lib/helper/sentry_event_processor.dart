import 'dart:async';

import 'package:meet/helper/user.agent.dart';
import 'package:sentry/sentry.dart';

/// Event processor that adds custom tags to all Sentry events
/// Also filters out Sentry's own errors to prevent infinite loops
class TagEventProcessor implements EventProcessor {
  @override
  FutureOr<SentryEvent?> apply(SentryEvent event, Hint hint) async {
    // Filter out Sentry's own errors to prevent infinite loops
    if (event.logger == 'sentry') {
      return null; // Don't send Sentry's own errors
    }
    final message = event.message?.formatted ?? '';
    if (message.contains('[sentry]')) {
      return null; // Don't send Sentry's own errors
    }
    final appVersion = await UserAgent().appVersion;
    event.tags = {
      ...?event.tags,
      'page-locale': 'en-us',
      'app-version': appVersion,
    };
    return event;
  }
}
