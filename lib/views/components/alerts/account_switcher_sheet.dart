import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/version_text.dart';

Future<void> showAccountSwitcherBottomSheet(
  BuildContext context, {
  required String displayName,
  required String email,
  required String initials,
  required String versionDisplay,
  required VoidCallback onLogout,
  VoidCallback? onSwitchAccount,
  VoidCallback? onAddAccount,
  VoidCallback? onDeleteAccount,
  bool switchEnabled = false,
  bool addEnabled = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.1),
    builder: (_) => BaseBottomSheet(
      blurSigma: 12,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(40),
        topRight: Radius.circular(40),
      ),
      contentPadding: const EdgeInsets.only(bottom: 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomSheetHandleBar(),
            const SizedBox(height: 55),
            AccountSwitcherView(
              displayName: displayName,
              email: email,
              initials: initials,
              onLogout: onLogout,
              onSwitchAccount: onSwitchAccount,
              onAddAccount: onAddAccount,
              onDeleteAccount: onDeleteAccount,
              switchEnabled: switchEnabled,
              addEnabled: addEnabled,
              versionDisplay: versionDisplay,
            ),
          ],
        ),
      ),
    ),
  );
}

class AccountSwitcherView extends StatelessWidget {
  const AccountSwitcherView({
    required this.displayName,
    required this.email,
    required this.initials,
    required this.onLogout,
    required this.versionDisplay,
    super.key,
    this.onSwitchAccount,
    this.onAddAccount,
    this.onDeleteAccount,
    this.switchEnabled = false,
    this.addEnabled = false,
    this.width = 351,
  });

  final String displayName;
  final String email;
  final String initials;
  final String versionDisplay;

  final VoidCallback onLogout;
  final VoidCallback? onSwitchAccount;
  final VoidCallback? onAddAccount;
  final VoidCallback? onDeleteAccount;

  final bool switchEnabled;
  final bool addEnabled;

  final double width;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        /// Profile
        _Profile(initials: initials, displayName: displayName, email: email),
        const SizedBox(height: 38),

        /// Options section
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Grouped action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Manage accounts button (custom)
                  GestureDetector(
                    onTap: switchEnabled ? onSwitchAccount : null,
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      padding: const EdgeInsets.only(
                        top: 20,
                        left: 24,
                        right: 12,
                        bottom: 20,
                      ),
                      decoration: ShapeDecoration(
                        color: context.colors.backgroundCard,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: context.colors.borderCard),
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          context.images.iconSettings.svg20(
                            color: context.colors.textNorm,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              context.local.manage_accounts,
                              style: ProtonStyles.body1Medium(
                                color: context.colors.textNorm,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (onDeleteAccount != null)
                            _PopupMenuButton(onDeleteAccount: onDeleteAccount)
                          else
                            const SizedBox(width: 20, height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),

        /// Sign out button
        _SignOut(onLogout: onLogout),

        /// version
        VersionText(versionDisplay: versionDisplay),
      ],
    );
  }
}

class _SignOut extends StatelessWidget {
  const _SignOut({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 60,
        child: Material(
          color: context.colors.interActionWeak,
          borderRadius: BorderRadius.circular(200),
          child: InkWell(
            borderRadius: BorderRadius.circular(200),
            onTap: () {
              Navigator.of(context).pop();
              onLogout();
            },
            child: Center(
              child: Text(
                context.local.sign_out,
                textAlign: TextAlign.center,
                style: ProtonStyles.body1Medium(color: context.colors.textNorm),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({
    required this.initials,
    required this.displayName,
    required this.email,
  });

  final String initials;
  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar initials
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.colors.interActionPurpleMinor1,
            borderRadius: BorderRadius.circular(20002),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: ProtonStyles.body2Medium(
              color: context.colors.textInverted,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: ProtonStyles.subheadline(
            color: context.colors.textNorm,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          email,
          textAlign: TextAlign.center,
          style: ProtonStyles.body2Regular(
            color: context.colors.textWeak,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _PopupMenuButton extends StatelessWidget {
  const _PopupMenuButton({required this.onDeleteAccount});

  final VoidCallback? onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      position: PopupMenuPosition.over,
      offset: const Offset(0, -60),
      icon: context.images.iconMore.svg20(color: context.colors.textDisable),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      elevation: 0,
      color: Colors.transparent,
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 32,
                  bottom: 24,
                ),
                decoration: ShapeDecoration(
                  color: context.colors.backgroundPopupMenu,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    onDeleteAccount?.call();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        context.images.iconDelete.svg20(
                          color: context.colors.signalDanger,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          context.local.delete_account,
                          style: ProtonStyles.body1Semibold(
                            color: context.colors.signalDanger,
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
      ],
    );
  }
}
