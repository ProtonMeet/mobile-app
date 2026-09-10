import 'dart:convert';

import 'package:meet/managers/providers/unleash.features.dart';
import 'package:unleash_proxy_client_flutter/toggle_config.dart';

/// Client-side defaults keyed by Unleash toggle name.
///
/// These are merged under every successful fetch so a toggle omitted by the
/// server keeps its [UnleashFeature.clientDefault]. When the server sends a
/// toggle, the server value wins.
Map<String, ToggleConfig> getDefaultToggles() {
  final defaults = <String, ToggleConfig>{};
  for (final feature in UnleashFeature.values) {
    final config = feature.defaultValue;
    if (config != null) {
      defaults[feature.toggleName] = config;
    }
  }
  return defaults;
}

/// Injects client bootstrap defaults into a Unleash `/frontend` fetch response.
///
/// Called from [UnleashDataProvider]'s fetcher on every successful (HTTP 200)
/// toggle payload, before the Unleash SDK parses it.
///
/// Merge rules:
/// 1. Start from [getDefaultToggles] — only [UnleashFeature] values with a
///    non-null [UnleashFeature.clientDefault] (e.g. VP9 off until Unleash ships it).
/// 2. Overlay toggles returned by the server — **server wins** when the same
///    name appears in both maps.
/// 3. Toggles the server omits keep the client default from step 1.
/// 4. Toggles with no [clientDefault] and omitted by the server are unchanged
///    (still absent from the merged payload).
///
/// Returns the original UTF-8 body unchanged if JSON is missing, malformed, or
/// not in the expected `{ "toggles": [ ... ] }` shape.
String mergeTogglesWithClientDefaults(List<int> bodyBytes) {
  final defaults = getDefaultToggles();
  if (defaults.isEmpty) {
    return utf8.decode(bodyBytes);
  }

  final decoded = _tryDecodeTogglePayload(bodyBytes);
  if (decoded == null) {
    return utf8.decode(bodyBytes);
  }

  final toggles = decoded['toggles'];
  if (toggles is! List) {
    return utf8.decode(bodyBytes);
  }

  final merged = <String, Map<String, dynamic>>{
    for (final entry in defaults.entries)
      entry.key: {'name': entry.key, ...entry.value.toMap()},
  };

  for (final toggle in toggles) {
    if (toggle is Map<String, dynamic>) {
      final name = toggle['name'];
      if (name is String) {
        merged[name] = Map<String, dynamic>.from(toggle);
      }
    }
  }

  return jsonEncode({'toggles': merged.values.toList()});
}

Map<String, dynamic>? _tryDecodeTogglePayload(List<int> bodyBytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
