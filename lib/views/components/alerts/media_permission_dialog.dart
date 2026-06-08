import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:permission_handler/permission_handler.dart';

/// Inform sheet when notification permission is required for screen sharing
/// (same layout as [showMediaPermissionSettingsDialog]).
Future<void> showNotificationPermissionSettingsDialog(
  BuildContext context, {
  VoidCallback? onReturned,
}) async {
  await _showPermissionInformSheet(
    context,
    title: context.local.notification_permission_settings_title,
    message: context.local.notification_permission_settings_message,
    showOpenSettings: false,
    onReturned: onReturned,
  );
}

/// Show a dialog that explains camera/microphone were denied previously
/// and offers to open the system Settings page.
/// - Pass which permissions are currently denied/permanentlyDenied so the
///   dialog can tailor the copy.
/// - onReturned runs after the dialog closes (e.g., re-check permissions).
Future<void> showMediaPermissionSettingsDialog(
  BuildContext context, {
  required bool cameraDenied,
  required bool microphoneDenied,
  VoidCallback? onReturned,
  String title = '',
}) async {
  final needsCamera = cameraDenied;
  final needsMic = microphoneDenied;

  // Tailored title
  final String computedTitle = (needsCamera && needsMic)
      ? 'Enable camera & microphone'
      : needsCamera
      ? 'Enable camera access'
      : 'Enable microphone access';

  // Tailored explanation
  String buildMessage() {
    final b = StringBuffer(
      'You previously denied access, so ${needsCamera && needsMic ? 'both features are' : 'this feature is'} blocked.',
    );
    b.write('\n\nTo join a secure call, please enable ');
    if (needsCamera && needsMic) {
      b.write('Camera and Microphone');
    } else if (needsCamera) {
      b.write('Camera');
    } else {
      b.write('Microphone');
    }
    b.write(' in your system settings:\n');
    b.write('• Open Settings\n');
    b.write('• Find this app\n');
    if (needsCamera) b.write('• Allow Camera\n');
    if (needsMic) b.write('• Allow Microphone\n');
    return b.toString();
  }

  await _showPermissionInformSheet(
    context,
    title: title.isEmpty ? computedTitle : title,
    message: buildMessage(),
    onReturned: onReturned,
  );
}

Future<void> _showPermissionInformSheet(
  BuildContext context, {
  required String title,
  required String message,
  bool showOpenSettings = true,
  VoidCallback? onReturned,
}) async {
  void dismiss() {
    Navigator.of(context).maybePop();
    onReturned?.call();
  }

  final padding =
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom) +
      const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Center(
        child: AnimatedPadding(
          padding: padding,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxMobileSheetWidth),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: dialogContext.colors.interActionWeakMinor3,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: dialogContext.colors.appBorderNorm),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: ProtonStyles.headline(
                                  color: dialogContext.colors.textNorm,
                                ),
                              ),
                            ),
                            InkResponse(
                              onTap: () =>
                                  Navigator.of(dialogContext).maybePop(),
                              radius: 24,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: dialogContext.colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: dialogContext.colors.white.withValues(
                                    alpha: 0.60,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            message,
                            style: ProtonStyles.body2Medium(
                              color: dialogContext.colors.textWeak,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (showOpenSettings)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).maybePop(),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color:
                                          dialogContext.colors.appBorderNorm,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(200),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: Text(
                                    dialogContext.local.cancel,
                                    style: ProtonStyles.body1Semibold(
                                      color: dialogContext.colors.textNorm,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    await openAppSettings();
                                    if (dialogContext.mounted) {
                                      if (Navigator.of(dialogContext)
                                          .canPop()) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    }
                                    onReturned?.call();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        dialogContext.colors.interActionWeak,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(200),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: Text(
                                    dialogContext.local.open_settings,
                                    style: ProtonStyles.body1Semibold(
                                      color: dialogContext.colors.textNorm,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: dismiss,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: dialogContext.colors.appBorderNorm,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(200),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: Text(
                                dialogContext.local.cancel,
                                style: ProtonStyles.body1Semibold(
                                  color: dialogContext.colors.textNorm,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
