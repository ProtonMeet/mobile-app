import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/scenes/settings/settings_section_header.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Debug sheet: Unleash denoise flags + per-backend native load probes.
class DenoiseDiagnosticsDebugSheet {
  DenoiseDiagnosticsDebugSheet._();

  static Future<void> show(BuildContext context) async {
    if (!kDebugMode || !ProtonDenoiseEffects.isSupported) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _DenoiseDiagnosticsDebugBody(),
    );
  }
}

class _LinkedLib {
  const _LinkedLib({required this.label, required this.type});

  final String label;
  final DenoiseType type;
}

class _DenoiseFlagRow {
  const _DenoiseFlagRow({
    required this.feature,
    required this.label,
    this.linkedLibs = const [],
    this.parentNote,
  });

  final UnleashFeature feature;
  final String label;
  final List<_LinkedLib> linkedLibs;
  final String? parentNote;
}

const _denoiseFlagRows = <_DenoiseFlagRow>[
  _DenoiseFlagRow(
    feature: UnleashFeature.meetAudioDenoise,
    label: 'MeetAudioDenoise',
    parentNote: 'Parent — gates all denoise UI and attach',
  ),
  _DenoiseFlagRow(
    feature: UnleashFeature.meetAudioDenoiseRnnoise,
    label: 'MeetAudioDenoiseRnnoise',
    linkedLibs: [_LinkedLib(label: 'RNNoise', type: DenoiseType.rnnoise)],
  ),
  _DenoiseFlagRow(
    feature: UnleashFeature.meetAudioDenoiseDeepfilter,
    label: 'MeetAudioDenoiseDeepfilter',
    linkedLibs: [
      _LinkedLib(label: 'DeepFilter 3', type: DenoiseType.deepfilter),
      _LinkedLib(label: 'DeepFilter 2', type: DenoiseType.deepfilter2),
    ],
  ),
  _DenoiseFlagRow(
    feature: UnleashFeature.meetAudioDenoiseDtlnRs,
    label: 'MeetAudioDenoiseDtlnRs',
    linkedLibs: [_LinkedLib(label: 'DTLN', type: DenoiseType.dtlnRs)],
  ),
];

class _DenoiseDiagnosticsDebugBody extends StatefulWidget {
  const _DenoiseDiagnosticsDebugBody();

  @override
  State<_DenoiseDiagnosticsDebugBody> createState() =>
      _DenoiseDiagnosticsDebugBodyState();
}

