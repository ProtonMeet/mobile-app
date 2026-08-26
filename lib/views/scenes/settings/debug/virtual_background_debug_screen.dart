import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/background_blur/camera_background_effect_service.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/views/components/bottom.sheets/virtual_background_sheet.dart';
import 'package:meet/views/components/safe_video_track_renderer.dart';
import 'package:meet/views/scenes/settings/debug/mask_edge_sliders.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Debug screen: live camera preview + production virtual background sheet.
class VirtualBackgroundDebugScreen extends StatefulWidget {
  const VirtualBackgroundDebugScreen({super.key});

  static Future<void> show(BuildContext context) async {
    if (!kDebugMode || kIsWeb || !ProtonVideoEffects.isSupported) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const VirtualBackgroundDebugScreen(),
      ),
    );
  }

  @override
  State<VirtualBackgroundDebugScreen> createState() =>
      _VirtualBackgroundDebugScreenState();
}

class _VirtualBackgroundDebugScreenState
    extends State<VirtualBackgroundDebugScreen> {
  LocalVideoTrack? _videoTrack;
  BackgroundBlurTrackProcessor? _blurProcessor;
  CameraPosition? _cameraPosition;
  CameraBackgroundSelection _selection = const CameraBackgroundSelection.none();
  bool _effectsReady = false;
  bool _permissionGranted = false;
  bool _starting = true;
  bool _applyingSelection = false;
  String? _error;
  MaskEdgeTuning _maskEdge = MaskEdgeTuning.standard;
  bool _synchronousSegmentation = false;

  bool get _canFlipCamera => iOS || android;

  @override
  void initState() {
    super.initState();
    if (_canFlipCamera) {
      _cameraPosition = CameraPosition.front;
    }
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_stopCamera());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final granted = await PermissionService().requestCameraPermission();
      final ready = await ProtonVideoEffects.instance.isBackgroundBlurReady();
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionGranted = granted;
        _effectsReady = ready;
      });
      if (!granted) {
        setState(() {
          _starting = false;
          _error = 'Camera permission denied.';
        });
        return;
      }
      if (!ready) {
        setState(() {
          _starting = false;
          _error = 'Native video effects are not ready on this device.';
        });
        return;
      }
      await ProtonVideoEffects.instance.applyPlatformDefaultSegmentationModel();
      await _startCamera();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _error = '$e';
      });
    }
  }

  Future<void> _stopCamera() async {
    try {
      await ProtonVideoEffects.instance.clearReplacementBackground();
    } catch (_) {}
    final track = _videoTrack;
    _videoTrack = null;
    _blurProcessor = null;
    if (track != null) {
      final trackId = track.mediaStreamTrack.id;
      if (trackId != null && trackId.isNotEmpty) {
        try {
          await ProtonVideoEffects.instance.detachBackgroundBlur(
            trackId: trackId,
          );
        } catch (_) {}
      }
      try {
        await track.stop();
      } catch (_) {}
    }
  }

  /// Production config for [selection], with the debug-only mask edge overrides layered on.
  BackgroundBlurConfig _configForSelection(
    CameraBackgroundSelection selection,
  ) {
    return resolveCameraBackgroundBlurConfig(selection).copyWith(
      maskEdge: _maskEdge,
      synchronousSegmentation: _synchronousSegmentation,
    );
  }

  /// Mask edge changes reshape the composite only, so they apply without rebuilding the track.
  Future<void> _applyMaskEdgeLive() async {
    if (!_selection.isEffectActive) {
      return;
    }
    final config = _configForSelection(_selection);
    _blurProcessor?.setBackgroundBlurConfig(config);
    try {
      await ProtonVideoEffects.instance.setBackgroundBlurConfig(config);
    } catch (_) {}
  }

  void _onMaskEdgeChanged(MaskEdgeTuning tuning) {
    setState(() => _maskEdge = tuning);
    unawaited(_applyMaskEdgeLive());
  }

  void _onSynchronousSegmentationChanged(bool enabled) {
    setState(() => _synchronousSegmentation = enabled);
    unawaited(_applyMaskEdgeLive());
  }

  Future<void> _startCamera() async {
    await _stopCamera();
    if (!_permissionGranted || !_effectsReady) {
      return;
    }

    BackgroundBlurTrackProcessor? processor;
    if (_selection.isEffectActive) {
      final config = _configForSelection(_selection);
      processor = ProtonVideoEffects.instance.createBlurTrackProcessor(
        config: config,
      );
      await prepareCameraBackgroundSelectionForTrackCreation(_selection);
    }
    _blurProcessor = processor;

    final track = await LocalVideoTrackHelper.cameraTrack(
      parameters: VideoParametersPresets.h720_169,
      position: _cameraPosition,
      processor: processor,
      backgroundSelection: _selection,
    );
    await track.start();
    if (!mounted) {
      await track.stop();
      return;
    }
    setState(() {
      _videoTrack = track;
      _starting = false;
      _error = null;
    });
  }

  Future<void> _applySelection(CameraBackgroundSelection selection) async {
    if (_starting || _applyingSelection) {
      return;
    }
    setState(() {
      _selection = selection;
      _applyingSelection = true;
      _error = null;
    });
    try {
      await _startCamera();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to apply background: $e');
    } finally {
      if (mounted) {
        setState(() => _applyingSelection = false);
      }
    }
  }

  Future<void> _openBackgroundSheet() async {
    if (_starting || _applyingSelection) {
      return;
    }
    final selection = await VirtualBackgroundSheet.show(
      context,
      initialSelection: _selection,
      previewTrack: _videoTrack,
    );
    if (selection == null || !mounted) {
      return;
    }
    await _applySelection(selection);
  }

  Future<void> _flipCamera() async {
    if (!_canFlipCamera || _starting || _applyingSelection) {
      return;
    }
    setState(() {
      _cameraPosition = _cameraPosition?.switched() ?? CameraPosition.back;
      _starting = true;
    });
    try {
      await _startCamera();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _error = '$e';
      });
    }
  }

  String _selectionLabel(CameraBackgroundSelection selection) {
    return switch (selection.kind) {
      CameraBackgroundEffectKind.none => 'None',
      CameraBackgroundEffectKind.blur => 'Blur',
      CameraBackgroundEffectKind.preset => 'Preset: ${selection.presetId}',
      CameraBackgroundEffectKind.custom =>
        'Custom: ${selection.customImagePath}',
    };
  }

  Widget _roundControlButton({
    required BuildContext context,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    final bg = context.colors.controlBarBtnBackground;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(14),
        decoration: ShapeDecoration(
          color: bg,
          shape: RoundedRectangleBorder(
            side: BorderSide(width: 0.86, color: bg),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _preview(BuildContext context) {
    const aspectRatio = 16 / 9;
    final maxWidth = (context.width - 32).clamp(280.0, 360.0);
    final height = maxWidth / aspectRatio;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: maxWidth,
          height: height,
          child: ColoredBox(
            color: context.colors.interActionPurpleMinor3,
            child: _videoTrack != null
                ? SafeVideoTrackRenderer(
                    videoTrack: _videoTrack!,
                    mirrorMode: _cameraPosition == CameraPosition.front
                        ? VideoViewMirrorMode.mirror
                        : VideoViewMirrorMode.off,
                  )
                : Center(
                    child: _starting
                        ? const CircularProgressIndicator()
                        : Icon(
                            Icons.videocam_off,
                            size: 48,
                            color: context.colors.textWeak,
                          ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodySmall = ProtonStyles.body2Regular(color: context.colors.textWeak);

    return Scaffold(
      backgroundColor: context.colors.backgroundNorm,
      appBar: AppBar(title: const Text('Virtual backgrounds')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            _preview(context),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_canFlipCamera) ...[
                  _roundControlButton(
                    context: context,
                    onTap: _starting || _applyingSelection
                        ? null
                        : () => unawaited(_flipCamera()),
                    child: context.images.iconSwapCamera.svg(
                      width: 20,
                      height: 20,
                      fit: BoxFit.fill,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                _roundControlButton(
                  context: context,
                  onTap: _starting || _applyingSelection
                      ? null
                      : () => unawaited(_openBackgroundSheet()),
                  child: Icon(
                    Icons.wallpaper,
                    size: 20,
                    color: context.colors.textNorm,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _starting || _applyingSelection
                  ? null
                  : () => unawaited(_openBackgroundSheet()),
              child: _applyingSelection
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.local.virtual_backgrounds_title),
            ),
            if (maskEdgeTuningSupported && _selection.isEffectActive) ...[
              const SizedBox(height: 24),
              MaskEdgeSliders(tuning: _maskEdge, onChanged: _onMaskEdgeChanged),
              const SizedBox(height: 8),
              SynchronousSegmentationSwitch(
                value: _synchronousSegmentation,
                onChanged: _onSynchronousSegmentationChanged,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Current selection',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(_selectionLabel(_selection), style: bodySmall),
            const SizedBox(height: 8),
            Text(
              'Opens the same bottom sheet used on prejoin. '
              'No Unleash flag required in this debug screen.',
              style: bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Native effects ready: ${_effectsReady ? 'yes' : 'no'}',
              style: bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
