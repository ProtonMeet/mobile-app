// recording_status_handler.dart
//
// Inbound side of the multi-recording protocol. Pure validation logic that
// returns the *decision* (start/stop/drop) for an MLS-decrypted recording
// status payload. Side-effects (dispatching bloc events, logging dialogs,
// etc.) live on the caller side so this stays trivially unit-testable.
import 'dart:convert';

import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/scenes/room/envelope_sender.dart';
import 'package:meet/views/scenes/room/message_topic.dart';

/// Inclusive bounds borrowed from web's `isValidMessageString`. The recording
/// status payload itself is tiny (~20 chars JSON) but we keep the same window
/// so any future fields can ride the same envelope.
const int _kMinDecryptedLen = 1;
const int _kMaxDecryptedLen = 50000;

/// Sentinel identity used to represent a LiveKit server-side (egress)
/// recording in `participantsRecording`. Chosen so it can never collide with
/// a real LiveKit participant identity.
const String kServerRecordingIdentity = '__livekit_server_recording__';

/// Outcome of validating an incoming recording-status envelope.
enum RecordingStatusDecision { started, stopped, drop }

class RecordingStatusInbound {
  const RecordingStatusInbound({
    required this.decision,
    required this.senderIdentity,
  });

  final RecordingStatusDecision decision;

  /// The LiveKit identity of the *trusted* sender — the one that should be
  /// added to / removed from `participantsRecording`. This is the MLS-verified
  /// identity, never the raw `participant.identity` from the data event.
  final String senderIdentity;
}

class RecordingStatusReceiver {
  RecordingStatusReceiver._();

  /// Run the full validation pipeline for a `recordingStatus` envelope that's
  /// already been MLS-decrypted by the upstream chat router.
  ///
  /// - [envelope] : the parsed outer data-channel JSON
  /// - [decryptedPlaintext] : output of `appCore.decryptMessage` on
  ///   `envelope['message']` — must be the JSON string `{"status":"started"}`
  ///   or `{"status":"stopped"}`.
  /// - [mlsSenderId] : the participant id reported by MLS for the decrypted
  ///   message. Used for anti-spoofing.
  /// - [liveKitSenderIdentity] : `participant.identity` from the LiveKit
  ///   `DataReceivedEvent`.
  /// - [isSenderAdminOrHost] : pre-computed authorization gate. Receivers
  ///   MUST drop status updates from non-admin/host senders.
  static RecordingStatusInbound validate({
    required Map<String, dynamic> envelope,
    required String? decryptedPlaintext,
    required String? mlsSenderId,
    required String? liveKitSenderIdentity,
    required bool isSenderAdminOrHost,
  }) {
    // 1. Authorization: only host/admin status updates are honored. The web
    //    receiver drops everything else silently here.
    if (!isSenderAdminOrHost) {
      l.logger.w(
        '[RecordingStatusReceiver] dropping unauthorized sender '
        '$liveKitSenderIdentity',
      );
      return _drop(liveKitSenderIdentity);
    }

    // 2. We need a sender on both sides.
    if (liveKitSenderIdentity == null ||
        mlsSenderId == null ||
        decryptedPlaintext == null) {
      l.logger.w(
        '[RecordingStatusReceiver] missing sender/decrypt result '
        '(lk=$liveKitSenderIdentity mls=$mlsSenderId)',
      );
      return _drop(liveKitSenderIdentity);
    }

    // 3. Anti-spoofing: the LiveKit identity must match the MLS sender id.
    if (liveKitSenderIdentity != mlsSenderId) {
      l.logger.e(
        '[RecordingStatusReceiver] identity mismatch '
        'lk=$liveKitSenderIdentity mls=$mlsSenderId',
      );
      return _drop(liveKitSenderIdentity);
    }

    // 4. The envelope `id` must be `${senderId}-${timestamp}`.
    final claimedFromEnvelope = claimedParticipantIdFromEnvelope(envelope);
    if (claimedFromEnvelope == null ||
        claimedFromEnvelope != mlsSenderId) {
      l.logger.e(
        '[RecordingStatusReceiver] envelope id prefix mismatch '
        '(claimed=$claimedFromEnvelope mls=$mlsSenderId)',
      );
      return _drop(liveKitSenderIdentity);
    }

    // 5. Length / charset sanity on the decrypted payload.
    if (!_isValidMessageString(decryptedPlaintext)) {
      l.logger.w(
        '[RecordingStatusReceiver] dropped invalid decrypted payload '
        '(len=${decryptedPlaintext.length})',
      );
      return _drop(liveKitSenderIdentity);
    }

    // 6. Parse `{"status":"started"|"stopped"}`.
    Object? parsed;
    try {
      parsed = jsonDecode(decryptedPlaintext);
    } catch (_) {
      l.logger.w('[RecordingStatusReceiver] payload is not valid JSON');
      return _drop(liveKitSenderIdentity);
    }
    if (parsed is! Map) {
      l.logger.w('[RecordingStatusReceiver] payload is not a JSON object');
      return _drop(liveKitSenderIdentity);
    }
    final statusRaw = parsed['status'];
    if (statusRaw is! String) {
      l.logger.w('[RecordingStatusReceiver] payload missing string status');
      return _drop(liveKitSenderIdentity);
    }

    final lower = statusRaw.toLowerCase();
    if (lower == RecordingStatus.started.name) {
      return RecordingStatusInbound(
        decision: RecordingStatusDecision.started,
        senderIdentity: mlsSenderId,
      );
    }
    if (lower == RecordingStatus.stopped.name) {
      return RecordingStatusInbound(
        decision: RecordingStatusDecision.stopped,
        senderIdentity: mlsSenderId,
      );
    }

    l.logger.w('[RecordingStatusReceiver] unknown status value: $statusRaw');
    return _drop(liveKitSenderIdentity);
  }

  static RecordingStatusInbound _drop(String? sender) =>
      RecordingStatusInbound(
        decision: RecordingStatusDecision.drop,
        senderIdentity: sender ?? '',
      );

  /// Mirrors web's `isValidMessageString`. Length-bounded + printable.
  /// Control characters other than common whitespace are rejected.
  static bool _isValidMessageString(String s) {
    if (s.length < _kMinDecryptedLen || s.length > _kMaxDecryptedLen) {
      return false;
    }
    for (final code in s.codeUnits) {
      // Allow tab, LF, CR, and anything from space onwards.
      if (code == 0x09 || code == 0x0A || code == 0x0D) continue;
      if (code < 0x20) return false;
      // Reject explicit DELETE.
      if (code == 0x7F) return false;
    }
    return true;
  }
}
