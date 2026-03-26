import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/dashboard/dashboard_page.dart';

class _MeetingLockedDialogConstants {
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
  static const double borderColorAlpha = 0.03;
}

Future<void> showMeetingLockedBottomSheet(
  BuildContext context, {
  String? meetingLink,
}) {
  // Navigate back to dashboard first
  Navigator.of(context).popUntil(
    (route) => route.settings.name == DashboardPage.routeName || route.isFirst,
  );

  // Wait for navigation to complete, then show bottom sheet
  return Future.delayed(Duration.zero, () {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        final mediaQuery = MediaQuery.of(context);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.35),
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height - 100),
          routeSettings: const RouteSettings(name: 'meeting_locked'),
          builder: (_) => MeetingLockedModal(meetingLink: meetingLink),
        );
      }
    });
  });
}

class MeetingLockedModal extends StatefulWidget {
  const MeetingLockedModal({this.meetingLink, super.key});

  final String? meetingLink;

  @override
  State<MeetingLockedModal> createState() => _MeetingLockedModalState();
}

class _MeetingLockedModalState extends State<MeetingLockedModal> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(
        _MeetingLockedDialogConstants.borderRadiusMedium,
      ),
      topRight: Radius.circular(
        _MeetingLockedDialogConstants.borderRadiusMedium,
      ),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _MeetingLockedDialogConstants.borderColorAlpha,
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
        topLeft: Radius.circular(
          _MeetingLockedDialogConstants.borderRadiusLarge,
        ),
        topRight: Radius.circular(
          _MeetingLockedDialogConstants.borderRadiusLarge,
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
                            _MeetingLockedDialogConstants.borderRadiusMedium,
                          ),
                          topRight: Radius.circular(
                            _MeetingLockedDialogConstants.borderRadiusMedium,
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
                  const SizedBox(height: 40),

                  // Error iconCenter(
                  context.images.iconLocked.svg(width: 57, height: 69),

                  // Text content
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        Text(
                          context.local.meeting_locked,
                          textAlign: TextAlign.center,
                          style: ProtonStyles.headline(
                            color: context.colors.textNorm,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.local.meeting_locked_description,
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
                  // Close button
                  RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.drawerBackground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(200),
                            ),
                          ),
                          child: Text(
                            context.local.close,
                            style: ProtonStyles.body1Semibold(
                              color: context.colors.protonBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Avoid overflow by navigator bar on some android devices
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
