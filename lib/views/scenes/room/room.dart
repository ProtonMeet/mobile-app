import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/constants/test_ids.dart';
import 'package:meet/helper/background_blur/camera_background_effect_service.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/global_notification.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/mobile_upgrade_warning_notification.dart';
import 'package:meet/helper/old_android_sdk_warning.dart';
import 'package:meet/helper/old_ios_sdk_warning.dart';
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/android_notification_service.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/channels/call_activity_action_channel.dart';
import 'package:meet/managers/channels/physical_key_channel.dart';
import 'package:meet/managers/channels/platform.channel.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/notification_service.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/room.manager.dart' show RoomManager;
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:meet/managers/services/in_app_review_service.dart';
import 'package:meet/managers/user_activity.manager.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/platform/html.window.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/chat_event.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_plain_text.dart';
import 'package:meet/views/components/alerts/media_permission_dialog.dart';
import 'package:meet/views/components/alerts/meeting_will_end_dialog.dart';
import 'package:meet/views/components/alerts/session_expired_dialog.dart';
import 'package:meet/views/components/bottom.sheets/leave_room_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/virtual_background_sheet.dart';
import 'package:meet/views/components/custom.tooltip.dart';
import 'package:meet/views/components/loading_view.dart';
import 'package:meet/views/components/test_id.dart';
import 'package:meet/views/scenes/app/app.router.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';
import 'package:meet/views/scenes/exts.dart';
import 'package:meet/views/scenes/feedbacks/left_meeting_feedback_sheet.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_bloc.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_event.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_incoming_notification.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_state.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_transport.dart';
import 'package:meet/views/scenes/room/chat/chat_bubble.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';
import 'package:meet/views/scenes/room/chat/mention_message_content.dart';
import 'package:meet/views/scenes/room/reaction_stream/reaction_stream.dart';
import 'package:meet/views/scenes/room/controls_bar/controls_bar_responsive.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/layout/fixed_sizing_camera_layout.dart';
import 'package:meet/views/scenes/room/layout/responsive_camera_layout.dart';
import 'package:meet/views/scenes/room/live_captions/live_caption_language_setting_row.dart';
import 'package:meet/views/scenes/room/live_captions/live_captions_modal.dart';
import 'package:meet/views/scenes/room/live_captions/live_captions_sheet.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/participant_list/participant_list.dart';
import 'package:meet/views/scenes/room/room_is_ready_dialog.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_bloc.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_event.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_transport.dart';
import 'package:meet/views/scenes/room/settings/in_room_settings_bindings_sync.dart';
import 'package:meet/views/scenes/room/settings/in_room_settings_panel.dart';
import 'package:meet/views/scenes/room/widgets/floating.action.button.location.dart';
import 'package:meet/views/scenes/room/widgets/meet_screen_select_dialog.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_event.dart';
import 'package:meet/views/scenes/signin/auth_state.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:meet/views/scenes/widgets/statistics_dialog.dart';
import 'package:proton_denoise/proton_denoise.dart';
import 'package:proton_video_effects/proton_video_effects.dart';
import 'package:sentry/sentry.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'camera_layout.dart';
import 'controls_bar/controls_action.dart';
import 'envelope_sender.dart';
import 'info/meeting_info_panel.dart';
import 'message_topic.dart';
import 'pip_view.dart';
import 'recording/meeting_recorder.dart';
import 'recording/recording_controls.dart';
import 'recording/recording_status_handler.dart';
import 'recording/recording_top_banner.dart';
import 'room_bloc.dart';
import 'room_event.dart';
import 'room_reconnection_listeners.dart';
import 'room_state.dart';
import 'room_top_bar.dart';
import 'side_panel_widget.dart';
import 'speaker_phone/speaker_phone_panel.dart';
import 'widgets/room_connection_aware_media_area.dart';

