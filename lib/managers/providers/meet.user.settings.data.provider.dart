import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/event.loop.syncable.dart';
import 'package:meet/managers/providers/feature.flag.aware.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/rust/proton_meet/models/event.dart';
import 'package:meet/rust/proton_meet/models/user_settings.dart';

class MeetUserSettingsLoaded extends DataState {
  MeetUserSettingsLoaded(this.settings);

  final FrbUserSettings settings;

  @override
  List<Object?> get props => [settings];
}

class MeetUserSettingsGuest extends DataState {
  @override
  List<Object?> get props => [];
}

/// Caches the signed-in user's Meet user settings (`GET/PUT /meet/v1/user-settings`).
///
/// Local persistence can be layered on top of the in-memory cache later; callers
/// should use this provider rather than calling [AppCore] directly.
class MeetUserSettingsDataProvider extends DataProvider
    implements EventLoopSyncable, FeatureFlagAware {
  MeetUserSettingsDataProvider({required AppCoreManager manager})
    : _manager = manager;

  final AppCoreManager _manager;

  FrbUserSettings? _settings;
  Future<FrbUserSettings?>? _loadInFlight;
  int _fetchGeneration = 0;

  FrbUserSettings? get settings => _settings;

  bool get defaultWaitingRoomEnabled => _settings?.waitingRoom ?? false;

  /// Returns cached settings or fetches from the server when missing.
  Future<FrbUserSettings?> ensureLoaded() async {
    if (_settings != null) {
      return _settings;
    }
    return refreshIfNeeded();
  }

  /// Convenience for flows that only need the waiting-room default.
  ///
  /// Returns `false` for unpaid users even when the saved preference is on.
  Future<bool> resolveWaitingRoomDefault({required bool isPaidUser}) async {
    if (!isPaidUser) {
      return false;
    }
    await ensureLoaded();
    return defaultWaitingRoomEnabled;
  }

  /// Returns cached settings for signed-in users, fetching only when missing.
  Future<FrbUserSettings?> refreshIfNeeded() async {
    if (!_manager.isAuthenticated) {
      await clear();
      return null;
    }
    if (_settings != null) {
      return _settings;
    }
    return _fetchFromNetwork();
  }

  Future<FrbUserSettings?> _fetchFromNetwork({bool force = false}) async {
    if (!force && _loadInFlight != null) {
      return _loadInFlight;
    }

    final generation = ++_fetchGeneration;
    final future = _fetchFromNetworkImpl(generation);
    _loadInFlight = future;
    try {
      return await future;
    } finally {
      if (_loadInFlight == future) {
        _loadInFlight = null;
      }
    }
  }

  Future<FrbUserSettings?> _fetchFromNetworkImpl(int generation) async {
    try {
      final next = await _manager.appCore.getUserSettings();
      if (generation != _fetchGeneration) {
        return _settings;
      }
      if (_settings == next) {
        return _settings;
      }
      _settings = next;
      logger.i(
        'Meet user settings loaded: waitingRoom=${_settings!.waitingRoom}',
      );
      emitState(MeetUserSettingsLoaded(_settings!));
      return _settings;
    } catch (e, st) {
      logger.w('Failed to load Meet user settings', error: e, stackTrace: st);
      return _settings;
    }
  }

  Future<FrbUserSettings> updateWaitingRoom({required bool enable}) async {
    _settings = await _manager.appCore.updateUserSettingsWaitingRoom(
      enable: enable,
    );
    emitState(MeetUserSettingsLoaded(_settings!));
    return _settings!;
  }

  /// Applies a value pushed by the event loop or another sync path without a
  /// network round-trip. No-op when unchanged.
  void applyRemoteSettings(FrbUserSettings settings) {
    if (_settings == settings) {
      return;
    }
    _settings = settings;
    emitState(MeetUserSettingsLoaded(settings));
  }

  @override
  bool shouldSyncFromEventLoop(FrbGetEventsResponse response) =>
      response.hasUserChanges;

  @override
  Future<void> syncFromEventLoop() => reload();

  @override
  Future<void> syncFromFeatureFlags(UnleashDataProvider unleash) async {
    if (!unleash.isMeetWaitingRoom()) {
      return;
    }
    await ensureLoaded();
  }

  @override
  Future<void> clear() async {
    _settings = null;
    emitState(MeetUserSettingsGuest());
  }

  @override
  Future<void> reload() async {
    if (!_manager.isAuthenticated) {
      await clear();
      return;
    }
    _settings = null;
    await _fetchFromNetwork(force: true);
  }
}
