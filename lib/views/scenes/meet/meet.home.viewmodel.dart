import 'package:flutter/foundation.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/views/scenes/core/view.navigatior.identifiers.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';

import 'meet.home.coordinator.dart';

abstract class MeetHomeViewModel extends ViewModel<MeetHomeCoordinator> {
  MeetHomeViewModel(super.coordinator, this.args, this.appCoreManager);

  String get token;

  String get displayName;

  JoinArgs args;

  void logout();

  Future<void> requestPermissions();

  AppCoreManager appCoreManager;
}

class MeetHomeViewModelImpl extends MeetHomeViewModel {
  final String _token;
  final String _displayName;
  final PermissionService _permissionService;

  MeetHomeViewModelImpl(
    super.coordinator,
    super.args,
    super.appCoreManager,
    this._token,
    this._displayName,
    this._permissionService,
  );

  @override
  String get token => _token;

  @override
  String get displayName => _displayName;

  @override
  Future<void> loadData() async {}

  @override
  Future<void> move(NavID to) async {}

  @override
  void logout() {
    coordinator.logout();
  }

  @override
  Future<void> requestPermissions() async {
    if (kIsWeb) {
      return;
    }
    final cameraPermission = await _permissionService.hasCameraPermission();
    final microphonePermission = await _permissionService
        .hasMicrophonePermission();
    logger.i('cameraPermission: $cameraPermission');
    logger.i('microphonePermission: $microphonePermission');
    if (!cameraPermission) {
      await _permissionService.requestCameraPermission();
    }
    if (!microphonePermission) {
      await _permissionService.requestMicrophonePermission();
    }
  }
}
