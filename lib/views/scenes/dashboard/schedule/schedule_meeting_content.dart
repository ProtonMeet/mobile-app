import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

import 'schedule_meeting_field_row.dart';
import 'schedule_meeting_handle.dart';
import 'schedule_meeting_header.dart';

class ScheduleMeetingContent extends StatelessWidget {
  const ScheduleMeetingContent({
    required this.titleController,
    required this.titleHint,
    required this.dateLabel,
    required this.startTimeLabel,
    required this.durationLabel,
    required this.timeZoneLabel,
    required this.recurrenceLabel,
    required this.isSaveEnabled,
    required this.onTapTitle,
    required this.onSelectDate,
    required this.onSelectStartTime,
    required this.onSelectDuration,
    required this.onSelectTimeZone,
    required this.onSelectRecurrence,
    required this.onSave,
    required this.onCancel,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.displayColors,
    this.timeValidationError,
    super.key,
  });

  final TextEditingController titleController;
  final String titleHint;
  final String dateLabel;
  final String startTimeLabel;
  final String durationLabel;
  final String timeZoneLabel;
  final String recurrenceLabel;
  final bool isSaveEnabled;
  final VoidCallback onTapTitle;
  final VoidCallback onSelectDate;
  final VoidCallback onSelectStartTime;
  final VoidCallback onSelectDuration;
  final VoidCallback onSelectTimeZone;
  final VoidCallback onSelectRecurrence;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final ParticipantDisplayColors? displayColors;
  final String? timeValidationError;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ScheduleHandle(onDragUpdate: onDragUpdate, onDragEnd: onDragEnd),
        const SizedBox(height: 47),
        ScheduleMeetingHeader(displayColors: displayColors),

        /// title field
        ScheduleMeetingFieldRow(
          topBorder: false,
          icon: context.images.iconScheduleText.svg20(),
          label: titleHint,
          onTap: onTapTitle,
          child: TextField(
            controller: titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: titleHint,
              hintStyle: ProtonStyles.body2Medium(
                color: context.colors.textHint,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: ProtonStyles.body2Medium(color: context.colors.textNorm),
          ),
        ),

        /// date field
        GestureDetector(
          onTap: onSelectDate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: ShapeDecoration(
              shape: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              ),
            ),
            child: Row(
              children: [
                context.images.iconScheduleToday.svg20(
                  color: timeValidationError != null
                      ? context.colors.notificationError
                      : context.colors.textDisable,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: onSelectDate,
                            child: Text(
                              dateLabel,
                              style: ProtonStyles.body2Medium(
                                color: context.colors.textNorm,
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: onSelectStartTime,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      context.local.schedule_at,
                                      style: ProtonStyles.body2Medium(
                                        color: context.colors.textNorm,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        startTimeLabel,
                                        style: ProtonStyles.body2Medium(
                                          color: context.colors.textNorm,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (timeValidationError != null) ...[
                        Text(
                          timeValidationError!,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.notificationError,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        /// duration field
        ScheduleMeetingFieldRow(
          topBorder: false,
          icon: context.images.iconScheduleTime.svg20(),
          label: durationLabel,
          onTap: onSelectDuration,
        ),

        /// time zone field
        ScheduleMeetingFieldRow(
          topBorder: false,
          icon: context.images.iconScheduleTimeZone.svg20(),
          label: timeZoneLabel,
          onTap: onSelectTimeZone,
        ),

        /// recurrence field
        ScheduleMeetingFieldRow(
          topBorder: false,
          icon: context.images.iconScheduleRepeat.svg20(),
          label: recurrenceLabel,
          onTap: onSelectRecurrence,
        ),
        const SizedBox(height: 8),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSaveEnabled ? onSave : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isSaveEnabled
                    ? displayColors?.actionBackgroundColor ??
                          context.colors.interActionNorm
                    : context.colors.backgroundDark,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(200),
                ),
              ),
              child: Text(
                context.local.save,
                style: ProtonStyles.body1Semibold(
                  color: isSaveEnabled
                      ? context.colors.textInverted
                      : context.colors.textDisable,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.white.withValues(alpha: 0.08),
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(200),
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
        ],
      ),
    );
  }
}
