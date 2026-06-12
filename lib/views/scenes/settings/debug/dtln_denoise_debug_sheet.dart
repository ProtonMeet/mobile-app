import 'package:flutter/material.dart';
import 'package:meet/views/scenes/settings/debug/offline_file_denoise_debug_sheet.dart';
import 'package:proton_denoise/denoise_type.dart';

/// @deprecated Use [OfflineFileDenoiseDebugSheet] with [DenoiseType.dtlnRs].
class DtlnDenoiseDebugSheet {
  DtlnDenoiseDebugSheet._();

  static Future<void> show(BuildContext context) =>
      OfflineFileDenoiseDebugSheet.show(context, type: DenoiseType.dtlnRs);
}
