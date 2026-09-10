import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/settings/settings_action_item.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proton_denoise/denoise_type.dart';
import 'package:proton_denoise/offline_denoise_debug.dart';
import 'package:share_plus/share_plus.dart';

/// Debug sheet: offline file denoise using the same native pipelines as in-meeting attach.
class OfflineFileDenoiseDebugSheet {
  OfflineFileDenoiseDebugSheet._();

  static Future<void> show(
    BuildContext context, {
    required DenoiseType type,
  }) async {
    if (!kDebugMode || !Platform.isAndroid) {
      return;
    }
    if (type != DenoiseType.rnnoise && type != DenoiseType.dtlnRs) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OfflineFileDenoiseDebugBody(type: type),
    );
  }
}

class _OfflineFileDenoiseDebugBody extends StatefulWidget {
  const _OfflineFileDenoiseDebugBody({required this.type});

  final DenoiseType type;

  @override
  State<_OfflineFileDenoiseDebugBody> createState() =>
      _OfflineFileDenoiseDebugBodyState();
}

class _OfflineFileDenoiseDebugBodyState
    extends State<_OfflineFileDenoiseDebugBody> {
  final _pathController = TextEditingController(
    text: '/storage/emulated/0/Download/lawnmower.mp3',
  );
  bool _busy = false;
  String? _status;
  String? _outputPath;
  bool _nativeReady = false;

  String get _title => switch (widget.type) {
    DenoiseType.rnnoise => 'RNNoise file denoise (debug)',
    DenoiseType.dtlnRs => 'DTLN file denoise (debug)',
    _ => 'File denoise (debug)',
  };

  String get _notReadyHint => switch (widget.type) {
    DenoiseType.rnnoise => 'RNNoise native not ready.',
    DenoiseType.dtlnRs =>
      'dtln-rs native not ready. Rebuild after utilities/build-dtln-rs.sh android.',
    _ => 'Native not ready.',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_loadReady());
  }

  Future<void> _loadReady() async {
    final ready = await OfflineDenoiseDebugChannel.isTypeReady(widget.type);
    if (!mounted) {
      return;
    }
    setState(() => _nativeReady = ready);
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<bool> _ensureCanReadExternalAudio() async {
    if (await Permission.audio.isGranted ||
        await Permission.storage.isGranted) {
      return true;
    }
    final status = await Permission.audio.request();
    if (status.isGranted) {
      return true;
    }
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  Future<void> _runDenoise() async {
    final input = _pathController.text.trim();
    if (input.isEmpty) {
      setState(() => _status = 'Enter a file path on the device.');
      return;
    }
    if (!await _ensureCanReadExternalAudio()) {
      setState(
        () => _status =
            'Grant audio/storage permission to read files in Downloads.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Decoding and denoising…';
      _outputPath = null;
    });
    try {
      final result = await OfflineDenoiseDebugChannel.denoiseFile(
        inputPath: input,
        type: widget.type,
      );
      final out = result['outputPath'] as String?;
      setState(() {
        _outputPath = out;
        _status = out != null
            ? 'Done (${result['sampleRateHz']} Hz WAV, same pipeline as in-call)'
            : 'Done';
      });
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _shareOutput() async {
    final path = _outputPath;
    if (path == null || !File(path).existsSync()) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: '${widget.type.displayName} denoised WAV',
      ),
    );
  }

  Future<void> _copyToDownloads() async {
    final path = _outputPath;
    if (path == null) {
      return;
    }
    final src = File(path);
    if (!src.existsSync()) {
      return;
    }
    final downloads = Directory('/storage/emulated/0/Download');
    if (!downloads.existsSync()) {
      setState(() => _status = 'Downloads folder not found');
      return;
    }
    final dest = File('${downloads.path}/${src.uri.pathSegments.last}');
    await src.copy(dest.path);
    setState(() => _status = 'Copied to ${dest.path}');
  }

  @override
  Widget build(BuildContext context) {
    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: context.isLandscape,
      modalOnBackdropTap: () => Navigator.of(context).pop(),
      modalMaxHeight: context.height * 0.85,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(_title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SettingsSectionHeader(title: 'Input'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Push test audio from your Mac:\n'
                  'adb push ~/Downloads/lawnmower.mp3 '
                  '/sdcard/Download/lawnmower.mp3',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.textWeak,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'Audio file on device',
                    hintText: '/storage/emulated/0/Download/lawnmower.mp3',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              if (!_nativeReady)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _notReadyHint,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const SizedBox(height: 12),
              SettingsActionItem(
                title: _busy ? 'Running…' : 'Run denoise',
                onTap: _busy || !_nativeReady ? () {} : _runDenoise,
                isFirst: true,
              ),
              const SizedBox(height: 1),
              SettingsActionItem(
                title: 'Share denoised WAV',
                onTap: _outputPath == null
                    ? () {}
                    : () => unawaited(_shareOutput()),
              ),
              const SizedBox(height: 1),
              SettingsActionItem(
                title: 'Copy to Downloads',
                onTap: _outputPath == null
                    ? () {}
                    : () => unawaited(_copyToDownloads()),
                isLast: true,
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_status!),
                ),
              if (_outputPath != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SelectableText('Output:\n$_outputPath'),
                ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }
}