const _waitingRoomJoinRequestNotificationTag = 'waiting_room_join_request';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final String roomKey;
  final String displayName;
  final String roomId;
  final FrbMeetInfo meetInfo;
  final FrbUpcomingMeeting meetLink;
  final PreJoinType preJoinType;
  final AuthBloc? authBloc;

  /// User preference for camera background effects carried over from prejoin.
  final bool cameraBackgroundBlurEnabled;
  final CameraBackgroundSelection cameraBackgroundSelection;

  /// Meeting limits resolved during pre-join; skips getMeetingInfo in room.
  final FrbMeetingInfo? prefetchedMeetingInfo;

  /// Host hint from pre-join; speeds up host UI before meet-api loads.
  final bool isMeetingHost;

  const RoomPage(
    this.room,
    this.listener,
    this.roomKey,
    this.displayName,
    this.roomId,
    this.meetInfo,
    this.meetLink,
    this.preJoinType, {
    this.authBloc,
    this.cameraBackgroundBlurEnabled = false,
    this.cameraBackgroundSelection = const CameraBackgroundSelection.none(),
    this.prefetchedMeetingInfo,
    this.isMeetingHost = false,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

const double bottomControlHeight = 86;

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  late final RoomBloc _bloc;

  EventsListener<RoomEvent>? _currentListener;
  StreamSubscription? _deviceChangeSub;
  StreamSubscription<DataState>? _appStateSubscription;

  RoomSidePanel? _openSidePanel;

  bool _isSidePanelOpen(RoomSidePanel panel) => _openSidePanel == panel;

  /// Tells chat whether its panel is visible, which drives seen/unread state
  /// and whether an incoming message raises a toast.
  void _syncChatOpenWithSidePanel() {
    _chatBloc.add(
      ChatPanelVisibilityChanged(isOpen: _isSidePanelOpen(RoomSidePanel.chat)),
    );
  }

  void _closeSidePanel() {
    if (_openSidePanel == null) return;
    setState(() {
      _openSidePanel = null;
    });
    _syncChatOpenWithSidePanel();
  }

  /// Opens [panel], or closes it when already open. Only one panel at a time.
  void _toggleSidePanel(RoomSidePanel panel) {
    final closing = _openSidePanel == panel;
    final switching = _openSidePanel != null && !closing;
    if (switching) {
      dismissRoomPanelBottomSheetIfPresent();
    }
    setState(() {
      if (closing) {
        _openSidePanel = null;
      } else {
        _openSidePanel = panel;
      }
    });
    _syncChatOpenWithSidePanel();
  }

  void _openChatSidePanel() {
    if (_openSidePanel == RoomSidePanel.chat) return;
    LocalToast.dismissActiveToastification();
    if (_openSidePanel != null) {
      dismissRoomPanelBottomSheetIfPresent();
    }
    setState(() {
      _openSidePanel = RoomSidePanel.chat;
    });
    _syncChatOpenWithSidePanel();
  }

  /// Enter mobile fullscreen and close any open side panel so chat unread state
  /// is not cleared while the panel is hidden.
  void _enterMobileFullScreen() {
    if (_openSidePanel != null) {
      dismissRoomPanelBottomSheetIfPresent();
      setState(() {
        _openSidePanel = null;
      });
      _syncChatOpenWithSidePanel();
    }
    _bloc.add(ToggleFullScreen());
  }

  bool _isLandscape = false;
  bool _isScreenSharing = false;
  bool _hideSelfCamera = false;
  bool _unsubscribeVideoByDefault = false;
  final CameraLayout _layout = CameraLayout.grid;
  final bool _showRotationButton = false;

  int _screenSharingIndex = 0;
  bool _isCameraView = false;
  bool _cameraWasEnabledBeforePause = false;
  VideoMaxBitrate _cameraMaxBitrate = defaultCameraMaxBitrate;
  VideoResolution _cameraResolution = defaultCameraResolution;
  final appCoreManager = ManagerFactory().get<AppCoreManager>();
  UserConfig? userConfig;

  List<MediaDevice> _videoInputs = [];
  bool _isLeavingByUser = false;
  bool _isHandlingSessionExpired = false;

  /// LiveKit transport reconnects during this meeting (for store-review quality).
  bool _hadLiveKitTransportIssuesThisMeeting = false;
  final Map<String, ParticipantReaction> _activeReactions = {};

  /// Owns the chat transcript for the whole call. Created here because chat
  /// must accumulate messages from join onward, not from the first time the
  /// panel is opened.
  late final ChatBloc _chatBloc;
  late final InRoomSettingsBloc _inRoomSettingsBloc;

  StreamSubscription<ChatIncomingNotification>? _chatToastSub;

  /// Latest chat message awaiting a toast this frame, if any.
  ChatIncomingNotification? _pendingChatToast;
  bool _chatToastScheduled = false;

  /// Read-only view of the transcript for widgets that still render off the
  /// controller directly.
  ChatController get _chatController => _chatBloc.controller;

  bool get _newChatEnabled => ManagerFactory()
      .get<DataProviderManager>()
      .unleashDataProvider
      .isMeetNewChatHandling();

  bool get _chatThreadsEnabled => ManagerFactory()
      .get<DataProviderManager>()
      .unleashDataProvider
      .isMeetChatThreads();

  bool get _chatMentionsEnabled => ManagerFactory()
      .get<DataProviderManager>()
      .unleashDataProvider
      .isMeetChatMentions();

  /// Recording-status envelopes received before [RoomState.isRoomInitialized]
  /// flipped true. We can't validate them yet because the participant map (and
  /// therefore admin/host lookup) isn't loaded. Drained by
  /// [_processPendingRecordingStatus] once the room is ready.
  final List<
    ({
      Map<String, dynamic> envelope,
      String? decryptedPlaintext,
      String? mlsSenderId,
      String? liveKitSenderIdentity,
    })
  >
  _pendingRecordingStatuses = [];
  Timer? _pendingRecordingStatusTimer;

  late final MeetingRecorder? _meetingRecorder;

  final JustTheController _stopSharingTooltipController = JustTheController();

  static const EdgeInsets _screenSharePanelPadding = EdgeInsets.all(4);

  /// Mirror of `state.isLocalScreenSharing` for tooltip show/hide edges.
  bool _wasLocalScreenSharing = false;

  bool _mobileUpgradeWarningShown = false;

  @override
  void initState() {
    super.initState();
    _hadLiveKitTransportIssuesThisMeeting = false;
    WidgetsBinding.instance.addObserver(this);
    // Avoid showing "unknown route" UI while in an active meeting.
    Coordinator.suppressUnknownRouteUi = true;

    _bloc = RoomBloc(widget.room, widget.listener, widget.meetInfo)
      ..add(
        RoomInitialized(
          room: widget.room,
          listener: widget.listener,
          roomKey: widget.roomKey,
          meetLinkName: widget.meetInfo.meetLinkName,
          displayName: widget.displayName,
          preJoinType: widget.preJoinType,
          meetingLink: widget.meetLink,
          cameraBackgroundBlurEnabled: widget.cameraBackgroundBlurEnabled,
          cameraBackgroundSelection: widget.cameraBackgroundSelection,
          prefetchedMeetingInfo: widget.prefetchedMeetingInfo,
          isPaidUser: widget.authBloc?.state.isPaidUser ?? false,
          isMeetingHost:
              widget.isMeetingHost || widget.preJoinType == PreJoinType.create,
        ),
      );

    _chatBloc = ChatBloc(
      transport: AppCoreChatTransport(
        appCore: () => appCoreManager.appCore,
        room: () => _bloc.state.room,
      ),
      isThreadedChatEnabled: () => _newChatEnabled,
      isChatMentionsEnabled: () => _chatMentionsEnabled,
      participantCount: () {
        final roomState = _bloc.state;
        // Either source can be ahead of the other while the roster settles.
        return roomState.participantTracks.length > roomState.participantsCount
            ? roomState.participantTracks.length
            : roomState.participantsCount;
      },
    );
    _chatToastSub = _chatBloc.incomingMessageToasts.listen(
      _showIncomingChatToast,
    );

    _inRoomSettingsBloc =
        InRoomSettingsBloc(
          dataProviderManager: ManagerFactory().get<DataProviderManager>(),
          transport: _RoomHostSettingsTransport(this),
        )..add(
          InRoomSettingsInitialized(
            lockMeeting: widget.meetInfo.isLocked,
            waitingRoomEnabled: widget.meetInfo.hasWaitingRoom,
          ),
        );

    if (widget.isMeetingHost || widget.preJoinType == PreJoinType.create) {
      _inRoomSettingsBloc.add(InRoomHostStatusUpdated(isHost: true));
    }

    if (_bloc.isMeetMeetingRecordingNativeEnabled()) {
      _meetingRecorder = MeetingRecorder(
        room: widget.room,
        bloc: _bloc,
        publishRecordingStatus: _publishRecordingStatus,
        onError: (message) {
          if (mounted) {
            LocalToast.showToastification(
              context,
              context.local.error,
              message,
            );
          }
        },
        onRecoverableRecordings: (sessions) {
          if (!mounted || sessions.isEmpty) return;
          LocalToast.showToastification(
            context,
            context.local.recording_in_progress,
            context.local.recording_recovered_message,
          );
        },
        onRecordingInterrupted: () {
          if (!mounted) return;
          LocalToast.showToastification(
            context,
            context.local.recording_in_progress,
            context.local.recording_interrupted_background,
          );
        },
      );
      unawaited(_meetingRecorder!.init());
    } else {
      _meetingRecorder = null;
    }

    // Initialize call activity action channel for Dynamic Island actions
    //TODO(fix): move to room_bloc.dart
    final localParticipant = widget.room.localParticipant;
    if (localParticipant != null) {
      CallActivityActionChannel.initialize(widget.room, localParticipant);
    }

    /// avoid screen off
    enableWakelock();

    /// load user settings from shared preference
    loadUserConfig();

    // add callbacks for finer grained events
    //TODO(deprecate): remove it after migration to room_bloc.dart
    // Initialize listener from widget (initial setup)
    _currentListener = widget.listener;
    setUpListeners(_currentListener!);

    //TODO(fix): move to room_bloc.dart
    // PiP: Android + iOS (was Android-only, so iOS never got InitializePip / pipAvailable).
    if (android || iOS) {
      if (_bloc.isPictureInPictureFeatureEnabled()) {
        _bloc.add(InitializePip(roomName: widget.meetInfo.meetName));
      }

      // Show the persistent in-meeting notification immediately on entering
      // the meeting (rather than waiting for AppLifecycleState.inactive
      // which might have random crashes if the lifecycle state changes before the notification is shown).
      unawaited(_showMeetingNotification());
    }

    // Load video devices for swap camera functionality
    //TODO(fix): move to room_bloc.dart
    reloadVideoDevices();
    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((_) {
      if (mounted) {
        reloadVideoDevices();
      }
    });

    if (desktop) {
      onWindowShouldClose = () async {
        unawaited(_bloc.state.room.disconnect());
        final listener = _currentListener ?? _bloc.state.listener;
        await listener.waitFor<RoomDisconnectedEvent>(
          duration: const Duration(seconds: 5),
        );
      };
    }
    if (kIsWeb) {
      preventGoPrevPage();
    }

    final appStateManager = ManagerFactory().get<AppStateManager>();
    _appStateSubscription = appStateManager.stream.listen((state) {
      if (state is AppSessionFailed) {
        unawaited(_handleSessionExpiredDuringCall());
      }
    });

    // Set up home key listener for Android PIP
    //TODO(fix): move to room_bloc.dart
    if (android && _bloc.isPictureInPictureFeatureEnabled()) {
      PhysicalKeyChannel.initialize(
        onHomeKeyPressedCallback: _handleHomeKeyPressed,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    if (_isLandscape != (mediaQuery.orientation == Orientation.landscape)) {
      setState(() {
        _isLandscape = mediaQuery.orientation == Orientation.landscape;
      });
    }
  }

  //TODO(fix): move to room_bloc.dart
  Future<void> _handleHomeKeyPressed() async {
    // User pressed home key - enter PIP mode and show notification
    if (!_bloc.state.isPipMode && _bloc.state.pipInitialized) {
      _bloc.add(EnterPipMode());
    }
  }

  /// Reset auto fullscreen timer when user interacts (touch/focus)
  void _resetAutoFullScreenTimer() {
    _bloc.add(ResetAutoFullScreenTimer());
  }

  /// P1: Deprecated OS version (Android SDK / iOS).
  /// P2: Outdated app version ([MeetMobileUpgradeWarning]).
  Future<void> _maybeShowInRoomMobileWarning(BuildContext context) async {
    if (_mobileUpgradeWarningShown) return;

    if (_bloc.isOldAndroidSdkWarningEnabled() && android) {
      final showOldAndroidWarning = await isDeprecatedAndroidSdk();
      if (!mounted || !context.mounted) return;
      if (showOldAndroidWarning) {
        _mobileUpgradeWarningShown = true;
        showOldAndroidSdkWarningNotification(context);
        return;
      }
    }

    if (_bloc.isOldIosSdkWarningEnabled() && iOS) {
      final showOldIosWarning = await isDeprecatedIosVersion();
      if (!mounted || !context.mounted) return;
      if (showOldIosWarning) {
        _mobileUpgradeWarningShown = true;
        showOldIosSdkWarningNotification(context);
        return;
      }
    }

    if (!_bloc.isMeetMobileUpgradeWarningEnabled()) return;
    if (!mounted || !context.mounted) return;
    _mobileUpgradeWarningShown = true;
    showMobileUpgradeWarningNotification(context);
  }

  @override
  void dispose() {
    _activeReactions.clear();
    unawaited(_chatToastSub?.cancel());
    unawaited(_chatBloc.close());
    unawaited(_inRoomSettingsBloc.close());

    WidgetsBinding.instance.removeObserver(this);
    // Restore normal unknown-route behavior after leaving the meeting.
    Coordinator.suppressUnknownRouteUi = false;

    _deviceChangeSub?.cancel();
    _deviceChangeSub = null;
    _appStateSubscription?.cancel();
    _appStateSubscription = null;

    _pendingRecordingStatusTimer?.cancel();
    _pendingRecordingStatusTimer = null;
    _pendingRecordingStatuses.clear();

    unawaited(_meetingRecorder?.dispose());

    // Dispose call activity action channel
    //TODO(fix): move to room_bloc.dart
    CallActivityActionChannel.dispose();

    // Dispose home key channel
    //TODO(fix): move to room_bloc.dart
    if (android) {
      PhysicalKeyChannel.dispose();
      try {
        final notificationService = ManagerFactory().get<NotificationService>();
        notificationService.hideBackgroundNotification();
        notificationService.clearBackgroundNotificationTapCallback();
      } catch (e) {
        // NotificationService might not be registered on non-Android platforms
      }
    }
    // Drop the decoded background image the native engine is holding so the
    // user's photo does not stay resident after the meeting. Track creation
    // re-supplies it via `prepareCameraBackgroundSelectionForTrackCreation`,
    // so a later prejoin or rejoin still gets its background.
    unawaited(_clearNativeReplacementBackground());

    // PIP cleanup is handled by bloc
    GlobalNotification.dismiss(tag: _waitingRoomJoinRequestNotificationTag);
    _bloc.close();
    disableWakelock();
    onWindowShouldClose = null;
    super.dispose();
  }

  Future<void> _handleSessionExpiredDuringCall() async {
    if (!mounted || _isHandlingSessionExpired || _isLeavingByUser) {
      return;
    }
    _isHandlingSessionExpired = true;
    try {
      // Leave room immediately and skip in-room "left meeting" feedback UI.
      await _leaveRoom(isShowLeftMeetingBottomSheet: false);

      // Show session sheet after room navigation completed (popUntil in _leaveRoom).
      // To-do: check if we really need addPostFrameCallback here
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rootContext =
            Coordinator.rootNavigatorKey.currentState?.overlay?.context ??
            Coordinator.rootNavigatorKey.currentContext;
        if (rootContext == null || !rootContext.mounted) return;
        unawaited(
          showSessionErrorDialog(
            rootContext,
            onSignIn: () async {
              widget.authBloc?.add(LoginWithNative());
            },
            onContinueWithoutSignIn: () async {},
          ),
        );
      });
    } finally {
      _isHandlingSessionExpired = false;
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    // Only handle PIP if feature flag is enabled
    if (android) {
      if (state == AppLifecycleState.detached) {
        await _hideNotification('app detached');
        // App is being terminated, exit PIP
        if (_bloc.isPictureInPictureFeatureEnabled()) {
          _bloc.add(ExitPipMode());
        }
      } else if (state == AppLifecycleState.inactive) {
        // Intentionally NO notification show/hide here.
        // Because triggering it from `inactive` races
        // against Android 13/14 runtime permission re-evaluation during
        // transitions
      } else if (state == AppLifecycleState.resumed) {
        if (_bloc.isPictureInPictureFeatureEnabled()) {
          // Exit PIP when app comes to foreground
          if (_bloc.state.isPipMode) {
            _bloc.add(ExitPipMode());
          }
        }

        // To-do: check if we really need addPostFrameCallback here
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            if (android && _cameraWasEnabledBeforePause) {
              try {
                // Check camera permission before accessing camera
                final permissionService = PermissionService();
                final hasPermission = await permissionService
                    .hasCameraPermission();
                if (hasPermission) {
                  final participant = _bloc.state.room.localParticipant;
                  if (participant != null) {
                    final isCameraEnabled = participant.isCameraEnabled();
                    if (!isCameraEnabled) {
                      await participant.setCameraEnabled(
                        _cameraWasEnabledBeforePause,
                      );
                    }
                  }
                } else {
                  l.logger.w(
                    '[RoomPage] Camera permission not granted, skipping camera re-enable',
                  );
                  _cameraWasEnabledBeforePause = false;
                }
              } catch (e) {
                l.logger.e(
                  '[RoomPage] Error re-enabling camera after resume: $e',
                );
                _cameraWasEnabledBeforePause = false;
              }
            }
            _ensureVideoTrackStartedAfterResume();
          }
        });
      } else if (state == AppLifecycleState.paused) {
        if (android && !_bloc.state.isPipMode) {
          // Screen is being turned off or app going to background
          // Save current camera state and disable camera automatically to prevent some android model didn't disable camera automatically when screen off
          try {
            // Check camera permission before accessing camera
            final permissionService = PermissionService();
            final hasPermission = await permissionService.hasCameraPermission();
            if (hasPermission) {
              final participant = _bloc.state.room.localParticipant;
              if (participant != null) {
                try {
                  _cameraWasEnabledBeforePause = participant.isCameraEnabled();
                  if (_cameraWasEnabledBeforePause) {
                    l.logger.i(
                      '[RoomPage] Disabling camera due to screen off/pause',
                    );
                    await participant.setCameraEnabled(false);
                  }
                } catch (e) {
                  l.logger.e(
                    '[RoomPage] Error accessing camera state during pause: $e',
                  );
                  _cameraWasEnabledBeforePause = false;
                }
              }
            } else {
              l.logger.d(
                '[RoomPage] Camera permission not granted, skipping camera disable',
              );
              _cameraWasEnabledBeforePause = false;
            }
          } catch (e) {
            l.logger.e(
              '[RoomPage] Error checking camera permission during pause: $e',
            );
            _cameraWasEnabledBeforePause = false;
          }
        }
      }
    }

    // iOS: start PiP while still active (inactive), before the process is suspended.
    if (iOS &&
        state == AppLifecycleState.inactive &&
        _bloc.isPictureInPictureFeatureEnabled() &&
        _bloc.state.pipInitialized &&
        _bloc.state.pipAvailable == true &&
        !_bloc.state.isPipMode) {
      _bloc.add(EnterPipMode());
    }

    if (iOS &&
        state == AppLifecycleState.resumed &&
        _bloc.isPictureInPictureFeatureEnabled() &&
        _bloc.state.isPipMode) {
      _bloc.add(ExitPipMode());
    }

    if ((iOS || android) &&
        state == AppLifecycleState.resumed &&
        _meetingRecorder != null) {
      unawaited(_meetingRecorder.syncNativeRecordingState());
    }
  }

  Future<void> enableWakelock() async {
    if (linux) return;
    final wakelockEnabled = await WakelockPlus.enabled;
    if (!wakelockEnabled) {
      await WakelockPlus.enable();
    }
  }

  Future<void> disableWakelock() async {
    final wakelockEnabled = await WakelockPlus.enabled;
    if (wakelockEnabled) {
      await WakelockPlus.disable();
    }
  }

  /// Wire the system call notification hang-up action to the same leave path
  /// as the in-app Leave meeting button.
  void _registerNotificationEndCallCallback() {
    if (!android) return;

    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      if (notificationService is AndroidNotificationService) {
        notificationService.setEndCallFromNotificationCallback(
          _onEndCallFromNotification,
        );
      }
    } catch (e) {
      l.logger.e('[RoomPage] Error registering notification end-call: $e');
    }
  }

  Future<void> _onEndCallFromNotification() async {
    if (_isLeavingByUser) {
      l.logger.d('[RoomPage] Skip duplicate notification end-call');
      return;
    }
    l.logger.i('[RoomPage] End call requested from notification');
    await _leaveRoom(isShowLeftMeetingBottomSheet: false);
  }

  /// Show the persistent in-meeting notification immediately on entering
  /// the meeting.
  ///
  /// On Android, [AndroidNotificationService] requests POST_NOTIFICATIONS
  /// when missing, then starts the ongoing meeting notification. Safe to call
  /// on every enter — idempotent and does not throw.
  Future<void> _showMeetingNotification() async {
    if (!android) return;

    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      await notificationService.showBackgroundNotification(
        roomName: widget.meetInfo.meetName,
        callId: widget.meetInfo.meetLinkName,
      );
      _registerNotificationEndCallCallback();
      l.logger.d('[RoomPage] In-meeting notification show requested');
    } catch (e) {
      // Defensive: the service itself is hardened, but if the manager
      // factory or platform channel is in an unusual state we still want
      // entering the meeting to succeed.
      l.logger.e('[RoomPage] Error showing in-meeting notification: $e');
    }
  }

  /// Hide background notification with error handling and logging
  Future<void> _hideNotification(String context) async {
    if (!android) return;

    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      await notificationService.hideBackgroundNotification();
      l.logger.d('[RoomPage] Notification hidden: $context');
    } catch (e) {
      l.logger.e('[RoomPage] Error hiding notification ($context): $e');
    }
  }

  // TODO(fix): move to room_bloc.dart and merge to state
  Future<void> loadUserConfig() async {
    userConfig = await appCoreManager.appCore.getUserConfig();
    if (userConfig != null) {
      _cameraMaxBitrate = userConfig!.cameraMaxBitrate;
      _cameraResolution = userConfig!.cameraResolution;
    }
  }

  /// Ensure video track is started after resuming from background
  Future<void> _ensureVideoTrackStartedAfterResume() async {
    try {
      // Check camera permission before accessing camera
      final permissionService = PermissionService();
      final hasPermission = await permissionService.hasCameraPermission();
      if (!hasPermission) {
        l.logger.d(
          '[RoomPage] Camera permission not granted, skipping video track restart',
        );
        return;
      }

      final participant = _bloc.state.room.localParticipant;
      if (participant == null) {
        return;
      }

      final isCameraEnabled = participant.isCameraEnabled();
      if (!isCameraEnabled) {
        return;
      }

      final tracks = participant.trackPublications.values.toList();
      LocalTrackPublication? videoTrackPub;

      for (LocalTrackPublication track in tracks) {
        if (track.track is LocalVideoTrack && !track.isScreenShare) {
          videoTrackPub = track;
          break;
        }
      }

      if (videoTrackPub == null) {
        l.logger.w('[RoomPage] Video track missing after resume');
        return;
      }
      try {
        final videoTrack = videoTrackPub.track as LocalVideoTrack?;
        if (videoTrack != null && videoTrack.isActive) {
          // restart track to fix android camera stuck after resume issue
          await videoTrack.restartTrack();
        }
      } catch (e) {
        l.logger.e('[RoomPage] Error refreshing video track: $e');
      }

      // Pausing stops the capturer and resuming restarts it, which swaps in a
      // fresh WebRTC track id. The native effect is keyed by that id, so
      // without re-attaching the background stops applying while the UI still
      // reports it as on. Mirrors what the controls bar does on manual enable.
      final selection = _bloc.state.cameraBackgroundSelection;
      if (selection.isEffectActive) {
        await syncLocalCameraBackgroundEffect(
          room: _bloc.state.room,
          selection: selection,
        );
      }
    } catch (e) {
      l.logger.e('[RoomPage] Error ensuring video track started: $e');
    }
  }

  // TODO(fix): move to room_bloc.dart
  void reloadVideoDevices() {
    Hardware.instance.enumerateDevices().then((devices) {
      if (mounted) {
        setState(() {
          _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
        });
      }
    });
  }

  /// for more information, see [event types](https://docs.livekit.io/client/events/#events)
  void setUpListeners(EventsListener<RoomEvent> listener) => listener
    ..on<RoomAttemptReconnectEvent>((_) {
      _hadLiveKitTransportIssuesThisMeeting = true;
    })
    ..on<RoomReconnectingEvent>((_) {
      _hadLiveKitTransportIssuesThisMeeting = true;
    })
    ..on<RoomDisconnectedEvent>((event) async {
      if (event.reason != null) {
        // Room disconnected
        l.logger.e('Room disconnected: reason => ${event.reason}');
      }
      // Exit PIP and hide notification when room disconnects
      if (android) {
        _bloc.add(ExitPipMode());
        await _hideNotification('room disconnected');
      }
      _chatBloc.add(
        ChatSystemNoticeAdded(
          message: 'Room disconnected: reason => ${event.reason}',
          identity: 'system',
          name: 'System',
        ),
      );
      // To-do: check if we really need addPostFrameCallback here
      WidgetsBindingCompatible.instance?.addPostFrameCallback((
        timeStamp,
      ) async {
        bool shouldPop = true;
        if (event.reason == DisconnectReason.roomDeleted) {
          final navigatorContext = Navigator.of(
            context,
            rootNavigator: true,
          ).context;
          LocalToast.showToast(
            navigatorContext,
            navigatorContext.local.meeting_ended_by_host,
            duration: 5,
          );
          // Do not show left meeting bottom sheet when meeting is ended by host
          await _leaveRoom(isShowLeftMeetingBottomSheet: false);
        } else if (event.reason == DisconnectReason.participantRemoved) {
          await _leaveRoom(leftMeetingBottomSheetIsKickedOut: true);
        } else if (event.reason == DisconnectReason.stateMismatch) {
          Sentry.captureMessage(
            'Room disconnected caused by state mismatch, auto rejoin',
            level: SentryLevel.warning,
          );
          // auto rejoin when disconnect reason is state mismatch
          _bloc.add(const StartRejoinMeeting());
          shouldPop = false;
        } else if (_isLeavingByUser) {
          // Manual leave flow handles its own navigation/bottom sheet.
          shouldPop = false;
        } else if (event.reason != null &&
            event.reason != DisconnectReason.clientInitiated) {
          // Log abnormal error to sentry
          Sentry.captureMessage(
            'Room disconnected unexpectedly: ${event.reason}',
            level: SentryLevel.error,
          );
        }

        if (shouldPop && mounted) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).popUntil((route) => route.isFirst);
        }
      });
    })
    ..on<RoomRecordingStatusChanged>((event) {
      // Server-initiated recordings (LiveKit egress) — surface as a synthetic
      // recorder identity in the multi-recording set so the banner appears
      // for everyone. We dedupe by a sentinel identity that no real
      // participant can collide with.
      if (event.activeRecording) {
        _bloc.add(
          const ParticipantRecordingStarted(identity: kServerRecordingIdentity),
        );
      } else {
        _bloc.add(
          const ParticipantRecordingStopped(identity: kServerRecordingIdentity),
        );
      }
    })
    ..on<DataReceivedEvent>((event) async {
      // MimiV1 chat payloads are raw MLS binary (not JSON envelopes). Route
      // them through the new decode path when the feature flag is enabled.
      if (_newChatEnabled && !_isJsonEnvelope(event.data)) {
        try {
          await _handleMimiChat(event);
        } catch (e) {
          l.logger.w('[RoomPage] _handleMimiChat failed: $e');
        }
        return;
      }
      try {
        handleChatMessage(event);
      } catch (e) {
        // if we cannot process the message, fallback to legacy _handleE2EEMessage()
        try {
          final topic = MessageTopic.values.firstWhere(
            (e) => e.name.toLowerCase() == event.topic!.toLowerCase(),
          );
          if (topic == MessageTopic.e2eeMessage) {
            await _handleE2EEMessage(event);
          }
        } catch (e) {
          if (mounted) {
            await context.showDataReceivedDialog(e.toString());
          }
        }
      }
    })
    ..on<AudioPlaybackStatusChanged>((event) async {
      if (!_bloc.state.room.canPlaybackAudio) {
        if (mounted) {
          final bool? yesno = await context.showPlayAudioManuallyDialog();
          if (yesno == true) {
            await _bloc.state.room.startAudio();
          }
        }
      }
    });

  Future<String> encryptMessage(String plainText) async {
    final encryptedBytes = await appCoreManager.appCore.encryptMessage(
      message: plainText,
    );
    final test = String.fromCharCodes(encryptedBytes);
    return test;
  }

  Future<({String plaintext, String mlsSenderId})?> decryptMessage(
    String encryptedText,
  ) async {
    final bytes = Uint8List.fromList(
      encryptedText.codeUnits.map((c) => c & 0xFF).toList(),
    );
    try {
      final (decryptedMessage, senderId) = await appCoreManager.appCore
          .decryptMessage(data: bytes);
      return (plaintext: decryptedMessage, mlsSenderId: senderId);
    } catch (e) {
      l.logger.e('Error decrypting message: $e');
      return null;
    }
  }

  Participant? _participantWithIdentity(String identity) {
    final room = _bloc.state.room;
    final local = room.localParticipant;
    if (local != null && local.identity == identity) {
      return local;
    }
    for (final p in room.remoteParticipants.values) {
      if (p.identity == identity) {
        return p;
      }
    }
    return null;
  }

  String _displayNameForTrustedSender(
    String trustedId,
    DataReceivedEvent event,
    String fallbackName,
  ) {
    final p = _participantWithIdentity(trustedId);
    if (p != null) {
      return _bloc.getParticipantDisplayName(p);
    }
    if (event.participant != null && event.participant!.identity == trustedId) {
      return _bloc.getParticipantDisplayName(event.participant!);
    }
    return fallbackName;
  }

  void _setActiveReaction({
    required String identity,
    required String emoji,
    required int timestamp,
  }) {
    if (!mounted) return;
    setState(() {
      _activeReactions[identity] = ParticipantReaction(
        emoji: emoji,
        timestamp: timestamp,
      );
    });
  }

  bool? _parseRaiseHandMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        final raisedValue = decoded['raised'];
        if (raisedValue is bool) {
          return raisedValue;
        }
        return null;
      }
    } catch (_) {}
    return null;
  }

  String? _parseAdminLowerHandIdentity(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        final identity = decoded['identity'];
        if (identity is String && identity.isNotEmpty) {
          return identity;
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isParticipantAdminOrHost(String identity) {
    final participant = _bloc.state.frbParticipantsMap[identity];
    if (participant == null) {
      return false;
    }
    return participant.isAdmin == 1 || participant.isHost == 1;
  }

  Future<void> _handleEmojiReaction(
    String message,
    String identity,
    String name,
  ) async {
    if (!availableEmojiReactions.contains(message)) {
      l.logger.w(
        '[RoomPage] _handleEmojiReaction ignored unsupported emoji: $message',
      );
      return;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _setActiveReaction(
      identity: identity,
      emoji: message,
      timestamp: timestamp,
    );
    l.logger.d(
      '[RoomPage] _handleEmojiReaction: identity=$identity, name=$name, emoji=$message',
    );
  }

  Future<void> useEmojiReaction(String emoji) async {
    if (!availableEmojiReactions.contains(emoji)) {
      return;
    }
    final room = _bloc.state.room;
    final localParticipant = room.localParticipant;
    final identity = localParticipant?.identity;
    if (localParticipant == null || identity == null) {
      l.logger.w(
        '[RoomPage] Cannot send emoji reaction: localParticipant null',
      );
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final encryptedMessage = await encryptMessage(emoji);
    final envelope = <String, dynamic>{
      'type': PublishableDataType.emojiReaction.value,
      'id': '$identity-$timestamp',
      'message': encryptedMessage,
      'timestamp': timestamp,
    };

    await localParticipant.publishData(
      utf8.encode(jsonEncode(envelope)),
      reliable: false,
      topic: PublishableDataType.emojiReaction.value,
    );

    _setActiveReaction(identity: identity, emoji: emoji, timestamp: timestamp);
  }

  Future<void> _handleRaiseHand(
    String message,
    String identity,
    String name,
  ) async {
    final isRaised = _parseRaiseHandMessage(message);
    if (isRaised == null) {
      l.logger.w(
        '[RoomPage] _handleRaiseHand ignored unsupported value: $message',
      );
      return;
    }

    _bloc.add(SetParticipantRaisedHand(identity: identity, raised: isRaised));

    l.logger.d(
      '[RoomPage] _handleRaiseHand: identity=$identity, name=$name, raised=$isRaised',
    );
  }

  Future<void> _handleAdminLowerHand(
    String message,
    String senderIdentity,
    String senderName,
  ) async {
    final targetIdentity = _parseAdminLowerHandIdentity(message);
    if (targetIdentity == null) {
      l.logger.w(
        '[RoomPage] _handleAdminLowerHand ignored malformed payload: $message',
      );
      return;
    }

    if (!_isParticipantAdminOrHost(senderIdentity)) {
      l.logger.w(
        '[RoomPage] _handleAdminLowerHand ignored unauthorized sender: identity=$senderIdentity, name=$senderName',
      );
      return;
    }

    _bloc.add(
      SetParticipantRaisedHand(identity: targetIdentity, raised: false),
    );
    l.logger.d(
      '[RoomPage] _handleAdminLowerHand: sender=$senderIdentity, target=$targetIdentity',
    );
  }

  Future<void> useRaiseHand({required bool raised}) async {
    final room = _bloc.state.room;
    final localParticipant = room.localParticipant;
    final identity = localParticipant?.identity;
    if (localParticipant == null || identity == null) {
      l.logger.w('[RoomPage] Cannot send raise hand: localParticipant null');
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final encryptedMessage = await encryptMessage(
      jsonEncode({'raised': raised}),
    );
    final envelope = <String, dynamic>{
      'type': PublishableDataType.raiseHand.value,
      'id': '$identity-$timestamp',
      'message': encryptedMessage,
      'timestamp': timestamp,
    };

    await localParticipant.publishData(
      utf8.encode(jsonEncode(envelope)),
      reliable: false,
      topic: PublishableDataType.raiseHand.value,
    );

    _bloc.add(SetParticipantRaisedHand(identity: identity, raised: raised));
  }

  Future<void> publishAdminLowerHand(String identity) async {
    final room = _bloc.state.room;
    final localParticipant = room.localParticipant;
    final localIdentity = localParticipant?.identity;
    if (localParticipant == null || localIdentity == null) {
      l.logger.w(
        '[RoomPage] Cannot send lower hand admin message: localParticipant null',
      );
      return;
    }
    if (!_bloc.state.isLocalParticipantAdminOrHost) {
      l.logger.w(
        '[RoomPage] Cannot send lower hand admin message: local participant is not admin/host',
      );
      return;
    }

    _bloc.add(SetParticipantRaisedHand(identity: identity, raised: false));
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    try {
      final encryptedMessage = await encryptMessage(
        jsonEncode({'identity': identity}),
      );
      final envelope = <String, dynamic>{
        'type': PublishableDataType.lowerHandAdmin.value,
        'id': '$localIdentity-$timestamp',
        'message': encryptedMessage,
        'timestamp': timestamp,
      };

      await localParticipant.publishData(
        utf8.encode(jsonEncode(envelope)),
        reliable: true,
        topic: PublishableDataType.lowerHandAdmin.value,
      );
    } catch (e) {
      l.logger.e('[RoomPage] publishAdminLowerHand failed: $e');
      _bloc.add(SetParticipantRaisedHand(identity: identity, raised: true));
    }
  }

  Future<void> _handleChatMessageReaction(
    String message,
    String identity,
    String name,
  ) async {
    // Legacy reaction protocol (no event ids / unreact). Only meaningful when
    // the MimiV1 chat path is disabled; otherwise reactions flow through
    // [_handleMimiChat]. Left as a best-effort no-op for legacy peers.
    l.logger.d(
      '[RoomPage] legacy _handleChatMessageReaction: identity=$identity, name=$name',
    );
  }

  Future<void> broadcastE2EEMessage(
    String message, {
    PublishableDataType type = PublishableDataType.message,
  }) async {
    final room = _bloc.state.room;
    final identity = room.localParticipant?.identity;
    if (identity == null) {
      l.logger.w(
        '[RoomPage] Cannot broadcast message: localParticipant is null',
      );
      return;
    }
    // Add locally first
    if (type == PublishableDataType.message) {
      addMessage(message, identity, widget.displayName);
    }

    // 1. Encrypt -> bytes
    final encryptedMessage = await encryptMessage(message);

    // 3. Build JSON payload compatible with web
    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> messageContent = {
      'type': type.value,
      'id': '$identity-$now',
      'message': encryptedMessage, // <-- string, not raw bytes
      'timestamp': now,
    };

    final encodedMessage = jsonEncode(messageContent);

    await room.localParticipant!.publishData(
      utf8.encode(encodedMessage),
      reliable: true,
    );
  }

  /// Publishes MLS-encrypted recording status to peers (web-compatible envelope).
  Future<void> _publishRecordingStatus(
    RecordingStatus status, {
    String? targetParticipantIdentity,
  }) async {
    final room = _bloc.state.room;
    final identity = room.localParticipant?.identity;
    if (identity == null) {
      l.logger.w(
        '[RoomPage] Cannot publish recording status: localParticipant is null',
      );
      return;
    }

    final message = jsonEncode({'status': status.name});
    final encryptedMessage = await encryptMessage(message);
    final now = DateTime.now().millisecondsSinceEpoch;
    final envelope = jsonEncode({
      'type': PublishableDataType.recordingStatus.value,
      'id': '$identity-$now',
      'message': encryptedMessage,
      'timestamp': now,
    });

    await room.localParticipant!.publishData(
      utf8.encode(envelope),
      reliable: true,
      destinationIdentities: targetParticipantIdentity != null
          ? [targetParticipantIdentity]
          : null,
    );
  }

  void _showIncomingChatToast(ChatIncomingNotification notification) {
    // Several messages can land in the same frame — an MLS catch-up after a
    // reconnect delivers a whole backlog at once — so show only the most
    // recent instead of stacking a toast per message.
    _pendingChatToast = notification;
    if (_chatToastScheduled) {
      return;
    }
    _chatToastScheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatToastScheduled = false;
      final pending = _pendingChatToast;
      _pendingChatToast = null;
      if (pending == null || !mounted || !context.mounted) {
        return;
      }
      if (_isSidePanelOpen(RoomSidePanel.chat)) {
        return;
      }

      final msg = pending.message;
      final localId = _bloc.state.room.localParticipant?.identity ?? '';
      final participantTracks = _bloc.state.participantTracks;
      final nameMap = buildParticipantNameMap(participantTracks);
      final plainBody = mentionPlainText(
        msg.message,
        participantNameMap: nameMap,
        localIdentity: localId,
        everyoneName: context.local.chat_mention_everyone,
        unknownName: context.local.unknown,
      );
      final senderName = msg.name.trim().isNotEmpty
          ? msg.name.trim()
          : msg.identity;
      final title = pending.isMention
          ? context.local.chat_mention_notified_title(senderName)
          : senderName;
      final mentionTitleWidget = pending.isMention
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: senderName,
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                  ),
                  TextSpan(
                    text: ' ${context.local.chat_mention_notified_suffix}',
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textWeak,
                    ),
                  ),
                ],
              ),
            )
          : null;

      final hasBody = msg.message.trim().isNotEmpty;
      LocalToast.showToastification(
        context,
        title,
        hasBody ? plainBody : '',
        avatarName: senderName,
        titleWidget: mentionTitleWidget,
        index: resolveParticipantColorIndex(
          msg.identity,
          participantTracks: participantTracks,
        ),
        autoCloseInSeconds: pending.isMention ? 30 : 8,
        bottomMargin: bottomControlHeight + 16,
        horizontalMargin: 16,
        messageWidget: hasBody
            ? MentionMessageContent(
                message: msg.message,
                localIdentity: localId,
                participantNameMap: nameMap,
                selectable: false,
              )
            : null,
        onTap: (_) => _openChatSidePanel(),
      );
    });
  }

  /// Sends a chat message. When [replyToId]/[topicId] are set it is a thread
  /// reply. Uses the MimiV1 compose path when the feature flag is enabled,
  /// otherwise falls back to the legacy broadcast (no threads).
  Future<void> sendChatMessage(
    String text, {
    String? replyToId,
    String? topicId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    if (!_newChatEnabled) {
      await broadcastE2EEMessage(trimmed);
      return;
    }

    _chatBloc.add(
      ChatMessageSubmitted(
        text: trimmed,
        senderDisplayName: widget.displayName,
        replyToId: replyToId,
        topicId: topicId,
      ),
    );
  }

  /// Toggles an emoji reaction (MimiV1) on [messageId].
  Future<void> toggleChatReaction(String messageId, String emoji) async {
    if (!_newChatEnabled) return;
    _chatBloc.add(ChatReactionToggled(messageId: messageId, emoji: emoji));
  }

  /// Retries a failed outgoing message, preserving thread metadata.
  void _retryChatMessage(RoomChatMessage message) {
    _chatBloc.add(
      ChatMessageRetryRequested(
        messageId: message.id,
        text: message.message,
        senderDisplayName: widget.displayName,
        replyToId: message.inReplyToId,
        topicId: message.topicId,
      ),
    );
  }

  /// Decodes an incoming MimiV1 payload with retry ([0, 2s, 5s]) — MLS may not
  /// be ready yet, so we must not silently drop.
  Future<FrbChatIncomingEvent?> _decodeChatWithRetry(List<int> data) async {
    const delaysMs = [0, 2000, 5000];
    for (final delay in delaysMs) {
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      try {
        return await appCoreManager.appCore.decodeChat(data: data);
      } catch (e) {
        l.logger.w('[RoomPage] decodeChat failed (retrying): $e');
      }
    }
    return null;
  }

  /// True when [data] is a JSON envelope (legacy / control message) rather than
  /// a raw MimiV1 MLS binary payload.
  bool _isJsonEnvelope(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      return decoded is Map;
    } catch (_) {
      return false;
    }
  }

  /// Handles an incoming MimiV1 chat data-channel payload.
  Future<void> _handleMimiChat(DataReceivedEvent event) async {
    final decoded = await _decodeChatWithRetry(event.data);
    if (decoded == null) return;

    // Identity check: LiveKit identity must equal MLS sender id.
    final liveKitId = event.participant?.identity;
    if (liveKitId != null && liveKitId != decoded.senderParticipantId) {
      l.logger.e(
        '[RoomPage] MimiV1 sender mismatch: livekit=$liveKitId '
        'mls=${decoded.senderParticipantId}',
      );
      return;
    }

    if (!mounted || !context.mounted) {
      l.logger.w('[RoomPage] Cannot handle MimiV1 chat: not mounted');
      return;
    }

    final localId = _bloc.state.room.localParticipant?.identity;
    final fallbackName = event.participant != null
        ? _bloc.getParticipantDisplayName(event.participant!)
        : (event.participant?.name ?? context.local.unknown);

    switch (decoded.kind) {
      case FrbChatEventKind.message:
        // Ignore our own echo — we already added a local echo optimistically.
        if (localId != null && decoded.senderParticipantId == localId) return;
        final displayName = _displayNameForTrustedSender(
          decoded.senderParticipantId,
          event,
          fallbackName,
        );
        _chatBloc.add(
          ChatMessageReceived(
            id: decoded.id,
            message: decoded.text ?? '',
            timestamp: decoded.receivedAtMs.toInt(),
            identity: decoded.senderParticipantId,
            name: displayName,
            inReplyToId: decoded.inReplyToId,
            topicId: decoded.topicId,
            notify: true,
          ),
        );
        return;
      case FrbChatEventKind.reaction:
        if (localId != null && decoded.senderParticipantId == localId) return;
        _chatBloc.add(
          ChatReactionReceived(
            reactionId: decoded.id,
            senderIdentity: decoded.senderParticipantId,
            replacesId: decoded.replacesId,
            targetId: decoded.targetId,
            emoji: decoded.emoji,
          ),
        );
        return;
      case FrbChatEventKind.unsupported:
        l.logger.d('[RoomPage] Received unsupported chat event');
        return;
    }
  }

  void addMessage(
    String message,
    String identity,
    String name, {
    bool showToast = false,
    String type = 'text',
    ChatJoinLeaveKind? joinLeaveKind,
    String? meetingName,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '$identity-${DateTime.now().microsecondsSinceEpoch}';

    if (type == 'system') {
      _chatBloc.add(
        ChatSystemNoticeAdded(
          message: message,
          identity: identity,
          name: name,
          joinLeaveKind: joinLeaveKind,
          meetingName: meetingName,
        ),
      );
    } else {
      _chatBloc.add(
        ChatMessageReceived(
          id: id,
          message: message,
          timestamp: now,
          identity: identity,
          name: name,
          notify: showToast,
        ),
      );
    }

    if (showToast && type != 'text') {
      LocalToast.showToastification(
        context,
        name,
        message,
        onTap: (_) => _openChatSidePanel(),
      );
    }
  }

  /// Validates an incoming recording-status envelope
  /// and dispatches the appropriate bloc event. Banner / consent modal are
  /// driven off bloc state changes (see [RecordingTopBanner] and the
  /// BlocListener in [build]) rather than imperatively from here, so a
  /// single source of truth governs the UI.
  void _handleRecordingStatus({
    required Map<String, dynamic> envelope,
    required String? decryptedPlaintext,
    required String? mlsSenderId,
    required String? liveKitSenderIdentity,
  }) {
    final isSenderAdminOrHost = liveKitSenderIdentity != null
        ? _isParticipantAdminOrHost(liveKitSenderIdentity)
        : false;

    final result = RecordingStatusReceiver.validate(
      envelope: envelope,
      decryptedPlaintext: decryptedPlaintext,
      mlsSenderId: mlsSenderId,
      liveKitSenderIdentity: liveKitSenderIdentity,
      isSenderAdminOrHost: isSenderAdminOrHost,
    );

    switch (result.decision) {
      case RecordingStatusDecision.started:
        _bloc.add(ParticipantRecordingStarted(identity: result.senderIdentity));
      case RecordingStatusDecision.stopped:
        _bloc.add(ParticipantRecordingStopped(identity: result.senderIdentity));
      case RecordingStatusDecision.drop:
        break;
    }
  }

  /// Drains [_pendingRecordingStatuses] once the room is initialized. While
  /// the room is still warming up we keep polling every 1s — cheap because
  /// the queue is usually empty and the timer is one-shot per tick.
  void _processPendingRecordingStatus() {
    if (_pendingRecordingStatuses.isEmpty) {
      _pendingRecordingStatusTimer?.cancel();
      _pendingRecordingStatusTimer = null;
      return;
    }

    if (!_bloc.state.isRoomInitialized) {
      // Schedule a re-check; replace any in-flight timer so we don't stack
      // multiple drains.
      _pendingRecordingStatusTimer?.cancel();
      _pendingRecordingStatusTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        _processPendingRecordingStatus();
      });
      return;
    }

    final drained = List.of(_pendingRecordingStatuses);
    _pendingRecordingStatuses.clear();
    _pendingRecordingStatusTimer?.cancel();
    _pendingRecordingStatusTimer = null;

    for (final args in drained) {
      _handleRecordingStatus(
        envelope: args.envelope,
        decryptedPlaintext: args.decryptedPlaintext,
        mlsSenderId: args.mlsSenderId,
        liveKitSenderIdentity: args.liveKitSenderIdentity,
      );
    }
  }

  /// This handle e2ee message from legacy mobile version
  @Deprecated('Use handleChatMessage instead')
  Future<void> _handleE2EEMessage(DataReceivedEvent event) async {
    try {
      final name = event.participant?.name ?? context.local.unknown;
      final liveKitIdentity = event.participant?.identity;
      final encryptedMessage = utf8.decode(event.data);
      final result = await decryptMessage(encryptedMessage);
      if (result == null) {
        l.logger.e('Cannot decrypt message');
        return;
      }
      if (liveKitIdentity != null && liveKitIdentity != result.mlsSenderId) {
        l.logger.w(
          '[RoomPage] Legacy E2EE: MLS sender ${result.mlsSenderId} != '
          'LiveKit identity $liveKitIdentity',
        );
      }
      final trustedId = result.mlsSenderId;
      final displayName = _displayNameForTrustedSender(trustedId, event, name);
      addMessage(result.plaintext, trustedId, displayName);
      if (context.mounted && mounted && !_isSidePanelOpen(RoomSidePanel.chat)) {
        LocalToast.showToastification(
          context,
          displayName,
          result.plaintext,
          onTap: (_) => _openChatSidePanel(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> handleChatMessage(DataReceivedEvent event) async {
    final data = utf8.decode(event.data);
    l.logger.d('handleChatMessage data: $data');

    if (data.isEmpty) {
      l.logger.w('Invalid message: empty');
      return;
    }

    final decoded = jsonDecode(data);
    if (decoded is! Map) {
      l.logger.w('Invalid message: expected JSON object');
      return;
    }
    final messageJson = Map<String, dynamic>.from(decoded);
    final dataType = PublishableDataType.fromString(
      messageJson['type']?.toString(),
    );

    final message = messageJson['message'];
    final name = event.participant?.name ?? context.local.unknown;
    final fallbackDisplayName = event.participant != null
        ? _bloc.getParticipantDisplayName(event.participant!)
        : name;

    const mlsPayloadTypes = <PublishableDataType>{
      PublishableDataType.message,
      PublishableDataType.emojiReaction,
      PublishableDataType.raiseHand,
      PublishableDataType.chatMessageReaction,
      PublishableDataType.recordingStatus,
    };

    final encryptedText = message is String ? message : null;
    String? decryptedMessage;
    String? trustedSenderId;

    final isMlsPayload = dataType != null && mlsPayloadTypes.contains(dataType);
    if (isMlsPayload) {
      if (encryptedText != null) {
        final result = await decryptMessage(encryptedText);
        if (result != null) {
          final claimed = claimedParticipantIdFromEnvelope(messageJson);
          if (claimed == null) {
            l.logger.w(
              '[RoomPage] MLS envelope missing or invalid claimed sender id',
            );
          } else if (claimed != result.mlsSenderId) {
            l.logger.e(
              '[RoomPage] MLS envelope sender mismatch: claimed=$claimed '
              'mlsSenderId=${result.mlsSenderId}',
            );
          } else {
            decryptedMessage = result.plaintext;
            trustedSenderId = result.mlsSenderId;
          }
        }
      } else {
        l.logger.w(
          '[RoomPage] Expected encrypted string in message for $dataType',
        );
      }
    }

    switch (dataType) {
      case PublishableDataType.message:
        if (decryptedMessage == null || trustedSenderId == null) {
          return;
        }
        final displayName = _displayNameForTrustedSender(
          trustedSenderId,
          event,
          fallbackDisplayName,
        );
        addMessage(decryptedMessage, trustedSenderId, displayName);
        if (mounted &&
            context.mounted &&
            !_isSidePanelOpen(RoomSidePanel.chat)) {
          LocalToast.showToastification(
            context,
            displayName,
            decryptedMessage,
            onTap: (_) => _openChatSidePanel(),
          );
        }
        return;
      case PublishableDataType.emojiReaction:
        try {
          if (decryptedMessage != null && trustedSenderId != null) {
            final displayName = _displayNameForTrustedSender(
              trustedSenderId,
              event,
              fallbackDisplayName,
            );
            await _handleEmojiReaction(
              decryptedMessage,
              trustedSenderId,
              displayName,
            );
          }
        } catch (_) {}
        return;
      case PublishableDataType.raiseHand:
        try {
          if (decryptedMessage != null && trustedSenderId != null) {
            final displayName = _displayNameForTrustedSender(
              trustedSenderId,
              event,
              fallbackDisplayName,
            );
            await _handleRaiseHand(
              decryptedMessage,
              trustedSenderId,
              displayName,
            );
          }
        } catch (_) {}
        return;
      case PublishableDataType.lowerHandAdmin:
        try {
          if (decryptedMessage != null && trustedSenderId != null) {
            final displayName = _displayNameForTrustedSender(
              trustedSenderId,
              event,
              fallbackDisplayName,
            );
            await _handleAdminLowerHand(
              decryptedMessage,
              trustedSenderId,
              displayName,
            );
          }
        } catch (_) {}
        return;
      case PublishableDataType.chatMessageReaction:
        try {
          if (decryptedMessage != null && trustedSenderId != null) {
            final displayName = _displayNameForTrustedSender(
              trustedSenderId,
              event,
              fallbackDisplayName,
            );
            await _handleChatMessageReaction(
              decryptedMessage,
              trustedSenderId,
              displayName,
            );
          }
        } catch (_) {}

        return;
      case PublishableDataType.recordingStatus:
        if (_bloc.state.isRoomInitialized) {
          _handleRecordingStatus(
            envelope: messageJson,
            decryptedPlaintext: decryptedMessage,
            mlsSenderId: trustedSenderId,
            liveKitSenderIdentity: event.participant?.identity,
          );
        } else {
          // Defer until the room (and participant map) is ready; otherwise
          // `_isParticipantAdminOrHost` returns false and the receiver
          // silently drops the message.
          _pendingRecordingStatuses.add((
            envelope: messageJson,
            decryptedPlaintext: decryptedMessage,
            mlsSenderId: trustedSenderId,
            liveKitSenderIdentity: event.participant?.identity,
          ));
          _processPendingRecordingStatus();
        }
        return;
      case null:
        l.logger.w(
          '[RoomPage] handleChatMessage: unknown type ${messageJson['type']}',
        );
        return;
    }
  }

  Future<void> _showEmojiReactionMenu() async {
    if (!mounted) return;
    final localIdentity = _bloc.state.room.localParticipant?.identity;
    final isHandRaised = localIdentity != null
        ? _bloc.state.raisedHandsByIdentity[localIdentity] == true
        : false;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.backgroundNorm,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...availableEmojiReactions.map(
                    (emoji) => InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(useEmojiReaction(emoji));
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                    ),
                  ),
                  if (localIdentity != null)
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(useRaiseHand(raised: !isHandRaised));
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isHandRaised
                                ? Colors.grey.withValues(alpha: 0.35)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            raisedHandEmoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildCameraLayout(
    BuildContext context,
    List<ParticipantInfo> participantTracks,
    List<ParticipantInfo> speakerTracks,
    Map<String, bool> raisedHandsByIdentity,
    String iosPipRemoteCameraSubscriptionIdentity,
  ) {
    final room = _bloc.state.room;
    final showLowerHand =
        _bloc.state.isLocalParticipantAdminOrHost &&
        _bloc.isMeetAdminLowerHandEnabled();
    final void Function(String)? onLowerHandByIdentity = showLowerHand
        ? (identity) {
            unawaited(publishAdminLowerHand(identity));
          }
        : null;
    switch (_layout) {
      case CameraLayout.grid:
        return ResponsiveCameraLayout(
          participantTracks: participantTracks,
          room: room,
          reactionsByIdentity: _activeReactions,
          raisedHandsByIdentity: raisedHandsByIdentity,
          onLowerHandByIdentity: onLowerHandByIdentity,
          iosPipRemoteCameraSubscriptionIdentity:
              iosPipRemoteCameraSubscriptionIdentity,
        );
      case CameraLayout.fixedSizing:
        return FixedSizingCameraLayout(
          participantTracks: participantTracks,
          reactionsByIdentity: _activeReactions,
          raisedHandsByIdentity: raisedHandsByIdentity,
          onLowerHandByIdentity: onLowerHandByIdentity,
        );
      case CameraLayout.speaker:

        /// use fixedSizing layout when no active speaker
        if (speakerTracks.isEmpty) {
          return FixedSizingCameraLayout(
            participantTracks: participantTracks,
            reactionsByIdentity: _activeReactions,
            raisedHandsByIdentity: raisedHandsByIdentity,
            onLowerHandByIdentity: onLowerHandByIdentity,
          );
        }

        /// take first priority speaker into main layout
        final speakers = speakerTracks.take(1).toList();
        final participantTracksWithoutSpeaker = _bloc.withoutSpeakerTracks(
          participantTracks,
          speakers,
        );
        return buildSpeakerLayout(
          context,
          speakers,
          participantTracksWithoutSpeaker,
          raisedHandsByIdentity,
        );
      case CameraLayout.mutliSpeaker:

        /// use fixedSizing layout when no active speaker
        if (speakerTracks.isEmpty) {
          return FixedSizingCameraLayout(
            participantTracks: participantTracks,
            reactionsByIdentity: _activeReactions,
            raisedHandsByIdentity: raisedHandsByIdentity,
            onLowerHandByIdentity: onLowerHandByIdentity,
          );
        }

        /// take first priority speaker into main layout
        final speakers = speakerTracks;
        final participantTracksWithoutSpeaker = _bloc.withoutSpeakerTracks(
          participantTracks,
          speakers,
        );
        return buildSpeakerLayout(
          context,
          speakers,
          participantTracksWithoutSpeaker,
          raisedHandsByIdentity,
        );
    }
  }

  Widget buildSpeakerLayout(
    BuildContext context,
    List<ParticipantInfo> speakerTracks,
    List<ParticipantInfo> participantTracksWithoutSpeaker,
    Map<String, bool> raisedHandsByIdentity,
  ) {
    final showLowerHand =
        _bloc.state.isLocalParticipantAdminOrHost &&
        _bloc.isMeetAdminLowerHandEnabled();
    return Column(
      children: [
        SizedBox(
          height: 126,
          child: ListView.builder(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemCount: max(0, participantTracksWithoutSpeaker.length),
            itemBuilder: (BuildContext context, int index) => SizedBox(
              width: 224,
              height: 126,
              child: Container(
                margin: const EdgeInsets.all(0.3),
                child: ParticipantWidget.widgetFor(
                  224,
                  126,
                  getParticipantDisplayColors(
                    context,
                    participantTracksWithoutSpeaker[index]
                        .participant
                        .identity
                        .hashCode,
                  ),
                  participantTracksWithoutSpeaker[index],
                  showStatsLayer: false,
                  reaction:
                      _activeReactions[participantTracksWithoutSpeaker[index]
                          .participant
                          .identity],
                  isRaisedHand:
                      raisedHandsByIdentity[participantTracksWithoutSpeaker[index]
                          .participant
                          .identity] ==
                      true,
                  onLowerHand: showLowerHand
                      ? () {
                          unawaited(
                            publishAdminLowerHand(
                              participantTracksWithoutSpeaker[index]
                                  .participant
                                  .identity,
                            ),
                          );
                        }
                      : null,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: FixedSizingCameraLayout(
            participantTracks: speakerTracks,
            reactionsByIdentity: _activeReactions,
            raisedHandsByIdentity: raisedHandsByIdentity,
            onLowerHandByIdentity: showLowerHand
                ? (identity) {
                    unawaited(publishAdminLowerHand(identity));
                  }
                : null,
          ),
        ),
      ],
    );
  }

  /// leave room and disconnect from livekit
  Future<void> _leaveRoom({
    bool isShowLeftMeetingBottomSheet = true,
    bool leftMeetingBottomSheetShowRejoin = true,
    bool leftMeetingBottomSheetIsKickedOut = false,
    String? leftMeetingBottomSheetTitle,
    String? leftMeetingBottomSheetContent,
  }) async {
    _isLeavingByUser = true;

    if (_meetingRecorder?.isActive ?? false) {
      await _meetingRecorder!.finishRecording();
    }

    final meetingLink = widget.meetLink;
    final isHost = _bloc.state.isHost;
    final isPaidUser = _bloc.state.isPaidUser;
    final meetLinkName = _bloc.state.meetInfo.meetLinkName;

    if (!_bloc.isClosed) {
      _bloc.stopLivekitActiveUuidRefresh();
    }
    // Cancel rejoin if in progress to prevent adding events after bloc closes
    if (_bloc.state.isRejoining && !_bloc.isClosed) {
      l.logger.i('[Room] Cancelling rejoin before leaving room');
      try {
        _bloc.add(const CancelRejoinMeeting());
        // Wait a bit for the cancel to process
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        l.logger.w('[Room] Error cancelling rejoin: $e');
      }
    }

    // 1. disconnect MLS first (no need to await to provide better user experience),
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      appCoreManager.appCore.leaveRoom();
    } catch (e) {
      l.logger.e('Error leaving room: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'leave_room');
          scope.setTag('action_type', 'leave_room_api');
          scope.setTag('meeting_link_name', _bloc.state.meetInfo.meetLinkName);
        },
      );
    }

    // 2. disconnect from livekit
    try {
      await _bloc.state.room.disconnect();
    } catch (e) {
      l.logger.e('Error disconnecting room: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'leave_room');
          scope.setTag('action_type', 'disconnect');
          scope.setTag('meeting_link_name', _bloc.state.meetInfo.meetLinkName);
        },
      );
    }

    // Hide notification when leaving room
    await _hideNotification('leaving room');

    final rootNavigator = Coordinator.rootNavigatorKey.currentState;
    if (rootNavigator != null) {
      rootNavigator.popUntil((route) => route.isFirst);
    } else if (mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } else {
      l.logger.w('[Room] Leave room: no navigator available for pop');
      return;
    }

    final rootContext =
        Coordinator.rootNavigatorKey.currentState?.overlay?.context ??
        Coordinator.rootNavigatorKey.currentContext;
    if (rootContext != null &&
        rootContext.mounted &&
        isShowLeftMeetingBottomSheet) {
      var meetFeedbackOnSkip = false;
      try {
        meetFeedbackOnSkip = ManagerFactory()
            .get<DataProviderManager>()
            .unleashDataProvider
            .isMeetFeedbackOnSkip();
      } catch (e, st) {
        l.logger.w('[Room] Unleash for feedback skip: $e', stackTrace: st);
      }
      // Record the completion BEFORE showing the feedback bottom sheet so the
      // star score the user submits inside the sheet lands on this meeting's
      // [completedFeedbackScores] slot (otherwise withFeedback only sees prior
      // completions and writes to the wrong row).
      if (leftMeetingBottomSheetTitle == null &&
          !leftMeetingBottomSheetIsKickedOut) {
        try {
          final hadBadConnection =
              _hadLiveKitTransportIssuesThisMeeting ||
              _bloc.state.rejoinCount > 0;
          final wasInterrupted = _bloc.state.rejoinCount > 0;
          await ManagerFactory()
              .get<UserActivityManager>()
              .recordMeetingCompletedAndRequestDeferredReview(
                hadBadConnection: hadBadConnection,
                wasInterrupted: wasInterrupted,
              );
        } catch (e, st) {
          l.logger.w('[Room] record completion (leave): $e', stackTrace: st);
        }
      }
      if (rootContext.mounted) {
        final skipStoreReviewPrompt = await showLeftMeetingBottomSheet(
          rootContext,
          meetingLink: meetingLink,
          isHost: isHost,
          isPaidUser: isPaidUser,
          isMeetMobileShowStartMeetingButtonEnabled: true,
          isKickedOut: leftMeetingBottomSheetIsKickedOut,
          showRejoin: leftMeetingBottomSheetShowRejoin,
          title: leftMeetingBottomSheetTitle,
          content: leftMeetingBottomSheetContent,
          meetingLinkName: meetLinkName,
          meetFeedbackOnSkipEnabled: meetFeedbackOnSkip,
          onRejoinMeeting: () {
            _navigateToPreJoin(rootContext, meetingLink);
          },
          onStartMeetingNow: () {
            _navigateToStartMeeting(rootContext);
          },
        );
        if (leftMeetingBottomSheetTitle == null &&
            !leftMeetingBottomSheetIsKickedOut) {
          try {
            if (!skipStoreReviewPrompt) {
              final canShowStoreReview =
                  await InAppReviewService.canShowStoreReview();
              if (canShowStoreReview && rootContext.mounted) {
                await PreRatingSheet.show(
                  rootContext,
                  onPositiveAction: () => InAppReviewService.tryRequestReview(
                    thanksToastContext: rootContext,
                  ),
                  onNegativeAction: () async => {
                    await InAppReviewService.onPreRatingNegativeAction(),
                    await widget.authBloc?.reportProblem(),
                  },
                );
              }
            }
            _hadLiveKitTransportIssuesThisMeeting = false;
          } catch (e, st) {
            l.logger.w('[Room] store review (leave): $e', stackTrace: st);
          }
        }
      }
    }
    _isLeavingByUser = false;
  }

  /// End meeting for all participants
  Future<void> _endMeetingForAll() async {
    _isLeavingByUser = true;
    // Disconnect from room after ending meeting
    try {
      await _bloc.state.room.disconnect();
    } catch (e) {
      l.logger.e('Error disconnecting room: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'end_meeting_for_all');
          scope.setTag('action_type', 'disconnect');
          scope.setTag('meeting_link_name', _bloc.state.meetInfo.meetLinkName);
        },
      );
    }

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      await appCoreManager.appCore.endMeeting();
    } catch (e) {
      l.logger.e('Error ending meeting for all: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'end_meeting_for_all');
          scope.setTag('action_type', 'end_meeting_api');
          scope.setTag('meeting_link_name', _bloc.state.meetInfo.meetLinkName);
        },
      );
    }

    // Hide notification when ending meeting
    await _hideNotification('ending meeting');

    if (!mounted) return;

    final meetingLink = widget.meetLink;
    final isHost = _bloc.state.isHost;
    final isPaidUser = _bloc.state.isPaidUser;
    final meetLinkName = _bloc.state.meetInfo.meetLinkName;

    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);

    final rootContext =
        Coordinator.rootNavigatorKey.currentState?.overlay?.context ??
        Coordinator.rootNavigatorKey.currentContext;
    if (rootContext != null && rootContext.mounted && meetLinkName.isNotEmpty) {
      var meetFeedbackOnSkip = false;
      try {
        meetFeedbackOnSkip = ManagerFactory()
            .get<DataProviderManager>()
            .unleashDataProvider
            .isMeetFeedbackOnSkip();
      } catch (e, st) {
        l.logger.w('[Room] Unleash for feedback skip: $e', stackTrace: st);
      }
      // See `_leaveRoom`: completion must be recorded before the sheet so that
      // withFeedback can match the just-ended meeting's slot.
      try {
        final hadBadConnection =
            _hadLiveKitTransportIssuesThisMeeting ||
            _bloc.state.rejoinCount > 0;
        final wasInterrupted = _bloc.state.rejoinCount > 0;
        await ManagerFactory()
            .get<UserActivityManager>()
            .recordMeetingCompletedAndRequestDeferredReview(
              hadBadConnection: hadBadConnection,
              wasInterrupted: wasInterrupted,
            );
      } catch (e, st) {
        l.logger.w(
          '[Room] record completion (end-for-all): $e',
          stackTrace: st,
        );
      }
      if (rootContext.mounted) {
        final skipStoreReviewPrompt = await showLeftMeetingBottomSheet(
          rootContext,
          meetingLink: meetingLink,
          isHost: isHost,
          isPaidUser: isPaidUser,
          isMeetMobileShowStartMeetingButtonEnabled: true,
          meetingLinkName: meetLinkName,
          meetFeedbackOnSkipEnabled: meetFeedbackOnSkip,
          onRejoinMeeting: () {
            _navigateToPreJoin(rootContext, meetingLink);
          },
          onStartMeetingNow: () {
            _navigateToStartMeeting(rootContext);
          },
        );
        try {
          if (!skipStoreReviewPrompt) {
            final canShowStoreReview =
                await InAppReviewService.canShowStoreReview();
            if (canShowStoreReview && rootContext.mounted) {
              await PreRatingSheet.show(
                rootContext,
                onPositiveAction: () => InAppReviewService.tryRequestReview(
                  thanksToastContext: rootContext,
                ),
                onNegativeAction: () async => {
                  await InAppReviewService.onPreRatingNegativeAction(),
                  await widget.authBloc?.reportProblem(),
                },
              );
            }
          }
          _hadLiveKitTransportIssuesThisMeeting = false;
        } catch (e, st) {
          l.logger.w('[Room] store review (end-for-all): $e', stackTrace: st);
        }
      }
    }
    _isLeavingByUser = false;
  }

  /// Navigate to PreJoin page to rejoin the meeting
  void _navigateToPreJoin(
    BuildContext context,
    FrbUpcomingMeeting meetingLink,
  ) {
    // Extract meeting link information
    final meetLinkName = meetingLink.meetingLinkName;
    final password = meetingLink.meetingPassword;
    final meetingUrl = meetingLink.formatMeetingLink();

    // Use the stored authBloc or create a new one
    final authBloc =
        widget.authBloc ??
              AuthBloc(
                UserAgent(),
                ManagerFactory().get<PlatformChannelManager>(),
                ManagerFactory(),
                ManagerFactory()
                    .get<DataProviderManager>()
                    .meetUserSettingsDataProvider,
              )
          ..add(AuthInitialized());

    Navigator.pushNamed(
      context,
      RouteName.preJoin.path,
      arguments: {
        "room": meetLinkName,
        "password": password,
        "meetingLink": meetingUrl,
        "displayName": widget.displayName,
        "isVideoEnabled": false,
        "isAudioEnabled": false,
        "isE2EEEnabled": true,
        "authBloc": authBloc,
      },
    );
  }

  /// Navigate to PreJoin page to start a new meeting
  void _navigateToStartMeeting(BuildContext context) {
    final authBloc =
        widget.authBloc ??
              AuthBloc(
                UserAgent(),
                ManagerFactory().get<PlatformChannelManager>(),
                ManagerFactory(),
                ManagerFactory()
                    .get<DataProviderManager>()
                    .meetUserSettingsDataProvider,
              )
          ..add(AuthInitialized());

    final args = PreJoinArgs(type: PreJoinType.create, authBloc: authBloc);
    Navigator.pushNamed(context, RouteName.preJoin.path, arguments: args);
  }

  /// Toggle meeting lock state (lock/unlock)
  Future<bool> _toggleLockMeeting({required bool value}) async {
    bool success = false;
    Exception? caughtException;

    try {
      await _bloc.toggleLockMeeting(
        value: value,
        meetLinkName: widget.meetInfo.meetLinkName,
      );
      success = true;
    } catch (e) {
      caughtException = e as Exception;
      success = false;
    }

    if (!mounted) return success;

    if (caughtException != null) {
      if (caughtException is BridgeError_ApiResponse) {
        LocalToast.showErrorToast(context, caughtException.field0.error);
      } else {
        LocalToast.showErrorToast(context, caughtException.toString());
      }
    }

    if (success) {
      LocalToast.showToast(
        context,
        value
            ? context.local.meeting_locked_notification
            : context.local.meeting_unlocked_notification,
      );
    }
    return success;
  }

  Future<bool> _toggleWaitingRoomSetting({required bool value}) async {
    bool success = false;
    Exception? caughtException;

    try {
      await _bloc.toggleWaitingRoomSetting(
        value: value,
        meetLinkName: widget.meetInfo.meetLinkName,
      );
      success = true;
    } catch (e) {
      caughtException = e as Exception;
      success = false;
    }

    if (!mounted) return success;

    if (caughtException != null) {
      if (caughtException is BridgeError_ApiResponse) {
        LocalToast.showErrorToast(context, caughtException.field0.error);
      } else {
        LocalToast.showErrorToast(context, caughtException.toString());
      }
    }

    if (success) {
      context.showGlobalNotification(
        value
            ? context.local.waiting_room_enabled_notification
            : context.local.waiting_room_disabled_notification,
      );
    }
    return success;
  }

  Future<bool> _toggleLiveCaptionsAvailability(bool value) async {
    bool success = false;
    Exception? caughtException;

    try {
      await _bloc.toggleLiveCaptionsAvailabilityAsHost(
        value: value,
        meetLinkName: widget.meetInfo.meetLinkName,
      );
      success = true;
    } catch (e) {
      caughtException = e as Exception;
      success = false;
    }

    if (!mounted) return success;

    if (caughtException != null) {
      if (caughtException is BridgeError_ApiResponse) {
        LocalToast.showErrorToast(context, caughtException.field0.error);
      } else {
        LocalToast.showErrorToast(context, caughtException.toString());
      }
    }

    return success;
  }

  Future<void> leaveRoomDialog({
    bool isHost = false,
    bool isAlone = false,
  }) async {
    if (isAlone) {
      await _leaveRoom();
      return;
    }

    showLeaveRoomBottomSheet(
      context,
      onLeaveMeeting: () async {
        await _leaveRoom();
      },
      onEndMeetingForAll: () async {
        await _endMeetingForAll();
      },
      isHost: isHost,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Safety net: keep chat open state aligned if panel visibility changes
    // outside the toggle helpers (e.g. sheet dismiss callbacks).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncChatOpenWithSidePanel();
    });
    return MultiBlocProvider(
      providers: [
        BlocProvider<RoomBloc>(create: (context) => _bloc),
        BlocProvider<ChatBloc>.value(value: _chatBloc),
        BlocProvider<InRoomSettingsBloc>.value(value: _inRoomSettingsBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          if (widget.authBloc != null)
            BlocListener<AuthBloc, AuthState>(
              bloc: widget.authBloc,
              listenWhen: (prev, curr) => prev.isPaidUser != curr.isPaidUser,
              listener: (context, state) {
                _bloc.add(RoomIsPaidUserUpdated(isPaidUser: state.isPaidUser));
              },
            ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) => prev.isHost != curr.isHost,
            listener: (context, state) {
              _inRoomSettingsBloc.add(
                InRoomHostStatusUpdated(isHost: state.isHost),
              );
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) {
              final wasReady =
                  prev.isRoomInitialized && prev.isTrackInitialized;
              final isReady = curr.isRoomInitialized && curr.isTrackInitialized;
              return !wasReady && isReady;
            },
            listener: (context, state) {
              unawaited(_maybeShowInRoomMobileWarning(context));
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            // Show when both are true and at least one just became true. If
            // showMeetingIsReady is set in _onRoomInitialized before tracks are
            // sorted, isTrackInitialized flips later — the old listenWhen missed that.
            listenWhen: (prev, curr) =>
                curr.showMeetingIsReady &&
                curr.isTrackInitialized &&
                (!prev.showMeetingIsReady || !prev.isTrackInitialized),
            listener: (context, state) {
              if (state.showMeetingIsReady && state.isTrackInitialized) {
                showRoomReadyBottomSheet(
                  context,
                  meetingLink: state.meetingLink,
                  onCopied: () {},
                  onClosed: () {},
                );
              }
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                !prev.shouldShowWaitingRoomJoinRequestNotFoundError &&
                curr.shouldShowWaitingRoomJoinRequestNotFoundError,
            listener: (context, state) {
              LocalToast.showErrorToast(
                context,
                context.local.waiting_room_join_request_not_found,
              );
              _bloc.add(const WaitingRoomJoinRequestNotFoundErrorConsumed());
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                !prev.shouldShowLiveCaptionsSummonFailedError &&
                curr.shouldShowLiveCaptionsSummonFailedError,
            listener: (context, state) {
              LocalToast.showErrorToast(
                context,
                context.local.live_captions_summon_failed,
              );
              _bloc.add(const LiveCaptionsSummonFailedErrorConsumed());
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.waitingRoomParticipants.length !=
                curr.waitingRoomParticipants.length,
            listener: (context, state) {
              if (state.waitingRoomParticipants.isEmpty) {
                GlobalNotification.dismiss(
                  tag: _waitingRoomJoinRequestNotificationTag,
                );
                return;
              }
              context.showGlobalNotification(
                context.local.waiting_room_host_join_request_notification,
                duration: Duration.zero,
                showCloseButton: false,
                tag: _waitingRoomJoinRequestNotificationTag,
                onTap: () {
                  if (!mounted) {
                    return;
                  }
                  if (_openSidePanel != null) {
                    dismissRoomPanelBottomSheetIfPresent();
                  }
                  setState(() {
                    _openSidePanel = RoomSidePanel.participants;
                  });
                  _syncChatOpenWithSidePanel();
                },
              );
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.shouldShowMeetingWillEndDialog !=
                    curr.shouldShowMeetingWillEndDialog &&
                curr.shouldShowMeetingWillEndDialog,
            listener: (context, state) {
              if (state.shouldShowMeetingWillEndDialog) {
                // Show dialog
                showMeetingWillEndDialog(
                  context,
                  countdownSeconds: 30,
                  onStayInMeeting: () {
                    _bloc.add(StayInMeeting());
                  },
                  onLeaveMeeting: _leaveRoom,
                );
              }
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.shouldShowNotificationPermissionSettings !=
                    curr.shouldShowNotificationPermissionSettings &&
                curr.shouldShowNotificationPermissionSettings,
            listener: (context, state) async {
              await showNotificationPermissionSettingsDialog(
                context,
                onReturned: () {
                  unawaited(_showMeetingNotification());
                },
              );
              if (context.mounted) {
                _bloc.add(const NotificationPermissionSettingsConsumed());
              }
            },
          ),
          // Keep chat's notion of the local sender aligned across rejoins.
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.room.localParticipant?.identity !=
                curr.room.localParticipant?.identity,
            listener: (context, state) => _chatBloc.add(
              ChatLocalIdentityChanged(
                state.room.localParticipant?.identity ?? '',
              ),
            ),
          ),
          // Add chat message for all joined participants
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.joinedParticipants != curr.joinedParticipants,
            listener: (context, state) {
              final participantDetail = state.joinedParticipants.last;
              final meetingName = widget.meetInfo.meetName;
              addMessage(
                '',
                participantDetail.uuid,
                participantDetail.name,
                type: 'system',
                joinLeaveKind: ChatJoinLeaveKind.joined,
                meetingName: meetingName,
              );
            },
          ),
          // Reinitialize CallActivityActionChannel and listeners when room changes (e.g., after rejoin)
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.room != curr.room || prev.listener != curr.listener,
            listener: (context, state) async {
              // Cancel old listener if it exists
              if (_currentListener != null &&
                  _currentListener != state.listener) {
                try {
                  await _currentListener!.cancelAll();
                  await _currentListener!.dispose();
                } catch (e) {
                  l.logger.w('[RoomPage] Error disposing old listener: $e');
                }
              }

              // Update to new listener
              _currentListener = state.listener;

              // Re-setup listeners with new listener
              setUpListeners(_currentListener!);

              // Reinitialize CallActivityActionChannel
              final localParticipant = state.room.localParticipant;
              if (localParticipant != null) {
                CallActivityActionChannel.initialize(
                  state.room,
                  localParticipant,
                );
              }

              _registerNotificationEndCallCallback();
            },
          ),
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.leftParticipants != curr.leftParticipants,
            listener: (context, state) {
              final participantDetail = state.leftParticipants.last;
              // Add system message to chat bubble
              final meetingName = widget.meetInfo.meetName;
              addMessage(
                '',
                participantDetail.uuid,
                participantDetail.name,
                type: 'system',
                joinLeaveKind: ChatJoinLeaveKind.left,
                meetingName: meetingName,
              );
            },
          ),

          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.isLocalScreenSharing != curr.isLocalScreenSharing ||
                prev.isRemoteScreenSharing != curr.isRemoteScreenSharing,
            listener: (context, state) {
              final localShareJustStarted =
                  !_wasLocalScreenSharing && state.isLocalScreenSharing;
              final localShareJustStopped =
                  _wasLocalScreenSharing && !state.isLocalScreenSharing;
              _wasLocalScreenSharing = state.isLocalScreenSharing;

              if (localShareJustStopped) {
                unawaited(
                  _stopSharingTooltipController.hideTooltip(immediately: true),
                );
              }

              final nowSharing =
                  state.isLocalScreenSharing || state.isRemoteScreenSharing;
              setState(() {
                _isScreenSharing = nowSharing;
                if (nowSharing) {
                  // Auto move to screen sharing view on any share start
                  // (local or remote).
                  _isCameraView = false;
                }
              });

              if (localShareJustStarted) {
                _bloc.add(ResetAutoFullScreenTimer());
                unawaited(_maybeShowStopSharingTooltipOnce());
              }
            },
          ),
          // Show the consent modal once on every off→on transition. The
          // banner stays up for the whole duration; this listener only fires
          // on the *edge*.
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                !prev.isRecordingInProgress &&
                curr.isRecordingInProgress &&
                !curr.isLocalParticipantRecording,
            listener: (context, state) {
              context.showRecordingStatusChangedDialog(
                onLeaveMeeting: () async {
                  await _leaveRoom();
                },
              );
            },
          ),
        ],
        child: RoomReconnectionListeners(
          onLeaveRoom: _leaveRoom,
          child: PopScope(
            canPop: false,
            child: BlocSelector<RoomBloc, RoomState, (bool, bool)>(
              selector: (state) =>
                  (state.isRoomInitialized, state.isTrackInitialized),
              builder: (context, data) {
                final isRoomInitialized = data.$1;
                final isTrackInitialized = data.$2;
                final isRoomReady = isRoomInitialized && isTrackInitialized;
                if (isRoomReady && !desktop) {
                  _bloc.add(StartAutoFullScreenTimer());
                }
                return TestId(
                  id: TestIds.roomScreen,
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    backgroundColor: context.colors.interActionWeakMinor3,
                    floatingActionButton: desktop || !_showRotationButton
                        ? null
                        : TestId(
                            id: TestIds.roomRotate,
                            button: true,
                            child: FloatingActionButton(
                              backgroundColor: context.colors.protonBlue
                                  .withValues(alpha: 0.5),
                              onPressed: () async {
                                setState(() {
                                  _isLandscape = !_isLandscape;
                                });
                                if (_isLandscape) {
                                  await SystemChrome.setPreferredOrientations([
                                    DeviceOrientation.landscapeRight,
                                  ]);
                                } else {
                                  await SystemChrome.setPreferredOrientations([
                                    DeviceOrientation.portraitUp,
                                  ]);
                                }
                              },
                              child: Icon(Icons.screen_rotation_rounded),
                            ),
                          ),
                    floatingActionButtonLocation:
                        OffsetFloatingActionButtonLocation(
                          FloatingActionButtonLocation.endFloat,
                          const Offset(
                            0,
                            -135,
                          ), // move top 135 to avoid overflow on control bar
                        ),
                    body: SafeArea(
                      child: Stack(
                        children: [
                          ColoredBox(
                            color: context.colors.interActionWeakMinor3,
                            child: ResponsiveV2(xlarge: buildMobile(context)),
                          ),
                          // Show loading overlay when room is not initialized
                          if (!isRoomReady)
                            Positioned.fill(
                              child: ColoredBox(
                                color: context.colors.interActionWeakMinor3,
                                child: ResponsiveV2(
                                  xlarge: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 600,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          LoadingView(
                                            title: "Launching Meeting...",
                                            description:
                                                widget
                                                        .meetInfo
                                                        .participantsCount >
                                                    0
                                                ? 'Joining meeting with ${widget.meetInfo.participantsCount} other participants'
                                                : 'Starting meeting as the first participant',
                                            // To-do: check with designer to see if we need to show the different description for it
                                            // description: context
                                            //     .local
                                            //     .room_initialing_hint,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMobile(BuildContext context) {
    // In PIP mode, show special layouts since screen will be small
    return BlocSelector<RoomBloc, RoomState, (bool, Room)>(
      selector: (state) => (state.isPipMode, state.room),
      builder: (context, data) {
        final isPipMode = data.$1;
        final room = data.$2;
        // Android: shrink in-app UI. iOS: system PiP window (native video, no Flutter controls).
        if (isPipMode && android) {
          return PipView(room: room, isScreenSharing: _isScreenSharing);
        }
        return _buildNormalMobileView(context);
      },
    );
  }

  Widget _buildCameraMediaContent(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      (
        List<ParticipantInfo> participantTracks,
        List<ParticipantInfo> speakerTracks,
        Map<String, bool> raisedHandsByIdentity,
        String iosPipRemoteCameraSubscriptionIdentity,
      )
    >(
      selector: (state) => (
        state.participantTracks,
        state.speakerTracks,
        state.raisedHandsByIdentity,
        state.iosPipRemoteCameraSubscriptionIdentity,
      ),
      builder: (context, data) =>
          buildCameraLayout(context, data.$1, data.$2, data.$3, data.$4),
    );
  }

  Widget _buildScreenSharingMediaContent(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      (
        int index,
        List<ParticipantInfo> tracks,
        bool isFullScreen,
        Map<String, bool> raisedHandsByIdentity,
      )
    >(
      selector: (state) => (
        state.screenSharingIndex,
        state.screenSharingTracks,
        state.isFullScreen,
        state.raisedHandsByIdentity,
      ),
      builder: (context, state) {
        final tracks = state.$2;
        final index = state.$1;
        final isFullScreen = state.$3;
        final raisedHandsByIdentity = state.$4;

        if (tracks.isEmpty) {
          return const SizedBox.shrink();
        }

        final safeIndex = min(index, tracks.length - 1);

        _ensureScreenShareSubscribed(tracks[safeIndex].participant);
        final showLowerHand =
            _bloc.state.isLocalParticipantAdminOrHost &&
            _bloc.isMeetAdminLowerHandEnabled();

        return GestureDetector(
          onTap: () {
            if (!_bloc.state.isFullScreen) {
              _enterMobileFullScreen();
            } else {
              _resetAutoFullScreenTimer();
            }
          },
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: ParticipantWidget.widgetFor(
              context.width,
              context.height,
              getParticipantDisplayColors(
                context,
                tracks[safeIndex].participant.identity.hashCode,
              ),
              tracks[safeIndex],
              showStatsLayer: false,
              roundedBorder: false,
              isFullScreen: isFullScreen,
              reaction:
                  _activeReactions[tracks[safeIndex].participant.identity],
              isRaisedHand:
                  raisedHandsByIdentity[tracks[safeIndex]
                      .participant
                      .identity] ==
                  true,
              onLowerHand: showLowerHand
                  ? () {
                      unawaited(
                        publishAdminLowerHand(
                          tracks[safeIndex].participant.identity,
                        ),
                      );
                    }
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget? _buildActiveSidePanel(BuildContext context) {
    switch (_openSidePanel) {
      case RoomSidePanel.participants:
        return buildParticipantList(context);
      case RoomSidePanel.chat:
        return buildChatBubble(context);
      case RoomSidePanel.settings:
        return buildMeetingSettings(context);
      case RoomSidePanel.meetingInfo:
        return buildMeetingInfo(context);
      case null:
        return null;
    }
  }

  Widget _buildMediaArea(BuildContext context) {
    final mediaContent = (!_isScreenSharing || _isCameraView)
        ? _buildCameraMediaContent(context)
        : _buildScreenSharingMediaContent(context);
    return RoomConnectionAwareMediaArea(child: mediaContent);
  }

  Widget _buildMediaGestureWrapper(BuildContext context, Widget child) {
    return GestureDetector(
      onTap: () {
        if (!_bloc.state.isFullScreen) {
          _enterMobileFullScreen();
        } else {
          _resetAutoFullScreenTimer();
        }
      },
      onPanStart: (_) => _resetAutoFullScreenTimer(),
      onPanUpdate: (_) => _resetAutoFullScreenTimer(),
      child: child,
    );
  }

  /// Narrow layout: media plus optional bottom-sheet panel host.
  Widget _buildNarrowMainContent(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildMediaArea(context)),
        ?_buildActiveSidePanel(context),
      ],
    );
  }

  /// Builds the main content area (without controls bar)
  /// This is shared between mobile and desktop views
  Widget _buildMainContent(BuildContext context) {
    return _buildNarrowMainContent(context);
  }

  Widget _buildNormalMobileView(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      (Room, bool, bool, bool, bool, bool)
    >(
      selector: (state) => (
        state.room,
        state.isPipMode,
        state.isRoomInitialized,
        state.isTrackInitialized,
        state.isCameraEnabled,
        state.isPaidUser,
      ),
      builder: (context, data) {
        final room = data.$1;
        final isPipMode = data.$2;
        final isRoomInitialized = data.$3;
        final isTrackInitialized = data.$4;
        final isCameraEnabled = data.$5;
        final isPaidUser = data.$6;
        final isRoomReady = isRoomInitialized && isTrackInitialized;
        final header = (!isPipMode && isRoomReady)
            ? _buildHeaderWithSlide(
                context: context,
                room: room,
                isCameraEnabled: isCameraEnabled,
                isPaidUser: isPaidUser,
              )
            : null;

        return LayoutBuilder(
          builder: (context, constraints) {
            final useSideRail = roomSidePanelUsesSideRail(constraints.maxWidth);
            final sidePanel = _buildActiveSidePanel(context);

            return Column(
              children: [
                const RecordingTopBanner(),
                ?header,
                Expanded(
                  child: useSideRail
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _withLiveCaptionsSheet(
                                context,
                                RepaintBoundary(
                                  child: _buildMediaGestureWrapper(
                                    context,
                                    _buildMediaArea(context),
                                  ),
                                ),
                              ),
                            ),
                            RoomAnimatedSideRail(
                              isOpen: _openSidePanel != null,
                              panel: _openSidePanel,
                              panelWidth: roomSidePanelWidth,
                              child: sidePanel ?? const SizedBox.shrink(),
                            ),
                          ],
                        )
                      : _withLiveCaptionsSheet(
                          context,
                          _buildMediaGestureWrapper(
                            context,
                            _buildMainContent(context),
                          ),
                        ),
                ),
                if (room.localParticipant != null) _buildControlsBarWithFade(),
              ],
            );
          },
        );
      },
    );
  }

  /// In-app picker with previews ([MeetScreenSelectDialog]). On Linux Wayland
  /// the xdg-desktop-portal dialog is the picker, since enumerating sources
  /// crashes libwebrtc there.
  Future<ScreenSharePickerResult?> _pickDesktopScreenShareSource(
    BuildContext context,
  ) async {
    if (linuxWayland) {
      return const ScreenSharePickerResult.systemPortal();
    }
    return MeetScreenSelectDialog.show(
      context,
      titleText: context.local.share_screen,
      screenTabText: 'Entire screen',
      cancelText: context.local.cancel,
      shareText: context.local.share_screen,
    );
  }

  void _dispatchDesktopScreenSharePick(
    ScreenSharePickerResult pick, {
    required String notificationTitle,
    required String notificationText,
  }) {
    _bloc.add(
      ToggleScreenShare(
        screenShareSourceId: pick.useSystemPortal ? null : pick.sourceId,
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      ),
    );
  }

  Future<void> _onToggleScreenSharePressed(BuildContext context) async {
    if (!_bloc.isScreenShareFeatureEnabled()) return;

    if (_bloc.state.isLocalScreenSharing) {
      _bloc.add(const ToggleScreenShare());
      return;
    }

    final notificationTitle = context.local.screen_sharing;
    final notificationText = context.local.sharing_your_screen;

    if (lkPlatformIsDesktop()) {
      final pick = await _pickDesktopScreenShareSource(context);
      if (!context.mounted || pick == null) return;
      _dispatchDesktopScreenSharePick(
        pick,
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      );
      return;
    }

    _bloc.add(
      ToggleScreenShare(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      ),
    );
  }

  Widget _buildHeaderWithSlide({
    required BuildContext context,
    required Room room,
    required bool isCameraEnabled,
    required bool isPaidUser,
  }) {
    return BlocSelector<RoomBloc, RoomState, (bool, bool)>(
      selector: (state) => (
        state.isLocalScreenSharing || state.isRemoteScreenSharing,
        state.isFullScreen,
      ),
      builder: (context, data) {
        final isScreenSharing = data.$1;
        final isFullScreen = data.$2;
        // Slide header away in fullscreen on mobile only.
        final shouldHide = !desktop && isFullScreen;
        final headerHeight = RoomTopBar.totalHeight(context);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: shouldHide ? 0 : headerHeight,
          child: ClipRect(
            child: RoomTopBar(
              shareScreenWidget: isScreenSharing
                  ? buildPanelWhenScreenSharing(context, room.localParticipant)
                  : null,
              roomName: widget.meetInfo.meetName,
              onSwapCamera: () {
                _bloc.add(SwapCamera());
              },
              showSwapCamera:
                  !context.isAtLeastMedium &&
                  _videoInputs.length >= 2 &&
                  isCameraEnabled,
              isPaidUser: isPaidUser,
              showSpeakerButton:
                  !context.isAtLeastMedium &&
                  _bloc.state.isMeetMobileSpeakerToggleEnabled,
              onSpeakerButtonPressed: () {
                _openSpeakerPhonePanel(context);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsBarWithFade() {
    return BlocSelector<RoomBloc, RoomState, bool>(
      selector: (state) => state.isFullScreen,
      builder: (context, isFullScreen) {
        final shouldHide = !desktop && isFullScreen;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: shouldHide ? 0 : bottomControlHeight,
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(0, shouldHide ? bottomControlHeight : 0),
              child: IgnorePointer(
                ignoring: shouldHide,
                child: buildControlsBar(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _buildRecordingControls(RoomState state) {
    if (!_bloc.isMeetMeetingRecordingNativeEnabled()) {
      return null;
    }

    if (!state.isLocalParticipantAdminOrHost) {
      return null;
    }

    VoidCallback? upsellTap;
    if (!state.isPaidUser) {
      upsellTap = () {
        LocalToast.showToastification(
          context,
          context.local.start_recording,
          context.local.recording_paid_feature,
        );
      };
    }

    return RecordingControls(
      meetingRecorder: _meetingRecorder!,
      showUpsellOnTap: state.isPaidUser ? null : upsellTap,
    );
  }

  /// Floats the captions sheet over the media area, leaving the controls bar
  /// reachable. Taps outside the sheet fall through to [child].
  Widget _withLiveCaptionsSheet(BuildContext context, Widget child) {
    final withReactionStream = Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: ReactionStream(
              activeReactions: _activeReactions,
              localParticipantIdentity:
                  _bloc.state.room.localParticipant?.identity,
              displayNameForIdentity: _reactionStreamDisplayName,
            ),
          ),
        ),
      ],
    );
    if (!_bloc.isMeetLiveCaptionsEnabled()) {
      return withReactionStream;
    }
    return Stack(
      children: [
        Positioned.fill(child: withReactionStream),
        Positioned.fill(child: _buildLiveCaptionsSheet(context)),
      ],
    );
  }

  String _reactionStreamDisplayName(String identity) {
    final fromMap = _bloc.state.frbParticipantsMap[identity]?.displayName;
    if (fromMap != null && fromMap.isNotEmpty) {
      return fromMap;
    }
    final participant = _participantWithIdentity(identity);
    if (participant != null) {
      return _bloc.getParticipantDisplayName(participant);
    }
    return '';
  }

  Widget _buildLiveCaptionsSheet(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      (bool, Transcriptions, Map<String, MeetParticipant>)
    >(
      selector: (state) => (
        state.liveCaptionsWanted,
        state.liveCaptionsTranscriptions,
        state.frbParticipantsMap,
      ),
      builder: (context, data) {
        if (!data.$1) {
          return const SizedBox.shrink();
        }
        return LiveCaptionsSheet(
          transcriptions: data.$2,
          participantNamesByIdentity: data.$3,
          onSave: () => _copyLiveCaptionsHistory(context, data.$3),
          onOpenSettings: _bloc.isMeetLiveCaptionsLanguageSelectorEnabled()
              ? () => _openLiveCaptionsSettings(context)
              : null,
        );
      },
    );
  }

  Future<void> _copyLiveCaptionsHistory(
    BuildContext context,
    Map<String, MeetParticipant> participantNamesByIdentity,
  ) async {
    final text = _bloc.formatLiveCaptionsHistoryForClipboard(
      participantNamesByIdentity,
    );
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      LocalToast.showToast(context, context.local.copied_to_clipboard);
    }
  }

  void _openLiveCaptionsSettings(BuildContext context) {
    if (!_bloc.isMeetLiveCaptionsLanguageSelectorEnabled()) {
      return;
    }
    if (_bloc.state.isLiveCaptionsPreferenceWriteInFlight) {
      return;
    }
    showLiveCaptionLanguagePicker(
      context,
      selectedLanguage: _bloc.state.liveCaptionLanguage,
      onLanguageSelected: _handleLiveCaptionLanguageSelected,
    );
  }

  /// Controls overflow menu: same enable/disable flow as meeting settings.
  void _toggleLiveCaptions() {
    unawaited(
      _handleLiveCaptionsToggleChanged(
        enabled: !_bloc.state.liveCaptionsWanted,
      ),
    );
  }

  Future<void> _handleLiveCaptionsToggleChanged({required bool enabled}) async {
    final roomState = _bloc.state;
    if (enabled && !roomState.liveCaptionsAvailableForParticipants) {
      if (!mounted) return;
      LocalToast.showWarningToast(
        context,
        context.local.live_captions_disabled_by_host,
      );
      return;
    }
    if (enabled) {
      final confirmed = await showLiveCaptionsEnableDialog(context);
      if (!mounted || confirmed != true) {
        return;
      }
    }
    _bloc.add(SetLiveCaptionsWanted(enabled: enabled));
  }

  Future<void> _handleLiveCaptionLanguageSelected(String language) async {
    _bloc.add(SetLiveCaptionLanguage(language: language));
  }

  Widget buildControlsBar() {
    return BlocSelector<RoomBloc, RoomState, RoomState>(
      selector: (state) {
        return state;
      },
      builder: (context, state) {
        return BlocSelector<ChatBloc, ChatState, int>(
          selector: (chatState) => chatState.unreadCount,
          builder: (context, chatUnreadCount) =>
              _buildControlsBarBody(context, state, chatUnreadCount),
        );
      },
    );
  }

  Widget _buildControlsBarBody(
    BuildContext context,
    RoomState state,
    int chatUnreadCount,
  ) {
    return SizedBox(
      width: context.width,
      height: bottomControlHeight,
      child: ResponsiveControlsBar(
        room: state.room,
        backgroundColor: context.colors.interActionWeakMinor3,
        onLeave: () {
          // Only show the "End meeting for all" button when the local
          // participant is the only host in the meeting.
          leaveRoomDialog(isHost: state.isOnlyHost, isAlone: state.isAlone);
        },
        cameraResolution: _cameraResolution,
        cameraMaxBitrate: _cameraMaxBitrate,
        currentCameraPosition: state.currentCameraPosition,
        cameraBackgroundSelection: state.cameraBackgroundSelection,
        applyAudioDenoise: state.audioDenoiseEnabled,
        recordingControls: _buildRecordingControls(state),
        trailing: state.isLocalScreenSharing
            ? CustomTooltip(
                controller: _stopSharingTooltipController,
                triggerMode: TooltipTriggerMode.manual,
                message: context.local.tap_to_stop_sharing,
                child: Material(
                  color: context.colors.signalDangerMajor3,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _bloc.add(ToggleScreenShare()),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: context.images.iconScreenShare.svg(
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            context.colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        audioDenoiseType: state.audioDenoiseType,
        optionalActionsBuilder: () {
          final isSpeakerMuted = state.isSpeakerMuted ?? false;

          // Screen share toggle. We build two slightly different
          // `ControlAction`s rather than one shared instance:
          //   - `unshareAction` is shown at the very FRONT of the row
          //     while we are actively presenting, and carries the
          //     showcase GlobalKey (so the tutorial tip points at it).
          //   - `shareAction` is shown in the default slot otherwise,
          //     and intentionally has NO globalKey (preventing the
          //     showcase from latching onto the "Share screen" button
          //     when there is nothing to stop).
          final isScreenShareEnabled = _bloc.isScreenShareFeatureEnabled();
          void onScreenShareTapped() {
            unawaited(_onToggleScreenSharePressed(context));
          }

          final shareAction = isScreenShareEnabled
              ? ControlAction(
                  icon: context.images.iconScreenShare.svg(
                    width: 24,
                    height: 24,
                  ),
                  tooltip: context.local.share_screen,
                  onPressed: onScreenShareTapped,
                  isActive: true,
                  testId: TestIds.roomScreenShare,
                )
              : null;

          return [
            /// Mute speaker
            ControlAction(
              testId: TestIds.roomSpeakerMute,
              activeIcon: context.images.iconSpeakerOn.svg(
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  context.colors.textNorm,
                  BlendMode.srcIn,
                ),
              ),
              icon: context.images.iconSpeakerOff.svg(
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  context.colors.textNorm,
                  BlendMode.srcIn,
                ),
              ),
              tooltip: isSpeakerMuted ? 'Unmute speaker' : 'Mute speaker',
              onPressed: () {
                _bloc.add(ToggleSpeaker());
              },
              isActive: !isSpeakerMuted,
              inactiveBackgroundColor: context.colors.signalDangerMajor3,
            ),

            /// Emoji reactions
            if (state.room.localParticipant != null)
              ControlAction(
                testId: TestIds.roomReactions,
                icon: Icon(Icons.emoji_emotions_outlined, size: 24),
                tooltip: context.local.emoji_reactions,
                onPressed: () {
                  unawaited(_showEmojiReactionMenu());
                },
              ),

            /// PiP - only show if supported and feature flag is enabled
            if (_bloc.isPictureInPictureFeatureEnabled() &&
                state.pipAvailable == true)
              ControlAction(
                testId: TestIds.roomPip,
                icon: const Icon(Icons.picture_in_picture),
                tooltip: context.local.enter_pip,
                onPressed: () {
                  _bloc.add(EnterPipMode(backgroundApp: iOS));
                },
              ),

            /// Screen share (start) — hidden while sharing; the stop
            /// control lives in the controls bar as the second-to-last
            /// button (right before the leave button).
            if (!state.isLocalScreenSharing && shareAction != null) shareAction,

            /// Live captions — toggled from the controls bar.
            if (_bloc.isMeetLiveCaptionsEnabled() &&
                state.room.localParticipant != null)
              ControlAction(
                testId: TestIds.roomLiveCaptions,
                icon: context.images.iconLiveCaption.svg24(
                  color: context.colors.textNorm,
                ),
                activeIcon: context.images.iconLiveCaption.svg24(
                  color: context.colors.interActionNorm,
                ),
                tooltip: state.liveCaptionsWanted
                    ? context.local.live_captions_turn_off
                    : context.local.live_captions_turn_on,
                isActive: state.liveCaptionsWanted,
                onPressed: () {
                  if (state.isLiveCaptionsPreferenceWriteInFlight) {
                    return;
                  }
                  _toggleLiveCaptions();
                },
              ),

            /// Participants
            ControlAction(
              testId: TestIds.roomParticipants,
              icon: context.images.iconParticipants.svg24(),
              badge: '${state.currentParticipantCount}',
              tooltip:
                  '${context.local.show_participants_list} (${state.currentParticipantCount})',
              onPressed: () => _toggleSidePanel(RoomSidePanel.participants),
            ),

            /// Chat
            ControlAction(
              testId: TestIds.roomChat,
              icon: context.images.iconChat.svg(width: 24, height: 24),
              tooltip:
                  context.local.show_chatroom +
                  (chatUnreadCount > 0 ? ' ($chatUnreadCount)' : ''),
              badge: chatUnreadCount > 0 ? chatUnreadCount.toString() : null,
              onPressed: () => _toggleSidePanel(RoomSidePanel.chat),
            ),

            /// Settings
            ControlAction(
              testId: TestIds.roomSettings,
              icon: context.images.iconSettings.svg(width: 24, height: 24),
              tooltip: context.local.show_settings,
              onPressed: () => _toggleSidePanel(RoomSidePanel.settings),
            ),

            /// Info
            ControlAction(
              testId: TestIds.roomInfo,
              icon: context.images.iconInfo.svg(width: 24, height: 24),
              tooltip: context.local.meeting_info,
              onPressed: () => _toggleSidePanel(RoomSidePanel.meetingInfo),
            ),
          ];
        },
      ),
    );
  }

  Widget buildParticipantsCameraWehnScreenSharing(BuildContext context) {
    final participantTracksWhenScreenSharing = _bloc
        .getParticipantTracksWhenScreenSharing();
    final showLowerHand =
        _bloc.state.isLocalParticipantAdminOrHost &&
        _bloc.isMeetAdminLowerHandEnabled();
    if (_layout == CameraLayout.speaker ||
        _layout == CameraLayout.mutliSpeaker) {
      if (participantTracksWhenScreenSharing.isEmpty) {
        return SizedBox(
          width: 160,
          child: Center(child: Text(context.local.no_active_speaker)),
        );
      }
    }
    if (_layout == CameraLayout.grid) {
      return SizedBox(
        width: 160,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: max(0, participantTracksWhenScreenSharing.length),
          itemBuilder: (BuildContext context, int index) => Container(
            padding: const EdgeInsets.all(4),
            width: 160,
            height: 200,
            child: Container(
              margin: const EdgeInsets.all(0.3),
              child: ParticipantWidget.widgetFor(
                152,
                192,
                getParticipantDisplayColors(
                  context,
                  participantTracksWhenScreenSharing[index]
                      .participant
                      .identity
                      .hashCode,
                ),
                participantTracksWhenScreenSharing[index],
                showStatsLayer: false,
                reaction:
                    _activeReactions[participantTracksWhenScreenSharing[index]
                        .participant
                        .identity],
                isRaisedHand:
                    _bloc
                        .state
                        .raisedHandsByIdentity[participantTracksWhenScreenSharing[index]
                        .participant
                        .identity] ==
                    true,
                onLowerHand: showLowerHand
                    ? () {
                        unawaited(
                          publishAdminLowerHand(
                            participantTracksWhenScreenSharing[index]
                                .participant
                                .identity,
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 160,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: max(0, participantTracksWhenScreenSharing.length),
        itemBuilder: (BuildContext context, int index) => SizedBox(
          width: 160,
          height: 90,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 0.5, vertical: 1.2),
            child: ParticipantWidget.widgetFor(
              160,
              90,
              getParticipantDisplayColors(
                context,
                participantTracksWhenScreenSharing[index]
                    .participant
                    .identity
                    .hashCode,
              ),
              participantTracksWhenScreenSharing[index],
              showStatsLayer: false,
              reaction:
                  _activeReactions[participantTracksWhenScreenSharing[index]
                      .participant
                      .identity],
              isRaisedHand:
                  _bloc
                      .state
                      .raisedHandsByIdentity[participantTracksWhenScreenSharing[index]
                      .participant
                      .identity] ==
                  true,
              onLowerHand: showLowerHand
                  ? () {
                      unawaited(
                        publishAdminLowerHand(
                          participantTracksWhenScreenSharing[index]
                              .participant
                              .identity,
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  /// Shows the "tap to stop sharing" tooltip only the first time the local
  /// participant ever starts a screen share. The shown state is persisted in
  /// SharedPreferences so it is never displayed again on subsequent shares.
  Future<void> _maybeShowStopSharingTooltipOnce() async {
    final prefs = ManagerFactory().get<PreferencesManager>();
    final alreadyShown = await prefs.getStopSharingTooltipShown();
    if (alreadyShown) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_bloc.state.isLocalScreenSharing) return;
      unawaited(_stopSharingTooltipController.showTooltip(immediately: true));
      // Persist only once the tooltip has actually been shown.
      unawaited(prefs.setStopSharingTooltipShown(shown: true));
    });
  }

  Widget buildPanelWhenScreenSharing(
    BuildContext context,
    LocalParticipant? participant,
  ) {
    return Padding(
      padding: _screenSharePanelPadding,
      child: BlocSelector<RoomBloc, RoomState, List<ParticipantInfo>>(
        selector: (state) => state.screenSharingTracks,
        builder: (context, tracks) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tracks.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isCameraView = true;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      alignment: Alignment.center,
                      padding: _screenSharePanelPadding,
                      decoration: BoxDecoration(
                        color: _isCameraView
                            ? context.colors.interActionWeak
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.colors.textWeak),
                      ),
                      child: Text(
                        context.local.camera_view,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                for (int i = 0; i < tracks.length; i++)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isCameraView = false;
                        _screenSharingIndex = i;
                      });
                      _enterMobileFullScreen();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      alignment: Alignment.center,
                      padding: _screenSharePanelPadding,
                      decoration: BoxDecoration(
                        color: (i == _screenSharingIndex && !_isCameraView)
                            ? context.colors.interActionWeak
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.colors.textWeak),
                      ),
                      child: Text(
                        '🖥️ ${_bloc.getParticipantDisplayName(tracks[i].participant)} ${context.local.is_presenting}',
                        overflow: TextOverflow.ellipsis,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void showAllStatsDialog(BuildContext context) {
    // Get all participants (local + remote)
    final room = _bloc.state.room;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) {
      return;
    }
    final List<Participant> allParticipants = [
      localParticipant,
      ...room.remoteParticipants.values,
    ];

    StatisticsDialog.showAllParticipantsStats(context, allParticipants);
  }

  Widget _wrapSidePanel({required RoomSidePanel panel, required Widget child}) {
    final maxWidth =
        roomSidePanelUsesSideRail(MediaQuery.of(context).size.width)
        ? roomSidePanelWidth
        : double.infinity;
    return SidePanelOrSheet(
      key: ValueKey(panel),
      isScreenSharing: _isScreenSharing,
      isCameraView: _isCameraView,
      maxWidth: maxWidth,
      sheetBlocProviders: [
        BlocProvider<InRoomSettingsBloc>.value(value: _inRoomSettingsBloc),
      ],
      child: child,
      onDismissed: () {
        if (_openSidePanel != panel) return;
        _closeSidePanel();
      },
    );
  }

  Widget buildParticipantList(BuildContext context) {
    return _wrapSidePanel(
      panel: RoomSidePanel.participants,
      child: buildParticipantListContent(context),
    );
  }

  Widget buildChatBubble(BuildContext context) {
    return _wrapSidePanel(
      panel: RoomSidePanel.chat,
      child: buildChatBubbleContent(context),
    );
  }

  Widget buildMeetingSettings(BuildContext context) {
    return BlocSelector<RoomBloc, RoomState, bool>(
      selector: (state) => state.isHost,
      builder: (context, isHost) {
        return _wrapSidePanel(
          panel: RoomSidePanel.settings,
          child: buildMeetingSettingsContent(context, isHost: isHost),
        );
      },
    );
  }

  Widget buildMeetingInfo(BuildContext context) {
    return _wrapSidePanel(
      panel: RoomSidePanel.meetingInfo,
      child: buildMeetingInfoContent(context),
    );
  }

  Widget buildMeetingInfoContent(BuildContext context) {
    // Get meeting info from widget
    final meetingTitle = widget.meetInfo.meetName;
    return SizedBox.expand(
      child: MeetingInfoPanel(
        meetingTitle: meetingTitle,
        meetingDate: widget.meetLink.formatStartDateTime(
          context,
          useLocalTimezone: true,
        ),
        meetingTime: widget.meetLink.formatStartOnlyTime(
          context,
          useLocalTimezone: true,
        ),
        participantsCount: _bloc.state.room.remoteParticipants.length,
      ),
    );
  }

  void _openSpeakerPhonePanel(BuildContext context) {
    final roomBloc = context.read<RoomBloc>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (BuildContext context) {
        return BlocProvider<RoomBloc>.value(
          value: roomBloc,
          child: SafeArea(
            child: IntrinsicHeight(child: const SpeakerPhonePanel()),
          ),
        );
      },
    );
  }

  Widget buildChatBubbleContent(BuildContext context) {
    return BlocSelector<RoomBloc, RoomState, (List<ParticipantInfo>, Room)>(
      selector: (s) => (s.participantTracks, s.room),
      builder: (context, data) {
        final room = data.$2;
        final localId = room.localParticipant?.identity ?? '';
        return ChatBubble(
          controller: _chatController,
          userIdentity: localId,
          userName: widget.displayName,
          chatThreadsEnabled: _chatThreadsEnabled,
          chatMentionsEnabled: _chatMentionsEnabled,
          onSend: sendChatMessage,
          onToggleReaction: toggleChatReaction,
          onRetry: _retryChatMessage,
          onDiscard: (m) => _chatBloc.add(ChatMessageDiscarded(m.id)),
          participantTracks: data.$1,
        );
      },
    );
  }

  /// Local camera feed used to preview background choices inside the sheet.
  ///
  /// Null while the camera is off: muting leaves the publication and its track
  /// in place, so without the mute check the sheet would render a live-looking
  /// preview from a camera the user has already turned off.
  VideoTrack? get _localCameraTrack {
    final lp = _bloc.state.room.localParticipant;
    if (lp == null) {
      return null;
    }
    for (final pub in lp.videoTrackPublications) {
      if (pub.isScreenShare || pub.muted) {
        continue;
      }
      final track = pub.track;
      if (track is LocalVideoTrack) {
        return track;
      }
    }
    return null;
  }

  /// Camera feed shown only inside the background sheet, while the in-room
  /// camera is off.
  ///
  /// Deliberately never published: unmuting to get a preview would light up the
  /// user's tile for everyone else and flip room state that they did not ask to
  /// change. This track is created when the sheet opens, rendered locally, and
  /// stopped again on close, so nothing reaches remote participants.
  Future<LocalVideoTrack?> _createSheetPreviewTrack(
    CameraBackgroundSelection selection,
  ) async {
    try {
      final track = await LocalVideoTrackHelper.cameraTrack(
        parameters: VideoParametersPresets.h720_169,
        backgroundSelection: selection,
      );
      await track.start();
      return track;
    } catch (e) {
      l.logger.w('[RoomPage] preview-only camera track failed: $e');
      return null;
    }
  }

  Future<void> _clearNativeReplacementBackground() async {
    if (kIsWeb) {
      return;
    }
    try {
      await ProtonVideoEffects.instance.clearReplacementBackground();
    } catch (_) {}
  }

  Future<void> _stopSheetPreviewTrack(LocalVideoTrack track) async {
    final trackId = track.mediaStreamTrack.id;
    if (trackId != null && trackId.isNotEmpty) {
      try {
        await ProtonVideoEffects.instance.detachBackgroundBlur(
          trackId: trackId,
        );
      } catch (_) {}
    }
    try {
      await track.stop();
    } catch (_) {}
  }

  Future<void> _openVirtualBackgroundSheet(
    BuildContext context,
    CameraBackgroundSelection current,
  ) async {
    final published = _localCameraTrack;
    // Null means the camera is muted, so borrow an unpublished one purely for
    // the preview rather than leaving the sheet blank.
    final previewOnly = published == null
        ? await _createSheetPreviewTrack(current)
        : null;
    try {
      if (!context.mounted) {
        return;
      }
      final selection = await VirtualBackgroundSheet.show(
        context,
        initialSelection: current,
        previewTrack: published ?? previewOnly,
      );
      if (selection == null || selection == current) {
        return;
      }
      _bloc.add(SetCameraBackgroundSelection(selection));
    } finally {
      if (previewOnly != null) {
        await _stopSheetPreviewTrack(previewOnly);
      }
    }
  }

  Widget buildMeetingSettingsContent(
    BuildContext context, {
    bool isHost = false,
  }) {
    final showCameraBackground =
        !kIsWeb &&
        ManagerFactory()
            .get<DataProviderManager>()
            .unleashDataProvider
            .isMeetCameraBackgroundBlur();
    final showAudioDenoiseCandidate =
        !kIsWeb && DenoiseAudioService.instance.isAvailable;
    return FutureBuilder(
      future: showAudioDenoiseCandidate
          ? DenoiseAudioService.instance.listAvailableTypesForUi()
          : Future.value(const <DenoiseTypeInfo>[]),
      builder: (context, denoiseTypesSnapshot) {
        final denoiseTypeInfos = denoiseTypesSnapshot.data ?? const [];
        final showAudioDenoise =
            showAudioDenoiseCandidate && denoiseTypeInfos.isNotEmpty;
        final denoiseTypeOptions = denoiseTypeInfos
            .map((info) => DenoiseTypeUiOption(type: info.type))
            .toList();
        return BlocSelector<
          RoomBloc,
          RoomState,
          (bool, bool, CameraBackgroundSelection, bool, DenoiseType, bool, bool)
        >(
          selector: (state) => (
            state.isRejoining,
            state.forceShowConnectionStatusBanner,
            state.cameraBackgroundSelection,
            state.audioDenoiseEnabled,
            state.audioDenoiseType,
            state.isPaidUser,
            state.liveCaptionsAvailableForParticipants,
          ),
          builder: (context, data) {
            final isRejoining = data.$1;
            final forceShowConnectionStatusBanner = data.$2;
            final cameraBackgroundSelection = data.$3;
            final audioDenoiseEnabled = data.$4;
            final storedAudioDenoiseType = data.$5;
            final isPaidUser = data.$6;
            final liveCaptionsAvailableForParticipants = data.$7;
            final showLiveCaptions = _bloc.isMeetLiveCaptionsEnabled();
            final selectedAudioDenoiseType =
                denoiseTypeOptions.any((o) => o.type == storedAudioDenoiseType)
                ? storedAudioDenoiseType
                : denoiseTypeOptions.firstOrNull?.type;
            final showConnectionSettings =
                _bloc.isMeetAutoReconnectionEnabled() &&
                _bloc.isMeetMobileEnableNetworkToolEnabled();
            return InRoomSettingsBindingsSync(
              bloc: _inRoomSettingsBloc,
              bindings: InRoomSettingsBindingsUpdated(
                isHost: isHost,
                isPaidUser: isPaidUser,
                showLiveCaptions: showLiveCaptions,
                liveCaptionsAvailableForParticipants:
                    liveCaptionsAvailableForParticipants,
                incomingVideoEnabled: !_unsubscribeVideoByDefault,
                selfViewEnabled: !_hideSelfCamera,
                showAudioDenoise: showAudioDenoise,
                audioDenoiseEnabled: audioDenoiseEnabled,
                audioDenoiseTypes: denoiseTypeOptions,
                selectedAudioDenoiseType: selectedAudioDenoiseType,
                showCameraBackground: showCameraBackground,
                cameraBackgroundSelection: cameraBackgroundSelection,
                showConnectionSettings: showConnectionSettings,
                isRejoining: isRejoining,
                forceShowConnectionStatusBanner:
                    forceShowConnectionStatusBanner,
                onIncomingVideoChanged: _setIncomingVideoEnabled,
                onSelfViewChanged: _setSelfViewEnabled,
                onAudioDenoiseChanged: showAudioDenoise
                    ? (value) =>
                          _bloc.add(SetAudioDenoiseEnabled(enabled: value))
                    : null,
                onAudioDenoiseTypeSelected: denoiseTypeOptions.length > 1
                    ? (type) => _bloc.add(SetAudioDenoiseType(type: type))
                    : null,
                onBackgroundBlurChanged: (value) => _bloc.add(
                  SetCameraBackgroundSelection(
                    value
                        ? const CameraBackgroundSelection.blur()
                        : const CameraBackgroundSelection.none(),
                  ),
                ),
                onVirtualBackgroundsTap: () {
                  dismissRoomPanelBottomSheetIfPresent();
                  _closeSidePanel();
                  unawaited(
                    _openVirtualBackgroundSheet(
                      this.context,
                      cameraBackgroundSelection,
                    ),
                  );
                },
                onReconnectPressed: showConnectionSettings
                    ? () => _bloc.add(
                        const StartRejoinMeeting(reason: RejoinReason.other),
                      )
                    : null,
                onForceShowConnectionStatusBannerChanged: showConnectionSettings
                    ? (value) => _bloc.add(
                        SetForceShowConnectionStatusBanner(value: value),
                      )
                    : null,
              ),
              child: const InRoomSettingsPanel(),
            );
          },
        );
      },
    );
  }

  /// Mirrors the design wording: the switch turns incoming video on, while the
  /// bloc stores the opposite ("unsubscribe by default").
  void _setIncomingVideoEnabled(bool enabled) {
    _inRoomSettingsBloc.add(InRoomIncomingVideoToggled(enabled: enabled));
    _bloc.add(SetUnsubscribeVideoByDefault(value: !enabled));

    setState(() {
      _unsubscribeVideoByDefault = !enabled;
      if (enabled) {
        subscribeAllVideoTracks();
      } else {
        unsubscribeAllVideoTracks();
      }
    });
  }

  void _setSelfViewEnabled(bool enabled) {
    _inRoomSettingsBloc.add(InRoomSelfViewToggled(enabled: enabled));
    _bloc.add(SetHideSelfView(hideSelfView: !enabled));
    setState(() {
      _hideSelfCamera = !enabled;
    });
  }

  void unsubscribeAllVideoTracks() {
    final room = _bloc.state.room;
    for (final remoteParticipant in room.remoteParticipants.values.toList()) {
      for (final pub in remoteParticipant.videoTrackPublications) {
        /// do not unsubscribe screen share track
        if (!pub.isScreenShare) {
          pub.unsubscribe();
        }
      }
    }
  }

  void subscribeAllVideoTracks() {
    final room = _bloc.state.room;
    for (final remoteParticipant in room.remoteParticipants.values.toList()) {
      for (final pub in remoteParticipant.videoTrackPublications) {
        pub.subscribe();
      }
    }
  }

  /// Safety-net re-subscribe for the screen-share view.
  ///
  /// With `autoSubscribe: false` (see [RoomManager.connectRoom]) the SFU only
  /// forwards tracks we explicitly subscribe to. The bridge subscribes
  /// screen-share on TrackPublished/Unmuted, but a transient network blip,
  /// rejoin, or any future selective-unsubscribe pass could leave the
  /// publication silent. Each time the user (re-)enters the screen-share
  /// view we re-assert subscription on the active sharer's screen-share
  /// publications. Idempotent: bails when already subscribed.
  void _ensureScreenShareSubscribed(Participant participant) {
    for (final pub in participant.videoTrackPublications) {
      if (pub.source != TrackSource.screenShareVideo) continue;
      if (pub is RemoteTrackPublication && !pub.subscribed) {
        pub.subscribe();
      }
    }
    for (final pub in participant.audioTrackPublications) {
      if (pub.source != TrackSource.screenShareAudio) continue;
      if (pub is RemoteTrackPublication && !pub.subscribed) {
        pub.subscribe();
      }
    }
  }

  Widget buildParticipantListContent(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: BlocSelector<RoomBloc, RoomState, String>(
        selector: (state) {
          // Create a hash of participant identities and their states for comparison
          // This ensures we only rebuild when participants actually change
          final room = state.room;
          final localParticipant = room.localParticipant;
          final remoteParticipants = room.remoteParticipants.values.toList();
          final raisedHandsByIdentity = state.raisedHandsByIdentity;

          final buffer = StringBuffer();
          if (localParticipant != null) {
            buffer.write('${localParticipant.identity}_');
            buffer.write('${localParticipant.hasAudio}_');
            buffer.write('${localParticipant.hasVideo}_');
            buffer.write(
              '${localParticipant.audioTrackPublications.firstOrNull?.muted}_',
            );
            buffer.write(
              '${localParticipant.videoTrackPublications.firstOrNull?.muted}_',
            );
            buffer.write(
              '${raisedHandsByIdentity[localParticipant.identity]}_',
            );
          }
          for (final p in remoteParticipants) {
            buffer.write('${p.identity}_');
            buffer.write('${p.hasAudio}_');
            buffer.write('${p.hasVideo}_');
            buffer.write('${p.audioTrackPublications.firstOrNull?.muted}_');
            buffer.write('${p.videoTrackPublications.firstOrNull?.muted}_');
            buffer.write('${raisedHandsByIdentity[p.identity]}_');
          }
          // Rebuild when the waiting-room join requests change (host view).
          for (final w in state.waitingRoomParticipants) {
            buffer.write('wr:${w.requestId}_');
          }
          return buffer.toString();
        },
        builder: (context, _) {
          final blocState = context.read<RoomBloc>().state;
          final room = blocState.room;
          final raisedHandsByIdentity = blocState.raisedHandsByIdentity;
          final localParticipant = room.localParticipant;
          final remoteParticipants = room.remoteParticipants.values.toList();

          final participants = <ParticipantDetail>[];

          // Pull the host/admin + recording-set lookups once instead of
          // re-querying them per row.
          final frbParticipantsMap = blocState.frbParticipantsMap;
          final showRecordingChips = _bloc.isMeetMultipleRecordingEnabled();
          bool participantIsHost(String identity) {
            final p = frbParticipantsMap[identity];
            if (p == null) return false;
            return p.isAdmin == 1 || p.isHost == 1;
          }

          bool participantIsRecording(String identity) =>
              showRecordingChips && blocState.isParticipantRecording(identity);

          // Add local participant
          if (localParticipant != null) {
            participants.add(
              ParticipantDetail(
                name: _bloc.getParticipantDisplayName(localParticipant),
                hasAudio:
                    (localParticipant.hasAudio) &&
                    localParticipant
                            .audioTrackPublications
                            .firstOrNull
                            ?.muted ==
                        false,
                hasVideo:
                    (localParticipant.hasVideo) &&
                    localParticipant
                            .videoTrackPublications
                            .firstOrNull
                            ?.muted ==
                        false,
                isMe: true,
                isHost: participantIsHost(localParticipant.identity),
                isRaisedHand:
                    raisedHandsByIdentity[localParticipant.identity] == true,
                isRecording: participantIsRecording(localParticipant.identity),
                participant: localParticipant,
              ),
            );
          }

          // Add remote participants
          participants.addAll(
            remoteParticipants.map(
              (element) => ParticipantDetail(
                name: _bloc.getParticipantDisplayName(element),
                hasAudio:
                    element.hasAudio &&
                    element.audioTrackPublications.firstOrNull?.muted == false,
                hasVideo:
                    element.hasVideo &&
                    element.videoTrackPublications.firstOrNull?.muted == false,
                isHost: participantIsHost(element.identity),
                isRaisedHand: raisedHandsByIdentity[element.identity] == true,
                isRecording: participantIsRecording(element.identity),
                participant: element,
              ),
            ),
          );

          final indexedParticipants = participants.asMap().entries.toList();
          indexedParticipants.sort((a, b) {
            if (a.value.isRaisedHand != b.value.isRaisedHand) {
              return a.value.isRaisedHand ? -1 : 1;
            }
            return a.key.compareTo(b.key);
          });
          final sortedParticipants = indexedParticipants
              .map((e) => e.value)
              .toList(growable: false);

          final waitingParticipants = blocState.waitingRoomParticipants
              .where((w) => w.isActive)
              .map(
                (w) => WaitingRoomParticipantDetail(
                  id: w.requestId,
                  participantUid: w.participantUid,
                  name: w.resolvedDisplayName,
                  joinedAt: w.receivedAt,
                ),
              )
              .toList(growable: false);

          return ParticipantList(
            participants: sortedParticipants,
            waitingParticipants: waitingParticipants,
            isHost: blocState.isHost,
            onTapParticipantVideoRemoteAction: (participant) async {
              if (participant != null) {
                final isMuted =
                    participant.audioTrackPublications.firstOrNull?.muted ??
                    true;
                final appCoreManager = ManagerFactory().get<AppCoreManager>();
                await appCoreManager.appCore.updateParticipantTrackSettings(
                  participantUuid: participant.identity,
                  audio: isMuted ? 0 : 1,
                  video: 0,
                );
              }
            },
            onTapParticipantAudioRemoteAction: (participant) async {
              if (participant != null) {
                final isMuted =
                    participant.videoTrackPublications.firstOrNull?.muted ??
                    true;
                final appCoreManager = ManagerFactory().get<AppCoreManager>();
                final result = await appCoreManager.appCore
                    .updateParticipantTrackSettings(
                      participantUuid: participant.identity,
                      audio: 0,
                      video: isMuted ? 0 : 1,
                    );
                l.logger.w("result: $result");
              }
            },
            onTapParticipantVideoLocalAction: (participant) async {
              if (participant != null) {
                bool isSubscribing = false;
                for (final pub in participant.videoTrackPublications) {
                  if (pub.track != null && pub is RemoteTrackPublication) {
                    isSubscribing = (isSubscribing || pub.subscribed);
                  }
                }
                if (isSubscribing) {
                  for (final pub in participant.videoTrackPublications) {
                    if (pub is RemoteTrackPublication) {
                      if (pub.subscribed && !pub.isScreenShare) {
                        await pub.unsubscribe();
                      }
                    }
                  }
                } else {
                  /// we want to subscribe this participant's video track
                  /// we will need to add to whitelist to avoid it's unsubscribe by global setting `unsubscribeVideoByDefault`
                  for (final pub in participant.videoTrackPublications) {
                    if (pub is RemoteTrackPublication) {
                      if (!pub.subscribed) {
                        await pub.subscribe();
                      }
                    }
                  }
                }
              }
            },
            onTapParticipantAudioLocalAction: (participant) async {
              if (participant != null) {
                bool isSubscribing = false;
                for (final pub in participant.audioTrackPublications) {
                  if (pub.track != null && pub is RemoteTrackPublication) {
                    isSubscribing = (isSubscribing || pub.subscribed);
                  }
                }
                if (isSubscribing) {
                  for (final pub in participant.audioTrackPublications) {
                    if (pub is RemoteTrackPublication) {
                      if (pub.subscribed) {
                        await pub.unsubscribe();
                      }
                    }
                  }
                } else {
                  for (final pub in participant.audioTrackPublications) {
                    if (pub is RemoteTrackPublication) {
                      if (!pub.subscribed) {
                        await pub.subscribe();
                      }
                    }
                  }
                }
              }
            },
          );
        },
      ),
    );
  }
}

class _RoomHostSettingsTransport implements InRoomHostSettingsTransport {
  _RoomHostSettingsTransport(this._roomPage);

  final _RoomPageState _roomPage;

  @override
  Future<bool> toggleLockMeeting({required bool value}) =>
      _roomPage._toggleLockMeeting(value: value);

  @override
  Future<bool> toggleWaitingRoom({required bool value}) =>
      _roomPage._toggleWaitingRoomSetting(value: value);

  @override
  Future<bool> toggleLiveCaptionsAvailability({required bool value}) =>
      _roomPage._toggleLiveCaptionsAvailability(value);
}
