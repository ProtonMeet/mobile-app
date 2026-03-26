import 'dart:async';

import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.dart';
import 'package:meet/managers/services/service.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/dashboard_event.dart';

/// Event loop manager that polls for meeting updates and sends them to DashboardBloc
/// Only active when user is logged in
/// Implements exponential backoff retry logic
/// Uses event API to efficiently check for changes before fetching full meeting list
class MeetingEventLoopManager extends Service implements Manager {
  final AppCoreManager _appCoreManager;
  final AppStateManager _appStateManager;

  // Stream controller for meeting updates
  final _meetingUpdateStreamController =
      StreamController<List<FrbUpcomingMeeting>>.broadcast();
  Stream<List<FrbUpcomingMeeting>> get meetingUpdateStream =>
      _meetingUpdateStreamController.stream;

  // Backoff retry state
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 5);
  static const Duration _maxRetryDelay = Duration(minutes: 5);
  static const Duration _normalPollInterval = Duration(seconds: 60);

  // Track last known meetings hash to detect changes
  String? _lastMeetingHash;

  // Track last event ID for event polling (cached in memory)
  String? _lastEventId;

  // Dashboard bloc reference (will be set when available)
  DashboardBloc? _dashboardBloc;
  StreamSubscription<List<FrbUpcomingMeeting>>? _updateSubscription;

  MeetingEventLoopManager(
    this._appCoreManager,
    this._appStateManager, {
    super.duration = _normalPollInterval,
  });

  @override
  Future<void> init() async {
    // Subscribe to meeting updates and forward to dashboard bloc
    _updateSubscription = meetingUpdateStream.listen((meetings) {
      if (_dashboardBloc != null) {
        _dashboardBloc!.add(MeetingUpdateEvent(meetings: meetings));
      }
    });

    // If user is already authenticated (existing session), start the event loop
    if (_isUserLoggedIn()) {
      logger.d(
        '[MeetingEventLoopManager] User already authenticated on init, starting event loop',
      );
      start();
    }
  }

  /// Set the dashboard bloc reference
  void setDashboardBloc(DashboardBloc bloc) {
    _dashboardBloc = bloc;
  }

  @override
  void start() {
    logger.d('[MeetingEventLoopManager] Starting event loop');
    // Reset event ID when starting - will be initialized on first update
    _lastEventId = null;
    super.start();
  }

  @override
  void stop() {
    logger.d('[MeetingEventLoopManager] Stopping event loop');
    super.stop();
    _retryCount = 0;
  }

  @override
  Future<Duration?> onUpdate() async {
    // Check if user is still logged in
    if (!_isUserLoggedIn()) {
      logger.d('[MeetingEventLoopManager] User logged out, stopping');
      stop();
      return null;
    }

    // Skip if app is in background
    if (_appStateManager.isInBackground) {
      logger.d('[MeetingEventLoopManager] App in background, skipping update');
      return const Duration(seconds: 60); // Check less frequently in background
    }

    try {
      onUpdateing = true;

      // Initialize event ID if not set
      if (_lastEventId == null) {
        logger.d('[MeetingEventLoopManager] Initializing event ID');
        _lastEventId = await _appCoreManager.appCore.getLatestEventId();
        logger.d('[MeetingEventLoopManager] Initial event ID: $_lastEventId');
      }

      // Poll events using event API
      final eventResponse = await _appCoreManager.appCore.getEvents(
        eventId: _lastEventId!,
      );

      // Update last event ID (cache in memory)
      _lastEventId = eventResponse.eventId;

      // Check if we need to reload meetings:
      // 1. If refresh flag is set
      // 2. If there are any meeting events (create/update/delete)
      final needsReload =
          eventResponse.refresh ||
          (eventResponse.meetingEvents != null &&
              eventResponse.meetingEvents!.isNotEmpty);

      if (needsReload) {
        logger.d(
          '[MeetingEventLoopManager] Reload needed: refresh=${eventResponse.refresh}, '
          'events=${eventResponse.meetingEvents?.length ?? 0}',
        );

        // Fetch full upcoming meetings list
        final meetings = await _appCoreManager.appCore.getUpcomingMeetings();

        // Check if meetings have changed
        final currentHash = _hashMeetings(meetings);
        if (currentHash != _lastMeetingHash) {
          logger.d(
            '[MeetingEventLoopManager] Meetings changed, sending update. '
            'Count: ${meetings.length}',
          );
          _lastMeetingHash = currentHash;

          // Send update through stream
          _meetingUpdateStreamController.add(meetings);
        } else {
          logger.d('[MeetingEventLoopManager] No meeting changes detected');
        }
      } else {
        logger.d(
          '[MeetingEventLoopManager] No reload needed. '
          'More events available: ${eventResponse.more}',
        );
      }

      // Reset retry count on success
      _retryCount = 0;
      onUpdateing = false;
      return _normalPollInterval;
    } catch (e, stackTrace) {
      // Handle different error types
      if (e is BridgeError_ApiResponse) {
        logger.e(
          '[MeetingEventLoopManager] API response error: ${e.field0.error}',
          error: e.field0.error,
          stackTrace: stackTrace,
        );
      } else {
        logger.e(
          '[MeetingEventLoopManager] Error in event loop: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
      onUpdateing = false;

      // Exponential backoff retry
      _retryCount++;
      if (_retryCount >= _maxRetryCount) {
        logger.w(
          '[MeetingEventLoopManager] Max retry count reached, '
          'using max delay',
        );
        return _maxRetryDelay;
      }

      final retryDelay = _calculateBackoffDelay(_retryCount);
      logger.d(
        '[MeetingEventLoopManager] Retrying in ${retryDelay.inSeconds}s '
        '(attempt $_retryCount/$_maxRetryCount)',
      );
      return retryDelay;
    }
  }

  /// Calculate exponential backoff delay
  Duration _calculateBackoffDelay(int retryCount) {
    final delaySeconds = _baseRetryDelay.inSeconds * (1 << retryCount);
    final delay = Duration(seconds: delaySeconds);
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }

  /// Check if user is logged in
  bool _isUserLoggedIn() {
    try {
      // Check AppCoreManager authentication state
      if (!_appCoreManager.isAuthenticated) {
        return false;
      }

      // Also check AuthBloc if available
      // Note: This is a best-effort check since we might not have direct access
      // The main check is AppCoreManager.isAuthenticated
      return true;
    } catch (e) {
      logger.e('[MeetingEventLoopManager] Error checking login state: $e');
      return false;
    }
  }

  /// Generate a hash of meetings list to detect changes
  String _hashMeetings(List<FrbUpcomingMeeting> meetings) {
    // Create a simple hash based on meeting IDs and update times
    final hashParts = meetings.map((m) {
      return '${m.meetingLinkName}_${m.startTime}_${m.endTime}_${m.meetingName}';
    }).toList()..sort();
    return hashParts.join('|');
  }

  @override
  Future<void> login(String userID) async {
    logger.d('[MeetingEventLoopManager] User logged in, starting event loop');
    _retryCount = 0;
    _lastMeetingHash = null;
    _lastEventId = null; // Will be initialized on first update
    start();
  }

  @override
  Future<void> logout() async {
    logger.d('[MeetingEventLoopManager] User logged out, stopping event loop');
    stop();
    _lastMeetingHash = null;
    _lastEventId = null;
    _retryCount = 0;
  }

  @override
  Future<void> dispose() async {
    await _updateSubscription?.cancel();
    await _meetingUpdateStreamController.close();
    stop();
  }

  @override
  Future<void> reload() async {
    // Force a refresh on reload
    _lastMeetingHash = null;
    if (_isUserLoggedIn()) {
      start();
    }
  }

  @override
  Priority getPriority() {
    return Priority.level3; // Medium priority
  }
}
