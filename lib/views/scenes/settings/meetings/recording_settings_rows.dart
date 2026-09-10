import 'package:flutter/material.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location.dart';
import 'package:meet/views/scenes/settings/meetings/recording_save_location_setting.dart';
import 'package:meet/views/scenes/settings/meetings/saved_recordings_sheet.dart';

/// Save location + saved recordings rows for app settings and in-call settings.
List<Widget> buildRecordingSettingsRows() => [
  if (RecordingSaveLocationConfig.supportsSaveLocationPicker)
    const RecordingSaveLocationRow(),
  const SavedRecordingsSettingRow(),
];
