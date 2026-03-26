import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

class _EarlyAccessDialogConstants {
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
  static const double borderColorAlpha = 0.03;
}

class EarlyAccessDialog extends StatefulWidget {
  const EarlyAccessDialog({
    required this.onLogin,
    required this.isLoggedIn,
    super.key,
  });

  final VoidCallback? onLogin;
  final bool isLoggedIn;

  @override
  State<EarlyAccessDialog> createState() => _EarlyAccessDialogState();
}

class _EarlyAccessDialogState extends State<EarlyAccessDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(_EarlyAccessDialogConstants.borderRadiusMedium),
      topRight: Radius.circular(_EarlyAccessDialogConstants.borderRadiusMedium),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _EarlyAccessDialogConstants.borderColorAlpha,
        ),
      ),
      borderRadius: borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape && mobile;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(_EarlyAccessDialogConstants.borderRadiusLarge),
        topRight: Radius.circular(
          _EarlyAccessDialogConstants.borderRadiusLarge,
        ),
      ),
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            decoration: _buildContainerDecoration(context),
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: _buildScrollableContent(context, isLandscape),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent(BuildContext context, bool isLandscape) {
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight: !isLandscape ? 36.0 : 8.0,
              expandedHeight: !isLandscape ? 36.0 : 8.0,
              flexibleSpace: SizedBox.expand(
                child: ClipRRect(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Colors.transparent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(
                            _EarlyAccessDialogConstants.borderRadiusMedium,
                          ),
                          topRight: Radius.circular(
                            _EarlyAccessDialogConstants.borderRadiusMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 24),

                  /// icon
                  Center(
                    child: context.images.iconEarlyAccess.svg(
                      width: 70,
                      height: 70,
                      fit: BoxFit.fitWidth,
                    ),
                  ),

                  /// text content
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        Text(
                          widget.isLoggedIn
                              ? context.local.early_access_title_for_login_user
                              : context.local.early_access_title,
                          textAlign: TextAlign.center,
                          style: ProtonStyles.headline(
                            color: context.colors.textNorm,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.local.early_access_description,
                          textAlign: TextAlign.center,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.textWeak,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  /// login button, only show if onLogin is not null
                  if (widget.onLogin != null)
                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onLogin?.call();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.protonBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(200),
                              ),
                            ),
                            child: Text(
                              context.local.sign_in,
                              style: ProtonStyles.body1Semibold(
                                color: context.colors.textInverted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),

                  /// cancel button
                  RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.drawerBackground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(200),
                            ),
                          ),
                          child: Text(
                            context.local.go_back_to_dashboard,
                            style: ProtonStyles.body1Semibold(
                              color: context.colors.protonBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // try avoid overflow by navigator bar on some android devices
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: !isLandscape ? 36.0 : 8.0,
          child: AbsorbPointer(
            child: Stack(
              children: [
                if (!isLandscape)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 36.0,
                    child: BottomSheetHandleBar(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showUserLoginCheckBottomSheet(
  BuildContext context, {
  VoidCallback? onLogin,
  bool isLoggedIn = false,
}) {
  final mediaQuery = MediaQuery.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    constraints: BoxConstraints(maxHeight: mediaQuery.size.height - 100),
    builder: (_) => EarlyAccessDialog(onLogin: onLogin, isLoggedIn: isLoggedIn),
  );
}
