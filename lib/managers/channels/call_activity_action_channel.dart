import 'dart:io';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;

/// Channel for handling call activity actions from Dynamic Island
class CallActivityActionChannel {
  static const _channel = MethodChannel('me.proton.meet/call_activity_action');

  static Room? _currentRoom;
  static LocalParticipant? _currentParticipant;

  /// Initialize the channel with the current room and participant
  static void initialize(Room room, LocalParticipant participant) {
    _currentRoom = room;
    _currentParticipant = participant;

    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Clean up when leaving the room
  static void dispose() {
    _currentRoom = null;
    _currentParticipant = null;
    _channel.setMethodCallHandler(null);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (!Platform.isIOS) {
      return;
    }

    final participant = _currentParticipant;
    if (participant == null) {
      l.logger.d('CallActivityActionChannel: No active participant');
      return;
    }

    try {
      switch (call.method) {
        case 'toggleMute':
          await _toggleMute(participant);
        case 'toggleSpeaker':
          await _toggleSpeaker();
        case 'endCall':
          await _endCall();
        default:
          l.logger.d(
            'CallActivityActionChannel: Unknown method ${call.method}',
          );
      }
    } catch (e) {
      l.logger.e(
        'CallActivityActionChannel: Error handling ${call.method}: $e',
      );
    }
  }

  static Future<void> _toggleMute(LocalParticipant participant) async {
    final isCurrentlyMuted = participant.isMuted;
    await participant.setMicrophoneEnabled(!isCurrentlyMuted);
    l.logger.d(
      'CallActivityActionChannel: Toggled mute to ${!isCurrentlyMuted}',
    );
  }

  static Future<void> _toggleSpeaker() async {
    final room = _currentRoom;
    if (room == null) {
      l.logger.d(
        'CallActivityActionChannel: No active room for speaker toggle',
      );
      return;
    }

    // Get current audio output devices
    final devices = await Hardware.instance.enumerateDevices();
    final audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();

    if (audioOutputs.isEmpty) {
      l.logger.d('CallActivityActionChannel: No audio output devices found');
      return;
    }

    // Toggle between speaker and earpiece
    final currentDevice = room.selectedAudioOutputDeviceId;
    final speakerDevice = audioOutputs.firstWhere(
      (d) => d.kind == 'audiooutput' && d.deviceId != currentDevice,
      orElse: () => audioOutputs.first,
    );

    await room.setAudioOutputDevice(speakerDevice);
    l.logger.d('CallActivityActionChannel: Toggled speaker');
  }

  static Future<void> _endCall() async {
    final room = _currentRoom;
    if (room == null) {
      l.logger.d('CallActivityActionChannel: No active room to end');
      return;
    }

    try {
      // Disconnect from the room
      await room.disconnect();
      // Send a message to Flutter to navigate back
      // This will be handled by the room_bloc which already handles RoomDisconnectedEvent
      l.logger.d('CallActivityActionChannel: Ended call');
    } catch (e) {
      l.logger.e('CallActivityActionChannel: Error ending call: $e');
    }
  }
}
