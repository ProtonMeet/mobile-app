import 'dart:math';

import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/managers/services/force_upgrade.dart';
import 'package:meet/models/unlock.timer.dart';
import 'package:meet/models/unlock.type.dart';

enum LoadingTask {
  eligible,
  homeRecheck,
  syncRecheck,
  // subscription,
  // controllers,
  // userSettings,
  // eventLoop,
}

abstract class AppState extends DataState {}

class AppCryptoFailed extends AppState {
  final String message;

  AppCryptoFailed({required this.message});

  @override
  List<Object?> get props => [message];
}

class AppSessionFailed extends AppState {
  final String message;

  AppSessionFailed({required this.message});

  @override
  List<Object?> get props => [message];
}

class AppPermissionState extends AppState {
  final String message;

  AppPermissionState({required this.message});

  @override
  List<Object?> get props => [message];
}

class AppUnlockFailedState extends AppState {
  final String message;

  AppUnlockFailedState({required this.message});

  @override
  List<Object?> get props => [message];
}

class AppForceUpgradeState extends AppState {
  final String message;

  AppForceUpgradeState({required this.message});

  @override
  List<Object?> get props => [message];
}

class AppUnlockForceLogoutState extends AppState {
  AppUnlockForceLogoutState();

  @override
  List<Object?> get props => [];
}

class AppStateManager extends DataProvider implements Manager {
  final bool appInBetaState = true;
  bool isHomeInitialed = false;
  bool isHomeLoading = false;
  bool isConnectivityOK = true;
  bool exponentialBackoffForConcurrentlyMode = false;
  bool isLocked = false;
  bool isAuthenticating = false;
  bool isInBackground = false;
  List<LoadingTask> failedTask = [];

  /// const key
  final unlockKey = "proton_meet_app_k_unlock_type";
  final unlockErrorKey = "proton_meet_app_k_unlock_error_count";
  final lockTimerKey = "proton_meet_app_k_lock_timer";
  final lockTimerAppLastActivateTimeKey =
      "proton_meet_app_k_lock_timer_app_last_activate_time";

  /// user eligible
  final userEligible = "proton_meet_app_k_is_user_eligible";

  /// Secure storage key for the app state
  final SecureStorageManager secureStore;

  /// Shared preferences key for the app state
  final PreferencesManager shared;

  /// constructor
  AppStateManager(this.secureStore, this.shared);

  // bool updateStateFrom(BridgeError exception) {
  //   handleMuonClientError(exception);
  //   if (handleSessionError(exception)) {
  //     return true;
  //   }
  //   if (handleForceUpgrade(exception)) {
  //     return true;
  //   }
  //   return false;
  // }

  // void handleMuonClientError(BridgeError exception) {
  //   if (ifMuonClientError(exception)) {
  //     isConnectivityOK = false;
  //   }
  // }

  // bool handleAppCryptoError(BridgeError exception) {
  //   final message = parseAppCryptoError(exception);
  //   if (message != null) {
  //     emitState(AppCryptoFailed(message: message));
  //     return true;
  //   }
  //   return false;
  // }

  // bool handleSessionError(BridgeError exception) {
  //   final message = parseSessionExpireError(exception);
  //   if (message != null) {
  //     emitState(AppSessionFailed(message: message));
  //     return true;
  //   }
  //   return false;
  // }

  Future<UnlockModel> getUnlockType() async {
    final saved = await secureStore.get(unlockKey);
    if (saved.isEmpty) {
      return UnlockModel(type: UnlockType.none);
    }
    return UnlockModel.fromJsonString(saved);
  }

  Future<void> saveUnlockType(UnlockModel model) async {
    final save = model.toString();
    await secureStore.set(unlockKey, save);
  }

  Future<LockTimer> getLockTimer() async {
    final saved = await secureStore.get(lockTimerKey);
    LockTimer lockTimer = LockTimer.immediately;
    try {
      lockTimer = LockTimer.values.byName(saved);
    } catch (e) {
      /// can not find lock timer with given saved name
    }
    return lockTimer;
  }

  Future<void> saveLockTimer(LockTimer lockTimer) async {
    await secureStore.set(lockTimerKey, lockTimer.name);
  }

  Future<void> saveAppLastActivateTime() async {}

