import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;

/// Debounces microphone enable/disable calls to prevent rapid state changes
/// that can cause audio glitching in WebRTC
class MicrophoneToggleDebouncer {
  // Track pending enable operation
  Future<void>? _pendingEnable;
  // Track pending disable operation
  Future<void>? _pendingDisable;
  // Track the current desired state
  bool? _desiredState;
  // Track if an operation is currently executing
  bool _operationInFlight = false;
  // Track last operation completion time for cooldown
  DateTime? _lastOperationTime;
  // Track operation timestamps for rate limiting
  final List<DateTime> _recentOperations = [];
  // Minimum time between operations (cooldown period)
  static const Duration _cooldownPeriod = Duration(milliseconds: 200);
  // Debounce delay
  static const Duration _debounceDelay = Duration(milliseconds: 300);
  // Maximum operations per second (rate limiting)
  static const int _maxOperationsPerSecond = 3;
  // Time window for rate limiting
  static const Duration _rateLimitWindow = Duration(seconds: 1);

  /// Enable microphone with debouncing
  /// If a pending disable exists, it will be cancelled
  /// If already enabled or an enable is pending, this is a no-op
  Future<void> enable(
    LocalParticipant participant, {
    Duration delay = _debounceDelay,
  }) async {
    // Cancel any pending disable
    _pendingDisable = null;
    _desiredState = true;

    // Rate limiting - check if we're exceeding max operations per second
    final now = DateTime.now();
    _recentOperations.removeWhere(
      (opTime) => now.difference(opTime) > _rateLimitWindow,
    );

    if (_recentOperations.length >= _maxOperationsPerSecond) {
      final oldestOp = _recentOperations.first;
      final waitTime = _rateLimitWindow - now.difference(oldestOp);
      if (waitTime.inMilliseconds > 0) {
        l.logger.w(
          '[MicrophoneDebouncer] Rate limit exceeded, waiting ${waitTime.inMilliseconds}ms',
        );
        await Future.delayed(waitTime);
        // Retry after rate limit wait
        return enable(participant, delay: delay);
      }
    }

    // Check cooldown period - prevent operations too close together
    if (_lastOperationTime != null) {
      final timeSinceLastOp = now.difference(_lastOperationTime!);
      if (timeSinceLastOp < _cooldownPeriod) {
        final waitTime = _cooldownPeriod - timeSinceLastOp;
        l.logger.d(
          '[MicrophoneDebouncer] Cooldown active, waiting ${waitTime.inMilliseconds}ms',
        );
        await Future.delayed(waitTime);
      }
    }

    // Check current state
    final isCurrentlyEnabled = participant.isMicrophoneEnabled();
    if (isCurrentlyEnabled && !_operationInFlight) {
      l.logger.d('[MicrophoneDebouncer] Already enabled, skipping');
      return;
    }

    // If an enable is already pending, update desired state and return
    if (_pendingEnable != null) {
      l.logger.d(
        '[MicrophoneDebouncer] Enable already pending, updating desired state',
      );
      return;
    }

    // If operation is in flight, wait for it to complete
    if (_operationInFlight) {
      l.logger.d('[MicrophoneDebouncer] Operation in flight, waiting...');
      await Future.delayed(delay);
      // Retry after delay
      return enable(participant, delay: delay);
    }

    // Schedule enable with delay
    _pendingEnable = Future.delayed(delay, () async {
      // Check if this operation was cancelled
      if (_pendingEnable == null || _desiredState != true) {
        _pendingEnable = null;
        return; // Operation was cancelled
      }

      // Mark operation as in flight
      _operationInFlight = true;
      _pendingEnable = null;

      try {
        // Double-check current state before enabling
        final currentState = participant.isMicrophoneEnabled();
        if (!currentState) {
          await participant.setMicrophoneEnabled(true);
          l.logger.d('[MicrophoneDebouncer] Microphone enabled');
        } else {
          l.logger.d(
            '[MicrophoneDebouncer] Microphone already enabled, skipping',
          );
        }
      } catch (e) {
        l.logger.e('Failed to enable microphone: $e');
      } finally {
        _operationInFlight = false;
        _desiredState = null;
        final operationTime = DateTime.now();
        _lastOperationTime = operationTime;
        _recentOperations.add(operationTime);
      }
    });

    // Wait for the operation to complete
    await _pendingEnable;
  }

