import 'dart:async';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/bridge_session_check.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/frb_upcoming_meetings.dart';
import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/helper/external.url.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/sentry_create_room.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/meeting.event.loop.manager.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/services/force_upgrade.dart';
import 'package:meet/managers/user_activity.manager.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/recurrence_frequency.dart'
    as frb_recurrence_frequency;
import 'package:meet/rust/proton_meet/models/schedule_meeting.dart'
    as rust_schedule;
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/models/user_state.dart';
import 'package:meet/views/scenes/utils.dart' as utils;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'schedule/schedule_meeting_dialog.dart';
import 'search/sort_sheet.dart';
import 'upcoming/meet_upcoming_title.dart';

class DashboardBloc extends Bloc<DashboardBlocEvent, DashboardState> {
  StreamSubscription<Uri>? _appLinkSub;
  StreamSubscription<List<FrbUpcomingMeeting>>? _meetingUpdateSub;

  DashboardBloc() : super(const DashboardState()) {
    on<InitDashboardEvent>(_onInitDashboardEvent);
    on<FetchUserStateEvent>(_onFetchUserStateEvent);
    on<RetryDashboardLoadEvent>((event, emit) => add(FetchUserStateEvent()));
    on<CreatePersonalMeetingEvent>(_onCreatePersonalMeetingEvent);
    on<RotatePersonalMeetingLinkEvent>(_onRotatePersonalMeetingLinkEvent);
    on<CreateSecureMeetingEvent>(_onCreateSecureMeetingEvent);
    on<JoinMeetingWithLinkEvent>(_onJoinMeetingWithLinkEvent);
    on<ResetEarlyAccessDialogEvent>(_onResetEarlyAccessDialogEvent);
    on<DismissDashboardInfoCardEvent>(_onDismissDashboardInfoCardEvent);
    on<UpdateUpcomingStateEvent>(_onUpdateUpcomingStateEvent);
    on<ResetDashboardStateEvent>(_onResetDashboardStateEvent);
    on<CreateMeetingEvent>(_onCreateMeetingEvent);
    on<DeleteMeetingEvent>(_onDeleteMeetingEvent);
    on<UpdateMeetingEvent>(_onUpdateMeetingEvent);
    on<ClearCreatedMeetingLinkEvent>(_onClearCreatedMeetingLinkEvent);
    on<ScheduleMeetingEvent>(_onScheduleMeetingEvent);
    on<UpdateScheduledMeetingEvent>(_onUpdateScheduledMeetingEvent);
    on<DownloadScheduledMeetingIcsEvent>(_onDownloadScheduledMeetingIcsEvent);
    on<AddScheduledMeetingToCalendarEvent>(
      _onAddScheduledMeetingToCalendarEvent,
    );
    on<OpenScheduledMeetingCalendarEvent>(_onOpenScheduledMeetingCalendarEvent);
    on<ClearScheduledMeetingSummaryEvent>(_onClearScheduledMeetingSummaryEvent);
    on<ClearScheduledMeetingIcsEvent>(_onClearScheduledMeetingIcsEvent);

    /// Search mode events
    on<EnterSearchModeEvent>(_onEnterSearchModeEvent);
    on<ExitSearchModeEvent>(_onExitSearchModeEvent);
    on<UpdateSearchQueryEvent>(_onUpdateSearchQueryEvent);
    on<UpdateSortOptionMyRoomsEvent>(_onUpdateSortOptionMyRoomsEvent);
    on<UpdateSortOptionMyMeetingsEvent>(_onUpdateSortOptionMyMeetingsEvent);
    on<LoadSignInCardVisibilityEvent>(_onLoadSignInCardVisibilityEvent);
    on<DismissSignInCardEvent>(_onDismissSignInCardEvent);
    on<MeetingUpdateEvent>(_onMeetingUpdateEvent);
    on<PatchMeetingWaitingRoomEvent>(_onPatchMeetingWaitingRoomEvent);
    on<InAppUpdateDownloadedEvent>(_onInAppUpdateDownloadedEvent);
    on<ClearInAppUpdateDownloadedEvent>(_onClearInAppUpdateDownloadedEvent);

    // Connect to meeting event loop manager
    _connectToMeetingEventLoop();

    _appLinkSub ??= AppLinks().uriLinkStream.listen((uri) {
      // Block deeplinks when in force upgrade state
      final appStateManager = ManagerFactory().get<AppStateManager>();
      final currentState = appStateManager.state;
      if (currentState is AppForceUpgradeState) {
        if (kDebugMode) {
          l.logger.i('Deeplink blocked: app is in force upgrade state');
        }
        return;
      }
      if (kDebugMode) {
        l.logger.i('onAppLink: ${uri.scheme}://${uri.host}${uri.path}-xxxxxxx');
      }
      add(JoinMeetingWithLinkEvent(joinMeetingWithLinkUrl: uri.toString()));
    });
  }

