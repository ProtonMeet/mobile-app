import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:permission_handler/permission_handler.dart';

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

  final padding =
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom) +
      const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  await showDialog<void>(
    context: context,
    builder: (_) {
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
                  color: context.colors.interActionWeakMinor3,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: context.colors.appBorderNorm),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title row with close
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.isEmpty ? computedTitle : title,
                                style: ProtonStyles.headline(
                                  color: context.colors.textNorm,
                                ),
                              ),
                            ),
                            InkResponse(
                              onTap: () => Navigator.of(context).maybePop(),
                              radius: 24,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: context.colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: context.colors.white.withValues(
                                    alpha: 0.60,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Message
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            buildMessage(),
                            style: ProtonStyles.body2Medium(
                              color: context.colors.textWeak,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Actions
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: context.colors.appBorderNorm,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(
                                  context.local.cancel,
                                  style: ProtonStyles.body1Semibold(
                                    color: context.colors.textNorm,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  await openAppSettings();
                                  if (context.mounted) {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    }
                                  }
                                  onReturned?.call();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      context.colors.interActionWeak,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(
                                  context.local.open_settings,
                                  style: ProtonStyles.body1Semibold(
                                    color: context.colors.textNorm,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