  /// Disable microphone with debouncing
  /// If a pending enable exists, it will be cancelled
  /// If already disabled or a disable is pending, this is a no-op
  Future<void> disable(
    LocalParticipant participant, {
    Duration delay = _debounceDelay,
  }) async {
    // Cancel any pending enable
    _pendingEnable = null;
    _desiredState = false;

    // Rate limiting - check if we're exceeding max operations per second
    final now = DateTime.now();
    _recentOperations.removeWhere(
      (opTime) => now.difference(opTime) > _rateLimitWindow,
    );

    if (_recentOperations.length >= _maxOperationsPerSecond) {
      final oldestOp = _recentOperations.first;
      final waitTime = _rateLimitWindow - now.difference(oldestOp);
      if (waitTime.inMilliseconds > 0) {
        l.logger.w(
          '[MicrophoneDebouncer] Rate limit exceeded, waiting ${waitTime.inMilliseconds}ms',
        );
        await Future.delayed(waitTime);
        // Retry after rate limit wait
        return disable(participant, delay: delay);
      }
    }

    // Check cooldown period - prevent operations too close together
    if (_lastOperationTime != null) {
      final timeSinceLastOp = now.difference(_lastOperationTime!);
      if (timeSinceLastOp < _cooldownPeriod) {
        final waitTime = _cooldownPeriod - timeSinceLastOp;
        l.logger.d(
          '[MicrophoneDebouncer] Cooldown active, waiting ${waitTime.inMilliseconds}ms',
        );
        await Future.delayed(waitTime);
      }
    }

    // Check current state
    final isCurrentlyEnabled = participant.isMicrophoneEnabled();
    if (!isCurrentlyEnabled && !_operationInFlight) {
      l.logger.d('[MicrophoneDebouncer] Already disabled, skipping');
      return;
    }

    // If a disable is already pending, update desired state and return
    if (_pendingDisable != null) {
      l.logger.d(
        '[MicrophoneDebouncer] Disable already pending, updating desired state',
      );
      return;
    }

    // If operation is in flight, wait for it to complete
    if (_operationInFlight) {
      l.logger.d('[MicrophoneDebouncer] Operation in flight, waiting...');
      await Future.delayed(delay);
      // Retry after delay
      return disable(participant, delay: delay);
    }

    // Schedule disable with delay
    _pendingDisable = Future.delayed(delay, () async {
      // Check if this operation was cancelled
      if (_pendingDisable == null || _desiredState != false) {
        _pendingDisable = null;
        return; // Operation was cancelled
      }

      // Mark operation as in flight
      _operationInFlight = true;
      _pendingDisable = null;

      try {
        // Double-check current state before disabling
        final currentState = participant.isMicrophoneEnabled();
        if (currentState) {
          await participant.setMicrophoneEnabled(false);
          l.logger.d('[MicrophoneDebouncer] Microphone disabled');
        } else {
          l.logger.d(
            '[MicrophoneDebouncer] Microphone already disabled, skipping',
          );
        }
      } catch (e) {
        l.logger.e('Failed to disable microphone: $e');
      } finally {
        _operationInFlight = false;
        _desiredState = null;
        final operationTime = DateTime.now();
        _lastOperationTime = operationTime;
        _recentOperations.add(operationTime);
      }
    });

    // Wait for the operation to complete
    await _pendingDisable;
  }

  /// Cancel all pending operations
  void clear() {
    _pendingEnable = null;
    _pendingDisable = null;
    _desiredState = null;
    _operationInFlight = false;
    _lastOperationTime = null;
    _recentOperations.clear();
  }

  /// Check if there's a pending operation
  bool get hasPendingOperation =>
      _pendingEnable != null || _pendingDisable != null;

  /// Check if an operation is currently executing
  bool get isOperationInFlight => _operationInFlight;
}
