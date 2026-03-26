import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;

/// Global tracker for setKeyWithEpoch operations per room
class _SetKeyWithEpochTracker {
  _SetKeyWithEpochTracker._internal();

  static final _SetKeyWithEpochTracker _instance =
      _SetKeyWithEpochTracker._internal();

  factory _SetKeyWithEpochTracker() => _instance;

  final Map<Room, Completer<void>> _operations = {};

  bool isSetKeyWithEpochInProgress(Room room) {
    final operation = _operations[room];
    return operation != null && !operation.isCompleted;
  }

  void startOperation(Room room, Completer<void> completer) {
    _operations[room] = completer;
  }

  void completeOperation(Room room, Completer<void> completer) {
    if (_operations[room] == completer) {
      Future.delayed(const Duration(milliseconds: 10), () {
        if (_operations[room] == completer) {
          _operations.remove(room);
        }
      });
    }
  }

  void clear() => _operations.clear();
}

/// This extension is used to set the key with epoch for the proton meet key provider.
/// The logic should be synced with the JS implementation, or it will have decryption issues.
extension ProtonMeetEpochKey on BaseKeyProvider {
  int getKeyIndexFromEpoch(BigInt epoch) {
    final keyringSize = options.keyRingSize;
    if (keyringSize <= 0) return 0;
    final ringSize = BigInt.from(keyringSize);
    return (epoch % ringSize).toInt();
  }

  Future<void> setKeyWithEpoch(String key, BigInt epoch) async {
    final index = getKeyIndexFromEpoch(epoch);
    final bytes = Uint8List.fromList(base64Decode(key));
    if (options.sharedKey) {
      await setSharedKey(String.fromCharCodes(bytes), keyIndex: index);
    } else {
      await setKey(
        String.fromCharCodes(bytes),
        participantId: '',
        keyIndex: index,
      );
    }
  }
}

/// Extension for Room to safely set key index, checking if setKeyWithEpoch is in progress
extension SafeKeyIndexSetter on Room {
  /// Safely execute setKeyIndex, retrying if setKeyWithEpoch is in progress
  Future<void> safeSetKeyIndex(int keyIndex) async {
    final tracker = _SetKeyWithEpochTracker();
    const maxRetries = 4;
    const retryDelay = Duration(milliseconds: 50);

    // Retry up to 4 times if setKeyWithEpoch is in progress
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (!tracker.isSetKeyWithEpochInProgress(this)) {
        // setKeyWithEpoch is not in progress, proceed with setKeyIndex
        try {
          await e2eeManager?.setKeyIndex(keyIndex);
          return;
        } catch (e) {
          rethrow;
        }
      }

      if (attempt < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }

    // After 4 retries, setKeyWithEpoch is still in progress, skip
    l.logger.d(
      '[SafeKeyIndexSetter] Skipping setKeyIndex($keyIndex) - setKeyWithEpoch is still in progress after $maxRetries retries',
    );
  }

  /// Safely execute setKeyWithEpoch with tracking
  Future<void> safeSetKeyWithEpoch(String groupKey, BigInt epoch) async {
    final tracker = _SetKeyWithEpochTracker();
    // Create a completer to track this operation
    final completer = Completer<void>();
    tracker.startOperation(this, completer);

    try {
      await e2eeManager?.keyProvider.setKeyWithEpoch(groupKey, epoch);
      completer.complete();
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      tracker.completeOperation(this, completer);
    }
  }
}
