import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/views/components/safe_video_track_renderer.dart';
import 'package:meet/views/scenes/settings/debug/mask_edge_sliders.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Debug screen: live camera preview with tunable blur sigma and obscure opacity.
class BackgroundBlurDebugScreen extends StatefulWidget {
  const BackgroundBlurDebugScreen({super.key});

  /// Opens only in debug builds ([kDebugMode]).
  static Future<void> show(BuildContext context) async {
    if (!kDebugMode || kIsWeb || !ProtonVideoEffects.isSupported) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const BackgroundBlurDebugScreen(),
      ),
    );
  }

  @override
  State<BackgroundBlurDebugScreen> createState() =>
      _BackgroundBlurDebugScreenState();
}

class _BackgroundBlurDebugScreenState extends State<BackgroundBlurDebugScreen> {
  static const double _minBlurSigma = BackgroundBlurConfig.minBlurSigma;
  static const double _maxBlurSigma = BackgroundBlurConfig.maxBlurSigma;
  LocalVideoTrack? _videoTrack;
  BackgroundBlurTrackProcessor? _blurProcessor;
  CameraPosition? _cameraPosition;
  bool _blurEnabled = true;
  bool _blurReady = false;
  bool _permissionGranted = false;
  bool _starting = true;
  String? _error;
  late double _blurSigma;
  late double _obscureOpacity;
  MaskEdgeTuning _maskEdge = MaskEdgeTuning.standard;
  bool _synchronousSegmentation = false;
  SegmentationModelPreference _segmentModel = (iOS || macOS)
      ? SegmentationModelPreference.vision
      : SegmentationModelPreference.landscape;
  String? _segmentBackend;
  bool _switchingSegmentModel = false;

  bool get _canFlipCamera => iOS || android;
  bool get _canPickSegmentModel => iOS || android || macOS;

  List<ButtonSegment<SegmentationModelPreference>> get _segmentModelSegments {
    if (iOS) {
      return const [
        ButtonSegment(
          value: SegmentationModelPreference.vision,
          label: Text('Vision'),
        ),
        ButtonSegment(
          value: SegmentationModelPreference.single,
          label: Text('Single'),
        ),
        ButtonSegment(
          value: SegmentationModelPreference.landscape,
          label: Text('Landscape'),
        ),
      ];
    }
    if (macOS) {
      return const [
        ButtonSegment(
          value: SegmentationModelPreference.vision,
          label: Text('Vision'),
        ),
      ];
    }
    return const [
      ButtonSegment(
        value: SegmentationModelPreference.single,
        label: Text('Single'),
      ),
      ButtonSegment(
        value: SegmentationModelPreference.landscape,
        label: Text('Landscape'),
      ),
    ];
  }

  BackgroundBlurConfig get _blurConfig => BackgroundBlurConfig(
    blurSigma: _blurSigma,
    backgroundObscureOpacity: _obscureOpacity,
    maskEdge: _maskEdge,
    synchronousSegmentation: _synchronousSegmentation,
  );

  bool get _canTuneMaskEdge => maskEdgeTuningSupported;

