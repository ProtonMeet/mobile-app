import 'package:proton_denoise/denoise_type.dart';

/// Metadata for a denoise algorithm shown in settings UI.
class DenoiseTypeInfo {
  const DenoiseTypeInfo({required this.type, required this.isReady});

  final DenoiseType type;
  final bool isReady;
}

/// Per-backend native probe for debug settings.
class DenoiseDiagnosticEntry {
  const DenoiseDiagnosticEntry({
    required this.type,
    required this.displayName,
    required this.isReady,
    required this.details,
  });

  final DenoiseType type;
  final String displayName;
  final bool isReady;
  final Map<String, dynamic> details;
}

/// Result of [ProtonDenoiseEffects.diagnoseDenoiseWithStatus].
class DenoiseDiagnosticsResult {
  const DenoiseDiagnosticsResult({
    required this.entries,
    this.note,
    this.usedFallback = false,
  });

  final List<DenoiseDiagnosticEntry> entries;
  final String? note;
  final bool usedFallback;
}

/// Result of [ProtonDenoiseEffects.warmUpDenoise] (production-style init probe).
class DenoiseWarmUpResult {
  const DenoiseWarmUpResult({
    required this.type,
    required this.warmUpOk,
    required this.warmUpMs,
    required this.details,
  });

  final DenoiseType type;
  final bool warmUpOk;
  final int warmUpMs;
  final Map<String, dynamic> details;
}
