import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/sentry_waiting_room.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/rust/proton_meet/models/join_request.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:sentry/sentry.dart';

import 'room_bloc_participants.dart';
import 'room_event.dart';
import 'room_state.dart';

mixin RoomWaitingRoomHandlers
    on Bloc<RoomBlocEvent, RoomState>, RoomParticipantsHandlers {
  Timer? _waitingRoomExpirationTimer;
  Timer? _waitingRoomDisplayNameRetryTimer;
  int _waitingRoomDisplayNameRetryAttempts = 0;
  int _expiredWaitingRoomJoinRequestCount = 0;
  bool _expiredWaitingRoomJoinRequestSentryReported = false;

  void registerWaitingRoomHandlers() {
    on<WaitingRoomJoinRequestReceived>(_onWaitingRoomJoinRequestReceived);
    on<WaitingRoomJoinRequestRemoved>(_onWaitingRoomJoinRequestRemoved);
    on<WaitingRoomJoinRequestsExpirationTick>(
      _onWaitingRoomJoinRequestsExpirationTick,
    );
    on<WaitingRoomJoinRequestDisplayNameRetry>(
      _onWaitingRoomJoinRequestDisplayNameRetry,
    );
    on<AdmitWaitingRoomJoinRequest>(_onAdmitWaitingRoomJoinRequest);
    on<RejectWaitingRoomJoinRequest>(_onRejectWaitingRoomJoinRequest);
    on<AdmitAllWaitingRoomJoinRequests>(_onAdmitAllWaitingRoomJoinRequests);
    on<WaitingRoomJoinRequestNotFoundErrorConsumed>(
      _onWaitingRoomJoinRequestNotFoundErrorConsumed,
    );
  }

  Future<void> _onWaitingRoomJoinRequestReceived(
    WaitingRoomJoinRequestReceived event,
    Emitter<RoomState> emit,
  ) async {
    if (event.expiresAt != null && !event.expiresAt!.isAfter(DateTime.now())) {
      _recordExpiredWaitingRoomJoinRequestOnReceive(event);
      return;
    }

    final resolved = await resolveParticipantDisplayNameByUuid(
      event.participantUid,
    );

    final existingIndex = state.waitingRoomParticipants.indexWhere(
      (p) => p.requestId == event.requestId,
    );
    final request = WaitingRoomJoinRequest(
      requestId: event.requestId,
      participantUid: event.participantUid,
      displayName: resolved.displayName,
      receivedAt: DateTime.now(),
      expiresAt: event.expiresAt,
    );

    final next = List<WaitingRoomJoinRequest>.of(state.waitingRoomParticipants);
    if (existingIndex >= 0) {
      next[existingIndex] = request;
    } else {
      next.add(request);
    }
    final nextState = state.copyWith(
      waitingRoomParticipants: next,
      frbParticipantsMap: resolved.participants,
    );
    emit(nextState);
    _syncWaitingRoomExpirationTimer(nextState.waitingRoomParticipants);
    if (_hasUnresolvedWaitingRoomDisplayNames(nextState.waitingRoomParticipants)) {
      _waitingRoomDisplayNameRetryAttempts = 0;
      _scheduleWaitingRoomDisplayNameRetry();
    }
  }

  void _onWaitingRoomJoinRequestRemoved(
    WaitingRoomJoinRequestRemoved event,
    Emitter<RoomState> emit,
  ) {
    // Legacy WS removals omit request_id; dropping by participantUid would
    // remove a newer re-request from the same guest.
    if (event.requestId.isEmpty) {
      return;
    }
    if (!state.waitingRoomParticipants.any(
      (p) => p.requestId == event.requestId,
    )) {
      return;
    }
    final next = state.waitingRoomParticipants
        .where((p) => p.requestId != event.requestId)
        .toList(growable: false);
    final nextState = state.copyWith(waitingRoomParticipants: next);
    emit(nextState);
    _syncWaitingRoomExpirationTimer(nextState.waitingRoomParticipants);
  }

  void _onWaitingRoomJoinRequestsExpirationTick(
    WaitingRoomJoinRequestsExpirationTick event,
    Emitter<RoomState> emit,
  ) {
    final pruned = _pruneExpiredWaitingRoomJoinRequests(state);
    if (pruned == state) {
      return;
    }
    emit(pruned);
    _syncWaitingRoomExpirationTimer(pruned.waitingRoomParticipants);
  }

  RoomState _pruneExpiredWaitingRoomJoinRequests(RoomState current) {
    final active = current.waitingRoomParticipants
        .where((request) => request.isActive)
        .toList(growable: false);
    if (active.length == current.waitingRoomParticipants.length) {
      return current;
    }
    return current.copyWith(waitingRoomParticipants: active);
  }

  WaitingRoomJoinRequest? _findActiveWaitingRoomJoinRequest(String requestId) {
    for (final request in state.waitingRoomParticipants) {
      if (request.requestId == requestId) {
        return request.isActive ? request : null;
      }
    }
    return null;
  }

  void _syncWaitingRoomExpirationTimer(
    List<WaitingRoomJoinRequest> waitingRoomParticipants,
  ) {
    final hasExpiring = waitingRoomParticipants.any(
      (request) => request.expiresAt != null && request.isActive,
    );
    if (!hasExpiring) {
      cancelWaitingRoomExpirationTimer();
      return;
    }
    _waitingRoomExpirationTimer ??= Timer.periodic(
      waitingRoomJoinRequestExpirationPollInterval,
      (_) {
        if (!isClosed) {
          add(const WaitingRoomJoinRequestsExpirationTick());
        }
      },
    );
  }

  void cancelWaitingRoomExpirationTimer() {
    _waitingRoomExpirationTimer?.cancel();
    _waitingRoomExpirationTimer = null;
  }

  bool _hasUnresolvedWaitingRoomDisplayNames(
    List<WaitingRoomJoinRequest> requests,
  ) {
    return requests.any(
      (request) => request.isActive && _isMissingWaitingRoomDisplayName(request),
    );
  }

  bool _isMissingWaitingRoomDisplayName(WaitingRoomJoinRequest request) {
    final name = request.displayName?.trim();
    return name == null || name.isEmpty;
  }

  void _scheduleWaitingRoomDisplayNameRetry() {
    _waitingRoomDisplayNameRetryTimer?.cancel();
    _waitingRoomDisplayNameRetryTimer = Timer(
      waitingRoomJoinRequestDisplayNameRetryDelay,
      () {
        if (!isClosed) {
          add(const WaitingRoomJoinRequestDisplayNameRetry());
        }
      },
    );
  }

  void cancelWaitingRoomDisplayNameRetryTimer() {
    _waitingRoomDisplayNameRetryTimer?.cancel();
    _waitingRoomDisplayNameRetryTimer = null;
    _waitingRoomDisplayNameRetryAttempts = 0;
  }

  Future<void> _onWaitingRoomJoinRequestDisplayNameRetry(
    WaitingRoomJoinRequestDisplayNameRetry event,
    Emitter<RoomState> emit,
  ) async {
    _waitingRoomDisplayNameRetryTimer = null;

    if (!_hasUnresolvedWaitingRoomDisplayNames(
      state.waitingRoomParticipants,
    )) {
      _waitingRoomDisplayNameRetryAttempts = 0;
      return;
    }

    if (_waitingRoomDisplayNameRetryAttempts >=
        waitingRoomJoinRequestDisplayNameRetryCount) {
      _waitingRoomDisplayNameRetryAttempts = 0;
      return;
    }
    _waitingRoomDisplayNameRetryAttempts++;

    Map<String, MeetParticipant> participants;
    try {
      participants = await loadFrbParticipants();
    } catch (e, stackTrace) {
      l.logger.w(
        '[RoomBloc] waiting-room display name retry failed: $e',
        stackTrace: stackTrace,
      );
      participants = state.frbParticipantsMap;
    }

    var changed = false;
    final next = state.waitingRoomParticipants.map((request) {
      if (!request.isActive || !_isMissingWaitingRoomDisplayName(request)) {
        return request;
      }
      final name = participants[request.participantUid]?.displayName?.trim();
      if (name == null || name.isEmpty) {
        return request;
      }
      changed = true;
      return WaitingRoomJoinRequest(
        requestId: request.requestId,
        participantUid: request.participantUid,
        displayName: name,
        receivedAt: request.receivedAt,
        expiresAt: request.expiresAt,
      );
    }).toList(growable: false);

    if (changed) {
      emit(
        state.copyWith(
          waitingRoomParticipants: next,
          frbParticipantsMap: participants,
        ),
      );
    }

    if (_hasUnresolvedWaitingRoomDisplayNames(next) &&
        _waitingRoomDisplayNameRetryAttempts <
            waitingRoomJoinRequestDisplayNameRetryCount) {
      _scheduleWaitingRoomDisplayNameRetry();
    } else {
      _waitingRoomDisplayNameRetryAttempts = 0;
    }
  }

  void _recordExpiredWaitingRoomJoinRequestOnReceive(
    WaitingRoomJoinRequestReceived event,
  ) {
    _expiredWaitingRoomJoinRequestCount++;
    final threshold = waitingRoomExpiredJoinRequestSentryThreshold;

    l.logger.i(
      '[RoomBloc] skipping expired waiting-room join request '
      '(requestId=${event.requestId}, participantUid=${event.participantUid}, '
      'expiresAt=${event.expiresAt?.toUtc().toIso8601String()}, '
      'expiredCount=$_expiredWaitingRoomJoinRequestCount, threshold=$threshold)',
    );

    if (_expiredWaitingRoomJoinRequestCount > threshold &&
        !_expiredWaitingRoomJoinRequestSentryReported) {
      _expiredWaitingRoomJoinRequestSentryReported = true;
      captureExpiredWaitingRoomJoinRequestsThresholdToSentry(
        expiredCount: _expiredWaitingRoomJoinRequestCount,
        threshold: threshold,
        requestId: event.requestId,
        participantUid: event.participantUid,
        expiresAt: event.expiresAt,
        meetLinkName: state.meetInfo.meetLinkName,
      );
    }
  }

  Future<void> _onAdmitWaitingRoomJoinRequest(
    AdmitWaitingRoomJoinRequest event,
    Emitter<RoomState> emit,
  ) async {
    final request = _findActiveWaitingRoomJoinRequest(event.requestId);
    if (request == null) {
      final pruned = _pruneExpiredWaitingRoomJoinRequests(state);
      if (pruned != state) {
        emit(pruned);
        _syncWaitingRoomExpirationTimer(pruned.waitingRoomParticipants);
      }
      return;
    }

    if (state.admittingWaitingRoomRequestIds.contains(event.requestId) ||
        state.rejectingWaitingRoomRequestIds.contains(event.requestId) ||
        state.isAdmitAllWaitingRoomInProgress) {
      return;
    }

    emit(
      state.copyWith(
        admittingWaitingRoomRequestIds: {
          ...state.admittingWaitingRoomRequestIds,
          event.requestId,
        },
      ),
    );

    final appCore = ManagerFactory().get<AppCoreManager>().appCore;
    try {
      await appCore.admitWaitingRoomJoinRequest(
        meetLinkName: state.meetInfo.meetLinkName,
        requestId: event.requestId,
      );
    } catch (e, st) {
      logBridgeError(
        'RoomBloc',
        'failed to admit waiting-room join request',
        e,
        stackTrace: st,
      );
      captureWaitingRoomFailureToSentry(
        flow: 'host_admit',
        error: e,
        stackTrace: st,
        meetLinkName: state.meetInfo.meetLinkName,
        requestId: event.requestId,
      );
      if (isWaitingRoomJoinRequestNotFoundError(e)) {
        emit(
          state.copyWith(shouldShowWaitingRoomJoinRequestNotFoundError: true),
        );
      }
    } finally {
      emit(
        state.copyWith(
          admittingWaitingRoomRequestIds: {
            ...state.admittingWaitingRoomRequestIds,
          }..remove(event.requestId),
        ),
      );
    }
  }

  void _onWaitingRoomJoinRequestNotFoundErrorConsumed(
    WaitingRoomJoinRequestNotFoundErrorConsumed event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(shouldShowWaitingRoomJoinRequestNotFoundError: false));
  }

  Future<void> _onRejectWaitingRoomJoinRequest(
    RejectWaitingRoomJoinRequest event,
    Emitter<RoomState> emit,
  ) async {
    final request = _findActiveWaitingRoomJoinRequest(event.requestId);
    if (request == null) {
      final pruned = _pruneExpiredWaitingRoomJoinRequests(state);
      if (pruned != state) {
        emit(pruned);
        _syncWaitingRoomExpirationTimer(pruned.waitingRoomParticipants);
      }
      return;
    }

    if (state.admittingWaitingRoomRequestIds.contains(event.requestId) ||
        state.rejectingWaitingRoomRequestIds.contains(event.requestId) ||
        state.isAdmitAllWaitingRoomInProgress) {
      return;
    }

    emit(
      state.copyWith(
        rejectingWaitingRoomRequestIds: {
          ...state.rejectingWaitingRoomRequestIds,
          event.requestId,
        },
      ),
    );

    final appCore = ManagerFactory().get<AppCoreManager>().appCore;
    try {
      await appCore.rejectWaitingRoomJoinRequest(
        meetLinkName: state.meetInfo.meetLinkName,
        requestId: event.requestId,
        participantUid: event.participantUid,
      );
      final next = state.waitingRoomParticipants
          .where((p) => p.requestId != event.requestId)
          .toList(growable: false);
      if (next.length != state.waitingRoomParticipants.length) {
        emit(state.copyWith(waitingRoomParticipants: next));
        _syncWaitingRoomExpirationTimer(next);
      }
    } catch (e, st) {
      l.logger.e(
        '[RoomBloc] failed to reject waiting-room join request: $e',
        stackTrace: st,
      );
      captureWaitingRoomFailureToSentry(
        flow: 'host_reject',
        error: e,
        stackTrace: st,
        meetLinkName: state.meetInfo.meetLinkName,
        requestId: event.requestId,
        participantUid: event.participantUid,
      );
    } finally {
      emit(
        state.copyWith(
          rejectingWaitingRoomRequestIds: {
            ...state.rejectingWaitingRoomRequestIds,
          }..remove(event.requestId),
        ),
      );
    }
  }

  Future<void> _onAdmitAllWaitingRoomJoinRequests(
    AdmitAllWaitingRoomJoinRequests event,
    Emitter<RoomState> emit,
  ) async {
    if (state.isAdmitAllWaitingRoomInProgress ||
        state.admittingWaitingRoomRequestIds.isNotEmpty ||
        state.rejectingWaitingRoomRequestIds.isNotEmpty) {
      return;
    }

    final pruned = _pruneExpiredWaitingRoomJoinRequests(state);
    if (pruned != state) {
      emit(pruned);
      _syncWaitingRoomExpirationTimer(pruned.waitingRoomParticipants);
    }

    if (pruned.waitingRoomParticipants.isEmpty) return;

    emit(state.copyWith(isAdmitAllWaitingRoomInProgress: true));

    final appCore = ManagerFactory().get<AppCoreManager>().appCore;
    try {
      await appCore.admitAllWaitingRoomJoinRequests(
        meetLinkName: state.meetInfo.meetLinkName,
      );
    } catch (e, st) {
      l.logger.e(
        '[RoomBloc] failed to admit all waiting-room join requests: $e',
        stackTrace: st,
      );
      captureWaitingRoomFailureToSentry(
        flow: 'host_admit_all',
        error: e,
        stackTrace: st,
        meetLinkName: state.meetInfo.meetLinkName,
      );
    } finally {
      emit(state.copyWith(isAdmitAllWaitingRoomInProgress: false));
    }
  }

  /// Registers AppCore callbacks so the host receives live waiting-room
  /// join request events from the Rust core and updates the participant list.
  Future<void> registerWaitingRoomCallbacks() async {
    final appCore = ManagerFactory().get<AppCoreManager>().appCore;
    try {
      // do not await here, or it will take longer to show the meeting
      appCore.setJoinRequestCallback(
        callback: (change, requestId, participantUid, expiresAt) {
          switch (change) {
            case JoinRequestChange.added:
              final expiresAtSeconds = expiresAt.toInt();
              add(
                WaitingRoomJoinRequestReceived(
                  requestId: requestId,
                  participantUid: participantUid,
                  expiresAt: expiresAtSeconds > 0
                      ? DateTime.fromMillisecondsSinceEpoch(
                          expiresAtSeconds * 1000,
                        )
                      : null,
                ),
              );
            case JoinRequestChange.removed:
              add(
                WaitingRoomJoinRequestRemoved(
                  requestId: requestId,
                  participantUid: participantUid,
                ),
              );
          }
        },
      );
    } catch (e, st) {
      l.logger.w('[RoomBloc] failed to register waiting-room callbacks: $e');
      captureWaitingRoomFailureToSentry(
        flow: 'host_register_callbacks',
        error: e,
        stackTrace: st,
        meetLinkName: state.meetInfo.meetLinkName,
        level: SentryLevel.warning,
      );
    }
  }

  Future<void> clearWaitingRoomCallbacks() async {
    final appCore = ManagerFactory().get<AppCoreManager>().appCore;
    try {
      await appCore.clearJoinRequestCallback();
    } catch (e) {
      l.logger.w('[RoomBloc] failed to clear waiting-room callbacks: $e');
    }
  }
}