  /// Determines whether the app requires user unlocking based on the lock timer.
  ///
  /// Returns `true` if the gap time exceeds the lock timer range, indicating that
  /// the user must unlock the app.
  /// Returns `false` if the gap time is within the lock timer range, allowing
  /// the user to skip the unlock process.
  Future<bool> isLockTimerNeedUnlock() async {
    return false;
  }

  Future<UnlockErrorCount> getErrorCount() async {
    final saved = await secureStore.get(unlockErrorKey);
    if (saved.isEmpty) {
      return UnlockErrorCount(count: 0);
    }
    final count = UnlockErrorCount.fromJsonString(saved);
    return count;
  }

  Future<void> updateCount(UnlockErrorCount count) async {
    final save = count.toString();
    await secureStore.set(unlockErrorKey, save);
    if (count.count >= 5) {
      emitState(AppUnlockFailedState(message: "Unlock failed too many times"));
    }
  }

  void logoutFromLock() {
    emitState(AppUnlockForceLogoutState());
  }

  ///
  Future<int> getEligible() async {
    final count = await secureStore.get(userEligible);
    return count == "1" ? 1 : 0;
  }

  /// get backoff duration for concurrent situation when server from offline back to online
  int getExponentialBackoffForConcurrently() {
    if (exponentialBackoffForConcurrentlyMode) {
      return _getNextBackoffDuration(0, minSeconds: 5, maxSeconds: 10);
    }
    return 0;
  }

  Future<void> setEligible() async {
    await secureStore.set(userEligible, "1");
  }

  int _getNextBackoffDuration(
    int attempt, {
    int minSeconds = 30,
    int maxSeconds = 600,
  }) {
    // Calculate the exponential backoff duration
    final int exponentialBackoff = pow(2, attempt).toInt();

    // Generate a random value within the exponential backoff range
    final int randomBackoff = Random.secure().nextInt(exponentialBackoff + 1);

    // Ensure the random backoff is within the specified range
    final int duration = min(max(minSeconds, randomBackoff), maxSeconds);

    return duration;
  }

  void loadingFailed(LoadingTask task) {
    if (!failedTask.any((element) => element == task)) {
      failedTask.add(task);
    }
  }

  void loadingSuccess(LoadingTask task) {
    failedTask.remove(task);
  }

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() {
    throw UnimplementedError();
  }

  @override
  Future<void> login(String userID) async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> logout() async {
    isLocked = false;
    isAuthenticating = false;
  }

  @override
  Future<void> reload() async {}

  /// Check if upgrade is needed based on feature flag
  void checkForceUpgradeFeatureFlag() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      final isNeedForceUpgrade = dataProviderManager.unleashDataProvider
          .isNeedForceUpgrade();
      if (isNeedForceUpgrade) {
        if (state is AppForceUpgradeState) return;
        emitState(AppForceUpgradeState(message: kDefaultForceUpgradeMessage));
        haltBackgroundTasksForForceUpgrade();
      }
    } catch (e) {
      l.logger.e('Error checking force upgrade feature flag: $e');
    }
  }

  @override
  Priority getPriority() {
    return Priority.level2;
  }
}

//final backoff = ExponentialBackoff(base: 1000, randomInterval: 500);
// Attempt 0: wait for 1100 ms
// Attempt 1: wait for 2300 ms
// Attempt 2: wait for 3950 ms
// Attempt 3: wait for 6800 ms
// Attempt 4: wait for 15800 ms
// Attempt 5: wait for 30800 ms
// Attempt 6: wait for 61900 ms
// Attempt 7: wait for 124700 ms
// Attempt 8: wait for 248200 ms
// Attempt 9: wait for 496900 ms

// this is new one but havne't used yet need more tests
class ExponentialBackoff {
  final int base;
  final int randomInterval;
  final Random _random = Random.secure();

  ExponentialBackoff({required this.base, required this.randomInterval});

  Duration calculateWaitInterval(int n) {
    // Calculate the exponential backoff time
    final int exponentialBackoff = base * pow(2, n).toInt();

    // Generate a random jitter within the range [-randomInterval, randomInterval]
    final int jitter = _random.nextInt(2 * randomInterval + 1) - randomInterval;

    // Calculate the final wait interval
    int waitInterval = exponentialBackoff + jitter;

    // Ensure the wait interval is not negative
    if (waitInterval < 0) {
      waitInterval = 0;
    }

    return Duration(milliseconds: waitInterval);
  }
}