class _DenoiseDiagnosticsDebugBodyState
    extends State<_DenoiseDiagnosticsDebugBody> {
  bool _loading = true;
  bool _warmingUp = false;
  String? _error;
  String? _diagnosticsNote;
  String? _warmUpNote;
  bool _usedFallback = false;
  List<DenoiseDiagnosticEntry> _entries = const [];
  final Map<DenoiseType, DenoiseWarmUpResult> _warmUpByType = {};
  late UnleashDataProvider _unleash;

  @override
  void initState() {
    super.initState();
    _unleash = ManagerFactory().get<DataProviderManager>().unleashDataProvider;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ProtonDenoiseEffects.instance
          .diagnoseDenoiseWithStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = result.entries;
        _diagnosticsNote = result.note;
        _usedFallback = result.usedFallback;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  DenoiseDiagnosticEntry? _entryFor(DenoiseType type) {
    for (final entry in _entries) {
      if (entry.type == type) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _warmUpAll() async {
    setState(() {
      _warmingUp = true;
      _warmUpNote = null;
    });
    try {
      final results = await ProtonDenoiseEffects.instance.warmUpDenoise();
      if (!mounted) {
        return;
      }
      setState(() {
        _warmUpByType
          ..clear()
          ..addEntries(results.map((r) => MapEntry(r.type, r)));
        _warmingUp = false;
        if (results.isEmpty) {
          _warmUpNote =
              'warmUpDenoise returned nothing — rebuild native app after plugin update';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _warmUpNote = 'Warm-up failed: $e';
        _warmingUp = false;
      });
    }
  }

  Color _warmUpColor(DenoiseType type) {
    final warmUp = _warmUpByType[type];
    if (warmUp == null) {
      return Colors.grey;
    }
    return warmUp.warmUpOk ? Colors.green : Colors.red;
  }

  String _warmUpLabel(DenoiseType type) {
    final warmUp = _warmUpByType[type];
    if (warmUp == null) {
      return 'Warm-up: not run';
    }
    if (warmUp.warmUpOk) {
      return 'Warm-up: ok (${warmUp.warmUpMs} ms)';
    }
    final error = warmUp.details['error']?.toString();
    if (error != null && error.isNotEmpty) {
      return 'Warm-up: failed — $error';
    }
    return 'Warm-up: failed';
  }

  List<String> _warmUpDetailLines(DenoiseType type) {
    final warmUp = _warmUpByType[type];
    if (warmUp == null) {
      return const [];
    }
    final lines = <String>[];
    for (final entry in warmUp.details.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.isEmpty) {
        continue;
      }
      lines.add('${entry.key}: $value');
    }
    return lines;
  }

  bool _effectiveFlag(UnleashFeature feature) => switch (feature) {
    UnleashFeature.meetAudioDenoise => _unleash.isMeetAudioDenoise(),
    UnleashFeature.meetAudioDenoiseRnnoise =>
      _unleash.isMeetAudioDenoiseRnnoise(),
    UnleashFeature.meetAudioDenoiseDeepfilter =>
      _unleash.isMeetAudioDenoiseDeepfilter(),
    UnleashFeature.meetAudioDenoiseDtlnRs =>
      _unleash.isMeetAudioDenoiseDtlnRs(),
    _ => _unleash.isFeatureEnabled(feature),
  };

  bool _parentEffectiveOn() => _unleash.isMeetAudioDenoise();

  bool _visibleInRoomSettings(DenoiseType type) {
    final entry = _entryFor(type);
    if (entry == null || !entry.isReady || !_parentEffectiveOn()) {
      return false;
    }
    return switch (type) {
      DenoiseType.rnnoise => _unleash.isMeetAudioDenoiseRnnoise(),
      DenoiseType.deepfilter ||
      DenoiseType.deepfilter2 => _unleash.isMeetAudioDenoiseDeepfilter(),
      DenoiseType.dtlnRs => _unleash.isMeetAudioDenoiseDtlnRs(),
      DenoiseType.none => false,
    };
  }

  Color _onOffColor(bool on) => on ? Colors.green : Colors.red;

  Color _nativeColor(DenoiseDiagnosticEntry? entry) {
    if (entry == null) {
      return Colors.red;
    }
    if (entry.isReady) {
      return Colors.green;
    }
    final createProbe = entry.details['createProbe'] as bool? ?? false;
    return createProbe ? Colors.orange : Colors.red;
  }

  String _nativeLabel(DenoiseDiagnosticEntry? entry) {
    if (entry == null) {
      return 'not reported by native';
    }
    if (entry.isReady) {
      return 'isReady: true';
    }
    final createProbe = entry.details['createProbe'] as bool? ?? false;
    if (createProbe) {
      return 'isReady: false (createProbe ok)';
    }
    return 'isReady: false';
  }

  List<String> _detailLines(DenoiseDiagnosticEntry entry) {
    final lines = <String>[];
    for (final mapEntry in entry.details.entries) {
      final value = mapEntry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.isEmpty) {
        continue;
      }
      lines.add('${mapEntry.key}: $value');
    }
    return lines;
  }

  String _reportForType(DenoiseType type, {String? label}) {
    final entry = _entryFor(type);
    final title = label ?? entry?.displayName ?? type.displayName;
    final buffer = StringBuffer()
      ..writeln('Denoise diagnostics — $title')
      ..writeln('Platform: $_platformLabel');

    if (_diagnosticsNote != null) {
      buffer.writeln('Diagnostics note: $_diagnosticsNote');
    }
    if (_warmUpNote != null) {
      buffer.writeln('Warm-up note: $_warmUpNote');
    }

    buffer.writeln('MeetAudioDenoise: ${_parentEffectiveOn() ? 'on' : 'off'}');
    final unleashOn = switch (type) {
      DenoiseType.rnnoise => _unleash.isFeatureEnabled(
        UnleashFeature.meetAudioDenoiseRnnoise,
      ),
      DenoiseType.deepfilter || DenoiseType.deepfilter2 =>
        _unleash.isFeatureEnabled(UnleashFeature.meetAudioDenoiseDeepfilter),
      DenoiseType.dtlnRs => _unleash.isFeatureEnabled(
        UnleashFeature.meetAudioDenoiseDtlnRs,
      ),
      DenoiseType.none => false,
    };
    buffer.writeln('Unleash backend flag: ${unleashOn ? 'on' : 'off'}');
    buffer.writeln('Visible in room settings: ${_visibleInRoomSettings(type)}');

    if (entry == null) {
      buffer.writeln('Native: not reported');
    } else {
      buffer.writeln(_nativeLabel(entry));
      for (final line in _detailLines(entry)) {
        buffer.writeln(line);
      }
    }

    buffer.writeln(_warmUpLabel(type));
    for (final line in _warmUpDetailLines(type)) {
      buffer.writeln(line);
    }

    return buffer.toString().trim();
  }

  String _reportForEntry(DenoiseDiagnosticEntry entry) =>
      _reportForType(entry.type, label: entry.displayName);

  Future<void> _copyReport(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _copyDetailsButton(
    BuildContext context, {
    required String report,
    String tooltip = 'Copy details',
  }) {
    return IconButton(
      icon: const Icon(Icons.copy, size: 18),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => unawaited(_copyReport(context, report)),
    );
  }

  String get _platformLabel {
    if (Platform.isIOS) {
      return 'iOS';
    }
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isMacOS) {
      return 'macOS';
    }
    return Platform.operatingSystem;
  }

  Widget _statusDot(Color color) => Icon(Icons.circle, size: 10, color: color);

  Widget _flagSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Denoise feature flags'),
        ..._denoiseFlagRows.map((row) => _buildFlagRow(context, row)),
      ],
    );
  }

  Widget _buildFlagRow(BuildContext context, _DenoiseFlagRow row) {
    final unleashOn = _unleash.isFeatureEnabled(row.feature);
    final effectiveOn = _effectiveFlag(row.feature);
    final overridden = unleashOn != effectiveOn;
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    final monoSmall = bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusDot(_onOffColor(effectiveOn)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                effectiveOn ? 'ON' : 'OFF',
                style: bodySmall?.copyWith(
                  color: _onOffColor(effectiveOn),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unleash: ${unleashOn ? 'on' : 'off'}'
                  '${overridden ? ' · effective override' : ''}',
                  style: monoSmall,
                ),
                if (row.parentNote != null)
                  Text(row.parentNote!, style: bodySmall),
                if (row.feature == UnleashFeature.meetAudioDenoise)
                  Text(
                    'Platform supported: ${ProtonDenoiseEffects.isSupported}',
                    style: monoSmall,
                  ),
                ...row.linkedLibs.map((lib) {
                  final entry = _entryFor(lib.type);
                  final nativeColor = _nativeColor(entry);
                  final inUi = _visibleInRoomSettings(lib.type);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _statusDot(nativeColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                lib.label,
                                style: bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (inUi)
                              const Icon(
                                Icons.check_circle,
                                size: 16,
                                color: Colors.green,
                              ),
                            _copyDetailsButton(
                              context,
                              report: _reportForType(
                                lib.type,
                                label: lib.label,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(_nativeLabel(entry), style: monoSmall),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 2),
                          child: Row(
                            children: [
                              _statusDot(_warmUpColor(lib.type)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _warmUpLabel(lib.type),
                                  style: monoSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            inUi
                                ? 'Visible in room settings'
                                : 'Hidden in room settings',
                            style: bodySmall?.copyWith(
                              color: inUi ? Colors.green : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nativeProbeSection(BuildContext context) {
    if (_entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No native denoise backends reported.'),
      );
    }

    final monoSmall = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(title: 'Native probe details'),
        ..._entries.map((entry) {
          final color = _nativeColor(entry);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _statusDot(color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.displayName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    _copyDetailsButton(context, report: _reportForEntry(entry)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_warmUpLabel(entry.type), style: monoSmall),
                ..._warmUpDetailLines(
                  entry.type,
                ).map((line) => Text(line, style: monoSmall)),
                const SizedBox(height: 4),
                ..._detailLines(
                  entry,
                ).map((line) => Text(line, style: monoSmall)),
              ],
            ),
          );
        }),
      ],
    );
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Denoise library diagnostics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Platform: $_platformLabel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.textWeak,
                  ),
                ),
                if (_diagnosticsNote != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _usedFallback
                        ? 'Using listDenoiseTypes fallback: $_diagnosticsNote'
                        : _diagnosticsNote!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _usedFallback ? Colors.orange : Colors.red,
                    ),
                  ),
                ],
                if (_warmUpNote != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _warmUpNote!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: (_loading || _warmingUp)
                          ? null
                          : () => unawaited(_warmUpAll()),
                      icon: _warmingUp
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Warm up all'),
                    ),
                    TextButton.icon(
                      onPressed: (_loading || _warmingUp)
                          ? null
                          : () => unawaited(_load()),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_loading && !_warmingUp)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          )
        else ...[
          if (_warmingUp)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(),
              ),
            ),
          SliverToBoxAdapter(child: _flagSection(context)),
          SliverToBoxAdapter(child: _nativeProbeSection(context)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
