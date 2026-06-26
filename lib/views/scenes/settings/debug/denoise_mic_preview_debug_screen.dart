import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/views/scenes/settings/debug/denoise_mic_preview_loopback.dart';
import 'package:meet/views/scenes/widgets/audio.devices.selector.dart';
import 'package:meet/views/scenes/widgets/sound_waveform.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Debug screen: local mic loopback with runtime denoise switching (no room join).
///
/// Uses LiveKit [LocalAudioTrack], [Hardware] device enumeration, and [Room] device
/// APIs (same as prejoin / in-call), plus a WebRTC loopback player to hear output.
class DenoiseMicPreviewDebugScreen extends StatefulWidget {
  const DenoiseMicPreviewDebugScreen({super.key});

  static Future<void> show(BuildContext context) async {
    if (!kDebugMode || kIsWeb || !ProtonDenoiseEffects.isSupported) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DenoiseMicPreviewDebugScreen(),
      ),
    );
  }

  @override
  State<DenoiseMicPreviewDebugScreen> createState() =>
      _DenoiseMicPreviewDebugScreenState();
}

class _DenoiseMicPreviewDebugScreenState
    extends State<DenoiseMicPreviewDebugScreen> {
  final ProtonDenoiseEffects _effects = ProtonDenoiseEffects.instance;
  final DenoiseMicPreviewLoopback _loopback = DenoiseMicPreviewLoopback();
  final Room _previewRoom = Room(
    roomOptions: const RoomOptions(
      defaultAudioPublishOptions: AudioPublishOptions(
        name: 'denoise_mic_preview',
      ),
    ),
  );

  LocalAudioTrack? _audioTrack;
  List<MediaDevice> _audioInputs = const [];
  List<MediaDevice> _audioOutputs = const [];
  MediaDevice? _selectedMic;
  MediaDevice? _selectedSpeaker;
  List<DenoiseTypeInfo> _nativeTypes = const [];
  DenoiseType _selectedType = DenoiseType.none;
  bool _monitoring = false;
  bool _starting = true;
  bool _switchingType = false;
  bool _isMicrophonePermissionGranted = false;
  double _deepFilterAttenLimDb = kDeepFilterDefaultAttenLimDb;
  String? _error;
  String? _attachedTrackId;
  StreamSubscription<List<MediaDevice>>? _deviceChangeSub;

  List<_PreviewOption> get _previewOptions {
    final options = <_PreviewOption>[
      const _PreviewOption(type: DenoiseType.none, ready: true),
    ];
    for (final info in _nativeTypes) {
      if (info.type == DenoiseType.none) {
        continue;
      }
      options.add(_PreviewOption(type: info.type, ready: info.isReady));
    }
    return options;
  }

  AudioCaptureOptions _captureOptions({String? deviceId}) {
    return AudioCaptureOptions(
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      deviceId: deviceId ?? _selectedMic?.deviceId,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_deviceChangeSub?.cancel());
    unawaited(_stopMonitoring());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final granted = await PermissionService().requestMicrophonePermission();
      if (!mounted) {
        return;
      }
      if (!granted) {
        setState(() {
          _starting = false;
          _isMicrophonePermissionGranted = false;
          _error = 'Microphone permission denied.';
        });
        return;
      }

      setState(() => _isMicrophonePermissionGranted = true);

      await _loadDevices();

      final types = await _effects.listDenoiseTypes();
      DenoiseType? firstReady;
      for (final info in types) {
        if (info.isReady && info.type != DenoiseType.none) {
          firstReady = info.type;
          break;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _nativeTypes = types;
        _selectedType = firstReady ?? DenoiseType.none;
        _starting = false;
      });

      await _startMonitoring();
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

  Future<void> _loadDevices() async {
    final devices = await Hardware.instance.enumerateDevices();
    final audioInputs = devices
        .where((device) => device.kind == 'audioinput')
        .toList();
    final audioOutputs = devices
        .where((device) => device.kind == 'audiooutput')
        .toList();

    MediaDevice? selectedMic = _selectedMic;
    if (selectedMic == null ||
        !audioInputs.any((d) => d.deviceId == selectedMic!.deviceId)) {
      selectedMic = audioInputs.isNotEmpty
          ? audioInputs.first
          : Hardware.instance.selectedAudioInput ?? selectedMic;
    }

    MediaDevice? selectedSpeaker = _selectedSpeaker;
    if (selectedSpeaker == null ||
        !audioOutputs.any((d) => d.deviceId == selectedSpeaker!.deviceId)) {
      selectedSpeaker = audioOutputs.isNotEmpty
          ? audioOutputs.first
          : Hardware.instance.selectedAudioOutput ?? selectedSpeaker;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _audioInputs = audioInputs;
      _audioOutputs = audioOutputs;
      _selectedMic = selectedMic;
      _selectedSpeaker = selectedSpeaker;
    });

    await _deviceChangeSub?.cancel();
    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((
      devices,
    ) {
      unawaited(_onDevicesChanged(devices));
    });
  }

  Future<void> _onDevicesChanged(List<MediaDevice> devices) async {
    if (!mounted) {
      return;
    }
    final audioInputs = devices
        .where((device) => device.kind == 'audioinput')
        .toList();
    final audioOutputs = devices
        .where((device) => device.kind == 'audiooutput')
        .toList();

    MediaDevice? selectedMic = _selectedMic;
    if (selectedMic == null ||
        !audioInputs.any((d) => d.deviceId == selectedMic!.deviceId)) {
      selectedMic = audioInputs.isNotEmpty
          ? audioInputs.first
          : Hardware.instance.selectedAudioInput ?? selectedMic;
    }

    MediaDevice? selectedSpeaker = _selectedSpeaker;
    if (selectedSpeaker == null ||
        !audioOutputs.any((d) => d.deviceId == selectedSpeaker!.deviceId)) {
      selectedSpeaker = audioOutputs.isNotEmpty
          ? audioOutputs.first
          : Hardware.instance.selectedAudioOutput ?? selectedSpeaker;
    }

    final previousMicId = _selectedMic?.deviceId;
    final previousSpeakerId = _selectedSpeaker?.deviceId;

    setState(() {
      _audioInputs = audioInputs;
      _audioOutputs = audioOutputs;
      _selectedMic = selectedMic;
      _selectedSpeaker = selectedSpeaker;
    });

    if (_monitoring &&
        selectedMic != null &&
        selectedMic.deviceId != previousMicId) {
      await _recreateAudioTrack();
    }
    if (_monitoring &&
        selectedSpeaker != null &&
        selectedSpeaker.deviceId != previousSpeakerId) {
      await _applySpeakerDevice(selectedSpeaker);
    }
  }

  Future<void> _prepareAudioSession() async {
    if (iOS) {
      await rtc.Helper.ensureAudioSession();
    }
    if (iOS || android) {
      await Hardware.instance.setSpeakerphoneOn(true);
    }
  }

  Future<void> _syncDevicesFromActiveTrack(LocalAudioTrack track) async {
    await _loadDevices();
    if (_audioInputs.isNotEmpty) {
      return;
    }

    final hardwareMic = Hardware.instance.selectedAudioInput;
    if (hardwareMic != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioInputs = [hardwareMic];
        _selectedMic ??= hardwareMic;
      });
      return;
    }

    final mediaTrack = track.mediaStreamTrack;
    final settings = mediaTrack.getSettings();
    final deviceId =
        (settings['deviceId'] as String?)?.trim().isNotEmpty == true
        ? settings['deviceId'] as String
        : 'default';
    final label = (mediaTrack.label ?? '').trim();
    final mic = MediaDevice(
      deviceId,
      label.isNotEmpty ? label : 'Default microphone',
      'audioinput',
      null,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _audioInputs = [mic];
      _selectedMic ??= mic;
    });
  }

  Future<void> _startMonitoring() async {
    if (!_isMicrophonePermissionGranted) {
      setState(() {
        _error = 'Microphone permission denied.';
        _starting = false;
      });
      return;
    }

    await _stopMonitoring();
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      await _prepareAudioSession();

      final selectedMic = _selectedMic;
      if (selectedMic != null) {
        await _previewRoom.setAudioInputDevice(selectedMic);
      }
      if (_selectedSpeaker != null) {
        await _applySpeakerDevice(_selectedSpeaker!);
      }

      final track = await LocalAudioTrack.create(_captureOptions());
      await track.start();

      await _applyDenoiseType(
        _selectedType,
        trackId: track.mediaStreamTrack.id,
      );
      await _loopback.start(track);

      if (_selectedSpeaker != null) {
        await _loopback.setAudioOutput(_selectedSpeaker!.deviceId);
      }

      // Inputs often appear only after capture has started (iOS / macOS).
      await _syncDevicesFromActiveTrack(track);

      if (!mounted) {
        await track.stop();
        await _loopback.stop();
        return;
      }

      setState(() {
        _audioTrack = track;
        _monitoring = true;
        _starting = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _monitoring = false;
        _starting = false;
        _error = '$e';
      });
    }
  }

  Future<void> _recreateAudioTrack() async {
    if (!_monitoring) {
      return;
    }

    final previousType = _selectedType;
    await _stopMonitoring();
    setState(() => _selectedType = previousType);
    await _startMonitoring();
  }

  Future<void> _stopMonitoring() async {
    final track = _audioTrack;
    final trackId = _attachedTrackId;

    _audioTrack = null;
    _attachedTrackId = null;
    _monitoring = false;

    if (trackId != null) {
      try {
        await _effects.detachDenoise(trackId: trackId);
      } catch (_) {}
    }

    await _loopback.stop();

    if (track != null) {
      try {
        await track.stop();
      } catch (_) {}
    }
  }

  Future<void> _applySpeakerDevice(MediaDevice device) async {
    await _previewRoom.setAudioOutputDevice(device);
    if (android || iOS) {
      await rtc.Helper.selectAudioOutput(device.deviceId);
    } else {
      await Hardware.instance.selectAudioOutput(device);
    }
    if (_loopback.playbackRenderer != null) {
      await _loopback.setAudioOutput(device.deviceId);
    }
  }

  Future<void> _onMicChanged(MediaDevice? device) async {
    if (device == null || device.deviceId == _selectedMic?.deviceId) {
      return;
    }
    setState(() {
      _selectedMic = device;
      _error = null;
    });
    try {
      await _previewRoom.setAudioInputDevice(device);
      if (_monitoring) {
        await _recreateAudioTrack();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to switch microphone: $e');
    }
  }

  Future<void> _onSpeakerChanged(MediaDevice? device) async {
    if (device == null || device.deviceId == _selectedSpeaker?.deviceId) {
      return;
    }
    setState(() {
      _selectedSpeaker = device;
      _error = null;
    });
    try {
      await _applySpeakerDevice(device);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to switch speaker: $e');
    }
  }

  Future<void> _applyDenoiseType(DenoiseType type, {String? trackId}) async {
    final id = trackId ?? _audioTrack?.mediaStreamTrack.id;
    if (id == null || id.isEmpty) {
      return;
    }

    if (_attachedTrackId != null && _attachedTrackId != id) {
      try {
        await _effects.detachDenoise(trackId: _attachedTrackId!);
      } catch (_) {}
      _attachedTrackId = null;
    }

    if (type == DenoiseType.none) {
      if (_attachedTrackId != null) {
        await _effects.detachDenoise(trackId: id);
        _attachedTrackId = null;
      }
      return;
    }

    if (!await _effects.isTypeReady(type)) {
      throw StateError('${type.displayName} is not ready on this device');
    }

    if (DenoiseAudioService.isDeepFilterType(type)) {
      await _effects.warmUpDenoise(type: type);
    }

    await _effects.attachDenoise(
      trackId: id,
      type: type,
      deepFilterAttenLimDb: DenoiseAudioService.isDeepFilterType(type)
          ? _deepFilterAttenLimDb
          : null,
    );
    _attachedTrackId = id;
  }

  bool get _isDeepFilterSelected =>
      DenoiseAudioService.isDeepFilterType(_selectedType);

  Future<void> _onDeepFilterAttenLimChanged(double value) async {
    setState(() => _deepFilterAttenLimDb = value);
    final trackId = _attachedTrackId ?? _audioTrack?.mediaStreamTrack.id;
    if (!_monitoring ||
        !_isDeepFilterSelected ||
        trackId == null ||
        trackId.isEmpty) {
      return;
    }
    try {
      await _effects.setDeepFilterAttenLim(trackId: trackId, attenLimDb: value);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to update DeepFilter strength: $e');
    }
  }

  Future<void> _onTypeSelected(DenoiseType type) async {
    if (_switchingType || type == _selectedType) {
      return;
    }
    setState(() {
      _selectedType = type;
      _switchingType = true;
      _error = null;
    });
    try {
      if (!_monitoring) {
        await _startMonitoring();
        return;
      }
      await _applyDenoiseType(type);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to switch denoise: $e');
    } finally {
      if (mounted) {
        setState(() => _switchingType = false);
      }
    }
  }

  Future<void> _toggleMonitoring() async {
    if (_starting || _switchingType) {
      return;
    }
    if (_monitoring) {
      await _stopMonitoring();
      if (mounted) {
        setState(() {});
      }
    } else {
      await _startMonitoring();
    }
  }

  Widget _typeRow(BuildContext context, _PreviewOption option) {
    final enabled = option.ready && !_switchingType && !_starting;
    final selected = _selectedType == option.type;
    final title = option.type == DenoiseType.none
        ? 'Off (raw mic)'
        : option.type.displayName;

    return Opacity(
      opacity: option.ready ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => unawaited(_onTypeSelected(option.type)) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.textNorm,
                      ),
                    ),
                    if (!option.ready)
                      Text(
                        'Not available on this device',
                        style: ProtonStyles.body2Regular(
                          color: context.colors.textWeak,
                        ),
                      ),
                  ],
                ),
              ),
              if (_switchingType && selected)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.protonBlue,
                  ),
                )
              else
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected
                      ? context.colors.protonBlue
                      : context.colors.interActionWeak,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodySmall = ProtonStyles.body2Regular(color: context.colors.textWeak);
    final track = _audioTrack;
    final playbackRenderer = _loopback.playbackRenderer;

    return Scaffold(
      backgroundColor: context.colors.backgroundNorm,
      appBar: AppBar(title: const Text('Denoise mic preview')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            Text(
              'Speak into your microphone and listen on your selected speaker or '
              'headphones. Switch algorithms below to compare without joining a '
              'meeting.',
              style: bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: use headphones to avoid feedback when monitoring on speaker.',
              style: bodySmall,
            ),
            const SizedBox(height: 20),
            Text(
              'Audio devices',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            AudioDevicesSelector(
              enabled: _monitoring,
              showContent: true,
              micDevices: _audioInputs,
              speakerDevices: _audioOutputs,
              selectedMic: _selectedMic,
              selectedSpeaker: _selectedSpeaker,
              onMicChanged: (device) => unawaited(_onMicChanged(device)),
              onSpeakerChanged: (device) =>
                  unawaited(_onSpeakerChanged(device)),
              permissionGranted: _isMicrophonePermissionGranted,
              backgroundColor: context.colors.backgroundSecondary,
              width: double.infinity,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Mic level',
                      style: ProtonStyles.body2Semibold(
                        color: context.colors.textWeak,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: Center(
                      child: track != null && _monitoring
                          ? SoundWaveformWidget(
                              key: ValueKey(track.mediaStreamTrack.id),
                              audioTrack: track,
                              barCount: 9,
                              width: 6,
                              maxHeight: 88,
                            )
                          : _starting
                          ? const CircularProgressIndicator()
                          : Icon(
                              Icons.mic_off,
                              size: 40,
                              color: context.colors.textWeak,
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: (_starting || _switchingType)
                        ? null
                        : () => unawaited(_toggleMonitoring()),
                    icon: Icon(_monitoring ? Icons.stop : Icons.mic),
                    label: Text(
                      _monitoring ? 'Stop monitoring' : 'Start monitoring',
                    ),
                  ),
                ],
              ),
            ),
            if (playbackRenderer != null)
              SizedBox(
                width: 1,
                height: 1,
                child: rtc.RTCVideoView(
                  playbackRenderer,
                  objectFit:
                      rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Denoise algorithm',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  for (final option in _previewOptions)
                    _typeRow(context, option),
                ],
              ),
            ),
            if (_isDeepFilterSelected) ...[
              const SizedBox(height: 16),
              Text(
                'DeepFilter strength',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Max noise attenuation: ${_deepFilterAttenLimDb.round()} dB. '
                'Lower = gentler (less musical noise). Default is '
                '${kDeepFilterDefaultAttenLimDb.round()} dB.',
                style: bodySmall,
              ),
              Slider(
                value: _deepFilterAttenLimDb,
                min: kDeepFilterMinAttenLimDb,
                max: kDeepFilterMaxAttenLimDb,
                divisions: (kDeepFilterMaxAttenLimDb - kDeepFilterMinAttenLimDb)
                    .round(),
                label: '${_deepFilterAttenLimDb.round()} dB',
                onChanged: (_starting || _switchingType)
                    ? null
                    : (value) => unawaited(_onDeepFilterAttenLimChanged(value)),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Mic: ${_selectedMic?.label ?? '—'} · '
              'Speaker: ${_selectedSpeaker?.label ?? '—'} · '
              'Denoise: ${_selectedType == DenoiseType.none ? 'Off' : _selectedType.displayName}'
              '${_isDeepFilterSelected ? ' (${_deepFilterAttenLimDb.round()} dB cap)' : ''} · '
              'Monitoring: ${_monitoring ? 'on' : 'off'}',
              style: bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewOption {
  const _PreviewOption({required this.type, required this.ready});

  final DenoiseType type;
  final bool ready;
}
