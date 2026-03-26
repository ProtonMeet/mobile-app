import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/dashboard/join/link_text_field.dart';
import 'package:meet/views/scenes/dashboard/schedule/add_to_calendar_sheet.dart';
import 'package:meet/views/scenes/dashboard/upcoming/meet_upcoming_title.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

class ActionButtons extends StatelessWidget {
  const ActionButtons({
    required this.status,
    required this.isRegenerating,
    required this.showCalendarButton,
    required this.onSubmit,
    required this.onCopy,
    this.onRegenerateLink,
    this.onDone,
    this.onAdd,
    this.onShare,
    this.onOpenOutlook,
    this.onOpenGoogle,
    this.onOpenProton,
    this.showProtonCalendar = false,
    this.showOutlookCalendar = false,
    this.isPersonalMeeting = false,
    this.tab,
    this.displayColors,
    super.key,
  });

  final LinkStatus status;
  final bool isRegenerating;
  final bool showCalendarButton;
  final VoidCallback onSubmit;
  final VoidCallback onCopy;
  final VoidCallback? onRegenerateLink;
  final VoidCallback? onDone;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;
  final VoidCallback? onOpenOutlook;
  final VoidCallback? onOpenGoogle;
  final VoidCallback? onOpenProton;
  final bool showProtonCalendar;
  final bool showOutlookCalendar;
  final bool isPersonalMeeting;
  final MeetUpcomingTab? tab;
  final ParticipantDisplayColors? displayColors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        /// Add to calendar button (if callbacks provided)
        ///  top button
        if (showCalendarButton) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: InkWell(
                onTap: () {
                  showAddToCalendarSheet(
                    context,
                    onAdd: onAdd ?? () {},
                    onShare: onShare ?? () {},
                    onOpenOutlook: onOpenOutlook ?? () {},
                    onOpenGoogle: onOpenGoogle ?? () {},
                    onOpenProton: onOpenProton ?? () {},
                    showOutlookCalendar: showOutlookCalendar,
                    showProtonCalendar: showProtonCalendar,
                  );
                },
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.interActionWeak,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text(
                    context.local.add_to_calendar,
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],

        /// Join button (enabled only when valid) - hide if showing scheduled meeting summary
        ///  top excepted if showCalendarButton
        if (onDone == null)
          Padding(
            padding: EdgeInsets.fromLTRB(24, showCalendarButton ? 8 : 0, 24, 0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: status == LinkStatus.valid ? onSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: status == LinkStatus.valid
                          ? displayColors?.actionBackgroundColor ??
                                context.colors.protonBlue
                          : context.colors.interActionWeekMinor1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(200),
                      ),
                    ),
                    child: Text(
                      context.local.join_meeting_button,
                      style: ProtonStyles.body1Semibold(
                        color: status == LinkStatus.valid
                            ? context.colors.textInverted
                            : context.colors.textDisable,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        /// Regenerate link button for personal meetings (separate from join/done buttons)
        ///  next to join button
        if (isPersonalMeeting && onRegenerateLink != null) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: SizedBox(
              width: double.infinity,
              child: InkWell(
                onTap: isRegenerating ? null : onRegenerateLink,
                borderRadius: BorderRadius.circular(200),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: ShapeDecoration(
                    color: isRegenerating
                        ? context.colors.interActionWeekMinor1
                        : context.colors.interActionWeak,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(200),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isRegenerating) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              context.colors.textDisable,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        isRegenerating
                            ? context.local.regenerating
                            : context.local.regenerate_link,
                        textAlign: TextAlign.center,
                        style: ProtonStyles.body1Semibold(
                          color: isRegenerating
                              ? context.colors.textDisable
                              : context.colors.textNorm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],

        /// Done button (if callback provided)
        ///  bottom button
        if (onDone != null) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              showCalendarButton ? 8 : 24,
              24,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.interActionPurpleMinor1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
                child: Text(
                  context.local.scheduled_meeting_done,
                  style: ProtonStyles.body1Semibold(
                    color: context.colors.textInverted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
