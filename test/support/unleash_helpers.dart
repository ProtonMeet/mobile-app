import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meet/constants/env.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/rust/proton_meet/models/unleash_response.dart';
import 'package:mockito/mockito.dart';
import 'package:unleash_proxy_client_flutter/in_memory_storage_provider.dart';
import 'package:unleash_proxy_client_flutter/parse_stringify_toggles.dart';
import 'package:unleash_proxy_client_flutter/toggle_config.dart';
import 'package:unleash_proxy_client_flutter/unleash_proxy_client_flutter.dart';
import 'package:unleash_proxy_client_flutter/variant.dart';

import '../mocks/app_core.mocks.dart';

const unleashTestAppName = 'ProtonMeet';

Uint8List encodeUnleashToggles(Map<String, bool> toggles) {
  final payload = {
    'toggles': toggles.entries
        .map(
          (entry) => {
            'name': entry.key,
            'enabled': entry.value,
            'impressionData': false,
            'variant': {'enabled': false, 'name': 'disabled'},
          },
        )
        .toList(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
}

UnleashResponse unleashTestResponse(
  Map<String, bool> toggles, {
  int statusCode = 200,
}) {
  return UnleashResponse(
    statusCode: statusCode,
    body: encodeUnleashToggles(toggles),
  );
}

void seedPersistedUnleashToggles(
  InMemoryStorageProvider storage,
  Map<String, bool> toggles,
) {
  final configs = {
    for (final entry in toggles.entries)
      entry.key: ToggleConfig(
        enabled: entry.value,
        impressionData: false,
        variant: Variant(enabled: false, name: 'disabled'),
      ),
  };
  storage.store[storageWithApp(unleashTestAppName, storageKey)] =
      stringifyToggles(configs);
}

Future<void> waitForUnleashInit(UnleashDataProvider provider) async {
  if (provider.unleashClient.clientState != ClientState.initializing) {
    return;
  }
  final completer = Completer<void>();
  provider.unleashClient.once('initialized', (_) {
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;
}

UnleashDataProvider createUnleashTestProvider(
  AppCoreManager appCoreManager,
  MockAppCore mockAppCore, {
  Map<String, bool> toggles = const {},
  bool bootstrapOverride = true,
  int refreshIntervalSeconds = 120,
  InMemoryStorageProvider? storageProvider,
  Map<String, bool> persistedToggles = const {},
}) {
  when(
    mockAppCore.fetchToggles(),
  ).thenAnswer((_) async => unleashTestResponse(toggles));

  final storage = storageProvider ?? InMemoryStorageProvider();
  seedPersistedUnleashToggles(storage, persistedToggles);

  return UnleashDataProvider(
    const ApiEnv.prod(),
    appCoreManager,
    bootstrapOverride: bootstrapOverride,
    storageProvider: storage,
    refreshIntervalSeconds: refreshIntervalSeconds,
  );
}
