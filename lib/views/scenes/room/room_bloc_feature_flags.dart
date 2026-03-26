import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';

import 'room_event.dart';
import 'room_state.dart';

mixin RoomFeatureFlagsHandlers on Bloc<RoomBlocEvent, RoomState> {
  /// Check if Picture-in-Picture feature is enabled via feature flag
  bool isPictureInPictureFeatureEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider.isMeetPictureInPicture();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (hide feature)
      l.logger.w('[RoomBloc] Error checking PIP feature flag: $e');
      return false;
    }
  }

  /// Check if Screen Share feature is enabled via feature flag
  bool isScreenShareFeatureEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider.isMeetScreenShare();
    } catch (e) {
      // If there's an error accessing the feature flag, default to true (enable feature) for iOS, and false for Android
      l.logger.w('[RoomBloc] Error checking Screen Share feature flag: $e');
      if (android) {
        return false;
      } else {
        return true;
      }
    }
  }

  /// Check if Mobile Speaker Toggle feature is enabled via feature flag
  bool isMeetMobileSpeakerToggleEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider
          .isMeetMobileSpeakerToggle();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (hide feature)
      l.logger.w(
        '[RoomBloc] Error checking Mobile Speaker Toggle feature flag: $e',
      );
      return false;
    }
  }

  /// Check if Auto Reconnection feature is enabled via feature flag
  bool isMeetAutoReconnectionEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider.isMeetAutoReconnection();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (disable feature)
      l.logger.w(
        '[RoomBloc] Error checking Auto Reconnection feature flag: $e',
      );
      return false;
    }
  }

  /// Check if Mobile Show Start Meeting Button feature is enabled via feature flag
  bool isMeetMobileShowStartMeetingButtonEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider.isMeetMobileShowStartMeetingButton();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (hide feature)
      l.logger.w(
        '[RoomBloc] Error checking Mobile Show Start Meeting Button feature flag: $e',
      );
      return false;
    }
  }

  /// Check if Mobile Enable Network Tool feature is enabled via feature flag
  bool isMeetMobileEnableNetworkToolEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider
          .isMeetMobileEnableNetworkTool();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (hide feature)
      l.logger.w(
        '[RoomBloc] Error checking Mobile Enable Network Tool feature flag: $e',
      );
      return false;
    }
  }

  /// Check if Emoji Reaction feature is enabled via feature flag
  bool isMeetMobileEnableEmojiReactionEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider
          .isMeetMobileEnableEmojiReaction();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (hide feature)
      l.logger.w(
        '[RoomBloc] Error checking Mobile Enable Emoji Reaction feature flag: $e',
      );
      return false;
    }
  }
}
