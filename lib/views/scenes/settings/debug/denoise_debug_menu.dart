import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/settings/settings_action_item.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/scenes/settings/debug/denoise_diagnostics_debug_sheet.dart';
import 'package:meet/views/scenes/settings/debug/denoise_mic_preview_debug_screen.dart';
import 'package:meet/views/scenes/settings/debug/offline_file_denoise_debug_sheet.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Debug-only submenu for denoise diagnostics, file tests, and live mic preview.
final class DenoiseDebugMenu {
  DenoiseDebugMenu._();

  static void show(BuildContext context) {
    if (!kDebugMode || !ProtonDenoiseEffects.isSupported) {
      return;
    }
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: sheetContext.colors.backgroundSecondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Denoise (debug)',
                            style: TextStyle(
                              color: sheetContext.colors.textNorm,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: sheetContext.colors.textNorm,
                          ),
                          onPressed: () =>
                              Navigator.of(sheetContext).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        const SettingsSectionHeader(title: 'Live'),
                        SettingsActionItem(
                          title: 'Mic preview & compare',
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(
                              DenoiseMicPreviewDebugScreen.show(context),
                            );
                          },
                          isFirst: true,
                          isLast: true,
                        ),
                        const SettingsSectionHeader(title: 'Diagnostics'),
                        SettingsActionItem(
                          title: 'Library diagnostics',
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            DenoiseDiagnosticsDebugSheet.show(context);
                          },
                          isFirst: true,
                          isLast: true,
                        ),
                        if (android) ...[
                          const SettingsSectionHeader(title: 'Offline file'),
                          SettingsActionItem(
                            title: 'RNNoise file denoise',
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              OfflineFileDenoiseDebugSheet.show(
                                context,
                                type: DenoiseType.rnnoise,
                              );
                            },
                            isFirst: true,
                          ),
                          SettingsActionItem(
                            title: 'DTLN file denoise',
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              OfflineFileDenoiseDebugSheet.show(
                                context,
                                type: DenoiseType.dtlnRs,
                              );
                            },
                            isLast: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
