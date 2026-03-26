import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/constants/proton.image.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/android_notification_service.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.migration.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/cache/documents.cache.service.dart';
import 'package:meet/managers/channels/platform.channel.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/meeting.event.loop.manager.dart';
import 'package:meet/managers/notification_service.dart';
import 'package:meet/managers/preferences/hive.preference.impl.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.memory.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:meet/views/scenes/app/app.coordinator.dart';
import 'package:meet/views/scenes/app/app.router.dart';
import 'package:meet/views/scenes/core/view.navigatior.identifiers.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:sentry/sentry.dart';

abstract class AppViewModel extends ViewModel<AppCoordinator> {
  ThemeProvider get themeProvider;

  ProtonColors get darkColorScheme;
  ProtonColors get lightColorScheme;

  ProtonImages get darkSvgImage;
  ProtonImages get lightSvgImage;

  AppRouter get router;

  AppViewModel(super.coordinator);
}

class AppViewModelImpl extends AppViewModel {
  @override
  late AppRouter router;

  ///
  @override
  final ThemeProvider themeProvider = ThemeProvider();

  @override
  ProtonColors get darkColorScheme => darkColorsExtension;
  @override
  ProtonColors get lightColorScheme => lightColorsExtension;
  @override
  ProtonImages get darkSvgImage => darkImageExtension;
  @override
  ProtonImages get lightSvgImage => lightImageExtension;

  ///
  final ManagerFactory serviceManager;

  AppViewModelImpl(super.coordinator, this.serviceManager) {
    router = AppRouter(serviceManager);
  }

  @override
  Future<void> loadData() async {
    await themeProvider.loadFromPreferences();

    /// read env
    final AppConfig config = appConfig;
    final apiEnv = config.apiEnv;
    try {
      final AppLinks appLinks = AppLinks();
      final storage = kIsWeb
          ? SecureStorageManager(storage: SecureStorageMemory())
          : SecureStorageManager(storage: SecureStorage());

      final permissionService = PermissionService();
      serviceManager.register(permissionService);

      /// Notification service (only Android implementation currently)
      if (android) {
        final notificationService =
            AndroidNotificationService() as NotificationService;
        await notificationService.init();
        serviceManager.register<NotificationService>(notificationService);
      }

      /// setup local services
      // LocalNotification.init();

      /// local auth manager
      // final localAuth = LocalAuthManager();
      // await localAuth.init();
      // serviceManager.register(localAuth);

      /// platform channel manager
      final platform = PlatformChannelManager(config.apiEnv);
      await platform.init();
      serviceManager.register(platform);

      final userAgent = UserAgent();

      /// notify native initalized
      platform.initalNativeApiEnv(
        apiEnv,
        await userAgent.appVersion,
        await userAgent.ua,
      );

      /// inital hive
      if (config.testMode) {
        await Hive.initFlutter(config.testMockStorage);
      } else {
        await Hive.initFlutter();
      }
      serviceManager.register(storage);

      /// preferences
      final hiveImpl = HivePreferenceImpl();
      await hiveImpl.init();
      final shared = PreferencesManager(hiveImpl);
      serviceManager.register(shared);

      /// documents cache service
      final documentsCacheService = DocumentsCacheService();
      await documentsCacheService.init();
      serviceManager.register(documentsCacheService);

      /// cache manager
      final appMigrationManager = AppMigrationManager(
        shared,
        storage,
        documentsCacheService,
      );
      await appMigrationManager.init();
      serviceManager.register(appMigrationManager);

      /// networking
      // final apiServiceManager = ProtonApiServiceManager(apiEnv, storage: storage);
      // await apiServiceManager.init();
      // serviceManager.register(apiServiceManager);

      /// app state manager
      final appStateManger = AppStateManager(storage, shared);
      await appStateManger.init();
      serviceManager.register(appStateManger);

      final appCoreManager = AppCoreManager(apiEnv, storage);
      await appCoreManager.init();
      serviceManager.register(appCoreManager);

      /// data provider manager
      final dataProviderManager = DataProviderManager(
        apiEnv,
        storage,
        shared,
        // apiServiceManager,
        // dbConnection,
        // userManager,
      );
      dataProviderManager.init();
      serviceManager.register(dataProviderManager);

      /// meeting event loop manager
      final meetingEventLoopManager = MeetingEventLoopManager(
        appCoreManager,
        appStateManger,
      );
      await meetingEventLoopManager.init();
      serviceManager.register(meetingEventLoopManager);

      await appLinks.getInitialLink();
      _showDashboardSafely(apiEnv);
    } catch (error, stackTrace) {
      logger.e(
        "App startup failed; routing to dashboard to avoid splash lock",
        error: error,
        stackTrace: stackTrace,
      );
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      _showDashboardSafely(apiEnv);
    }
  }

  void _showDashboardSafely(ApiEnv apiEnv) {
    try {
      coordinator.showDashboardPage(apiEnv);
    } catch (error, stackTrace) {
      logger.e(
        "Failed to navigate from splash",
        error: error,
        stackTrace: stackTrace,
      );
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
  }

  @override
  Future<void> move(NavID to) async {}
}
