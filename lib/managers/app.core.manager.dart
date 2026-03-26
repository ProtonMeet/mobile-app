import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/models/native.session.model.dart';
import 'package:meet/rust/proton_meet/core.dart';
import 'package:meet/rust/proton_meet/meet_auth_store.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/rust/proton_meet/storage/user_key_provider.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AppCoreManager implements Manager {
  late AppCore appCore;
  late ProtonMeetAuthStore authStore;
  late FrbUserKeyProvider userKeyProvider;
  final SecureStorageManager storage;

  String? userID;
  String? mailboxPassword;
  final ApiEnv env;
  final userAgent = UserAgent();

  final _mlsGroupKeyStreamController =
      StreamController<(String, BigInt)?>.broadcast();
  final _mlsSyncStateStreamController =
      StreamController<(MlsSyncState, RejoinReason?)>.broadcast();
  Stream<(String, BigInt)?> get mlsGroupKeyStream =>
      _mlsGroupKeyStreamController.stream;
  Stream<(MlsSyncState, RejoinReason?)> get mlsSyncStateStream =>
      _mlsSyncStateStreamController.stream;
  AppCoreManager(this.env, this.storage);

  bool get isAuthenticated => userID != null && mailboxPassword != null;

  @override
  Future<void> init() async {
    await loadSession();
    if (userID != null) {
      final String scopes = await storage.get("scopes");
      final String userId = await storage.get("userId");
      final String uid = await storage.get("sessionId");
      final String accessToken = await storage.get("accessToken");
      final String refreshToken = await storage.get("refreshToken");
      if (kDebugMode) {
        logger.i("sessionId = '$uid';");
      }
      authStore = ProtonMeetAuthStore.fromSession(
        env: env.toString(),
        userId: userId,
        uid: uid,
        access: accessToken,
        refresh: refreshToken,
        scopes: scopes.split(","),
      );
    } else {
      authStore = ProtonMeetAuthStore(env: env.toString());
    }

    userKeyProvider = FrbUserKeyProvider();

    /// Callback from Rust to save auth session
    await authStore.setAuthDartCallback(callback: sessionStoreCallback);
    appCore = await AppCore.newInstance(
      env: env.toString(),
      appVersion: await userAgent.appVersion,
      userAgent: await userAgent.ua,
      dbPath: await getDatabaseFolderPath(),
      authStore: authStore,
      wsHost: env.wsHost,
      httpHost: env.httpHost,
      userKeyProvider: userKeyProvider,
    );
    await appCore.setMlsGroupUpdateCallback(callback: mlsGroupUpdateCallback);
    await appCore.setMlsSyncStateUpdateCallback(
      callback: mlsSyncStateUpdateCallback,
    );
    // appCore.subscribeEvents().listen((event) {
    //   logger.i("App event: $event");
    // });
    await userKeyProvider.setGetPassphraseCallback(
      callback: userKeyProviderCallback,
    );
  }

  Future<String> sessionStoreCallback(ChildAuthSession session) async {
    if (kDebugMode) {
      logger.i(
        "Received Auth Session from Rust -> sessionId: ${session.sessionId}",
      );
    }
    await saveSession(session);
    return Future.value("Reply from Dart");
  }

  Future<String> userKeyProviderCallback(String passphrase) async {
    return Future.value(mailboxPassword ?? "");
  }

  Future<void> mlsGroupUpdateCallback(String roomId) async {
    try {
      final result = await appCore.getGroupKey();
      _mlsGroupKeyStreamController.add(result);
      if (kDebugMode) {
        logger.i(
          "MLS group updated for roomId: $roomId, key: ${result.$1}, epoch: ${result.$2}",
        );
      }
    } catch (e, stackTrace) {
      // Handle errors gracefully to avoid panicking Rust side
      // This can happen when MLS client is not yet initialized or group is not found
      logger.e(
        "Failed to get group key for roomId: $roomId",
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> mlsSyncStateUpdateCallback(
    MlsSyncState state,
    RejoinReason? reason,
  ) async {
    _mlsSyncStateStreamController.add((state, reason));
  }

  Future<void> initAfterLoginSession() async {
    final String scopes = await storage.get("scopes");
    final String userId = await storage.get("userId");
    final String uid = await storage.get("sessionId");
    final String accessToken = await storage.get("accessToken");
    final String refreshToken = await storage.get("refreshToken");
    mailboxPassword = await storage.get("userPassphrase");
    if (kDebugMode) {
      logger.i("sessionId = '$uid';");
    }
    authStore = ProtonMeetAuthStore.fromSession(
      env: env.toString(),
      userId: userId,
      uid: uid,
      access: accessToken,
      refresh: refreshToken,
      scopes: scopes.split(","),
    );
    await authStore.setAuthDartCallback(callback: sessionStoreCallback);
    userKeyProvider = FrbUserKeyProvider();
    await userKeyProvider.setGetPassphraseCallback(
      callback: userKeyProviderCallback,
    );
    appCore = await AppCore.newInstance(
      env: env.apiPath,
      appVersion: await userAgent.appVersion,
      userAgent: await userAgent.ua,
      dbPath: await getDatabaseFolderPath(),
      authStore: authStore,
      wsHost: env.wsHost,
      httpHost: env.httpHost,
      userKeyProvider: userKeyProvider,
    );
    await appCore.setMlsGroupUpdateCallback(callback: mlsGroupUpdateCallback);
    await appCore.setMlsSyncStateUpdateCallback(
      callback: mlsSyncStateUpdateCallback,
    );
  }

  Future<void> loadSession() async {
    final sessionId = await storage.get("sessionId");
    final accessToken = await storage.get("accessToken");
    final refreshToken = await storage.get("refreshToken");
    final scopesStr = await storage.get("scopes");
    final userId = await storage.get("userId");
    mailboxPassword = await storage.get("userPassphrase");

    if (sessionId.isNotEmpty &&
        accessToken.isNotEmpty &&
        refreshToken.isNotEmpty &&
        scopesStr.isNotEmpty &&
        userId.isNotEmpty) {
      userID = userId;
    } else {
      await storage.deleteAll();
    }
  }

  Future<void> saveSession(ChildAuthSession session) async {
    await storage.set("sessionId", session.sessionId);
    await storage.set("accessToken", session.accessToken);
    await storage.set("refreshToken", session.refreshToken);
    await storage.set("scopes", session.scopes.join(","));
    await storage.set("userId", session.userId);
  }

  Future<void> trySaveUserInfo(UserInfo user) async {
    await storage.set("userId", user.userId);
    await storage.set("userMail", user.userMail);
    await storage.set("userName", user.userName);
    await storage.set("userDisplayName", user.userDisplayName);
    await storage.set("sessionId", user.sessionId);
    await storage.set("accessToken", user.accessToken);
    await storage.set("refreshToken", user.refreshToken);
    await storage.set("scopes", user.scopes);
    await storage.set("userKeyID", user.userKeyID);
    await storage.set("userPrivateKey", user.userPrivateKey);
    await storage.set("userPassphrase", user.userPassphrase);
  }

  @override
  Future<void> login(String userID) async {
    this.userID = userID;

    await initAfterLoginSession();
  }

  @override
  Future<void> dispose() async {
    // Close the stream controller when disposing the manager
    await _mlsGroupKeyStreamController.close();
    await _mlsSyncStateStreamController.close();
  }

  @override
  Priority getPriority() {
    return Priority.level2;
  }

  @override
  Future<void> logout() async {
    try {
      await appCore.logout(userId: userID!);
    } catch (e) {
      logger.e("Error logging out: $e");
    }
    await storage.deleteAll();
    userID = null;
    mailboxPassword = null;

    await initAfterLoginSession();
  }

  @override
  Future<void> reload() {
    throw UnimplementedError();
  }

  Future<Directory> _getDatabaseFolder() async {
    const dbFolder = "databases";
    final appDocumentsDir = await getApplicationDocumentsDirectory();
    final folderPath = Directory(path.join(appDocumentsDir.path, dbFolder));

    if (!folderPath.existsSync()) {
      await folderPath.create(recursive: true);
    }
    return folderPath;
  }

  Future<String> getDatabaseFolderPath() async {
    final folder = await _getDatabaseFolder();
    return folder.path;
  }
}
