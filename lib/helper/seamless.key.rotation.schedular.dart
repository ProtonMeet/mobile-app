import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/proton.meet.key.extension.dart';
import 'package:meet/helper/logger.dart' as l;

class KeyRotationScheduler {
  final Room room;

  Timer? _timer;
  int? _pendingKeyIndex;

  KeyRotationScheduler(this.room);

  /// schedule a key rotation that becomes active after 3s
  /// if another schedule come in before delay ends, the previous
  /// keyIndex will be set immediately and start the new rotation
  void schedule(
    BigInt epoch,
    String groupKey, {
    Duration delay = const Duration(seconds: 3),
  }) {
    final keyIndex =
        room.e2eeManager?.keyProvider.getKeyIndexFromEpoch(epoch) ?? 0;

    /// set the key so it will be used for decryption immediately
    room.safeSetKeyWithEpoch(groupKey, epoch).catchError((e) {
      l.logger.e("error setting key with epoch in scheduler: $e");
    });

    _timer?.cancel();

    if (_pendingKeyIndex != null) {
      /// rotate the previous key in schedule immediately
      _rotateKey(_pendingKeyIndex!);
    }

    _pendingKeyIndex = keyIndex;
    _timer = Timer(delay, () {
      _rotateKey(keyIndex);
      _pendingKeyIndex = null;
      _timer = null;
    });
  }

  /// rotate the key to the next index, so we can use it to encrypt the video frames
  /// This will skip if setKeyWithEpoch is currently in progress
  void _rotateKey(int keyIndex) {
    // safeSetKeyIndex will automatically skip if setKeyWithEpoch is in progress
    room.safeSetKeyIndex(keyIndex).catchError((e) {
      // We may have ConcurrentModificationError since we have a periodic timer checking the key index on room_bloc (_onMlsGroupUpdated() event)
      // Skip the error since it's expected and the periodic timer will recover it
      l.logger.e("error rotating key: $e");
    });
  }
}
