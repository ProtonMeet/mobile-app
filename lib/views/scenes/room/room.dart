import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:logger/logger.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/channels/call_activity_action_channel.dart';
import 'package:meet/managers/channels/physical_key_channel.dart';
import 'package:meet/managers/channels/platform.channel.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/notification_service.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/platform/html.window.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/views/components/alerts/meeting_will_end_dialog.dart';
import 'package:meet/views/components/bottom.sheets/leave_room_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/left_meeting_bottom_sheet.dart';
import 'package:meet/views/components/button.inline.dart';
import 'package:meet/views/components/loading_view.dart';
import 'package:meet/views/scenes/app/app.router.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';
import 'package:meet/views/scenes/exts.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/chat/chat_bubble.dart';
import 'package:meet/views/scenes/room/controls_bar/controls_bar_responsive.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/layout/fixed_sizing_camera_layout.dart';
import 'package:meet/views/scenes/room/layout/responsive_camera_layout.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/participant_list/participant_list.dart';
import 'package:meet/views/scenes/room/room_is_ready_dialog.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';
import 'package:meet/views/scenes/room/widgets/floating.action.button.location.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_event.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:meet/views/scenes/widgets/meeting_settings_v2.dart';
import 'package:meet/views/scenes/widgets/statistics_dialog.dart';
import 'package:sentry/sentry.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'camera_layout.dart';
import 'controls_bar/controls_action.dart';
import 'info/meeting_info_panel.dart';
import 'message_topic.dart';
import 'pip_view.dart';
import 'room_bloc.dart';
import 'room_event.dart';
import 'room_reconnection_listeners.dart';
import 'room_state.dart';
import 'room_top_bar.dart';
import 'side_panel_widget.dart';
import 'speaker_phone/speaker_phone_panel.dart';
import 'widgets/connection_status_banner.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final String roomKey;
  final String displayName;
  final String roomId;
  final FrbMeetInfo meetInfo;
  final FrbUpcomingMeeting meetLink;
  final PreJoinType preJoinType;
  final bool isSpeakerPhoneEnabled;
  final AuthBloc? authBloc;
  const RoomPage(
    this.room,
    this.listener,
    this.roomKey,
    this.displayName,
    this.roomId,
    this.meetInfo,
    this.meetLink,
    this.preJoinType, {
    this.isSpeakerPhoneEnabled = false,
    this.authBloc,
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

  bool _showChatBubble = false;
  bool _showParticipantList = false;
  bool _showSettings = false;
  bool _showMeetingInfo = false;
  bool _showSpeakerPhonePanel = false;
  bool _isLandscape = false;
  bool _isScreenSharing = false;
  bool _hideSelfCamera = false;
  bool _unsubscribeVideoByDefault = false;
  bool _lockMeeting = false;
  final bool _pictureInPictureMode = false;
  final CameraLayout _layout = CameraLayout.grid;
  final bool _showRotationButton = false;

  DateTime _lastOpenChatTime = DateTime.now();
  int _screenSharingIndex = 0;
  bool _isCameraView = false;
  bool _cameraWasEnabledBeforePause = false;
  VideoMaxBitrate _cameraMaxBitrate = defaultCameraMaxBitrate;
  VideoResolution _cameraResolution = defaultCameraResolution;
  final appCoreManager = ManagerFactory().get<AppCoreManager>();
  UserConfig? userConfig;

  List<MediaDevice> _videoInputs = [];
  bool _isLeavingByUser = false;
  final Map<String, ParticipantReaction> _activeReactions = {};

  @override
  void initState() {
    super.initState();
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
          isSpeakerPhoneEnabled: widget.isSpeakerPhoneEnabled,
        ),
      );

    if (widget.meetInfo.isLocked) {
      setState(() {
        _lockMeeting = widget.meetInfo.isLocked;
      });
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
    if (android) {
      // Initialize PIP through bloc - only if feature flag is enabled
      if (_bloc.isPictureInPictureFeatureEnabled()) {
        _bloc.add(InitializePip(roomName: widget.meetInfo.meetName));
      }
      _bloc.add(SetSpeakerPhone(enabled: widget.isSpeakerPhoneEnabled));
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

  @override
  void dispose() {
    _activeReactions.clear();

    WidgetsBinding.instance.removeObserver(this);
    // Restore normal unknown-route behavior after leaving the meeting.
    Coordinator.suppressUnknownRouteUi = false;

    _deviceChangeSub?.cancel();
    _deviceChangeSub = null;

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
        notificationService.dispose();
      } catch (e) {
        // NotificationService might not be registered on non-Android platforms
      }
    }
    // PIP cleanup is handled by bloc
    _bloc.close();
    disableWakelock();
    onWindowShouldClose = null;
    super.dispose();
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
        // make sure the notification is shown when the app is inactive
        try {
          final notificationService = ManagerFactory()
              .get<NotificationService>();
          notificationService.showBackgroundNotification(
            roomName: widget.meetInfo.meetName,
          );
        } catch (e) {
          l.logger.e('[RoomPage] Error showing background notification: $e');
        }
      } else if (state == AppLifecycleState.resumed) {
        // App comes to foreground, hide notification
        await _hideNotification('app resumed');

        if (_bloc.isPictureInPictureFeatureEnabled()) {
          // Exit PIP when app comes to foreground
          if (_bloc.state.isPipMode) {
            _bloc.add(ExitPipMode());
          }
        }

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
      _bloc.add(
        AddSystemMessage(
          'Room disconnected: reason => ${event.reason}',
          'system',
          'System',
        ),
      );
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
          await _leaveRoom(
            leftMeetingBottomSheetShowRejoin: false,
            leftMeetingBottomSheetTitle:
                context.local.kicked_out_bottom_sheet_title,
            leftMeetingBottomSheetContent:
                context.local.kicked_out_bottom_sheet_content,
          );
        } else if (event.reason == DisconnectReason.stateMismatch) {
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
      if (event.activeRecording) {
        context.showRecordingStatusChangedDialog(
          onLeaveMeeting: () async {
            await _leaveRoom();
          },
        );
      } else {
        LocalToast.showToast(context, context.local.room_recording_stopped);
      }
    })
    ..on<DataReceivedEvent>((event) async {
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
          } else if (topic == MessageTopic.recordingStatus) {
            await _handleRecordingStatus(event);
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

  Future<String?> decryptMessage(
    String encryptedText, {
    String? identity,
    String? name,
  }) async {
    final bytes = Uint8List.fromList(
      encryptedText.codeUnits.map((c) => c & 0xFF).toList(),
    );

    final (decryptedMessage, senderId) = await appCoreManager.appCore
        .decryptMessage(data: bytes);
    return decryptedMessage;
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

  Future<void> _handleChatMessageReaction(
    String message,
    String identity,
    String name,
  ) async {
    // To-do: implement chat message reaction UI
    l.logger.d(
      '[RoomPage] _handleChatMessageReaction: identity=$identity, name=$name',
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

  void addMessage(
    String message,
    String identity,
    String name, {
    bool showToast = false,
    String type = 'text',
  }) {
    _bloc.add(
      AddSystemMessage(
        message,
        identity,
        name,
        type: type,
        logLevel: Level.info,
      ),
    );
    if (showToast) {
      LocalToast.showToastification(
        context,
        name,
        message,
        onTap: (_) {
          setState(() {
            _showChatBubble = true;
            _showParticipantList = false;
          });
        },
      );
    }
  }

  Future<void> _handleRecordingStatus(DataReceivedEvent event) async {
    final data = utf8.decode(event.data);
    final messageJson = jsonDecode(data);
    final message = messageJson['message'];
    final recordingStatus = RecordingStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == message.toLowerCase(),
    );
    if (recordingStatus == RecordingStatus.started) {
      context.showRecordingStatusChangedDialog(
        onLeaveMeeting: () async {
          await _leaveRoom();
        },
      );
    } else {
      LocalToast.showToast(context, context.local.room_recording_stopped);
    }
  }

  /// This handle e2ee message from legacy mobile version
  @Deprecated('Use handleChatMessage instead')
  Future<void> _handleE2EEMessage(DataReceivedEvent event) async {
    try {
      final name = event.participant?.name ?? context.local.unknown;
      final identity = event.participant?.identity ?? context.local.unknown;
      final encryptedMessage = utf8.decode(event.data);
      final message = await decryptMessage(
        encryptedMessage,
        identity: identity,
        name: name,
      );
      if (message == null) {
        l.logger.e("Cannot decrypt message");
        return;
      }
      addMessage(message, identity, name);
      if (context.mounted && mounted && !_showChatBubble) {
        LocalToast.showToastification(
          context,
          name,
          message,
          onTap: (_) {
            setState(() {
              _showChatBubble = true;
              _showParticipantList = false;
            });
          },
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

    final messageJson = jsonDecode(data);
    final dataType = PublishableDataType.fromString(
      messageJson['type']?.toString(),
    );
    final message = messageJson['message'];
    final name = event.participant?.name ?? context.local.unknown;
    final identity = event.participant?.identity ?? context.local.unknown;
    final displayName = event.participant != null
        ? _bloc.getParticipantDisplayName(event.participant!)
        : name;
    String? decryptedMessage;
    try {
      decryptedMessage = await decryptMessage(message);
    } catch (e) {
      l.logger.e('Error decrypting message: $e');
    }
    switch (dataType) {
      case PublishableDataType.recordingStatus:
        await _handleRecordingStatus(event);
        return;
      case PublishableDataType.message:
        addMessage(decryptedMessage ?? message, identity, displayName);
        if (mounted && context.mounted && !_showChatBubble) {
          LocalToast.showToastification(
            context,
            displayName,
            decryptedMessage ?? message,
            onTap: (_) {
              setState(() {
                _showChatBubble = true;
                _showParticipantList = false;
              });
            },
          );
        }
        return;
      case PublishableDataType.emojiReaction:
        try {
          if (decryptedMessage != null) {
            await _handleEmojiReaction(decryptedMessage, identity, displayName);
          }
        } catch (_) {}
        return;
      case PublishableDataType.raiseHand:
        try {
          if (decryptedMessage != null) {
            await _handleRaiseHand(decryptedMessage, identity, displayName);
          }
        } catch (_) {}
        return;
      case PublishableDataType.chatMessageReaction:
        try {
          if (decryptedMessage != null) {
            await _handleChatMessageReaction(
              decryptedMessage,
              identity,
              displayName,
            );
          }
        } catch (_) {}

        return;
      case null:
        l.logger.w(
          '[RoomPage] handleChatMessage: unknown type ${messageJson['type']}',
        );
        return;
    }
  }

  Future<void> _showEmojiReactionMenu() async {
    if (!_bloc.isMeetMobileEnableEmojiReactionEnabled()) return;
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                      child: Text(emoji, style: const TextStyle(fontSize: 30)),
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
        );
      },
    );
  }

  Widget buildCameraLayout(
    BuildContext context,
    List<ParticipantInfo> participantTracks,
    List<ParticipantInfo> speakerTracks,
    Map<String, bool> raisedHandsByIdentity,
  ) {
    // Hide participant tiles during rejoin, show them only after rejoin completes
    if (_bloc.state.isRejoining || _bloc.state.isLiveKitReconnecting) {
      return Container(
        color: Colors.transparent,
        width: context.width,
        height: context.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final room = _bloc.state.room;
    switch (_layout) {
      case CameraLayout.grid:
        return ResponsiveCameraLayout(
          participantTracks: participantTracks,
          room: room,
          reactionsByIdentity: _activeReactions,
          raisedHandsByIdentity: raisedHandsByIdentity,
        );
      case CameraLayout.fixedSizing:
        return FixedSizingCameraLayout(
          participantTracks: participantTracks,
          reactionsByIdentity: _activeReactions,
          raisedHandsByIdentity: raisedHandsByIdentity,
        );
      case CameraLayout.speaker:

        /// use fixedSizing layout when no active speaker
        if (speakerTracks.isEmpty) {
          return FixedSizingCameraLayout(
            participantTracks: participantTracks,
            reactionsByIdentity: _activeReactions,
            raisedHandsByIdentity: raisedHandsByIdentity,
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
                  getParticipantDisplayColors(context, index),
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
          ),
        ),
      ],
    );
  }

  /// leave room and disconnect from livekit
  Future<void> _leaveRoom({
    bool isShowLeftMeetingBottomSheet = true,
    bool leftMeetingBottomSheetShowRejoin = true,
    String? leftMeetingBottomSheetTitle,
    String? leftMeetingBottomSheetContent,
  }) async {
    _isLeavingByUser = true;
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

    if (!mounted) return;

    // Save meeting link for rejoin
    final meetingLink = widget.meetLink;
    final isHost = _bloc.state.isHost;
    final isPaidUser = _bloc.state.isPaidUser;

    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);

    final rootContext =
        Coordinator.rootNavigatorKey.currentState?.overlay?.context ??
        Coordinator.rootNavigatorKey.currentContext;
    if (rootContext != null &&
        rootContext.mounted &&
        isShowLeftMeetingBottomSheet) {
      final isMeetMobileShowStartMeetingButtonEnabled = _bloc
          .isMeetMobileShowStartMeetingButtonEnabled();
      await showLeftMeetingBottomSheet(
        rootContext,
        meetingLink: meetingLink,
        isHost: isHost,
        isPaidUser: isPaidUser,
        isMeetMobileShowStartMeetingButtonEnabled:
            isMeetMobileShowStartMeetingButtonEnabled,
        showRejoin: leftMeetingBottomSheetShowRejoin,
        title: leftMeetingBottomSheetTitle,
        content: leftMeetingBottomSheetContent,
        onRejoinMeeting: () {
          _navigateToPreJoin(rootContext, meetingLink);
        },
        onStartMeetingNow: () {
          _navigateToStartMeeting(rootContext);
        },
      );
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
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
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
              )
          ..add(AuthInitialized());

    final args = PreJoinArgs(type: PreJoinType.create, authBloc: authBloc);
    Navigator.pushNamed(context, RouteName.preJoin.path, arguments: args);
  }

  /// Toggle meeting lock state (lock/unlock)
  Future<bool> _toggleLockMeeting(bool value) async {
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
      setState(() {
        _lockMeeting = value;
      });
      LocalToast.showToast(
        context,
        value
            ? context.local.meeting_locked_notification
            : context.local.meeting_unlocked_notification,
      );
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
    return BlocProvider(
      create: (context) => _bloc,
      child: MultiBlocListener(
        listeners: [
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
          // Add chat message for all joined participants
          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.joinedParticipants != curr.joinedParticipants,
            listener: (context, state) {
              final participantDetail = state.joinedParticipants.last;
              final meetingName = widget.meetInfo.meetName;
              addMessage(
                'Joined $meetingName',
                participantDetail.uuid,
                participantDetail.name,
                type: 'system',
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
                'Left $meetingName',
                participantDetail.uuid,
                participantDetail.name,
                type: 'system',
              );
            },
          ),

          BlocListener<RoomBloc, RoomState>(
            listenWhen: (prev, curr) =>
                prev.isLocalScreenSharing != curr.isLocalScreenSharing ||
                prev.isRemoteScreenSharing != curr.isRemoteScreenSharing,
            listener: (context, state) {
              setState(() {
                _isScreenSharing =
                    state.isLocalScreenSharing || state.isRemoteScreenSharing;

                if (_isScreenSharing) {
                  _isCameraView = false; // auto move to screen sharing view
                }
              }); // triggers rebuild manually
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
                if (isRoomReady) {
                  _bloc.add(StartAutoFullScreenTimer());
                }
                return Scaffold(
                  resizeToAvoidBottomInset: false,
                  backgroundColor: context.colors.interActionWeakMinor3,
                  floatingActionButton: desktop || !_showRotationButton
                      ? null
                      : FloatingActionButton(
                          backgroundColor: context.colors.protonBlue.withValues(
                            alpha: 0.5,
                          ),
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
        if (isPipMode) {
          return PipView(room: room, isScreenSharing: _isScreenSharing);
        }
        return _buildNormalMobileView(context);
      },
    );
  }

  /// Builds the main content area (without controls bar)
  /// This is shared between mobile and desktop views
  Widget _buildMainContent(BuildContext context) {
    if (!_isScreenSharing || _isCameraView) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              const ConnectionStatusBanner(),
              Expanded(
                child:
                    BlocSelector<
                      RoomBloc,
                      RoomState,
                      (
                        List<ParticipantInfo> participantTracks,
                        List<ParticipantInfo> speakerTracks,
                        Map<String, bool> raisedHandsByIdentity,
                      )
                    >(
                      selector: (state) => (
                        state.participantTracks,
                        state.speakerTracks,
                        state.raisedHandsByIdentity,
                      ),
                      builder: (context, data) =>
                          buildCameraLayout(context, data.$1, data.$2, data.$3),
                    ),
              ),

              ///
              if (_showParticipantList && !_showChatBubble)
                buildParticipantList(context),

              ///
              if (_showChatBubble) buildChatBubble(context),

              ///
              if (_showSettings) buildMeetingSettings(context),

              ///
              if (_showMeetingInfo) buildMeetingInfo(context),

              ///
              if (_showSpeakerPhonePanel)
                buildSpeakerPhonePanel(context, width: constraints.maxWidth),
            ],
          );
        },
      );
    } else {
      // Screen sharing view
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              Expanded(
                child:
                    BlocSelector<
                      RoomBloc,
                      RoomState,
                      (
                        int index,
                        List<ParticipantInfo> tracks,
                        bool isFullScreen,
                        Map<String, bool> raisedHandsByIdentity,
                      )
                    >(
                      selector: (state) {
                        return (
                          state.screenSharingIndex,
                          state.screenSharingTracks,
                          state.isFullScreen,
                          state.raisedHandsByIdentity,
                        );
                      },
                      builder: (context, state) {
                        final tracks = state.$2;
                        final index = state.$1;
                        final isFullScreen = state.$3;
                        final raisedHandsByIdentity = state.$4;

                        if (tracks.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        final safeIndex = min(index, tracks.length - 1);

                        return GestureDetector(
                          onTap: () {
                            // Immediately enter full screen when tapping screen share
                            if (!_bloc.state.isFullScreen) {
                              _bloc.add(ToggleFullScreen());
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
                              getParticipantDisplayColors(context, safeIndex),
                              tracks[safeIndex],
                              showStatsLayer: false,
                              roundedBorder: false,
                              isFullScreen: isFullScreen,
                              reaction:
                                  _activeReactions[tracks[safeIndex]
                                      .participant
                                      .identity],
                              isRaisedHand:
                                  raisedHandsByIdentity[tracks[safeIndex]
                                      .participant
                                      .identity] ==
                                  true,
                            ),
                          ),
                        );
                      },
                    ),
              ),
              if (_showParticipantList && !_showChatBubble)
                buildParticipantList(context),
              if (_showChatBubble) buildChatBubble(context),
              if (_showSettings) buildMeetingSettings(context),
              if (_showMeetingInfo) buildMeetingInfo(context),
              if (_showSpeakerPhonePanel)
                buildSpeakerPhonePanel(context, width: constraints.maxWidth),
            ],
          );
        },
      );
    }
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
        return Stack(
          children: [
            Column(
              children: [
                if (!isPipMode && isRoomReady)
                  _buildHeaderWithSlide(
                    context: context,
                    room: room,
                    isCameraEnabled: isCameraEnabled,
                    isPaidUser: isPaidUser,
                  ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // Immediately enter full screen when tapping the view
                      if (!_bloc.state.isFullScreen) {
                        _bloc.add(ToggleFullScreen());
                      } else {
                        _resetAutoFullScreenTimer();
                      }
                    },
                    onPanStart: (_) => _resetAutoFullScreenTimer(),
                    onPanUpdate: (_) => _resetAutoFullScreenTimer(),
                    child: _buildMainContent(context),
                  ),
                ),
                if (room.localParticipant != null) _buildControlsBarWithFade(),
              ],
            ),
            // Floating stop screen share button
            BlocSelector<RoomBloc, RoomState, bool>(
              selector: (state) => state.isLocalScreenSharing,
              builder: (context, isLocalScreenSharing) {
                if (room.localParticipant != null && isLocalScreenSharing) {
                  return _buildStopScreenShareButton(context);
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildStopScreenShareButton(BuildContext context) {
    return Positioned(
      top: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: () {
              _bloc.add(ToggleScreenShare());
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: context.colors.signalDangerMajor3,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.local.stop_presenting,
                    style: ProtonStyles.body2Medium(
                      color: context.colors.textNorm,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
        // Always render the widget, but slide it up when full screen and controls bar are hidden
        final shouldHide = isFullScreen;
        const headerHeight = 60.0;

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
                setState(() {
                  _showSpeakerPhonePanel = !_showSpeakerPhonePanel;
                  if (_showSpeakerPhonePanel) {
                    _showChatBubble = false;
                    _showParticipantList = false;
                    _showMeetingInfo = false;
                    _showSettings = false;
                  }
                });
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
        final shouldHide = isFullScreen;

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

  Widget buildControlsBar() {
    return BlocSelector<RoomBloc, RoomState, RoomState>(
      selector: (state) {
        return state;
      },
      builder: (context, state) {
        final chatUnreadCount = state.messages
            .where(
              (message) =>
                  message is types.TextMessage &&
                  (message.createdAt ?? 0) >
                      _lastOpenChatTime.millisecondsSinceEpoch,
            )
            .length;
        return SizedBox(
          width: context.width,
          height: bottomControlHeight,
          child: ResponsiveControlsBar(
            room: state.room,
            backgroundColor: context.colors.interActionWeakMinor3,
            onLeave: () {
              leaveRoomDialog(isHost: state.isHost, isAlone: state.isAlone);
            },
            cameraResolution: _cameraResolution,
            cameraMaxBitrate: _cameraMaxBitrate,
            currentCameraPosition: state.currentCameraPosition,
            optionalActionsBuilder: () {
              final isSpeakerMuted = state.isSpeakerMuted ?? false;
              return [
                /// Emoji reactions
                if (_bloc.isMeetMobileEnableEmojiReactionEnabled() &&
                    state.room.localParticipant != null)
                  ControlAction(
                    icon: Icon(Icons.emoji_emotions_outlined, size: 24),
                    tooltip: context.local.emoji_reactions,
                    onPressed: () {
                      unawaited(_showEmojiReactionMenu());
                    },
                  ),

                /// Mute speaker
                ControlAction(
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

                /// PiP - only show if supported and feature flag is enabled
                if (_bloc.isPictureInPictureFeatureEnabled() &&
                    state.pipAvailable == true)
                  ControlAction(
                    icon: const Icon(Icons.picture_in_picture),
                    tooltip: context.local.enter_pip,
                    onPressed: () {
                      _bloc.add(EnterPipMode());
                    },
                  ),

                /// Screen share - only show if feature flag is enabled
                if (_bloc.isScreenShareFeatureEnabled())
                  ControlAction(
                    icon: context.images.iconScreenShare.svg(
                      width: 24,
                      height: 24,
                    ),
                    tooltip: state.isLocalScreenSharing
                        ? context.local.unshare_screen
                        : context.local.share_screen,
                    onPressed: () {
                      _bloc.add(ToggleScreenShare());
                    },
                  ),

                /// Participants
                ControlAction(
                  icon: context.images.iconParticipants.svg(
                    width: 24,
                    height: 24,
                  ),
                  badge: '${state.room.remoteParticipants.length + 1}',
                  tooltip:
                      '${context.local.show_participants_list} (${state.room.remoteParticipants.length + 1})',
                  onPressed: () {
                    setState(() {
                      _showParticipantList = !_showParticipantList;
                      // close chat bubble when show participant list on mobile
                      if (_showParticipantList) {
                        _showChatBubble = false;
                        _showSettings = false;
                        _showSpeakerPhonePanel = false;
                      }
                    });
                  },
                ),

                /// Chat
                ControlAction(
                  icon: context.images.iconChat.svg(width: 24, height: 24),
                  tooltip:
                      context.local.show_chatroom +
                      (chatUnreadCount > 0 ? ' ($chatUnreadCount)' : ''),
                  badge: chatUnreadCount > 0
                      ? chatUnreadCount.toString()
                      : null,
                  onPressed: () {
                    setState(() {
                      _showChatBubble = !_showChatBubble;
                      // close participant list when show chat bubble on mobile
                      if (_showChatBubble) {
                        _lastOpenChatTime = DateTime.now();
                        _showParticipantList = false;
                        _showSettings = false;
                        _showSpeakerPhonePanel = false;
                      }
                    });
                  },
                ),

                /// Settings
                ControlAction(
                  icon: context.images.iconSettings.svg(width: 24, height: 24),
                  tooltip: context.local.show_settings,
                  onPressed: () {
                    setState(() {
                      _showSettings = !_showSettings;
                      if (_showSettings) {
                        _showChatBubble = false;
                        _showParticipantList = false;
                        _showSpeakerPhonePanel = false;
                      }
                    });
                  },
                ),

                /// Info
                ControlAction(
                  icon: context.images.iconInfo.svg(width: 24, height: 24),
                  tooltip: context.local.meeting_info,
                  onPressed: () {
                    setState(() {
                      _showMeetingInfo = !_showMeetingInfo;
                      if (_showMeetingInfo) {
                        _showChatBubble = false;
                        _showParticipantList = false;
                        _showSettings = false;
                        _showSpeakerPhonePanel = false;
                      }
                    });
                  },
                ),
              ];
            },
          ),
        );
      },
    );
  }

  Widget buildParticipantsCameraWehnScreenSharing(BuildContext context) {
    final participantTracksWhenScreenSharing = _bloc
        .getParticipantTracksWhenScreenSharing();
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
                getParticipantDisplayColors(context, index),
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
              getParticipantDisplayColors(context, index),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPanelWhenScreenSharing(
    BuildContext context,
    LocalParticipant? participant,
  ) {
    final sharing = participant?.isScreenShareEnabled() ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: BlocSelector<RoomBloc, RoomState, List<ParticipantInfo>>(
          selector: (state) {
            return state.screenSharingTracks;
          },
          builder: (context, tracks) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (tracks.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isCameraView = true;
                          });
                        },
                        child: Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 4),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
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
                            _bloc.add(ToggleFullScreen());
                          });
                        },
                        child: Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 4),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (i == _screenSharingIndex && !_isCameraView)
                                ? context.colors.interActionWeak
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.colors.textWeak),
                          ),
                          child: Text(
                            "🖥️ ${_bloc.getParticipantDisplayName(tracks[i].participant)} ${context.local.is_presenting}",
                            overflow: TextOverflow.ellipsis,
                            style: ProtonStyles.body2Medium(
                              color: context.colors.textNorm,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (sharing)
                  ButtonInline(
                    text: context.local.stop_presenting,
                    onPressed: () async {
                      _bloc.add(ToggleScreenShare());
                    },
                    width: 160,
                    height: 32,
                    borderRadius: 40,
                    textColor: Colors.white,
                    backgroundColor: context.colors.protonBlue,
                  ),
              ],
            );
          },
        ),
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

  Widget buildSidePanelContent(BuildContext context, Widget child) {
    final shouldExpand = _isScreenSharing && !_isCameraView;
    // Use mobile-like UI for small screens, desktop-like for medium+ screens
    // This allows iOS and macOS to share UI based on screen size
    if (!context.isAtLeastMedium) {
      // Use bottom sheet style on mobile
      return AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: shouldExpand ? 0 : 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(top: false, child: child),
          ),
        ),
      );
    } else {
      // Default: side panel (desktop/web)
      return Padding(
        padding: EdgeInsets.only(
          top: shouldExpand ? 0 : 12,
          right: 8,
          bottom: 12,
        ),
        child: child,
      );
    }
  }

  Widget buildParticipantList(BuildContext context) {
    return SidePanelOrSheet(
      isScreenSharing: _isScreenSharing,
      isCameraView: _isCameraView,
      maxWidth: maxMobileSheetWidth,
      child: buildParticipantListContent(context),
      onDismissed: () {
        setState(() {
          _showParticipantList = false;
        });
      },
    );
  }

  Widget buildChatBubble(BuildContext context) {
    return SidePanelOrSheet(
      isScreenSharing: _isScreenSharing,
      isCameraView: _isCameraView,
      maxWidth: maxMobileSheetWidth,
      child: buildChatBubbleContent(context),
      onDismissed: () {
        setState(() {
          _lastOpenChatTime = DateTime.now();
          _showChatBubble = false;
        });
      },
    );
  }

  Widget buildMeetingSettings(BuildContext context) {
    return BlocSelector<RoomBloc, RoomState, bool>(
      selector: (state) => state.isHost,
      builder: (context, isHost) {
        return SidePanelOrSheet(
          isScreenSharing: _isScreenSharing,
          isCameraView: _isCameraView,
          maxWidth: maxMobileSheetWidth,
          child: buildMeetingSettingsContent(context, isHost: isHost),
          onDismissed: () {
            setState(() {
              _showSettings = false;
            });
          },
        );
      },
    );
  }

  Widget buildMeetingInfo(BuildContext context) {
    return SidePanelOrSheet(
      isScreenSharing: _isScreenSharing,
      isCameraView: _isCameraView,
      maxWidth: maxMobileSheetWidth,
      child: buildMeetingInfoContent(context),
      onDismissed: () {
        setState(() {
          _showMeetingInfo = false;
        });
      },
    );
  }

  Widget buildMeetingInfoContent(BuildContext context) {
    // Get meeting info from widget
    final meetingTitle = widget.meetInfo.meetName;
    return Container(
      width: double.infinity,
      height: context.height,
      color: Colors.transparent,
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

  Widget buildSpeakerPhonePanel(BuildContext context, {double width = 300.0}) {
    return SidePanelOrSheet(
      isScreenSharing: _isScreenSharing,
      isCameraView: _isCameraView,
      maxWidth: maxMobileSheetWidth,
      child: buildSpeakerPhoneContent(context, width: width),
      onDismissed: () {
        setState(() {
          _showSpeakerPhonePanel = false;
        });
      },
    );
  }

  Widget buildSpeakerPhoneContent(
    BuildContext context, {
    double width = 300.0,
  }) {
    return Container(
      width: width,
      height: context.height,
      color: Colors.transparent,
      child: const SpeakerPhonePanel(),
    );
  }

  Widget buildChatBubbleContent(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      (List<types.Message>, List<ParticipantInfo>, Room)
    >(
      selector: (s) => (s.messages, s.participantTracks, s.room),
      builder: (context, data) {
        final room = data.$3;
        return ChatBubble(
          userIdentity: room.localParticipant?.identity ?? '',
          userName: room.localParticipant?.name ?? '',
          onSendPressed: (types.PartialText text) async {
            await broadcastE2EEMessage(text.text);
          },
          messages: data.$1,
          participantTracks: data.$2,
        );
      },
    );
  }

  Widget buildMeetingSettingsContent(
    BuildContext context, {
    bool isHost = false,
  }) {
    return BlocSelector<RoomBloc, RoomState, (bool, bool)>(
      selector: (state) =>
          (state.isRejoining, state.forceShowConnectionStatusBanner),
      builder: (context, data) {
        final isRejoining = data.$1;
        final forceShowConnectionStatusBanner = data.$2;
        final isAutoReconnectionEnabled = _bloc.isMeetAutoReconnectionEnabled();
        final isNetworkToolEnabled = _bloc
            .isMeetMobileEnableNetworkToolEnabled();
        return MeetingSettingsV2(
          hideSelfView: _hideSelfCamera,
          unsubscribeVideoByDefault: _unsubscribeVideoByDefault,
          pictureInPictureMode: _pictureInPictureMode,
          lockMeeting: _lockMeeting,
          isHost: isHost,
          isRejoining: isRejoining,
          forceShowConnectionStatusBanner: forceShowConnectionStatusBanner,
          showConnectionSettings:
              isAutoReconnectionEnabled && isNetworkToolEnabled,
          onHideSelfViewChanged: ({required bool value}) {
            _bloc.add(SetHideSelfView(hideSelfView: value));
            setState(() {
              _hideSelfCamera = value;
            });
          },
          onLockMeetingChanged: isHost
              ? ({required bool value}) async {
                  return _toggleLockMeeting(value);
                }
              : null,
          onUnsubscribeVideoByDefaultChanged: ({required bool value}) {
            // Update bloc state first so new tracks are handled correctly
            _bloc.add(SetUnsubscribeVideoByDefault(value: value));

            setState(() {
              _unsubscribeVideoByDefault = value;
              if (value) {
                unsubscribeAllVideoTracks();
              } else {
                subscribeAllVideoTracks();
              }
            });
          },
          onReconnectPressed:
              (isAutoReconnectionEnabled && isNetworkToolEnabled)
              ? () {
                  _bloc.add(
                    const StartRejoinMeeting(reason: RejoinReason.other),
                  );
                }
              : null,
          onForceShowConnectionStatusBannerChanged:
              (isAutoReconnectionEnabled && isNetworkToolEnabled)
              ? ({required bool value}) {
                  _bloc.add(SetForceShowConnectionStatusBanner(value: value));
                }
              : null,
        );
      },
    );
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

  Widget buildParticipantListContent(BuildContext context) {
    return Container(
      width: double.infinity,
      height: context.height,
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
          return buffer.toString();
        },
        builder: (context, _) {
          final blocState = context.read<RoomBloc>().state;
          final room = blocState.room;
          final raisedHandsByIdentity = blocState.raisedHandsByIdentity;
          final localParticipant = room.localParticipant;
          final remoteParticipants = room.remoteParticipants.values.toList();

          final participants = <ParticipantDetail>[];

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
                isRaisedHand:
                    raisedHandsByIdentity[localParticipant.identity] == true,
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
                isRaisedHand: raisedHandsByIdentity[element.identity] == true,
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

          return ParticipantList(
            participants: sortedParticipants,
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