  /// Whether waiting-room switch UI should be shown (schedule / create dialogs).
  /// The server-driven waiting-room join flow is unaffected by this flag.
  bool isMeetWaitingRoomEnabled() {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider.isMeetWaitingRoom();
    } catch (e) {
      l.logger.w('[DashboardBloc] Error checking MeetWaitingRoom flag: $e');
      return false;
    }
  }

  void _connectToMeetingEventLoop() {
    try {
      final managerFactory = ManagerFactory();
      final eventLoopManager = managerFactory.get<MeetingEventLoopManager>();
      eventLoopManager.setDashboardBloc(this);
      _meetingUpdateSub = eventLoopManager.meetingUpdateStream.listen((
        meetings,
      ) {
        if (PlatformInfoChannel.isInForceUpgradeState()) {
          return;
        }
        add(MeetingUpdateEvent(meetings: meetings));
      });
      l.logger.d('[DashboardBloc] Connected to MeetingEventLoopManager');
    } catch (e) {
      l.logger.w('[DashboardBloc] MeetingEventLoopManager not available: $e');
    }
  }

  @override
  Future<void> close() async {
    await _appLinkSub?.cancel();
    await _meetingUpdateSub?.cancel();
    _appLinkSub = null;
    _meetingUpdateSub = null;
    return super.close();
  }

  /// True when dashboard-driven work should be skipped (app is in force-upgrade).
  bool _isBlockedByForceUpgrade(String operation) {
    if (!PlatformInfoChannel.isInForceUpgradeState()) {
      return false;
    }
    if (kDebugMode) {
      l.logger.d('[DashboardBloc] $operation blocked: force upgrade');
    }
    return true;
  }

  void _recordMeetingCreatedForUserActivity() {
    unawaited(() async {
      try {
        await ManagerFactory()
            .get<UserActivityManager>()
            .recordMeetingCreatedSuccessfully();
      } catch (e) {
        l.logger.d('[DashboardBloc] user activity create: $e');
      }
    }());
  }

  Future<void> _onInitDashboardEvent(
    InitDashboardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    emit(state.copyWith(isLoading: false));
    await _pingCheckForceUpgradeApi();
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      return;
    }
    try {
      add(FetchUserStateEvent());
      add(LoadSignInCardVisibilityEvent());
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      await dataProviderManager.unleashDataProvider.start();
      // Check force upgrade feature flag after unleash provider starts
      final appStateManager = ManagerFactory().get<AppStateManager>();
      appStateManager.checkForceUpgradeFeatureFlag();
    } catch (e) {
      l.logger.e('Error InitDashboardEvent: $e');
    }
  }

  /// Calls `AppCore.ping` so signed-out (and signed-in) users still see API-driven force upgrade.
  Future<void> _pingCheckForceUpgradeApi() async {
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      return;
    }
    try {
      final appCore = ManagerFactory().get<AppCoreManager>().appCore;
      await appCore.ping();
    } on BridgeError catch (e) {
      if (e.consumeBridgeSessionIfNeeded()) {
        return;
      }
      if (e is BridgeError_ApiResponse) {
        enterForceUpgradeFromApiIfNeeded(e.field0);
      }
    } catch (e, st) {
      l.logger.d('[DashboardBloc] ping force-upgrade check: $e\n$st');
    }
  }

  Future<void> _onJoinMeetingWithLinkEvent(
    JoinMeetingWithLinkEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('JoinMeetingWithLink')) {
      return;
    }
    emit(state.copyWith(joinMeetingWithLinkUrl: ""));
    emit(state.copyWith(joinMeetingWithLinkUrl: event.joinMeetingWithLinkUrl));
  }

  Future<void> _onDismissDashboardInfoCardEvent(
    DismissDashboardInfoCardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('DismissDashboardInfoCard')) {
      return;
    }
    if (state.infoCards.isEmpty) {
      emit(state.copyWith(isLoading: false));
      return;
    }
    final next = List.of(state.infoCards)..removeWhere((c) => c.id == event.id);
    emit(state.copyWith(isLoading: false, infoCards: next));
  }

  Future<void> _onFetchUserStateEvent(
    FetchUserStateEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('FetchUserState')) {
      return;
    }
    if (state.hasDashboardMutationInProgress) {
      l.logger.d(
        '[DashboardBloc] FetchUserStateEvent ignored: dashboard mutation in progress',
      );
      return;
    }
    if (state.isDashboardFetchUiBusy) {
      l.logger.d(
        '[DashboardBloc] FetchUserStateEvent ignored: fetch already in progress',
      );
      return;
    }

    emit(
      state.copyWith(
        error: "",
        errorDetail: "",
        isAnonymousUser: false,
        resetError: true,
        isLoading: false,
        isLoaded: false,
        isLoadingPersonalMeeting: true,
        isLoadingScheduledMeetings: true,
      ),
    );
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    final userId = appCoreManager.userID;
    final mailboxPassword = appCoreManager.mailboxPassword;
    if (userId == null ||
        mailboxPassword == null ||
        userId.isEmpty ||
        mailboxPassword.isEmpty) {
      emit(
        state.copyWith(
          error: '',
          errorDetail: "",
          isAnonymousUser: true,
          isLoadingPersonalMeeting: false,
          isLoadingScheduledMeetings: false,
          upcomingMeetings: [],
          // my room count default to 1 because we show the personal meeting room button and it was consider as a room
          myRoomsCount: 1,
          // mark as loaded to show the create meeting button and schedule meeting button to user
          isLoaded: true,
          offerFetchUserStateRetry: false,
        ),
      );
      return;
    }

    // Fetch user state with timeout and retry
    final UserState userState;
    try {
      userState = await utils.retryWithTimeout(
        action: () => appCoreManager.appCore.fetchUserState(
          userId: userId,
          // hacky way to force remote fetch user,
          //  make sure get latest key even without event loop.
          forceRemote: true,
        ),
        operationName: 'fetchUserState',
      );
    } catch (error, stackTrace) {
      if (error is BridgeError && error.consumeBridgeSessionIfNeeded()) {
        return;
      }
      if (error is BridgeError_ApiResponse) {
        l.logger.e(
          '[DashboardBloc] Error fetching user state: ${error.field0.detailString}',
        );
        emit(_recoverableDashboardFailure(state, errorResponse: error.field0));
      } else {
        l.logger.e(
          '[DashboardBloc] Error fetching user state: $error, $stackTrace',
        );
        emit(
          _recoverableDashboardFailure(
            state,
            error: isMissingUserStateError(error)
                ? _generalUserStateError
                : 'Failed to fetch user state: $error',
            errorDetail: error.toString(),
          ),
        );
      }
      return;
    }

    emit(
      state.copyWith(
        isLoadingScheduledMeetings: false,
        isLoadingUpcomingMeetings: true,
      ),
    );

    // Get upcoming meetings with timeout and retry
    late List<FrbUpcomingMeeting> upcomingMeetings;
    try {
      upcomingMeetings = await utils.retryWithTimeout<List<FrbUpcomingMeeting>>(
        action: () => appCoreManager.appCore.getUpcomingMeetings(),
        operationName: 'getUpcomingMeetings',
      );
    } catch (error, stackTrace) {
      if (error is BridgeError && error.consumeBridgeSessionIfNeeded()) {
        return;
      }
      l.logger.e(
        '[DashboardBloc] Error getting upcoming meetings: $error, $stackTrace',
      );
      if (error is BridgeError_ApiResponse) {
        emit(_recoverableDashboardFailure(state, errorResponse: error.field0));
        return;
      }

      if (isMissingUserStateError(error)) {
        final recoverySteps = <String>[
          'initial getUpcomingMeetings failed: $error',
        ];
        try {
          await appCoreManager.appCore.refreshUserStateFromApi(userId: userId);
          recoverySteps.add('refreshUserStateFromApi succeeded');
          upcomingMeetings = await utils
              .retryWithTimeout<List<FrbUpcomingMeeting>>(
                action: () => appCoreManager.appCore.getUpcomingMeetings(),
                operationName: 'getUpcomingMeetings_after_user_state_refresh',
              );
        } catch (retryError, retryStack) {
          l.logger.e(
            '[DashboardBloc] User-state recovery failed: $retryError, $retryStack',
          );
          recoverySteps.add('retry after refresh failed: $retryError');
          emit(
            _recoverableDashboardFailure(
              state,
              error: _generalUserStateError,
              errorDetail: recoverySteps.join('\n'),
            ),
          );
          return;
        }
      } else {
        emit(
          _recoverableDashboardFailure(
            state,
            error: 'Failed to load meetings: $error',
            errorDetail: error.toString(),
          ),
        );
        return;
      }
    }

    emit(
      state.copyWith(
        isLoaded: true,
        isLoadingScheduledMeetings: false,
        isLoadingUpcomingMeetings: false,
        upcomingMeetings: upcomingMeetings,
      ),
    );

    if (upcomingMeetings.isNotEmpty) {
      // Part 1: Personal meeting
      final personalMeeting = upcomingMeetings
          .where((meeting) => meeting.isPersonalMeeting)
          .first;

      final filterdMyRooms = upcomingMeetings.getFilteredAndSortedMyRooms();
      emit(
        state.copyWith(
          isLoadingPersonalMeeting: false,
          personalMeeting: personalMeeting,
          myRoomsCount: filterdMyRooms.length + 1,
        ),
      );
      final filterdMyMeetings = upcomingMeetings
          .getFilteredAndSortedMyMeetings();
      final newList = [
        ...filterdMyMeetings,

        /// Mock upcoming meetings auto debug only
        // ...generateMockUpcomingMeetings(),
      ];
      emit(
        state.copyWith(
          isLoadingScheduledMeetings: false,
          isLoadingUpcomingMeetings: false,
          myMeetingsCount: newList.length,
        ),
      );
      add(UpdateUpcomingStateEvent(upcomingTab: MeetUpcomingTab.myMeetings));
    } else {
      final displayName = userState.userData.name;
      final personalMeetingName = "$displayName's personal meeting";
      try {
        final personalMeeting = await appCoreManager.appCore
            .createPersonalMeeting(
              meetingName: personalMeetingName,
              isRotate: true,
              waitingRoom: false,
            );
        emit(
          state.copyWith(
            isLoadingPersonalMeeting: false,
            isLoadingUpcomingMeetings: false,
            personalMeeting: personalMeeting,
            myRoomsCount: 1,
            upcomingMeetings: [],
          ),
        );
        add(UpdateUpcomingStateEvent(upcomingTab: MeetUpcomingTab.myMeetings));
        _recordMeetingCreatedForUserActivity();
      } catch (error, stackTrace) {
        if (error is BridgeError && error.consumeBridgeSessionIfNeeded()) {
          emit(
            state.copyWith(
              isLoadingPersonalMeeting: false,
              isLoadingUpcomingMeetings: false,
              isLoaded: true,
              offerFetchUserStateRetry: false,
            ),
          );
          return;
        }
        captureCreateRoomFailureToSentry(
          flow: 'dashboard_bootstrap_personal_meeting',
          error: error,
          stackTrace: stackTrace,
          meetingType: MeetingType.personal,
          hasSession: true,
          meetingNameLength: personalMeetingName.length,
        );
        if (error is BridgeError_ApiResponse) {
          l.logger.e(
            '[DashboardBloc] Error creating personal meeting: ${error.field0.detailString}',
          );
          emit(
            state.copyWith(
              resetError: true,
              error: '',
              errorResponse: error.field0,
              errorDetail:
                  'Failed to create personal meeting: ${error.field0.detailString}',
              isLoadingPersonalMeeting: false,
              isLoadingUpcomingMeetings: false,
              isLoaded: true,
              offerFetchUserStateRetry: true,
            ),
          );
        } else {
          l.logger.e(
            '[DashboardBloc] Error creating personal meeting: $error, $stackTrace',
          );
          emit(
            state.copyWith(
              resetError: true,
              error: 'Failed to create personal meeting: $error',
              errorDetail: error.toString(),
              isLoadingPersonalMeeting: false,
              isLoadingUpcomingMeetings: false,
              isLoaded: true,
              offerFetchUserStateRetry: true,
            ),
          );
        }
      }
    }
  }

  static const String _generalUserStateError =
      'Unable to load your meetings right now. Please try again.';

  /// Shown when create/schedule meeting recovery (refresh + retry) still fails.
  static const String _meetingUserStateFailureMessage =
      'Unable to create or schedule your meeting right now. Please try again.';

  String _meetCoreBridgeDiagnostic(String payload) {
    final details = parseMeetCoreServiceErrorDetails(payload);
    final detailsSuffix = details == null ? '' : ', details: $details';
    return 'Meet core — ${meetCoreServiceMessageLine(payload)}'
        '$detailsSuffix\nraw: $payload';
  }

  /// Human-readable bridge/API payload for error details (support / debug).
  String _errorDiagnostic(Object error) {
    if (error is BridgeError) {
      return switch (error) {
        BridgeError_ApiResponse(:final field0) =>
          'API response — code: ${field0.code}, error: ${field0.error}, '
              'details: ${field0.details.isEmpty ? "(none)" : field0.details}',
        BridgeError_MeetCore(:final field0) => _meetCoreBridgeDiagnostic(
          field0,
        ),
        _ =>
          '${error.runtimeType} — user: ${error.userMessage}, '
              'detail: ${error.detailMessage}',
      };
    }
    return '${error.runtimeType}: $error';
  }

  Never _throwCreateMeetingRecoveryFailed({
    required List<String> recoveryLog,
    required Object lastError,
  }) {
    throw CreateMeetingUserStateRecoveryFailure(
      recoveryLog: recoveryLog,
      lastError: lastError,
    );
  }

  /// Calls [createMeeting]; on missing active user, refreshes user state and retries once.
  Future<FrbUpcomingMeeting> _createMeetingWithUserStateRecovery({
    required AppCoreManager appCoreManager,
    required String meetingName,
    required bool hasSession,
    required MeetingType meetingType,
    String? customPassword,
    int? startTime,
    int? endTime,
    String? timeZone,
    String? rRule,
    bool waitingRoom = false,
  }) async {
    Future<FrbUpcomingMeeting> create() => appCoreManager.appCore.createMeeting(
      meetingName: meetingName,
      hasSession: hasSession,
      meetingType: meetingType,
      customPassword: customPassword,
      startTime: startTime,
      endTime: endTime,
      timeZone: timeZone,
      rRule: rRule,
      waitingRoom: waitingRoom,
    );

    try {
      return await create();
    } on BridgeError catch (error) {
      if (!error.isMissingUserState) {
        rethrow;
      }
      final userId = appCoreManager.userID;
      if (userId == null || userId.isEmpty) {
        rethrow;
      }

      final recoveryLog = <String>[
        'createMeeting (attempt 1): ${_errorDiagnostic(error)}',
      ];
      l.logger.w(
        '[DashboardBloc] createMeeting missing user state; '
        'refreshing user state and retrying. $error',
      );

      try {
        await appCoreManager.appCore.refreshUserStateFromApi(userId: userId);
        recoveryLog.add('refreshUserStateFromApi: succeeded');
      } catch (refreshError, refreshStack) {
        recoveryLog.add(
          'refreshUserStateFromApi: failed — ${_errorDiagnostic(refreshError)}',
        );
        l.logger.e(
          '[DashboardBloc] refreshUserStateFromApi failed during create recovery',
          error: refreshError,
          stackTrace: refreshStack,
        );
        _throwCreateMeetingRecoveryFailed(
          recoveryLog: recoveryLog,
          lastError: refreshError,
        );
      }

      try {
        return await create();
      } catch (retryError, retryStack) {
        recoveryLog.add(
          'createMeeting (attempt 2): ${_errorDiagnostic(retryError)}',
        );
        l.logger.e(
          '[DashboardBloc] createMeeting retry failed after user-state refresh',
          error: retryError,
          stackTrace: retryStack,
        );
        _throwCreateMeetingRecoveryFailed(
          recoveryLog: recoveryLog,
          lastError: retryError,
        );
      }
    }
  }

  /// After failed fetch/load: empty lists, loaded flag, and CTAs visible again.
  DashboardState _recoverableDashboardFailure(
    DashboardState base, {
    String? error,
    ResponseError? errorResponse,
    String? errorDetail,
  }) {
    return base.copyWith(
      resetError: true,
      error: error ?? '',
      errorDetail: errorDetail,
      errorResponse: errorResponse,
      isLoaded: true,
      isLoadingPersonalMeeting: false,
      isLoadingScheduledMeetings: false,
      isLoadingUpcomingMeetings: false,
      upcomingMeetings: const [],
      meetinsDisplay: const [],
      clearPersonalMeeting: true,
      myMeetingsCount: 0,
      myRoomsCount: 0,
      offerFetchUserStateRetry: true,
    );
  }

  Future<void> _onCreatePersonalMeetingEvent(
    CreatePersonalMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('CreatePersonalMeeting')) {
      return;
    }
    emit(
      state.copyWith(
        error: "",
        errorDetail: "",
        isLoadingPersonalMeeting: true,
        goPersonalMeeting: false,
        offerFetchUserStateRetry: false,
      ),
    );

    if (state.personalMeeting != null) {
      if (event.goPersonalMeeting) {
        emit(
          state.copyWith(
            isLoadingPersonalMeeting: false,
            goPersonalMeeting: true,
            isLoading: false,
          ),
        );
      }
      return;
    }

    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    try {
      final personalMeetingName = "Personal Meeting";
      final personalMeeting = await appCoreManager.appCore
          .createPersonalMeeting(
            meetingName: personalMeetingName,
            isRotate: true,
            waitingRoom: false,
          );
      emit(
        state.copyWith(
          isLoadingPersonalMeeting: false,
          personalMeeting: personalMeeting,
          goPersonalMeeting: event.goPersonalMeeting,
        ),
      );
      _recordMeetingCreatedForUserActivity();
    } catch (error, stackTrace) {
      if (error is BridgeError && error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingPersonalMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      const nameLen = 'Personal Meeting'.length;
      captureCreateRoomFailureToSentry(
        flow: 'dashboard_create_personal_meeting',
        error: error,
        stackTrace: stackTrace,
        meetingType: MeetingType.personal,
        hasSession: true,
        meetingNameLength: nameLen,
      );
      if (error is BridgeError_ApiResponse) {
        l.logger.e(
          '[DashboardBloc] Error creating personal meeting: ${error.field0.detailString}',
        );
        emit(
          state.copyWith(
            resetError: true,
            error: '',
            errorResponse: error.field0,
            errorDetail:
                'Failed to create personal meeting: ${error.field0.detailString}',
            offerFetchUserStateRetry: false,
          ),
        );
      } else {
        l.logger.e(
          '[DashboardBloc] Error creating personal meeting: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            resetError: true,
            error: 'Failed to create personal meeting: $error',
            errorDetail: error.toString(),
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
    emit(state.copyWith(isLoading: false, isLoadingPersonalMeeting: false));
  }

  Future<void> _onRotatePersonalMeetingLinkEvent(
    RotatePersonalMeetingLinkEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('RotatePersonalMeetingLink')) {
      return;
    }
    emit(
      state.copyWith(
        error: "",
        errorDetail: "",
        isLoadingPersonalMeeting: true,
        offerFetchUserStateRetry: false,
      ),
    );

    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    try {
      final personalMeetingName = "Personal Meeting";
      final personalMeeting = await appCoreManager.appCore
          .createPersonalMeeting(
            meetingName: personalMeetingName,
            isRotate: true,
            waitingRoom: false,
          );
      emit(
        state.copyWith(
          isLoadingPersonalMeeting: false,
          personalMeeting: personalMeeting,
        ),
      );
    } catch (error, stackTrace) {
      if (error is BridgeError && error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingPersonalMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      const nameLen = 'Personal Meeting'.length;
      captureCreateRoomFailureToSentry(
        flow: 'dashboard_rotate_personal_meeting',
        error: error,
        stackTrace: stackTrace,
        meetingType: MeetingType.personal,
        hasSession: true,
        meetingNameLength: nameLen,
      );
      if (error is BridgeError_ApiResponse) {
        l.logger.e(
          '[DashboardBloc] Error rotating personal meeting link: ${error.field0.detailString}',
        );
        emit(
          state.copyWith(
            error: error.field0.error,
            errorDetail:
                'Failed to rotate personal meeting link: ${error.field0.detailString}',
            isLoadingPersonalMeeting: false,
            offerFetchUserStateRetry: false,
          ),
        );
      } else {
        l.logger.e(
          '[DashboardBloc] Error rotating personal meeting link: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            error: 'Failed to rotate personal meeting link: $error',
            errorDetail: error.toString(),
            isLoadingPersonalMeeting: false,
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
    emit(state.copyWith(isLoading: false, isLoadingPersonalMeeting: false));
  }

  Future<void> _onCreateSecureMeetingEvent(
    CreateSecureMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('CreateSecureMeeting')) {
      return;
    }
    emit(
      state.copyWith(
        error: "",
        errorDetail: "",
        isLoadingSecureMeeting: true,
        goSecureMeeting: false,
        offerFetchUserStateRetry: false,
      ),
    );

    emit(
      state.copyWith(
        isLoading: false,
        isLoadingSecureMeeting: false,
        goSecureMeeting: true,
      ),
    );
  }

  void _onResetEarlyAccessDialogEvent(
    ResetEarlyAccessDialogEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('ResetEarlyAccessDialog')) {
      return;
    }
    emit(state.copyWith(showEarlyAccessDialog: false, isLoading: false));
  }

  void _onUpdateUpcomingStateEvent(
    UpdateUpcomingStateEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('UpdateUpcomingState')) {
      return;
    }
    if (state.isLoadingUpcomingMeetings) {
      emit(state.copyWith(upcomingTab: event.upcomingTab));
      return;
    }

    emit(
      state.copyWith(
        upcomingTab: event.upcomingTab,
        isLoadingUpcomingMeetings: true,
      ),
    );

    if (event.upcomingTab == MeetUpcomingTab.myMeetings) {
      final filterdMyMeetings = state.upcomingMeetings
          .getFilteredAndSortedMyMeetings();
      final sortedMeetings = filterdMyMeetings.sortMeetings(
        state.sortOptionMyMeetings,
      );

      emit(
        state.copyWith(
          isLoadingUpcomingMeetings: false,
          meetinsDisplay: sortedMeetings,
          myMeetingsCount: sortedMeetings.length,
        ),
      );
    } else {
      final filterdMyRooms = state.upcomingMeetings
          .getFilteredAndSortedMyRooms();
      final sortedRooms = filterdMyRooms.sortRoomsWithPersonalFirst(
        state.sortOptionMyRooms,
      );

      if (state.personalMeeting != null) {
        final allMeetings = [state.personalMeeting!, ...sortedRooms];
        final sortedAll = allMeetings.sortRoomsWithPersonalFirst(
          state.sortOptionMyRooms,
        );
        emit(
          state.copyWith(
            isLoadingUpcomingMeetings: false,
            meetinsDisplay: sortedAll,
            myRoomsCount: sortedRooms.length + 1,
          ),
        );
      } else {
        emit(
          state.copyWith(
            isLoadingUpcomingMeetings: false,
            meetinsDisplay: sortedRooms,

            /// if anonymous user, my room count default to 1 because we show the personal meeting room button and it was consider as a room
            myRoomsCount: state.isAnonymousUser ? 1 : sortedRooms.length,
          ),
        );
      }
    }
  }

  Future<void> _onResetDashboardStateEvent(
    ResetDashboardStateEvent event,
    Emitter<DashboardState> emit,
  ) async {
    // Reset all user-specific state. isLoaded must stay true so empty-state CTAs
    // (schedule / create room) show for signed-out users—same as no-credentials fetch path.
    emit(const DashboardState(isLoaded: true));
    l.logger.d('[DashboardBloc] Dashboard state reset after logout');
    unawaited(_pingCheckForceUpgradeApi());
  }

  Future<void> _onCreateMeetingEvent(
    CreateMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('CreateMeeting')) {
      return;
    }
    emit(
      state.copyWith(
        resetError: true,
        isLoadingCreateMeeting: true,
        isLoading: true,
      ),
    );

    // Set up timeout to auto-dismiss loading after 30 seconds
    Timer? timeoutTimer;
    bool operationCompleted = false;

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!isClosed && !operationCompleted) {
        l.logger.w('[DashboardBloc] Create meeting timeout after 30s');
        emit(
          state.copyWith(
            isLoadingCreateMeeting: false,
            isLoading: false,
            error: 'Meeting creation timed out. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    });

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      final upcomingMeeting = await _createMeetingWithUserStateRecovery(
        appCoreManager: appCoreManager,
        meetingName: event.roomName,
        hasSession: true,
        meetingType: MeetingType.permanent,
        waitingRoom: event.waitingRoom,
      );
      operationCompleted = true;
      timeoutTimer.cancel();

      // Format meeting link for copying
      final meetingLink = upcomingMeeting.formatMeetingLink();

      final updatedMeetings = [...state.upcomingMeetings, upcomingMeeting];
      final filterdMyRooms = updatedMeetings.getFilteredAndSortedMyRooms();
      final filterdMyMeetings = updatedMeetings
          .getFilteredAndSortedMyMeetings();

      final myRoomsCount = state.personalMeeting != null
          ? filterdMyRooms.length + 1
          : filterdMyRooms.length;

      emit(
        state.copyWith(
          isLoadingCreateMeeting: false,
          isLoading: false,
          upcomingMeetings: updatedMeetings,
          myRoomsCount: myRoomsCount,
          myMeetingsCount: filterdMyMeetings.length,
          createdMeetingLink: meetingLink,
          upcomingTab: MeetUpcomingTab.myRooms,
          sortOptionMyRooms: SortOptionMyRooms.newCreated,
        ),
      );
      add(UpdateUpcomingStateEvent(upcomingTab: MeetUpcomingTab.myRooms));
      _recordMeetingCreatedForUserActivity();
    } on CreateMeetingUserStateRecoveryFailure catch (failure, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      l.logger.e(
        '[DashboardBloc] Create meeting failed after user-state recovery\n'
        '${failure.diagnosticLog}',
        error: failure.lastError,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            isLoadingCreateMeeting: false,
            isLoading: false,
            error: _meetingUserStateFailureMessage,
            errorDetail: failure.diagnosticLog,
            offerFetchUserStateRetry: true,
          ),
        );
      }
    } on BridgeError catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingCreateMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      if (!isClosed) {
        if (error is BridgeError_ApiResponse) {
          captureCreateRoomFailureToSentry(
            flow: 'dashboard_create_permanent_room',
            error: error,
            stackTrace: stackTrace,
            meetingType: MeetingType.permanent,
            hasSession: true,
            meetingNameLength: event.roomName.length,
          );
          l.logger.e('[DashboardBloc] Error creating meeting: $error');
          emit(
            state.copyWith(
              isLoadingCreateMeeting: false,
              isLoading: false,
              errorResponse: error.field0,
              offerFetchUserStateRetry: false,
            ),
          );
        } else {
          if (error.isMissingUserState) {
            l.logger.w(
              '[DashboardBloc] Create meeting missing user state. '
              'error=$error detail=${error.detailMessage}',
            );
          }
          l.logger.e(
            '[DashboardBloc] Error creating meeting: $error, $stackTrace',
          );
          emit(
            state.copyWith(
              isLoadingCreateMeeting: false,
              isLoading: false,
              error: error.isMissingUserState
                  ? _generalUserStateError
                  : extractErrorMessage(error),
              errorDetail: error.isMissingUserState ? error.toString() : '',
              offerFetchUserStateRetry: error.isMissingUserState,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (!isClosed) {
        final errorMessage = 'Failed to create meeting: $error';
        l.logger.e(
          '[DashboardBloc] Error creating meeting: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            isLoadingCreateMeeting: false,
            isLoading: false,
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  Future<void> _onDeleteMeetingEvent(
    DeleteMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('DeleteMeeting')) {
      return;
    }
    emit(
      state.copyWith(
        resetError: true,
        isLoadingDeleteMeeting: true,
        isLoading: true,
      ),
    );

    // Set up timeout to auto-dismiss loading after 30 seconds
    Timer? timeoutTimer;
    bool operationCompleted = false;

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!isClosed && !operationCompleted) {
        l.logger.w('[DashboardBloc] Delete meeting timeout after 30s');
        emit(
          state.copyWith(
            isLoadingDeleteMeeting: false,
            isLoading: false,
            error: 'Meeting deletion timed out. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    });

    try {
      // For now, remove from local list
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      await appCoreManager.appCore.deleteMeeting(meetingName: event.meetingId);

      // Remove meeting from local list
      final updatedMeetings = state.upcomingMeetings
          .where((meeting) => meeting.id != event.meetingId)
          .toList();

      // Check if deleted meeting was personal meeting
      final wasPersonalMeeting = state.personalMeeting?.id == event.meetingId;

      operationCompleted = true;
      timeoutTimer.cancel();

      if (!isClosed) {
        emit(
          state.copyWith(
            isLoadingDeleteMeeting: false,
            isLoading: false,
            upcomingMeetings: updatedMeetings,
            clearPersonalMeeting: wasPersonalMeeting,
          ),
        );
        // Update display based on current tab
        add(UpdateUpcomingStateEvent(upcomingTab: state.upcomingTab));
      }
    } on BridgeError catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingDeleteMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      if (!isClosed) {
        if (error is BridgeError_ApiResponse) {
          l.logger.e('[DashboardBloc] Error deleting meeting: $error');
          emit(
            state.copyWith(
              isLoadingDeleteMeeting: false,
              isLoading: false,
              errorResponse: error.field0,
              offerFetchUserStateRetry: false,
            ),
          );
        } else {
          l.logger.e(
            '[DashboardBloc] Error deleting meeting: $error, $stackTrace',
          );
          emit(
            state.copyWith(
              isLoadingDeleteMeeting: false,
              isLoading: false,
              error: extractErrorMessage(error),
              errorDetail: '',
              offerFetchUserStateRetry: false,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (!isClosed) {
        final errorMessage = 'Failed to delete meeting: $error';
        l.logger.e(
          '[DashboardBloc] Error deleting meeting: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            isLoadingDeleteMeeting: false,
            isLoading: false,
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  Future<void> _onUpdateMeetingEvent(
    UpdateMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('UpdateMeeting')) {
      return;
    }
    final updatedName = event.updatedMeetingName.trim();
    if (updatedName.isEmpty) {
      return;
    }

    emit(
      state.copyWith(
        resetError: true,
        isLoadingUpdateMeeting: true,
        isLoading: true,
      ),
    );

    // Set up timeout to auto-dismiss loading after 30 seconds
    Timer? timeoutTimer;
    bool operationCompleted = false;

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!isClosed && !operationCompleted) {
        l.logger.w('[DashboardBloc] Update meeting timeout after 30s');
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            error: 'Meeting update timed out. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    });

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      final appCore = appCoreManager.appCore;
      final updatedMeeting = await appCore.editMeetingName(
        meetingId: event.meeting.id,
        newMeetingName: updatedName,
        meetingPassword: event.meeting.meetingPassword,
      );

      final updatedMeetings = List<FrbUpcomingMeeting>.from(
        state.upcomingMeetings,
      );
      final updatedIndex = updatedMeetings.indexWhere(
        (meeting) => meeting.id == updatedMeeting.id,
      );
      if (updatedIndex != -1) {
        final existing = updatedMeetings[updatedIndex];
        updatedMeetings[updatedIndex] = FrbUpcomingMeeting(
          id: updatedMeeting.id,
          addressId: updatedMeeting.addressId,
          meetingLinkName: updatedMeeting.meetingLinkName,
          meetingName: updatedMeeting.meetingName,
          meetingPassword: updatedMeeting.meetingPassword,
          meetingType: updatedMeeting.meetingType,
          startTime: updatedMeeting.startTime,
          endTime: updatedMeeting.endTime,
          rRule: updatedMeeting.rRule,
          timeZone: updatedMeeting.timeZone,
          calendarId: updatedMeeting.calendarId,
          protonCalendar: updatedMeeting.protonCalendar,
          createTime: updatedMeeting.createTime,
          lastUsedTime: updatedMeeting.lastUsedTime,
          calendarEventId: updatedMeeting.calendarEventId,
          waitingRoom: existing.waitingRoom ?? updatedMeeting.waitingRoom,
        );
      }

      final isPersonalMeetingUpdate = updatedMeeting.isPersonalMeeting;

      operationCompleted = true;
      timeoutTimer.cancel();

      if (!isClosed) {
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            upcomingMeetings: updatedMeetings,
            personalMeeting: isPersonalMeetingUpdate
                ? updatedMeeting
                : state.personalMeeting,
          ),
        );
        add(UpdateUpcomingStateEvent(upcomingTab: state.upcomingTab));
      }
    } on BridgeError catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      if (!isClosed) {
        if (error is BridgeError_ApiResponse) {
          l.logger.e(
            '[DashboardBloc] Error updating meeting: ${error.field0.detailString}',
          );
          emit(
            state.copyWith(
              isLoadingUpdateMeeting: false,
              isLoading: false,
              errorResponse: error.field0,
              offerFetchUserStateRetry: false,
            ),
          );
        } else {
          l.logger.e(
            '[DashboardBloc] Error updating meeting: $error, $stackTrace',
          );
          emit(
            state.copyWith(
              isLoadingUpdateMeeting: false,
              isLoading: false,
              error: extractErrorMessage(error),
              errorDetail: '',
              offerFetchUserStateRetry: false,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (!isClosed) {
        final errorMessage = 'Failed to update meeting: $error';
        l.logger.e(
          '[DashboardBloc] Error updating meeting: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  void _onClearCreatedMeetingLinkEvent(
    ClearCreatedMeetingLinkEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('ClearCreatedMeetingLink')) {
      return;
    }
    emit(state.copyWith(createdMeetingLink: ''));
  }

  Future<void> _onScheduleMeetingEvent(
    ScheduleMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('ScheduleMeeting')) {
      return;
    }
    emit(
      state.copyWith(
        resetError: true,
        isLoadingScheduleMeeting: true,
        isLoading: true,
      ),
    );

    Timer? timeoutTimer;
    bool operationCompleted = false;

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!isClosed && !operationCompleted) {
        l.logger.w('[DashboardBloc] Schedule meeting timeout after 30s');
        emit(
          state.copyWith(
            isLoadingScheduleMeeting: false,
            isLoading: false,
            error: 'Meeting scheduling timed out. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    });

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      final normalizedTimeZone = _normalizeTimeZone(event.data.timeZone);

      // Create DateTime in the selected timezone
      tz.TZDateTime startDateTime;
      if (normalizedTimeZone != null) {
        try {
          final location = tz.getLocation(normalizedTimeZone);
          startDateTime = tz.TZDateTime(
            location,
            event.data.startDate.year,
            event.data.startDate.month,
            event.data.startDate.day,
            event.data.startTime.hour,
            event.data.startTime.minute,
          );
        } catch (e) {
          // Fallback to local timezone if timezone is invalid
          l.logger.w('Invalid timezone $normalizedTimeZone, using local: $e');
          startDateTime = tz.TZDateTime.local(
            event.data.startDate.year,
            event.data.startDate.month,
            event.data.startDate.day,
            event.data.startTime.hour,
            event.data.startTime.minute,
          );
        }
      } else {
        // Use local timezone if no timezone specified
        startDateTime = tz.TZDateTime.local(
          event.data.startDate.year,
          event.data.startDate.month,
          event.data.startDate.day,
          event.data.startTime.hour,
          event.data.startTime.minute,
        );
      }

      final endDateTime = startDateTime.add(
        Duration(minutes: event.data.durationMinutes),
      );

      // Convert to UTC timestamps (seconds)
      final startTimestamp =
          startDateTime.toUtc().millisecondsSinceEpoch ~/ 1000;
      final endTimestamp = endDateTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      final rRule = _mapRecurrenceToRRule(event.data.recurrence);
      final meetingType = event.data.recurrence == RecurrenceFrequency.none
          ? MeetingType.scheduled
          : MeetingType.recurring;
      final upcomingMeeting = await _createMeetingWithUserStateRecovery(
        appCoreManager: appCoreManager,
        meetingName: event.data.title,
        hasSession: true,
        meetingType: meetingType,
        startTime: startTimestamp,
        endTime: endTimestamp,
        timeZone: normalizedTimeZone,
        rRule: rRule,
        waitingRoom: event.data.waitingRoomEnabled,
      );

      operationCompleted = true;
      timeoutTimer.cancel();

      final updatedMeetings = [...state.upcomingMeetings, upcomingMeeting];
      final filterdMyRooms = updatedMeetings.getFilteredAndSortedMyRooms();
      final filterdMyMeetings = updatedMeetings
          .getFilteredAndSortedMyMeetings();

      final myRoomsCount = state.personalMeeting != null
          ? filterdMyRooms.length + 1
          : filterdMyRooms.length;

      emit(
        state.copyWith(
          isLoadingScheduleMeeting: false,
          isLoading: false,
          upcomingMeetings: updatedMeetings,
          myRoomsCount: myRoomsCount,
          myMeetingsCount: filterdMyMeetings.length,
          scheduledMeeting: upcomingMeeting,
          scheduledMeetingData: event.data,
          upcomingTab: MeetUpcomingTab.myMeetings,
          sortOptionMyMeetings: SortOptionMyMeetings.newCreated,
        ),
      );
      add(UpdateUpcomingStateEvent(upcomingTab: MeetUpcomingTab.myMeetings));
      _recordMeetingCreatedForUserActivity();
    } on CreateMeetingUserStateRecoveryFailure catch (failure, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      l.logger.e(
        '[DashboardBloc] Schedule meeting failed after user-state recovery\n'
        '${failure.diagnosticLog}',
        error: failure.lastError,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            isLoadingScheduleMeeting: false,
            isLoading: false,
            error: _meetingUserStateFailureMessage,
            errorDetail: failure.diagnosticLog,
            offerFetchUserStateRetry: true,
          ),
        );
      }
    } on BridgeError catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingScheduleMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      if (!isClosed) {
        final meetingType = event.data.recurrence == RecurrenceFrequency.none
            ? MeetingType.scheduled
            : MeetingType.recurring;
        if (error is BridgeError_ApiResponse) {
          l.logger.e('[DashboardBloc] Error scheduling meeting: $error');
          captureCreateRoomFailureToSentry(
            flow: 'dashboard_schedule_meeting',
            error: error,
            stackTrace: stackTrace,
            meetingType: meetingType,
            hasSession: true,
            meetingNameLength: event.data.title.length,
            scheduledMeeting: true,
          );
          emit(
            state.copyWith(
              isLoadingScheduleMeeting: false,
              isLoading: false,
              errorResponse: error.field0,
              offerFetchUserStateRetry: false,
            ),
          );
        } else {
          if (error.isMissingUserState) {
            l.logger.w(
              '[DashboardBloc] Schedule meeting missing user state. '
              'error=$error detail=${error.detailMessage}',
            );
          }
          l.logger.e(
            '[DashboardBloc] Error scheduling meeting: $error, $stackTrace',
          );
          captureCreateRoomFailureToSentry(
            flow: 'dashboard_schedule_meeting',
            error: error,
            stackTrace: stackTrace,
            meetingType: meetingType,
            hasSession: true,
            meetingNameLength: event.data.title.length,
            scheduledMeeting: true,
          );
          emit(
            state.copyWith(
              isLoadingScheduleMeeting: false,
              isLoading: false,
              error: error.isMissingUserState
                  ? _generalUserStateError
                  : extractErrorMessage(error),
              errorDetail: error.isMissingUserState ? error.toString() : '',
              offerFetchUserStateRetry: error.isMissingUserState,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (!isClosed) {
        final errorMessage = 'Failed to schedule meeting: $error';
        l.logger.e(
          '[DashboardBloc] Error scheduling meeting: $error, $stackTrace',
        );
        final meetingType = event.data.recurrence == RecurrenceFrequency.none
            ? MeetingType.scheduled
            : MeetingType.recurring;
        captureCreateRoomFailureToSentry(
          flow: 'dashboard_schedule_meeting',
          error: error,
          stackTrace: stackTrace,
          meetingType: meetingType,
          hasSession: true,
          meetingNameLength: event.data.title.length,
          scheduledMeeting: true,
        );
        emit(
          state.copyWith(
            isLoadingScheduleMeeting: false,
            isLoading: false,
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  Future<void> _onUpdateScheduledMeetingEvent(
    UpdateScheduledMeetingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('UpdateScheduledMeeting')) {
      return;
    }
    if (event.previewOnly) {
      emit(state.copyWith(resetScheduledMeeting: true));
      emit(
        state.copyWith(
          scheduledMeeting: event.meeting,
          scheduledMeetingData: event.data,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        resetError: true,
        isLoadingUpdateMeeting: true,
        isLoading: true,
      ),
    );

    Timer? timeoutTimer;
    bool operationCompleted = false;

    timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!isClosed && !operationCompleted) {
        l.logger.w(
          '[DashboardBloc] Update scheduled meeting timeout after 30s',
        );
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            error: 'Meeting update timed out. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    });

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      final appCore = appCoreManager.appCore;
      final updatedTitle = event.data.title.trim();
      FrbUpcomingMeeting updatedMeeting = event.meeting;
      if (updatedTitle.isNotEmpty &&
          updatedTitle != event.meeting.meetingName) {
        updatedMeeting = await appCore.editMeetingName(
          meetingId: event.meeting.id,
          newMeetingName: updatedTitle,
          meetingPassword: event.meeting.meetingPassword,
        );
      }

      final normalizedTimeZone = _normalizeTimeZone(event.data.timeZone);

      // Create DateTime in the selected timezone
      tz.TZDateTime startDateTime;
      if (normalizedTimeZone != null) {
        try {
          final location = tz.getLocation(normalizedTimeZone);
          startDateTime = tz.TZDateTime(
            location,
            event.data.startDate.year,
            event.data.startDate.month,
            event.data.startDate.day,
            event.data.startTime.hour,
            event.data.startTime.minute,
          );
        } catch (e) {
          // Fallback to local timezone if timezone is invalid
          l.logger.w('Invalid timezone $normalizedTimeZone, using local: $e');
          startDateTime = tz.TZDateTime.local(
            event.data.startDate.year,
            event.data.startDate.month,
            event.data.startDate.day,
            event.data.startTime.hour,
            event.data.startTime.minute,
          );
        }
      } else {
        // Use local timezone if no timezone specified
        startDateTime = tz.TZDateTime.local(
          event.data.startDate.year,
          event.data.startDate.month,
          event.data.startDate.day,
          event.data.startTime.hour,
          event.data.startTime.minute,
        );
      }

      final endDateTime = startDateTime.add(
        Duration(minutes: event.data.durationMinutes),
      );

      // Convert to UTC timestamps (seconds)
      final startTimestamp =
          startDateTime.toUtc().millisecondsSinceEpoch ~/ 1000;
      final endTimestamp = endDateTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      final rRule = _mapRecurrenceToRRule(event.data.recurrence);
      final updatedSchedule = await appCore.updateMeetingSchedule(
        meetingId: updatedMeeting.id,
        meetingName: updatedMeeting.meetingName,
        meetingPassword: updatedMeeting.meetingPassword,
        startTime: startTimestamp,
        endTime: endTimestamp,
        timeZone: normalizedTimeZone,
        rRule: rRule,
      );

      final updatedMeetings = List<FrbUpcomingMeeting>.from(
        state.upcomingMeetings,
      );
      final updatedIndex = updatedMeetings.indexWhere(
        (meeting) => meeting.id == updatedSchedule.id,
      );
      if (updatedIndex != -1) {
        updatedMeetings[updatedIndex] = updatedSchedule.withWaitingRoom(
          enabled: event.data.waitingRoomEnabled,
        );
      }

      operationCompleted = true;
      timeoutTimer.cancel();

      if (!isClosed) {
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            upcomingMeetings: updatedMeetings,
            scheduledMeetingData: event.data,
            scheduledMeeting: updatedSchedule.withWaitingRoom(
              enabled: event.data.waitingRoomEnabled,
            ),
          ),
        );
        add(UpdateUpcomingStateEvent(upcomingTab: state.upcomingTab));
      }
    } on BridgeError catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      if (!isClosed) {
        if (error is BridgeError_ApiResponse) {
          l.logger.e('[DashboardBloc] Error updating meeting: $error');
          emit(
            state.copyWith(
              isLoadingUpdateMeeting: false,
              isLoading: false,
              errorResponse: error.field0,
              offerFetchUserStateRetry: false,
            ),
          );
        } else {
          l.logger.e(
            '[DashboardBloc] Error updating meeting: $error, $stackTrace',
          );
          emit(
            state.copyWith(
              isLoadingUpdateMeeting: false,
              isLoading: false,
              error: extractErrorMessage(error),
              errorDetail: '',
              offerFetchUserStateRetry: false,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      operationCompleted = true;
      timeoutTimer.cancel();
      if (!isClosed) {
        final errorMessage = 'Failed to update meeting: $error';
        l.logger.e(
          '[DashboardBloc] Error updating meeting: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            isLoadingUpdateMeeting: false,
            isLoading: false,
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  String? _mapRecurrenceToRRule(RecurrenceFrequency recurrence) {
    switch (recurrence) {
      case RecurrenceFrequency.none:
        return null;
      case RecurrenceFrequency.daily:
        return 'FREQ=DAILY';
      case RecurrenceFrequency.weekly:
        return 'FREQ=WEEKLY';
      case RecurrenceFrequency.monthly:
        return 'FREQ=MONTHLY';
      case RecurrenceFrequency.yearly:
        return 'FREQ=YEARLY';
    }
  }

  String? _normalizeTimeZone(String? timeZone) {
    if (timeZone == null || timeZone.isEmpty) {
      return null;
    }
    final trimmed = timeZone.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (tz.timeZoneDatabase.locations.containsKey(trimmed)) {
      return timeZone;
    }
    final lower = trimmed.toLowerCase();
    final directMatch = tz.timeZoneDatabase.locations.keys.firstWhere(
      (zone) => zone.toLowerCase() == lower,
      orElse: () => '',
    );
    if (directMatch.isNotEmpty) {
      return directMatch;
    }
    final suffixMatch = tz.timeZoneDatabase.locations.keys.firstWhere(
      (zone) => zone.toLowerCase().endsWith('/$lower'),
      orElse: () => '',
    );
    if (suffixMatch.isNotEmpty) {
      return suffixMatch;
    }
    final abbrMatch = _matchTimeZoneByAbbreviation(lower);
    if (abbrMatch != null) {
      return abbrMatch;
    }
    return trimmed;
  }

  String? _matchTimeZoneByAbbreviation(String abbreviation) {
    final abbr = abbreviation.toUpperCase();
    final offset = DateTime.now().timeZoneOffset;
    String? bestMatch;
    for (final entry in tz.timeZoneDatabase.locations.entries) {
      final zoneNow = tz.TZDateTime.now(entry.value);
      if (zoneNow.timeZoneOffset == offset &&
          zoneNow.timeZoneName.toUpperCase() == abbr) {
        bestMatch ??= entry.key;
        if (entry.key.contains('/')) {
          return entry.key;
        }
      }
    }
    return bestMatch;
  }

  void _onClearScheduledMeetingSummaryEvent(
    ClearScheduledMeetingSummaryEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('ClearScheduledMeetingSummary')) {
      return;
    }
    emit(state.copyWith());
  }

  void _onClearScheduledMeetingIcsEvent(
    ClearScheduledMeetingIcsEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('ClearScheduledMeetingIcs')) {
      return;
    }
    emit(state.copyWith());
  }

  Future<void> _onDownloadScheduledMeetingIcsEvent(
    DownloadScheduledMeetingIcsEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('DownloadScheduledMeetingIcs')) {
      return;
    }
    try {
      final icsContent = await _generateIcsWithRust(
        event.data,
        meetingLink: event.meetingLink,
      );
      emit(
        state.copyWith(
          scheduledMeetingIcsContent: icsContent,
          scheduledMeetingIcsTitle: event.data.title,
        ),
      );
    } catch (error, stackTrace) {
      if (error is BridgeError && error.consumeBridgeSessionIfNeeded()) {
        emit(
          state.copyWith(
            error: '',
            errorDetail: '',
            offerFetchUserStateRetry: false,
          ),
        );
        return;
      }
      if (!isClosed) {
        final errorMessage = 'Failed to generate ICS: $error';
        l.logger.e('[DashboardBloc] Error generating ICS: $error, $stackTrace');
        emit(
          state.copyWith(
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  Future<void> _onAddScheduledMeetingToCalendarEvent(
    AddScheduledMeetingToCalendarEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('AddScheduledMeetingToCalendar')) {
      return;
    }
    try {
      final startDateTime = DateTime(
        event.data.startDate.year,
        event.data.startDate.month,
        event.data.startDate.day,
        event.data.startTime.hour,
        event.data.startTime.minute,
      );
      final endDateTime = startDateTime.add(
        Duration(minutes: event.data.durationMinutes),
      );
      final meetingLink = event.meetingLink?.trim();
      final recurrence = _mapCalendarRecurrence(event.data.recurrence);
      final added = await Add2Calendar.addEvent2Cal(
        Event(
          title: event.data.title,
          description: meetingLink,
          timeZone: event.data.timeZone,
          startDate: startDateTime,
          endDate: endDateTime,
          iosParams: meetingLink != null && meetingLink.isNotEmpty
              ? IOSParams(url: meetingLink)
              : const IOSParams(),
          recurrence: recurrence,
        ),
      );
      if (!added && !isClosed) {
        emit(
          state.copyWith(
            error: 'Failed to add calendar event. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!isClosed) {
        final errorMessage = 'Failed to add calendar event: $error';
        l.logger.e(
          '[DashboardBloc] Error adding calendar event: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  Future<void> _onOpenScheduledMeetingCalendarEvent(
    OpenScheduledMeetingCalendarEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('OpenScheduledMeetingCalendar')) {
      return;
    }
    try {
      final startDateTime = DateTime(
        event.data.startDate.year,
        event.data.startDate.month,
        event.data.startDate.day,
        event.data.startTime.hour,
        event.data.startTime.minute,
      );
      final endDateTime = startDateTime.add(
        Duration(minutes: event.data.durationMinutes),
      );
      final meetingLink = event.meetingLink?.trim();

      Uri? calendarUrl;
      switch (event.provider) {
        case CalendarProvider.outlook:
          final outlookAppUrl = Uri(
            scheme: 'ms-outlook',
            host: 'compose',
            queryParameters: {'subject': event.data.title, 'body': meetingLink},
          );
          if (await canLaunchUrl(Uri.parse(outlookAppUrl.toString()))) {
            await launchUrl(
              Uri.parse(outlookAppUrl.toString()),
              mode: LaunchMode.externalApplication,
            );
            return;
          }
          calendarUrl =
              Uri.https('outlook.live.com', '/calendar/0/deeplink/compose', {
                'subject': event.data.title,
                'body': meetingLink,
                'startdt': startDateTime.toIso8601String(),
                'enddt': endDateTime.toIso8601String(),
                'location': event.data.timeZone,
              });
        case CalendarProvider.google:
          final dates =
              '${_formatGoogleCalendarDate(startDateTime)}/${_formatGoogleCalendarDate(endDateTime)}';
          calendarUrl = Uri.https('calendar.google.com', '/calendar/render', {
            'action': 'TEMPLATE',
            'text': event.data.title,
            'dates': dates,
            'details': meetingLink,
            'location': event.data.timeZone,
            'ctz': event.data.timeZone,
          });
        case CalendarProvider.proton:
          final rRule = _mapRecurrenceToRRule(event.data.recurrence);
          final userId = ManagerFactory().get<AppCoreManager>().userID ?? '';
          final protonUrl = Uri(
            scheme: 'proton-calendar',
            host: 'protonmail.com',
            path: '/event/create',
            queryParameters: {
              'prefill': 'true',
              'title': event.data.title,
              'description': meetingLink,
              'startMillis': startDateTime.millisecondsSinceEpoch.toString(),
              'endMillis': endDateTime.millisecondsSinceEpoch.toString(),
              'timeZoneId': event.data.timeZone,
              'rRule': rRule,
              'allDay': 'false',
              'userId': userId,
            },
          );
          final urlString = protonUrl.toString();
          l.logger.i('[DashboardBloc] protonUrl: $urlString');
          final url = Uri.parse(urlString);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
            return;
          }
          ExternalUrl.shared.launchProtonCalendar();
      }

      if (await canLaunchUrl(Uri.parse(calendarUrl.toString()))) {
        await launchUrl(
          Uri.parse(calendarUrl.toString()),
          mode: LaunchMode.externalApplication,
        );
      } else if (!isClosed) {
        emit(
          state.copyWith(
            error: 'Failed to open calendar. Please try again.',
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!isClosed) {
        final errorMessage = 'Failed to open calendar: $error';
        l.logger.e(
          '[DashboardBloc] Error opening calendar: $error, $stackTrace',
        );
        emit(
          state.copyWith(
            error: errorMessage,
            errorDetail: "",
            offerFetchUserStateRetry: false,
          ),
        );
      }
    }
  }

  String _formatGoogleCalendarDate(DateTime dateTime) {
    return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dateTime.toUtc());
  }

  Future<String> _generateIcsWithRust(
    ScheduleMeetingData data, {
    String? meetingLink,
  }) async {
    final startDateTime = DateTime(
      data.startDate.year,
      data.startDate.month,
      data.startDate.day,
      data.startTime.hour,
      data.startTime.minute,
    );

    final endDateTime = _resolveScheduleMeetingEndDateTime(data, startDateTime);

    final startTimestamp = startDateTime.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endDateTime.millisecondsSinceEpoch ~/ 1000;

    final rustRecurrence = _mapRecurrenceFrequency(data.recurrence);
    final trimmedLink = meetingLink?.trim();
    final request = rust_schedule.ScheduleMeetingRequest(
      title: data.title,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      durationMinutes: data.durationMinutes,
      recurrence: rustRecurrence,
      description: (trimmedLink != null && trimmedLink.isNotEmpty)
          ? trimmedLink
          : null,
      timeZone: data.timeZone,
    );

    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    final appCore = appCoreManager.appCore;
    return appCore.exportScheduleMeetingToIcs(meeting: request);
  }

  DateTime _resolveScheduleMeetingEndDateTime(
    ScheduleMeetingData data,
    DateTime startDateTime,
  ) {
    if (data.endDate != null && data.endTime != null) {
      final explicitEnd = DateTime(
        data.endDate!.year,
        data.endDate!.month,
        data.endDate!.day,
        data.endTime!.hour,
        data.endTime!.minute,
      );
      if (explicitEnd.isAfter(startDateTime)) {
        return explicitEnd;
      }
    }

    return startDateTime.add(Duration(minutes: data.durationMinutes));
  }

  frb_recurrence_frequency.RecurrenceFrequency? _mapRecurrenceFrequency(
    RecurrenceFrequency recurrence,
  ) {
    switch (recurrence) {
      case RecurrenceFrequency.daily:
        return frb_recurrence_frequency.RecurrenceFrequency.daily;
      case RecurrenceFrequency.weekly:
        return frb_recurrence_frequency.RecurrenceFrequency.weekly;
      case RecurrenceFrequency.monthly:
        return frb_recurrence_frequency.RecurrenceFrequency.monthly;
      case RecurrenceFrequency.yearly:
        return frb_recurrence_frequency.RecurrenceFrequency.yearly;
      case RecurrenceFrequency.none:
        return null;
    }
  }

  Recurrence? _mapCalendarRecurrence(RecurrenceFrequency recurrence) {
    switch (recurrence) {
      case RecurrenceFrequency.none:
        return null;
      case RecurrenceFrequency.daily:
        return Recurrence(
          frequency: Frequency.daily,
          rRule: _mapRecurrenceToRRule(recurrence),
        );
      case RecurrenceFrequency.weekly:
        return Recurrence(
          frequency: Frequency.weekly,
          rRule: _mapRecurrenceToRRule(recurrence),
        );
      case RecurrenceFrequency.monthly:
        return Recurrence(
          frequency: Frequency.monthly,
          rRule: _mapRecurrenceToRRule(recurrence),
        );
      case RecurrenceFrequency.yearly:
        return Recurrence(
          frequency: Frequency.yearly,
          rRule: _mapRecurrenceToRRule(recurrence),
        );
    }
  }

  void _onEnterSearchModeEvent(
    EnterSearchModeEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('EnterSearchMode')) {
      return;
    }
    emit(
      state.copyWith(isSearchMode: true, searchQuery: '', searchResults: []),
    );
  }

  void _onExitSearchModeEvent(
    ExitSearchModeEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('ExitSearchMode')) {
      return;
    }
    emit(
      state.copyWith(isSearchMode: false, searchQuery: '', searchResults: []),
    );
  }

  void _onUpdateSearchQueryEvent(
    UpdateSearchQueryEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('UpdateSearchQuery')) {
      return;
    }
    final query = event.query.toLowerCase().trim();
    List<FrbUpcomingMeeting> results = [];

    if (query.isNotEmpty) {
      results = state.meetinsDisplay.where((meeting) {
        final title = meeting.meetingName.toLowerCase();
        return title.contains(query);
      }).toList();
    }

    final sortedResults = state.upcomingTab == MeetUpcomingTab.myMeetings
        ? results.sortMeetings(state.sortOptionMyMeetings)
        : results.sortRoomsWithPersonalFirst(state.sortOptionMyRooms);

    emit(
      state.copyWith(searchQuery: event.query, searchResults: sortedResults),
    );
  }

  void _onUpdateSortOptionMyRoomsEvent(
    UpdateSortOptionMyRoomsEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('UpdateSortOptionMyRooms')) {
      return;
    }
    if (state.upcomingTab != MeetUpcomingTab.myRooms) {
      emit(state.copyWith(sortOptionMyRooms: event.sortOption));
      return;
    }

    final filterdMyRooms = state.upcomingMeetings.getFilteredAndSortedMyRooms();
    final sortedRooms = filterdMyRooms.sortRoomsWithPersonalFirst(
      event.sortOption,
    );

    List<FrbUpcomingMeeting> sortedDisplay;
    if (state.personalMeeting != null) {
      final allMeetings = [state.personalMeeting!, ...sortedRooms];
      sortedDisplay = allMeetings.sortRoomsWithPersonalFirst(event.sortOption);
    } else {
      sortedDisplay = sortedRooms;
    }

    final sortedSearchResults = state.searchResults.isNotEmpty
        ? state.searchResults.sortRoomsWithPersonalFirst(event.sortOption)
        : <FrbUpcomingMeeting>[];

    emit(
      state.copyWith(
        sortOptionMyRooms: event.sortOption,
        meetinsDisplay: sortedDisplay,
        searchResults: sortedSearchResults,
      ),
    );
  }

  void _onUpdateSortOptionMyMeetingsEvent(
    UpdateSortOptionMyMeetingsEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('UpdateSortOptionMyMeetings')) {
      return;
    }
    if (state.upcomingTab != MeetUpcomingTab.myMeetings) {
      emit(state.copyWith(sortOptionMyMeetings: event.sortOption));
      return;
    }

    final filterdMyMeetings = state.upcomingMeetings
        .getFilteredAndSortedMyMeetings();
    final sortedMeetings = filterdMyMeetings.sortMeetings(event.sortOption);

    final sortedSearchResults = state.searchResults.isNotEmpty
        ? state.searchResults.sortMeetings(event.sortOption)
        : <FrbUpcomingMeeting>[];

    emit(
      state.copyWith(
        sortOptionMyMeetings: event.sortOption,
        meetinsDisplay: sortedMeetings,
        searchResults: sortedSearchResults,
      ),
    );
  }

  static const Duration _defaultSignInCardReset = Duration(days: 2);

  Future<void> _onLoadSignInCardVisibilityEvent(
    LoadSignInCardVisibilityEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('LoadSignInCardVisibility')) {
      return;
    }
    final prefs = ManagerFactory()
        .get<PreferencesManager>()
        .limitedDisplayPreferences;
    final shouldShow = await prefs.shouldShow(
      defaultResetDuration: _defaultSignInCardReset,
    );
    emit(state.copyWith(showSignInCard: shouldShow));
  }

  Future<void> _onDismissSignInCardEvent(
    DismissSignInCardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('DismissSignInCard')) {
      return;
    }
    final prefs = ManagerFactory()
        .get<PreferencesManager>()
        .limitedDisplayPreferences;
    await prefs.markDismissed(prefs.dashboardSignInCardDismissedAt);
    emit(state.copyWith(showSignInCard: false));
  }

  Future<void> _onMeetingUpdateEvent(
    MeetingUpdateEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (_isBlockedByForceUpgrade('MeetingUpdate')) {
      return;
    }
    l.logger.d(
      '[DashboardBloc] Received meeting update: ${event.meetings.length} meetings',
    );

    // Update the upcoming meetings in state
    emit(
      state.copyWith(
        upcomingMeetings: event.meetings,
        isLoadingUpcomingMeetings: false,
      ),
    );

    // Process meetings similar to _onFetchUserStateEvent
    if (event.meetings.isNotEmpty) {
      // Update personal meeting
      final personalMeeting = event.meetings
          .where((meeting) => meeting.isPersonalMeeting)
          .firstOrNull;

      final filterdMyRooms = event.meetings.getFilteredAndSortedMyRooms();
      final filterdMyMeetings = event.meetings.getFilteredAndSortedMyMeetings();

      emit(
        state.copyWith(
          personalMeeting: personalMeeting,
          myRoomsCount:
              filterdMyRooms.length + (personalMeeting != null ? 1 : 0),
          myMeetingsCount: filterdMyMeetings.length,
        ),
      );

      // Update display based on current tab
      add(UpdateUpcomingStateEvent(upcomingTab: state.upcomingTab));
    } else {
      emit(
        state.copyWith(myRoomsCount: 0, myMeetingsCount: 0, meetinsDisplay: []),
      );
    }
  }

  void _onPatchMeetingWaitingRoomEvent(
    PatchMeetingWaitingRoomEvent event,
    Emitter<DashboardState> emit,
  ) {
    if (_isBlockedByForceUpgrade('PatchMeetingWaitingRoom')) {
      return;
    }

    final linkName = event.meetingLinkName;
    if (linkName.isEmpty) {
      return;
    }

    var didPatch = false;
    final updatedMeetings = state.upcomingMeetings.map((meeting) {
      if (meeting.meetingLinkName != linkName) {
        return meeting;
      }
      didPatch = true;
      return meeting.withWaitingRoom(enabled: event.enabled);
    }).toList();

    FrbUpcomingMeeting? personalMeeting = state.personalMeeting;
    if (personalMeeting?.meetingLinkName == linkName) {
      personalMeeting = personalMeeting!.withWaitingRoom(
        enabled: event.enabled,
      );
      didPatch = true;
    }

    if (!didPatch) {
      return;
    }

    emit(
      state.copyWith(
        upcomingMeetings: updatedMeetings,
        personalMeeting: personalMeeting,
      ),
    );
    add(UpdateUpcomingStateEvent(upcomingTab: state.upcomingTab));
  }

  void _onInAppUpdateDownloadedEvent(
    InAppUpdateDownloadedEvent event,
    Emitter<DashboardState> emit,
  ) {
    emit(state.copyWith(inAppUpdateDownloaded: true));
  }

  void _onClearInAppUpdateDownloadedEvent(
    ClearInAppUpdateDownloadedEvent event,
    Emitter<DashboardState> emit,
  ) {
    emit(state.copyWith(inAppUpdateDownloaded: false));
  }
}

/// Create meeting failed after refreshing user state and retrying once.
final class CreateMeetingUserStateRecoveryFailure implements Exception {
  CreateMeetingUserStateRecoveryFailure({
    required this.recoveryLog,
    required this.lastError,
  });

  final List<String> recoveryLog;
  final Object lastError;

  String get diagnosticLog => recoveryLog.join('\n');

  @override
  String toString() =>
      'CreateMeetingUserStateRecoveryFailure(lastError: $lastError)';
}
