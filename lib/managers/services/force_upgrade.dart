import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/meeting.event.loop.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/rust/errors.dart';

/// Message shown when Unleash or API does not supply a specific string.
const String kDefaultForceUpgradeMessage =
    'A new version of Proton Meet is available. Please update to continue.';

/// Stops meeting event loop and Unleash periodic refresh (keeps client for reads).
void haltBackgroundTasksForForceUpgrade() {
  try {
    ManagerFactory().get<MeetingEventLoopManager>().stop();
  } catch (_) {}
  try {
    ManagerFactory()
        .get<DataProviderManager>()
        .unleashDataProvider
        .stopPeriodicRefresh();
  } catch (_) {}
}

/// When [error] looks like a force-upgrade response, moves app into [AppForceUpgradeState]
/// and stops meeting loop + Unleash periodic refresh.
void enterForceUpgradeFromApiIfNeeded(ResponseError error) {
  if (!error.indicatesForceUpgrade) return;
  final appState = ManagerFactory().get<AppStateManager>();
  if (appState.state is AppForceUpgradeState) return;
  final message = error.error.isNotEmpty
      ? error.error
      : kDefaultForceUpgradeMessage;
  appState.emitState(AppForceUpgradeState(message: message));
  haltBackgroundTasksForForceUpgrade();
}
