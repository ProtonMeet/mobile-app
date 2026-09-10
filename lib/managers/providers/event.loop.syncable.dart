import 'package:meet/rust/proton_meet/models/event.dart';

extension FrbGetEventsResponseEventLoop on FrbGetEventsResponse {
  bool get hasUserChanges =>
      refresh || user != null || (users != null && users!.isNotEmpty);
}

/// Providers that can refresh from remote/local sources when the event loop
/// reports relevant changes. Implementations must update their cache and
/// [DataProvider.emitState] so listening blocs can refresh UI.
abstract interface class EventLoopSyncable {
  bool shouldSyncFromEventLoop(FrbGetEventsResponse response);

  Future<void> syncFromEventLoop();
}
