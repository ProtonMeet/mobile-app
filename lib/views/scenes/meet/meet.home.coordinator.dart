import 'package:flutter/material.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/channels/native.view.channel.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/lock.core/lock.overlay.coordinator.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';

import 'meet.home.view.dart';
import 'meet.home.viewmodel.dart';

class MeetHomeCoordinator extends Coordinator {
  late ViewBase widget;
  final NativeViewChannel nativeViewChannel;
  final String token;
  final String displayName;
  final bool isVideoEnabled;
  final bool isAudioEnabled;
  final bool isE2EEEnabled;

  MeetHomeCoordinator({
    required this.nativeViewChannel,
    required this.token,
    required this.displayName,
    required this.isVideoEnabled,
    required this.isAudioEnabled,
    required this.isE2EEEnabled,
  }) {
    Coordinator.nestedNavigatorKey ??= GlobalKey<NavigatorState>(
      debugLabel: "HomeNestedNavigatorKey",
    );
  }

  @override
  void end() {
    Coordinator.nestedNavigatorKey = null;
  }

  void logout() {
    serviceManager.logout();
  }

  @override
  ViewBase<ViewModel> start() {
    final args = JoinArgs(
      meetingLink: FrbUpcomingMeeting.defaultValues(),
      e2eeKey: "e2eekey",
      isAudioEnabled: isAudioEnabled,
      isVideoEnabled: isVideoEnabled,
      e2ee: isE2EEEnabled,
    );
    final viewModel = MeetHomeViewModelImpl(
      this,
      args,
      serviceManager.get<AppCoreManager>(),
      token,
      displayName,
      serviceManager.get<PermissionService>(),
    );

    final overlayView = LockCoordinator().start();
    widget = MeetHomeView(viewModel, locker: overlayView);
    return widget;
  }
}
