import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/datetime.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:timezone/timezone.dart' as tz;

import 'duration_sheet.dart';
import 'recurrence_sheet.dart';
import 'schedule_meeting_content.dart';
import 'schedule_time_zone_sheet.dart';

enum RecurrenceFrequency {
  none('Does not repeat'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly'),
  yearly('Yearly');

  const RecurrenceFrequency(this.label);
  final String label;
}

class ScheduleMeetingData {
  final String title;
  final DateTime startDate;
  final TimeOfDay startTime;
  final int durationMinutes;
  final DateTime? endDate;
  final TimeOfDay? endTime;
  final String? timeZone;
  final RecurrenceFrequency recurrence;
  final bool showTimeZones;

  ScheduleMeetingData({
    required this.title,
    required this.startDate,
    required this.startTime,
    required this.durationMinutes,
    this.endDate,
    this.endTime,
    this.timeZone,
    this.recurrence = RecurrenceFrequency.none,
    this.showTimeZones = false,
  });
}

typedef OnScheduleMeeting = void Function(ScheduleMeetingData data);

Future<void> showScheduleMeetingDialog(
  BuildContext context, {
  required OnScheduleMeeting onSchedule,
  String? initialTitle,
  ScheduleMeetingData? initialData,
  ParticipantDisplayColors? displayColors,
}) {
  // Block dialog when in force upgrade state
  final appStateManager = ManagerFactory().get<AppStateManager>();
  final currentState = appStateManager.state;
  if (currentState is AppForceUpgradeState) {
    return Future.value();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) => ScheduleMeetingDialog(
      onSchedule: onSchedule,
      initialTitle: initialTitle,
      initialData: initialData,
      displayColors: displayColors,
    ),
  );
}

Future<void> showEditScheduleMeetingDialog(
  BuildContext context, {
  required OnScheduleMeeting onEdit,
  required ScheduleMeetingData initialData,
  ParticipantDisplayColors? displayColors,
}) {
  // Block dialog when in force upgrade state
  final appStateManager = ManagerFactory().get<AppStateManager>();
  final currentState = appStateManager.state;
  if (currentState is AppForceUpgradeState) {
    return Future.value();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) => ScheduleMeetingDialog(
      onSchedule: onEdit,
      initialTitle: initialData.title,
      initialData: initialData,
      displayColors: displayColors,
    ),
  );
}

class ScheduleMeetingDialog extends StatefulWidget {
  const ScheduleMeetingDialog({
    required this.onSchedule,
    super.key,
    this.initialTitle,
    this.initialData,
    this.displayColors,
  });

  final OnScheduleMeeting onSchedule;
  final String? initialTitle;
  final ScheduleMeetingData? initialData;
  final ParticipantDisplayColors? displayColors;

  @override
  State<ScheduleMeetingDialog> createState() => _ScheduleMeetingDialogState();
}

class ScheduleMeetingDialogMobile extends StatefulWidget {
  const ScheduleMeetingDialogMobile({
    required this.titleController,
    required this.titleHint,
    required this.dateLabel,
    required this.startTimeLabel,
    required this.durationLabel,
    required this.timeZoneLabel,
    required this.recurrenceLabel,
    required this.showTimeZones,
    required this.isSaveEnabled,
    required this.onTapTitle,
    required this.onSelectDate,
    required this.onSelectStartTime,
    required this.onSelectDuration,
    required this.onSelectTimeZone,
    required this.onSelectRecurrence,
    required this.onSave,
    required this.onCancel,
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
  final bool showTimeZones;
  final bool isSaveEnabled;
  final VoidCallback onTapTitle;
  final VoidCallback onSelectDate;
  final VoidCallback onSelectStartTime;
  final VoidCallback onSelectDuration;
  final VoidCallback onSelectTimeZone;
  final VoidCallback onSelectRecurrence;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ParticipantDisplayColors? displayColors;
  final String? timeValidationError;

  @override
  State<ScheduleMeetingDialogMobile> createState() =>
      _ScheduleMeetingDialogMobileState();
}

class _ScheduleMeetingDialogMobileState
    extends State<ScheduleMeetingDialogMobile> {
  double _dragOffset = 0;
  static const double _dismissThreshold = 80;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: BaseBottomSheet(
        onBackdropTap: widget.onCancel,
        dragOffset: _dragOffset,
        maxHeight: 800,
        contentPadding: const EdgeInsets.only(bottom: 24),
        backgroundColor: context.colors.interActionWeekMinor2.withValues(
          alpha: 0.30,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: ScheduleMeetingContent(
            titleController: widget.titleController,
            titleHint: widget.titleHint,
            dateLabel: widget.dateLabel,
            startTimeLabel: widget.startTimeLabel,
            durationLabel: widget.durationLabel,
            timeZoneLabel: widget.timeZoneLabel,
            recurrenceLabel: widget.recurrenceLabel,
            isSaveEnabled: widget.isSaveEnabled,
            onTapTitle: widget.onTapTitle,
            onSelectDate: widget.onSelectDate,
            onSelectStartTime: widget.onSelectStartTime,
            onSelectDuration: widget.onSelectDuration,
            onSelectTimeZone: widget.onSelectTimeZone,
            onSelectRecurrence: widget.onSelectRecurrence,
            onSave: widget.onSave,
            onCancel: widget.onCancel,
            timeValidationError: widget.timeValidationError,
            onDragUpdate: _handleDragUpdate,
            onDragEnd: _handleDragEnd,
            displayColors: widget.displayColors,
          ),
        ),
      ),
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0) {
      return;
    }
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 200);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dragOffset >= _dismissThreshold) {
      widget.onCancel();
      return;
    }
    setState(() {
      _dragOffset = 0;
    });
  }
}

