import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/strings.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/meet_join_link_parser.dart' as meet_link;
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/dashboard_state.dart';
import 'package:meet/views/scenes/dashboard/join/action_buttons.dart';
import 'package:meet/views/scenes/dashboard/join/header_title.dart';
import 'package:meet/views/scenes/dashboard/join/link_text_field.dart';
import 'package:meet/views/scenes/dashboard/upcoming/meet_upcoming_title.dart';
import 'package:meet/views/scenes/dashboard/upcoming/recurring_meeting_helper.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

typedef OnJoin =
    void Function(String roomId, String passcode, String meetingLink);
typedef OnRegenerateLink = void Function();

Future<void> showJoinMeetingDialog(
  BuildContext context, {
  String? initialUrl,
  String? meetingName,
  String? subtitle,
  String? rRule,
  bool editable = true,
  bool autofocus = true,
  ParticipantDisplayColors? displayColors,
  bool isPersonalMeeting = false,
  MeetUpcomingTab? tab,
  DashboardBloc? bloc,
  // join
  OnJoin? onJoin,
  // Regenerate link callback (for personal meetings)
  OnRegenerateLink? onRegenerateLink,
  // Calendar and Done callbacks
  VoidCallback? onDone,
  VoidCallback? onAdd,
  VoidCallback? onShare,
  VoidCallback? onOpenOutlook,
  VoidCallback? onOpenGoogle,
  VoidCallback? onOpenProton,
  bool showProtonCalendar = false,
  bool showOutlookCalendar = false,
}) {
  // Block dialog when in force upgrade state
  final appStateManager = ManagerFactory().get<AppStateManager>();
  final currentState = appStateManager.state;
  if (currentState is AppForceUpgradeState) {
    return Future.value();
  }

  final title = (meetingName != null && meetingName.isNotEmpty)
      ? meetingName
      : context.local.join_a_meeting;

  final dialog = JoinMeetingModel(
    onJoin: onJoin,
    title: title,
    subtitle: isPersonalMeeting
        ? context.local.personal_meeting_description
        : subtitle ?? context.local.join_meeting_subtitle,
    rRule: rRule,
    initialUrl: initialUrl,
    editable: editable,
    autofocus: autofocus,
    displayColors: displayColors,
    tab: tab,
    isPersonalMeeting: isPersonalMeeting,
    onRegenerateLink: onRegenerateLink,
    onDone: onDone,
    onAdd: onAdd,
    onShare: onShare,
    onOpenOutlook: onOpenOutlook,
    onOpenGoogle: onOpenGoogle,
    onOpenProton: onOpenProton,
    showProtonCalendar: showProtonCalendar,
    showOutlookCalendar: showOutlookCalendar,
    bloc: bloc,
  );

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) =>
        bloc != null ? BlocProvider.value(value: bloc, child: dialog) : dialog,
  );
}

Future<void> showJoinPersonalMeetingDialog(
  BuildContext context, {
  required OnJoin onJoin,
  required OnRegenerateLink onRegenerateLink,
  String? initialUrl,
  bool editable = true,
  bool autofocus = true,
  DashboardBloc? bloc,
}) {
  // Block dialog when in force upgrade state
  final appStateManager = ManagerFactory().get<AppStateManager>();
  final currentState = appStateManager.state;
  if (currentState is AppForceUpgradeState) {
    return Future.value();
  }

  // Read bloc from context before showing modal (context won't be available in builder)
  final dialog = JoinMeetingModel(
    onJoin: onJoin,
    initialUrl: initialUrl,
    editable: editable,
    title: context.local.personal_meeting,
    subtitle: context.local.personal_meeting_description,
    autofocus: autofocus,
    onRegenerateLink: onRegenerateLink,
    bloc: bloc,
  );

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) =>
        bloc != null ? BlocProvider.value(value: bloc, child: dialog) : dialog,
  );
}

