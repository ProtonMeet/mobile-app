import 'dart:async';

import 'package:flutter/material.dart';

class MLSRoomKeyInfo {
  final String roomKey;
  final int epoch;

  MLSRoomKeyInfo({required this.roomKey, required this.epoch});
}

@Deprecated(
  'Do not use this provider anymore, it requires context and will easy break when context is lost',
)
class MeetRoomKeyProvider extends ChangeNotifier {
  final Map<int, MLSRoomKeyInfo> _roomKeyInfoMaps = {};
  MLSRoomKeyInfo? _roomKeyInfo;

  MLSRoomKeyInfo? get roomKeyInfo => _roomKeyInfo;

  void setRoomKeyInfo(MLSRoomKeyInfo? value) {
    if (_roomKeyInfo != value && value != null) {
      _roomKeyInfo = value;
      _roomKeyInfoMaps[value.epoch] = value;
      notifyListeners();
    }
  }

  MLSRoomKeyInfo? getRoomKeyInfoByEpoch(int epoch) {
    return _roomKeyInfoMaps[epoch];
  }

  void clear() {
    _roomKeyInfo = null;
  }
}

//
class MeetRoomKeyStream {
  final _controller = StreamController<MLSRoomKeyInfo>.broadcast();
  final Map<int, MLSRoomKeyInfo> _cache = {};

  Stream<MLSRoomKeyInfo> get stream => _controller.stream;
  MLSRoomKeyInfo? current;

  void set(MLSRoomKeyInfo info) {
    current = info;
    _cache[info.epoch] = info;
    _controller.add(info);
  }

  MLSRoomKeyInfo? getByEpoch(int epoch) => _cache[epoch];

  void dispose() => _controller.close();
}

// final keyStream = MeetRoomKeyStream();
// keyStream.stream.listen((info) {
//   print('Received key: ${info.roomKey}');
// });
