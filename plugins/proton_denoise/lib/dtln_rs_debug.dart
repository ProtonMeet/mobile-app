import 'package:proton_denoise/denoise_type.dart';
import 'package:proton_denoise/offline_denoise_debug.dart';

/// @deprecated Use [OfflineDenoiseDebugChannel] with [DenoiseType.dtlnRs].
class DtlnRsDebugChannel {
  DtlnRsDebugChannel._();

  static Future<bool> isNativeReady() =>
      OfflineDenoiseDebugChannel.isTypeReady(DenoiseType.dtlnRs);

  static Future<Map<String, dynamic>> denoiseFile(String inputPath) =>
      OfflineDenoiseDebugChannel.denoiseFile(
        inputPath: inputPath,
        type: DenoiseType.dtlnRs,
      );
}