class JoinMeetingModel extends StatefulWidget {
  const JoinMeetingModel({
    required this.title,
    required this.subtitle,
    super.key,
    this.initialUrl,
    this.rRule,
    this.editable = true,
    this.autofocus = true,
    this.displayColors,
    this.tab,
    this.isPersonalMeeting = false,
    this.onJoin,
    this.onRegenerateLink,
    // Calendar and Done callbacks
    this.onDone,
    this.onAdd,
    this.onShare,
    this.onOpenOutlook,
    this.onOpenGoogle,
    this.onOpenProton,
    this.showProtonCalendar = false,
    this.showOutlookCalendar = false,
    this.bloc,
  });

  final OnJoin? onJoin;
  final String title;
  final String subtitle;
  final String? initialUrl;
  final String? rRule;
  final bool editable;
  final bool autofocus;
  final ParticipantDisplayColors? displayColors;
  final MeetUpcomingTab? tab;
  final bool isPersonalMeeting;
  final OnRegenerateLink? onRegenerateLink;
  // Calendar and Done callbacks
  final VoidCallback? onDone;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;
  final VoidCallback? onOpenOutlook;
  final VoidCallback? onOpenGoogle;
  final VoidCallback? onOpenProton;
  final bool showProtonCalendar;
  final bool showOutlookCalendar;
  final DashboardBloc? bloc;

  @override
  State<JoinMeetingModel> createState() => _JoinMeetingModelState();
}

