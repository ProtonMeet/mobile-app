import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

import 'dashboard_action_button.dart';
import 'dashboard_state.dart';

/// Responsive action buttons layout
/// - Small screens (< medium): Vertical stack (Column)
/// - Medium+ screens: Horizontal row (Row)
class DashboardActionButtons extends StatelessWidget {
  const DashboardActionButtons({
    required this.currentState,
    required this.authBloc,
    required this.onJoinMeeting,
    required this.onPersonalMeeting,
    required this.onSecureMeeting,
    super.key,
  });

  final DashboardState currentState;
  final AuthBloc authBloc;
  final VoidCallback onJoinMeeting;
  final VoidCallback onPersonalMeeting;
  final VoidCallback onSecureMeeting;

  @override
  Widget build(BuildContext context) {
    // Use ResponsiveV2 to determine layout
    final isSmallScreen =
        context.isSmall || context.isXSmall || context.isXXSmall;

    if (isSmallScreen) {
      // Mobile layout: Vertical stack
      return Column(
        children: [
          DashboardActionButton(
            title: context.local.join_a_meeting,
            icon: context.images.iconLink.svg(
              fit: BoxFit.fill,
              width: 18,
              height: 18,
            ),
            iconBackgroundColor: context.colors.interActionNormMinor3,
            backgroundColor: context.colors.backgroundCard,
            highlightColor: context.colors.backgroundNorm,
            onPressed: onJoinMeeting,
          ),
          const SizedBox(height: 4),
          DashboardActionButton(
            isLoading: currentState.isLoadingPersonalMeeting,
            title: context.local.personal_meeting_link,
            icon: context.images.iconUser.svg(
              fit: BoxFit.fill,
              width: 20,
              height: 20,
            ),
            iconBackgroundColor: context.colors.interActionNormMinor3,
            backgroundColor: context.colors.backgroundCard,
            highlightColor: context.colors.backgroundNorm,
            onPressed: onPersonalMeeting,
          ),
          const SizedBox(height: 4),
          DashboardActionButton(
            isLoading: currentState.isLoadingScheduledMeetings,
            title: context.local.start_secure_meeting,
            icon: context.images.iconPhone.svg(
              fit: BoxFit.fill,
              width: 20,
              height: 20,
            ),
            iconBackgroundColor: context.colors.interActionNormMinor3,
            backgroundColor: context.colors.backgroundCard,
            highlightColor: context.colors.backgroundNorm,
            onPressed: onSecureMeeting,
          ),
        ],
      );
    } else {
      // Desktop/Tablet layout: Horizontal row
      return Row(
        children: [
          Expanded(
            child: DashboardActionButton(
              title: context.local.join_a_meeting,
              icon: context.images.iconLink.svg(
                fit: BoxFit.fill,
                width: 18,
                height: 18,
              ),
              iconBackgroundColor: context.colors.interActionNormMinor3,
              backgroundColor: context.colors.backgroundCard,
              highlightColor: context.colors.backgroundNorm,
              onPressed: onJoinMeeting,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DashboardActionButton(
              isLoading: currentState.isLoadingPersonalMeeting,
              title: context.local.personal_meeting_link,
              icon: context.images.iconUser.svg(
                fit: BoxFit.fill,
                width: 20,
                height: 20,
              ),
              iconBackgroundColor: context.colors.interActionNormMinor3,
              backgroundColor: context.colors.backgroundCard,
              highlightColor: context.colors.backgroundNorm,
              onPressed: onPersonalMeeting,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DashboardActionButton(
              isLoading: currentState.isLoadingScheduledMeetings,
              title: context.local.start_secure_meeting,
              icon: context.images.iconPhone.svg(
                fit: BoxFit.fill,
                width: 20,
                height: 20,
              ),
              iconBackgroundColor: context.colors.interActionNormMinor3,
              backgroundColor: context.colors.backgroundCard,
              highlightColor: context.colors.backgroundNorm,
              onPressed: onSecureMeeting,
            ),
          ),
        ],
      );
    }
  }
}
