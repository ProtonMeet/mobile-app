import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

enum CameraLayout { fixedSizing, grid, speaker, mutliSpeaker }

extension CameraLayoutIcon on CameraLayout {
  IconData toIconData() {
    switch (this) {
      case CameraLayout.grid:
        return Icons.grid_view_rounded;
      case CameraLayout.fixedSizing:
        return Icons.view_module;
      case CameraLayout.speaker:
        return Icons.record_voice_over;
      case CameraLayout.mutliSpeaker:
        return Icons.group;
    }
  }

  String toLabel(BuildContext context) {
    switch (this) {
      case CameraLayout.grid:
        return context.local.layout_spaced_grid;
      case CameraLayout.fixedSizing:
        return context.local.layout_compact_grid;
      case CameraLayout.speaker:
        return context.local.layout_speaker_view;
      case CameraLayout.mutliSpeaker:
        return context.local.layout_multi_speaker_view;
    }
  }
}