class _JoinMeetingModelState extends State<JoinMeetingModel> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialUrl ?? '',
  );
  final FocusNode _focus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  String? _roomId;
  String? _passcode;
  String? _message;

  LinkStatus _status = LinkStatus.empty;
  Timer? _debounceTimer;
  bool _hasFocus = false;
  bool _hasInitialized = false;
  String? _previousPersonalMeetingLink;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(_onTextChanged);
    // Don't validate here - wait for didChangeDependencies to access inherited widgets
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Perform initial validation here when inherited widgets are available
    // Only do this once, on first call
    if (!_hasInitialized) {
      _hasInitialized = true;
      _revalidate(_ctrl.text, onInit: true);
      if (widget.isPersonalMeeting) {
        _previousPersonalMeetingLink = widget.initialUrl;
      }
    }
  }

  void _onFocusChange() {
    final hasFocus = _focus.hasFocus;
    if (_hasFocus != hasFocus) {
      _hasFocus = hasFocus;
      // Scroll to bottom when keyboard appears (focus gained)
      if (hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    }
  }

  void _onTextChanged() {
    // Debounce validation to reduce rebuilds
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _revalidate(_ctrl.text);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Validation + parsing ────────────────────────────────────────────────────
  void _revalidate(String raw, {bool onInit = false}) {
    final result = meet_link.parseMeetJoinLink(
      raw,
      allowedHost: appConfig.apiEnv.domain,
    );

    if (result.isEmpty) {
      setState(() {
        _status = LinkStatus.empty;
        _roomId = null;
        _passcode = null;
        _message = null;
      });
      return;
    }

    if (!result.isHttpUrl || !result.isAllowedHost) {
      setState(() {
        _roomId = "";
        _passcode = "";
        _status = LinkStatus.invalid;
        _message = context.local.please_enter_valid_meeting_link;
      });
      return;
    }

    setState(() {
      _roomId = result.roomId;
      _passcode = result.passcode;
      if (result.isValid) {
        _status = LinkStatus.valid;
        _message = null;
      } else {
        _status = LinkStatus.invalid;
        _message = context.local.please_enter_valid_meeting_link;
      }
    });
  }

  void _submit() {
    if (_status != LinkStatus.valid ||
        _roomId == null ||
        _passcode == null ||
        _passcode!.isEmpty) {
      return;
    }
    Navigator.of(context).pop();
    widget.onJoin?.call(_roomId!, _passcode!, _ctrl.text);
  }

  void _onCopy() {
    Clipboard.setData(ClipboardData(text: _ctrl.text));
    if (context.mounted) {
      LocalToast.showToast(context, context.local.link_copied_to_clipboard);
    }
  }

  void _scrollToBottom() {
    // Wait for keyboard animation and layout to complete, then scroll to bottom
    if (_scrollController.hasClients && mounted) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Listen to DashboardBloc state changes for personal meeting regeneration
    if (widget.bloc != null &&
        widget.isPersonalMeeting &&
        widget.onRegenerateLink != null) {
      return BlocListener<DashboardBloc, DashboardState>(
        listenWhen: (previous, current) {
          // Listen for personal meeting updates or loading state changes
          return previous.personalMeeting != current.personalMeeting ||
              previous.isLoadingPersonalMeeting !=
                  current.isLoadingPersonalMeeting ||
              previous.error != current.error;
        },
        listener: (context, state) {
          // Update text field when personal meeting link changes
          if (state.personalMeeting != null) {
            final newLink = state.personalMeeting!.formatMeetingLink();
            if (newLink != _previousPersonalMeetingLink) {
              _previousPersonalMeetingLink = newLink;
              _ctrl.text = newLink;
              _revalidate(newLink);
            }
          }
        },
        child: BlocBuilder<DashboardBloc, DashboardState>(
          buildWhen: (previous, current) =>
              previous.isLoadingPersonalMeeting !=
              current.isLoadingPersonalMeeting,
          builder: (context, state) =>
              _buildContent(context, state.isLoadingPersonalMeeting),
        ),
      );
    }

    return _buildContent(context, false);
  }

  Widget _buildContent(BuildContext context, bool isRegenerating) {
    final hintText = appConfig.apiEnv.baseUrl.meetingLinkHint;
    final meetingLogo = _getMeetingLogo();
    final showCalendarButton =
        widget.onAdd != null ||
        widget.onShare != null ||
        widget.onOpenOutlook != null ||
        widget.onOpenGoogle != null ||
        widget.onOpenProton != null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: BaseBottomSheet(
          onBackdropTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(40),
          borderSide: BorderSide(
            color: context.colors.white.withValues(alpha: 0.04),
          ),
          scrollController: _scrollController,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSheetHandleBar(),
                const SizedBox(height: 32),

                /// Icon above title
                meetingLogo.svg56(),
                const SizedBox(height: 24),

                /// Title & subtitle
                HeaderTitle(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  isPersonalMeeting: widget.isPersonalMeeting,
                  recurrenceFrequency: _getRecurrenceFrequency(),
                ),
                const SizedBox(height: 32),

                /// Field card with validation states
                LinkTextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  status: _status,
                  message: _message,
                  hintText: hintText,
                  editable: widget.editable,
                  autofocus: widget.autofocus,
                  displayColors: widget.displayColors,
                  onSubmitted: _submit,
                  onCopy: _onCopy,
                ),
                const SizedBox(height: 24),

                /// Action buttons (calendar, join, regenerate, copy, done)
                ActionButtons(
                  status: _status,
                  isRegenerating: isRegenerating,
                  showCalendarButton: showCalendarButton,
                  onSubmit: _submit,
                  onCopy: _onCopy,
                  onRegenerateLink: widget.onRegenerateLink,
                  onDone: widget.onDone,
                  onAdd: widget.onAdd,
                  onShare: widget.onShare,
                  onOpenOutlook: widget.onOpenOutlook,
                  onOpenGoogle: widget.onOpenGoogle,
                  onOpenProton: widget.onOpenProton,
                  showProtonCalendar: widget.showProtonCalendar,
                  showOutlookCalendar: widget.showOutlookCalendar,
                  isPersonalMeeting: widget.isPersonalMeeting,
                  tab: widget.tab,
                  displayColors: widget.displayColors,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SvgGenImage _getMeetingLogo() {
    /// when no tab, it is join meeting
    if (widget.tab == null) {
      return context.images.iconValidLink;
    }

    /// when tab is my meetings, it is meeting logo
    if (widget.tab == MeetUpcomingTab.myMeetings) {
      return widget.displayColors?.meetingLogo ??
          context.images.defaultRoomLogo;
    }

    /// when it is my room and when is personal meeting, it is personal logo
    if (widget.isPersonalMeeting) {
      return widget.displayColors?.personalLogo ??
          context.images.defaultRoomLogo;
    }

    /// when it is other room, it is room logo
    return widget.displayColors?.roomLogo ?? context.images.defaultRoomLogo;
  }

  String? _getRecurrenceFrequency() {
    if (widget.rRule == null || widget.rRule!.isEmpty) {
      return null;
    }
    return RecurringMeetingHelper.parseRecurrenceFrequency(widget.rRule);
  }
}