  @override
  void initState() {
    super.initState();
    _blurSigma = BackgroundBlurConfig.defaultBlurSigma;
    _obscureOpacity = BackgroundBlurConfig.defaultObscureOpacity;
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
        _blurReady = ready;
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
          _error = 'Native background blur is not ready on this device.';
        });
        return;
      }
      await ProtonVideoEffects.instance.applyPlatformDefaultSegmentationModel();
      await _startCamera();
      await _loadSegmentationModelInfo();
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

  Future<void> _loadSegmentationModelInfo() async {
    final info = await ProtonVideoEffects.instance.getSegmentationModelInfo();
    if (!mounted) {
      return;
    }
    setState(() {
      _segmentBackend = info.backend;
      if (info.model != null) {
        _segmentModel = info.model!;
      }
    });
  }

  Future<void> _onSegmentModelChanged(SegmentationModelPreference next) async {
    if (_segmentModel == next || _switchingSegmentModel) {
      return;
    }
    setState(() {
      _segmentModel = next;
      _switchingSegmentModel = true;
      _error = null;
    });
    try {
      await ProtonVideoEffects.instance.setSegmentationModelPreference(next);
      await _loadSegmentationModelInfo();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Segmentation model switch failed: $e');
    } finally {
      if (mounted) {
        setState(() => _switchingSegmentModel = false);
      }
    }
  }

  Future<void> _stopCamera() async {
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

  Future<void> _startCamera() async {
    await _stopCamera();
    if (!_permissionGranted || !_blurReady) {
      return;
    }

    BackgroundBlurTrackProcessor? processor;
    if (_blurEnabled) {
      processor = ProtonVideoEffects.instance.createBlurTrackProcessor(
        config: _blurConfig,
      );
      _blurProcessor = processor;
    }

    final track = await LocalVideoTrackHelper.cameraTrack(
      parameters: VideoParametersPresets.h720_169,
      position: _cameraPosition,
      processor: processor,
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

  Future<void> _applyBlurConfigLive() async {
    final config = _blurConfig;
    _blurProcessor?.setBackgroundBlurConfig(config);
    try {
      await ProtonVideoEffects.instance.setBackgroundBlurConfig(config);
    } catch (_) {}
  }

  Future<void> _toggleBlur() async {
    if (_starting) {
      return;
    }
    setState(() {
      _blurEnabled = !_blurEnabled;
      _starting = true;
    });
    try {
      if (_blurEnabled) {
        await _startCamera();
      } else {
        final track = _videoTrack;
        final trackId = track?.mediaStreamTrack.id;
        if (trackId != null && trackId.isNotEmpty) {
          await ProtonVideoEffects.instance.detachBackgroundBlur(
            trackId: trackId,
          );
        }
        _blurProcessor = null;
        if (mounted) {
          setState(() {
            _starting = false;
          });
        }
      }
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

  Future<void> _flipCamera() async {
    if (!_canFlipCamera || _starting) {
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

  void _onBlurSigmaChanged(double value) {
    setState(() => _blurSigma = value);
    if (_blurEnabled) {
      unawaited(_applyBlurConfigLive());
    }
  }

  void _onObscureOpacityChanged(double value) {
    setState(() => _obscureOpacity = value);
    if (_blurEnabled) {
      unawaited(_applyBlurConfigLive());
    }
  }

  void _onMaskEdgeChanged(MaskEdgeTuning tuning) {
    setState(() => _maskEdge = tuning);
    if (_blurEnabled) {
      unawaited(_applyBlurConfigLive());
    }
  }

  void _onSynchronousSegmentationChanged(bool enabled) {
    setState(() => _synchronousSegmentation = enabled);
    if (_blurEnabled) {
      unawaited(_applyBlurConfigLive());
    }
  }

  Future<void> _copyConfig() async {
    final buffer = StringBuffer()
      ..writeln('defaultBlurSigma => $_blurSigma')
      ..writeln(
        'defaultObscureOpacity => ${_obscureOpacity.toStringAsFixed(2)}',
      );
    if (_canTuneMaskEdge) {
      buffer
        ..writeln(
          'defaultFeatherHeightFraction => '
          '${_maskEdge.featherHeightFraction.toStringAsFixed(3)}',
        )
        ..writeln(
          'defaultErodeHeightFraction => '
          '${_maskEdge.erodeHeightFraction.toStringAsFixed(3)}',
        )
        ..writeln(
          'defaultSolidifySlope => ${_maskEdge.solidifySlope.toStringAsFixed(2)}',
        )
        ..writeln(
          'defaultSolidifyMidpoint => '
          '${_maskEdge.solidifyMidpoint.toStringAsFixed(2)}',
        )
        ..writeln(
          'defaultForegroundGamma => '
          '${_maskEdge.foregroundGamma.toStringAsFixed(2)}',
        );
    }
    final text = buffer.toString();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Blur config copied to clipboard')),
    );
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
    final height = (context.height * 0.48).clamp(300.0, 560.0);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodySmall = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.colors.textWeak);
    return Scaffold(
      backgroundColor: context.colors.backgroundNorm,
      appBar: AppBar(
        title: const Text('Background blur preview'),
        actions: [
          IconButton(
            tooltip: 'Copy config',
            onPressed: _copyConfig,
            icon: const Icon(Icons.copy, size: 20),
          ),
        ],
      ),
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
                    onTap: _starting ? null : () => unawaited(_flipCamera()),
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
                  onTap: _starting ? null : () => unawaited(_toggleBlur()),
                  child: Icon(
                    _blurEnabled ? Icons.blur_on : Icons.blur_off,
                    size: 20,
                    color: context.colors.textNorm,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            BlurParamSlider(
              title: 'Blur sigma',
              description:
                  'Gaussian blur strength (4–256). Higher = stronger background blur.',
              value: _blurSigma,
              min: _minBlurSigma,
              max: _maxBlurSigma,
              divisions: 126,
              formatValue: (v) => v.round().toString(),
              onChanged: _onBlurSigmaChanged,
            ),
            const SizedBox(height: 16),
            BlurParamSlider(
              title: 'Background obscure opacity',
              description:
                  'Gray veil over the blurred background (0 = none, 1 = heavy). '
                  'Helps hide doors / edges when blur alone is not enough.',
              value: _obscureOpacity,
              min: 0,
              max: 1,
              divisions: 20,
              formatValue: (v) => v.toStringAsFixed(2),
              onChanged: _onObscureOpacityChanged,
            ),
            if (_canTuneMaskEdge) ...[
              const SizedBox(height: 16),
              MaskEdgeSliders(tuning: _maskEdge, onChanged: _onMaskEdgeChanged),
              const SizedBox(height: 8),
              SynchronousSegmentationSwitch(
                value: _synchronousSegmentation,
                onChanged: _onSynchronousSegmentationChanged,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Segmentation model',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (_canPickSegmentModel) ...[
              Text(
                iOS
                    ? 'Production default: Vision. Single/Landscape use MediaPipe.'
                    : macOS
                    ? 'Production default: Apple Vision (only option on macOS).'
                    : 'Production default: landscape (16:9). Single = 256² square.',
                style: bodySmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<SegmentationModelPreference>(
                segments: _segmentModelSegments,
                selected: {_segmentModel},
                showSelectedIcon: false,
                onSelectionChanged: _switchingSegmentModel
                    ? null
                    : (selected) {
                        if (selected.isEmpty) {
                          return;
                        }
                        unawaited(_onSegmentModelChanged(selected.first));
                      },
              ),
              if (_segmentBackend != null) ...[
                const SizedBox(height: 4),
                Text('Active backend: $_segmentBackend', style: bodySmall),
              ],
            ],
            const SizedBox(height: 16),
            Text('Production defaults (plugin)', style: bodySmall),
            const SizedBox(height: 4),
            Text(
              'blurSigma: ${BackgroundBlurConfig.defaultBlurSigma}',
              style: bodySmall,
            ),
            Text(
              'obscureOpacity: ${BackgroundBlurConfig.defaultObscureOpacity}',
              style: bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Native blur ready: ${_blurReady ? 'yes' : 'no'} · '
              'Blur ${_blurEnabled ? 'on' : 'off'} · '
              'Segmenter: ${_segmentModel.name}',
              style: bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
