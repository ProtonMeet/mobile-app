import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/background_blur/virtual_background_image_picker.dart';
import 'package:meet/helper/background_blur/virtual_background_presets.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/safe_video_track_renderer.dart';
import 'package:path_provider/path_provider.dart';

/// Bottom sheet for choosing blur, bundled presets, or a custom image background.
class VirtualBackgroundSheet {
  VirtualBackgroundSheet._();

  static Future<CameraBackgroundSelection?> show(
    BuildContext context, {
    required CameraBackgroundSelection initialSelection,
    VideoTrack? previewTrack,
  }) {
    return showModalBottomSheet<CameraBackgroundSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => _VirtualBackgroundSheetBody(
        initialSelection: initialSelection,
        previewTrack: previewTrack,
      ),
    );
  }
}

class _VirtualBackgroundSheetBody extends StatefulWidget {
  const _VirtualBackgroundSheetBody({
    required this.initialSelection,
    this.previewTrack,
  });

  final CameraBackgroundSelection initialSelection;
  final VideoTrack? previewTrack;

  @override
  State<_VirtualBackgroundSheetBody> createState() =>
      _VirtualBackgroundSheetBodyState();
}

/// Decode width for preset tiles, sized for a third-of-sheet tile at 3x.
const int _presetThumbnailCacheWidth = 360;

class _VirtualBackgroundSheetBodyState
    extends State<_VirtualBackgroundSheetBody> {
  late CameraBackgroundSelection _selection;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
  }

  Future<void> _pickCustomImage() async {
    if (_pickingImage) {
      return;
    }
    setState(() => _pickingImage = true);
    try {
      final picked = await VirtualBackgroundImagePicker.pick();
      if (!mounted || picked == null || picked.isEmpty) {
        return;
      }
      final path = picked.filePath;
      if (path != null && path.isNotEmpty) {
        _commitSelection(CameraBackgroundSelection.custom(path));
        return;
      }
      final bytes = picked.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}/virtual_background_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(bytes, flush: true);
        _commitSelection(CameraBackgroundSelection.custom(file.path));
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      }
    }
  }

  void _commitSelection(CameraBackgroundSelection next) {
    setState(() => _selection = next);
    Navigator.of(context).pop(next);
  }

  bool _isSelectedEffect(CameraBackgroundEffectKind kind, {String? presetId}) {
    if (_selection.kind != kind) {
      return false;
    }
    if (kind == CameraBackgroundEffectKind.preset) {
      return _selection.presetId == presetId;
    }
    if (kind == CameraBackgroundEffectKind.custom) {
      return _selection.customImagePath != null;
    }
    return true;
  }

  /// Full-size preset artwork is multi-megapixel, so decode it down to tile
  /// size — six full decodes would otherwise sit in the image cache.
  Widget _presetThumbnail(VirtualBackgroundPreset preset) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: preset.asset.image(
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: _presetThumbnailCacheWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = VirtualBackgroundPresets.all;
    final previewHeight = macOS
        ? (context.isLandscape ? 220.0 : 280.0)
        : (context.isLandscape ? 160.0 : 198.0);

    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: context.isLandscape,
      modalOnBackdropTap: () => Navigator.of(context).pop(),
      modalMaxHeight: context.height * 0.88,
      modalFillMaxHeight: false,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              context.local.virtual_backgrounds_title,
              style: ProtonStyles.headline(
                fontSize: 18,
                color: context.colors.textNorm,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PreviewCard(
              height: previewHeight,
              previewTrack: widget.previewTrack,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EffectRow(
                      children: [
                        _EffectTile(
                          label: context.local.virtual_background_none,
                          selected: _isSelectedEffect(
                            CameraBackgroundEffectKind.none,
                          ),
                          onTap: () => _commitSelection(
                            const CameraBackgroundSelection.none(),
                          ),
                          child: Icon(
                            Icons.block,
                            color: context.colors.textNorm,
                            size: 20,
                          ),
                        ),
                        _EffectTile(
                          label: context.local.camera_background_blur,
                          selected: _isSelectedEffect(
                            CameraBackgroundEffectKind.blur,
                          ),
                          onTap: () => _commitSelection(
                            const CameraBackgroundSelection.blur(),
                          ),
                          child: Icon(
                            Icons.blur_on,
                            color: context.colors.textNorm,
                            size: 20,
                          ),
                        ),
                        _EffectTile(
                          label: context.local.virtual_background_custom,
                          selected: _isSelectedEffect(
                            CameraBackgroundEffectKind.custom,
                          ),
                          onTap: _pickingImage
                              ? null
                              : () => unawaited(_pickCustomImage()),
                          child: _pickingImage
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colors.textNorm,
                                  ),
                                )
                              : Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: context.colors.textNorm,
                                  size: 20,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _EffectRow(
                      children: [
                        for (final preset in presets.take(3))
                          _EffectTile(
                            selected: _isSelectedEffect(
                              CameraBackgroundEffectKind.preset,
                              presetId: preset.id,
                            ),
                            onTap: () => _commitSelection(
                              CameraBackgroundSelection.preset(preset.id),
                            ),
                            child: _presetThumbnail(preset),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _EffectRow(
                      children: [
                        for (final preset in presets.skip(3).take(3))
                          _EffectTile(
                            selected: _isSelectedEffect(
                              CameraBackgroundEffectKind.preset,
                              presetId: preset.id,
                            ),
                            onTap: () => _commitSelection(
                              CameraBackgroundSelection.preset(preset.id),
                            ),
                            child: _presetThumbnail(preset),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.height, this.previewTrack});

  final double height;
  final VideoTrack? previewTrack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: height * 16 / 9,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: context.colors.interActionPurpleMinor3),
              if (previewTrack != null)
                SafeVideoTrackRenderer(videoTrack: previewTrack!),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EffectRow extends StatelessWidget {
  const _EffectRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({
    required this.selected,
    required this.onTap,
    required this.child,
    this.label,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? context.colors.interActionNormMajor1
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: context.colors.interActionWeak,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
