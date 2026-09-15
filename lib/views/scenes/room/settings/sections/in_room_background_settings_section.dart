import 'dart:io';

import 'package:flutter/material.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/background_blur/virtual_background_presets.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/settings/settings_nav_row.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/components/settings/settings_toggle_row.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';

/// Camera background blur and virtual backgrounds.
class InRoomBackgroundSettingsSection extends StatelessWidget {
  const InRoomBackgroundSettingsSection({required this.state, super.key});

  final InRoomSettingsState state;

  @override
  Widget build(BuildContext context) {
    if (!state.showCameraBackground) {
      return const SizedBox.shrink();
    }

    final onVirtualBackgrounds = state.onVirtualBackgroundsTap;

    return SettingsSection(
      title: context.local.settings_section_background,
      rows: [
        SettingsToggleRow(
          title: context.local.camera_background_blur,
          value: state.backgroundBlurEnabled,
          onChanged: state.onBackgroundBlurChanged,
        ),
        if (onVirtualBackgrounds != null)
          SettingsNavRow(
            title: context.local.virtual_backgrounds_title,
            value: _virtualBackgroundLabel(context, state),
            accessory: _VirtualBackgroundSwatch(
              selection: state.cameraBackgroundSelection,
            ),
            onTap: onVirtualBackgrounds,
          ),
      ],
    );
  }
}

/// Null for blur and presets — the swatch already identifies the choice.
String? _virtualBackgroundLabel(
  BuildContext context,
  InRoomSettingsState state,
) {
  switch (state.cameraBackgroundSelection.kind) {
    case CameraBackgroundEffectKind.none:
      return context.local.virtual_background_none;
    case CameraBackgroundEffectKind.blur:
    case CameraBackgroundEffectKind.preset:
      return null;
    case CameraBackgroundEffectKind.custom:
      return context.local.virtual_background_custom;
  }
}

/// Preview of the active camera background next to the virtual backgrounds row.
class _VirtualBackgroundSwatch extends StatelessWidget {
  const _VirtualBackgroundSwatch({required this.selection});

  static const double _size = 28;

  /// Decode budget for the 28pt swatch at 3x.
  static const int _cacheWidth = 84;

  final CameraBackgroundSelection selection;

  @override
  Widget build(BuildContext context) {
    Widget? image;
    switch (selection.kind) {
      case CameraBackgroundEffectKind.preset:
        final preset = VirtualBackgroundPresets.byId(selection.presetId);
        image = preset?.asset.image(fit: BoxFit.cover, cacheWidth: _cacheWidth);
      case CameraBackgroundEffectKind.custom:
        final path = selection.customImagePath;
        if (path != null && path.isNotEmpty) {
          image = Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: _cacheWidth,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }
      case CameraBackgroundEffectKind.none:
        image = null;
      case CameraBackgroundEffectKind.blur:
        image = context.images.iconVirtualBackgroundBlur.svgSize(
          color: context.colors.textNorm,
          size: _size,
        );
    }

    if (image == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: _size, height: _size, child: image),
      ),
    );
  }
}
