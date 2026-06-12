/// How the area behind the segmented person is filled.
enum CameraBackgroundMode {
  /// Segmentation mask + blurred camera plate.
  blur,

  /// Segmentation mask + a still image (aspect-fill). Not enabled in app builds yet.
  replacementImage,
}

extension CameraBackgroundModeX on CameraBackgroundMode {
  String get channelId => switch (this) {
    CameraBackgroundMode.blur => 'blur',
    CameraBackgroundMode.replacementImage => 'image',
  };
}

CameraBackgroundMode cameraBackgroundModeFromChannelId(String? id) =>
    switch (id) {
      'blur' => CameraBackgroundMode.blur,
      'image' => CameraBackgroundMode.replacementImage,
      _ => CameraBackgroundMode.blur,
    };