class _ScheduleMeetingDialogState extends State<ScheduleMeetingDialog> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialData?.title ?? widget.initialTitle ?? '',
  );

  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime? _endDate;
  TimeOfDay? _endTime;
  int _durationMinutes = 30;
  RecurrenceFrequency _recurrence = RecurrenceFrequency.none;
  bool _showTimeZones = true;
  late String _selectedTimeZone;
  String? _deviceTimeZone;
  bool _hasInitialTimeZone = false;
  String? _timeValidationError;

  @override
  void initState() {
    super.initState();
    _deviceTimeZone = tz.local.name;
    _selectedTimeZone = _deviceTimeZone ?? tz.local.name;
    if (widget.initialData != null) {
      _applyInitialData(widget.initialData!);
    } else {
      // Set default end time to 1 hour after start time
      _applyDuration();
    }
    _loadDeviceTimeZone();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    // Clear validation error when user clicks to select date
    if (_timeValidationError != null) {
      setState(() {
        _timeValidationError = null;
      });
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final startDate = DateUtils.dateOnly(_startDate);
    final firstDate = startDate.isBefore(today) ? startDate : today;
    final initialDate = startDate.isBefore(firstDate) ? firstDate : startDate;
    final lastDate = DateTime.now().add(const Duration(days: 365 * 2));

    DateTime? picked;
    if (iOS) {
      picked = await _showCupertinoDatePicker(
        context: context,
        initialDate: initialDate,
        minimumDate: firstDate,
        maximumDate: lastDate,
      );
    } else {
      picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: context.colors.interActionNorm,
                onPrimary: context.colors.textInverted,
                onSurface: context.colors.textNorm,
                surface: context.colors.backgroundNorm,
              ),
              datePickerTheme: DatePickerThemeData(
                backgroundColor: context.colors.backgroundCard,
                headerBackgroundColor: context.colors.backgroundCard,
                headerForegroundColor: context.colors.textNorm,
                dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return context.colors.textInverted;
                  }
                  return context.colors.textNorm;
                }),
                todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return context.colors.textInverted;
                  }
                  return context.colors.textNorm;
                }),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: context.colors.backgroundNorm,
              ),
            ),
            child: child!,
          );
        },
      );
    }

    final selectedDate = picked;
    if (selectedDate != null) {
      setState(() {
        _startDate = selectedDate;
        // Update end date if it's before start date
        if (_endDate != null && _endDate!.isBefore(selectedDate)) {
          _endDate = selectedDate.add(const Duration(hours: 1));
        }
        // Clear validation error when date changes
        _timeValidationError = null;
      });
    }
  }

  Future<DateTime?> _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime minimumDate,
    required DateTime maximumDate,
  }) async {
    DateTime selectedDate = initialDate;
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return StatefulBuilder(
            builder: (context, setState) => BaseBottomSheet(
              backgroundColor: context.colors.backgroundNorm,
              contentPadding: const EdgeInsets.only(bottom: 24),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BottomSheetHandleBar(),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: CupertinoTheme(
                        data: CupertinoThemeData(
                          primaryColor: context.colors.interActionNorm,
                        ),
                        child: CupertinoDatePicker(
                          initialDateTime: selectedDate,
                          minimumDate: minimumDate,
                          maximumDate: maximumDate,
                          mode: CupertinoDatePickerMode.date,
                          onDateTimeChanged: (DateTime newDate) {
                            setState(() {
                              selectedDate = newDate;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(selectedDate);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.interActionNorm,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(200),
                            ),
                          ),
                          child: Text(
                            context.local.scheduled_meeting_done,
                            style: ProtonStyles.body1Medium(
                              color: context.colors.textInverted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectStartTime() async {
    // Clear validation error when user clicks to select time
    if (_timeValidationError != null) {
      setState(() {
        _timeValidationError = null;
      });
    }
    TimeOfDay? picked;
    if (iOS) {
      final pickedDateTime = await _showCupertinoTimePicker(
        context: context,
        initialTime: _startTime,
      );
      if (pickedDateTime != null) {
        picked = TimeOfDay.fromDateTime(pickedDateTime);
      }
    } else {
      picked = await showTimePicker(
        context: context,
        initialTime: _startTime,
        builder: (context, child) {
          final current = Theme.of(context).timePickerTheme;
          final baseTheme = Theme.of(context);
          return Theme(
            data: baseTheme.copyWith(
              colorScheme: baseTheme.colorScheme.copyWith(
                // 🔵 Selected hour/minute background
                primaryContainer: context.colors.backgroundTimePicker,
                // Selected hour/minute text
                onPrimaryContainer: context.colors.textNorm,
                //unselected hour/minute background
                surfaceContainerHighest: context.colors.borderCard,
                // clock text
                primary: context.colors.interActionNorm,
                // selected clock text
                onPrimary: context.colors.textInverted,
              ),
              timePickerTheme: current.copyWith(
                backgroundColor: context.colors.backgroundCard,
                dialBackgroundColor: context.colors.borderCard,
                entryModeIconColor: context.colors.textHint,
                dayPeriodBorderSide: BorderSide(
                  color: context.colors.borderCard,
                ),
                dayPeriodShape: RoundedRectangleBorder(
                  side: BorderSide(color: context.colors.borderCard),
                  borderRadius: BorderRadius.circular(8),
                ),

                // Selected background color
                dayPeriodColor: context.colors.backgroundTimePicker,
                // Selected text color
                dayPeriodTextColor: context.colors.textNorm,
                cancelButtonStyle: TextButton.styleFrom(
                  foregroundColor: context.colors.interActionNorm,
                ),
                confirmButtonStyle: TextButton.styleFrom(
                  foregroundColor: context.colors.interActionNorm,
                ),
              ),
            ),
            child: child!,
          );
        },
      );
    }

    final selectedTime = picked;
    if (selectedTime != null) {
      setState(() {
        _startTime = selectedTime;
        _applyDuration();
        // Clear validation error when time changes
        _timeValidationError = null;
      });
    }
  }

  Future<DateTime?> _showCupertinoTimePicker({
    required BuildContext context,
    required TimeOfDay initialTime,
  }) async {
    // Get minimum time if selected date is today in the selected timezone
    final minimumDateTime = _startDate.getMinimumTimeIfToday(_selectedTimeZone);

    final initialDateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      initialTime.hour,
      initialTime.minute,
    );
    // Ensure initial time is not before minimum
    final safeInitialDateTime =
        minimumDateTime != null && initialDateTime.isBefore(minimumDateTime)
        ? minimumDateTime
        : initialDateTime;
    DateTime selectedDateTime = safeInitialDateTime;

    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return StatefulBuilder(
            builder: (context, setState) => BaseBottomSheet(
              backgroundColor: context.colors.backgroundNorm,
              contentPadding: const EdgeInsets.only(bottom: 24),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BottomSheetHandleBar(),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: CupertinoTheme(
                        data: CupertinoThemeData(
                          barBackgroundColor: context.colors.protonBlue,
                        ),
                        child: CupertinoDatePicker(
                          initialDateTime: selectedDateTime,
                          minimumDate: minimumDateTime,
                          mode: CupertinoDatePickerMode.time,
                          onDateTimeChanged: (DateTime newDateTime) {
                            // Enforce minimum time if set
                            final minTime = minimumDateTime;
                            if (minTime != null &&
                                newDateTime.isBefore(minTime)) {
                              return; // Ignore invalid selection
                            }
                            setState(() {
                              selectedDateTime = newDateTime;
                            });
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(selectedDateTime);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.interActionNorm,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(200),
                            ),
                          ),
                          child: Text(
                            context.local.scheduled_meeting_done,
                            style: ProtonStyles.body1Medium(
                              color: context.colors.textInverted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectDuration() {
    const options = [15, 30, 45, 60, 90, 120];
    showDurationSheet(
      context,
      options: options,
      selectedMinutes: _durationMinutes,
      formatDuration: _formatDuration,
      onSelect: (minutes) {
        setState(() {
          _durationMinutes = minutes;
          _applyDuration();
        });
      },
    );
  }

  void _selectRecurrence() {
    showRecurrenceSheet(
      context,
      selected: _recurrence,
      onSelect: (freq) {
        setState(() {
          _recurrence = freq;
        });
      },
    );
  }

  Future<void> _loadDeviceTimeZone() async {
    try {
      final resolved = await getDefaultTimeZone();
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceTimeZone = resolved;
        if (!_hasInitialTimeZone) {
          _selectedTimeZone = resolved;
        }
      });
    } catch (e) {
      l.logger.e('[ScheduleMeetingDialog] Error loading device time zone: $e');
    }
  }

  void _applyInitialData(ScheduleMeetingData data) {
    _startDate = data.startDate;
    _startTime = data.startTime;
    _durationMinutes = data.durationMinutes;
    _recurrence = data.recurrence;
    _showTimeZones = data.showTimeZones;
    final timeZone = data.timeZone?.trim();
    if (timeZone != null && timeZone.isNotEmpty) {
      _selectedTimeZone = timeZone;
      _hasInitialTimeZone = true;
    }
    _applyDuration();
  }

  void _selectTimeZone() {
    showScheduleTimeZoneSheet(
      context,
      selectedTimeZone: _selectedTimeZone,
      deviceTimeZone: _deviceTimeZone ?? _selectedTimeZone,
      onSelect: (zone) {
        setState(() {
          _selectedTimeZone = zone;
        });
      },
    );
  }

  String _formatTimeZoneLabel(String name) {
    try {
      final location = tz.getLocation(name);
      final now = tz.TZDateTime.now(location);
      final offset = now.timeZoneOffset;
      final hours = offset.inHours;
      final minutes = offset.inMinutes.remainder(60).abs();
      final sign = hours >= 0 ? '+' : '-';
      final hh = hours.abs().toString().padLeft(2, '0');
      final mm = minutes.toString().padLeft(2, '0');
      return '$name (GMT$sign$hh:$mm)';
    } catch (_) {
      return name;
    }
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      return;
    }
    if (!_isEndAfterStart()) {
      return;
    }

    // Validate that the selected datetime is not in the past (respecting timezone)
    if (!_isDateTimeInFuture()) {
      // Show error message in the timezone field
      setState(() {
        _timeValidationError = "Meeting time can't be in past";
      });
      return;
    }

    // Clear validation error if validation passes
    if (_timeValidationError != null) {
      setState(() {
        _timeValidationError = null;
      });
    }

    Navigator.of(context).pop();
    widget.onSchedule(
      ScheduleMeetingData(
        title: title,
        startDate: _startDate,
        startTime: _startTime,
        durationMinutes: _durationMinutes,
        endDate: _endDate,
        endTime: _endTime,
        timeZone: _selectedTimeZone,
        recurrence: _recurrence,
        showTimeZones: _showTimeZones,
      ),
    );
  }

  /// Checks if the selected start date/time is in the future, respecting the selected timezone
  bool _isDateTimeInFuture() {
    return _startDate.isDateTimeInFuture(_startTime, _selectedTimeZone);
  }

  String _formatDate(DateTime date) {
    final weekday = context.weekdayNames[date.weekday - 1];
    final currentYear = DateTime.now().year;
    final yearSuffix = date.year != currentYear ? ', ${date.year}' : '';
    return '$weekday, ${context.monthNames[date.month - 1]} ${date.day}$yearSuffix';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am
        ? context.local.time_am
        : context.local.time_pm;
    return '$hour:$minute $period';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) {
      return '$hours hr';
    }
    return '$hours hr $remainder min';
  }

  bool _isEndAfterStart() {
    final endDate = _endDate ?? _startDate;
    final endTime = _endTime ?? _startTime;
    final startDateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endDateTime = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      endTime.hour,
      endTime.minute,
    );
    return endDateTime.isAfter(startDateTime);
  }

  void _applyDuration() {
    final startDateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endDateTime = startDateTime.add(Duration(minutes: _durationMinutes));
    _endDate = DateTime(endDateTime.year, endDateTime.month, endDateTime.day);
    _endTime = TimeOfDay.fromDateTime(endDateTime);
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _formatDate(_startDate);
    final startTime = _formatTime(_startTime);
    final durationLabel = _formatDuration(_durationMinutes);
    final timeZoneLabel = _showTimeZones
        ? _formatTimeZoneLabel(_selectedTimeZone)
        : '';
    return ScheduleMeetingDialogMobile(
      titleController: _titleCtrl,
      titleHint: context.local.add_title,
      dateLabel: startLabel,
      startTimeLabel: startTime,
      durationLabel: durationLabel,
      timeZoneLabel: timeZoneLabel,
      recurrenceLabel: _recurrence.label,
      showTimeZones: _showTimeZones,
      isSaveEnabled: _titleCtrl.text.trim().isNotEmpty && _isEndAfterStart(),
      onTapTitle: () => FocusScope.of(context).requestFocus(),
      onSelectDate: _selectStartDate,
      onSelectStartTime: _selectStartTime,
      onSelectDuration: _selectDuration,
      onSelectTimeZone: _selectTimeZone,
      onSelectRecurrence: _selectRecurrence,
      onSave: _submit,
      onCancel: () => Navigator.of(context).maybePop(),
      displayColors: widget.displayColors,
      timeValidationError: _timeValidationError,
    );
  }
}
