import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/alerts/account_switcher_sheet.dart';
import 'package:meet/views/components/alerts/create_room_dialog.dart';
import 'package:meet/views/components/alerts/dashboard_error.dart';
import 'package:meet/views/components/alerts/early_access_dialog.dart';
import 'package:meet/views/components/alerts/force.upgrade.dialog.dart';
import 'package:meet/views/components/alerts/signin_intro_sheet.dart';
import 'package:meet/views/components/bottom.sheets/almost_there_bottom_sheet.dart'
    show AlmostThereContext, showAlmostThereBottomSheet;
import 'package:meet/views/components/local.toast.view.dart';
import 'package:meet/views/scenes/account_deletion/account_deletion_view.dart';
import 'package:meet/views/scenes/app/app.router.dart';
import 'package:meet/views/scenes/dashboard/join/join_meeting_dialog.dart';
import 'package:meet/views/scenes/dashboard/upcoming/meet_upcoming_title.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/settings/app_settings.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_event.dart';
import 'package:meet/views/scenes/signin/auth_state.dart';
import 'package:meet/views/scenes/signin/signin.coordinator.dart';
import 'package:meet/views/scenes/signin/signin.view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_io/io.dart';

import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_screen.dart';
import 'dashboard_state.dart';
import 'schedule/schedule_meeting_dialog.dart';
import 'start_action/floating_start_button.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.dashboardBloc,
    required this.authBloc,
    super.key,
  });
  static const String routeName = '/dashboard';

  final DashboardBloc dashboardBloc;
  final AuthBloc authBloc;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ScrollController _dashboardScrollController = ScrollController();
  final UserAgent _userAgent = UserAgent();
  String _versionDisplay = '';
  StreamSubscription<DataState>? _appStateSubscription;

  @override
  void initState() {
    super.initState();

    _userAgent.displayWithoutName.then((value) {
      setState(() {
        _versionDisplay = value;
      });
    });

    // Listen to app state changes for force upgrade
    final appStateManager = ManagerFactory().get<AppStateManager>();
    _appStateSubscription = appStateManager.stream.listen((state) {
      if (state is AppForceUpgradeState && mounted) {
        showUpgradeErrorDialog(state.message, () {
          // No logout action needed, just show upgrade dialog
        });
      }
    });
  }

  @override
  void dispose() {
    _appStateSubscription?.cancel();
    _dashboardScrollController.dispose();
    super.dispose();
  }

  void joinMeetingWithLink(String roomId, String password, String meetingLink) {
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      return;
    }
    // TODO(improve): right now join meeting with a meeting link, we might need to dirrectly pass in the meeting object
    Navigator.pushNamed(
      context,
      RouteName.preJoin.path,
      arguments: {
        "room": roomId,
        "password": password,
        "meetingLink": meetingLink,
        // displayName will be filled in by the prejoin page,
        // no need to pass it here or it will override the cached display name logic in prejoin page
        "displayName": "",
        "isVideoEnabled": false,
        "isAudioEnabled": false,
        "isE2EEEnabled": true,
        "authBloc": widget.authBloc,
      },
    );
  }

  void startSecureMeeting() {
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      return;
    }
    final args = PreJoinArgs(
      type: PreJoinType.create,
      authBloc: widget.authBloc,
    );
    Navigator.pushNamed(context, RouteName.preJoin.path, arguments: args);
  }

  void _showFlutterSignIn(BuildContext context) {
    final coordinator = SigninCoordinator(
      onLoginSuccess: (user) {
        widget.authBloc.add(LoggedInUser(user));
      },
    );

    final signinWidget = coordinator.start();
    if (signinWidget is SigninView) {
      showDialog(context: context, builder: (context) => signinWidget);
    }
  }

  void _handleJoinMeeting() {
    showJoinMeetingDialog(
      context,
      bloc: widget.dashboardBloc,
      onJoin: joinMeetingWithLink,
    );
  }

  void _showSignInRequiredBottomSheet(AlmostThereContext almostThereContext) {
    final isMeetEarlyAccess = ManagerFactory()
        .get<DataProviderManager>()
        .unleashDataProvider
        .isMeetEarlyAccess();
    if (!isMeetEarlyAccess) {
      // If this is not in early access, ask user to login to have early access feature on
      showUserLoginCheckBottomSheet(
        context,
        onLogin: () {
          if (desktop) {
            _showFlutterSignIn(context);
          } else {
            widget.authBloc.add(LoginWithNative());
          }
        },
      );
    } else {
      // We will enable early access feature flag for all user after GA
      // If this is in early access, show almost there bottom sheet to ask user to create account or sign in to have the create meeting / schedule meeting feature
      showAlmostThereBottomSheet(
        context,
        almostThereContext: almostThereContext,
        onCreateAccount: () async {
          Navigator.of(context).maybePop();
          if (desktop) {
            _showFlutterSignIn(context);
          } else {
            widget.authBloc.add(SignupWithNative());
          }
        },
        onSignIn: () async {
          Navigator.of(context).maybePop();
          if (desktop) {
            _showFlutterSignIn(context);
          } else {
            widget.authBloc.add(LoginWithNative());
          }
        },
      );
    }
  }

  void _handlePersonalMeeting() {
    final authState = widget.authBloc.state;
    if (authState.isLoading) return;
    if (!authState.isSignedIn) {
      _showSignInRequiredBottomSheet(AlmostThereContext.personalRoom);
      return;
    }
    widget.dashboardBloc.add(
      CreatePersonalMeetingEvent(goPersonalMeeting: true),
    );
  }

  void _handleCreateRoom() {
    final authState = widget.authBloc.state;
    if (authState.isLoading) return;
    if (!authState.isSignedIn) {
      _showSignInRequiredBottomSheet(AlmostThereContext.createRoom);
      return;
    }
    showCreateRoomDialog(
      context,
      onCreateRoom: (roomName) {
        widget.dashboardBloc.add(CreateMeetingEvent(roomName: roomName));
      },
    );
  }

  void _handleSecureMeetingPress() {
    final authState = widget.authBloc.state;
    if (authState.isLoading) return;

    if (!authState.isSignedIn) {
      _showSignInRequiredBottomSheet(AlmostThereContext.createRoom);
      return;
    }
    widget.dashboardBloc.add(CreateSecureMeetingEvent(goSecureMeeting: true));
  }

  void _handleSchedule() {
    final authState = widget.authBloc.state;
    if (authState.isLoading) return;
    if (!authState.isSignedIn) {
      _showSignInRequiredBottomSheet(AlmostThereContext.schedule);
      return;
    }
    showScheduleMeetingDialog(
      context,
      displayColors: getParticipantDisplayColors(context, 0),
      onSchedule: (data) {
        widget.dashboardBloc.add(ScheduleMeetingEvent(data: data));
      },
    );
  }

  Future<void> _saveIcsFile(String icsContent, String title) async {
    final fileName = _buildIcsFileName(title);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName.ics');
    await file.writeAsString(icsContent);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: title,
      ),
    );
  }

  String _buildIcsFileName(String title) {
    final sanitized = title
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '')
        .toLowerCase();
    return sanitized.isEmpty ? 'proton_meet' : sanitized;
  }

  Future<void> _showScheduledMeetingSummary(
    BuildContext context, {
    required FrbUpcomingMeeting meeting,
    required ScheduleMeetingData data,
  }) async {
    final meetingLink = meeting.formatMeetingLink();
    final displayColors = getParticipantDisplayColors(context, 0);
    await showJoinMeetingDialog(
      context,
      bloc: widget.dashboardBloc,
      tab: MeetUpcomingTab.myMeetings,
      initialUrl: meetingLink,
      isPersonalMeeting: meeting.isPersonalMeeting,
      displayColors: displayColors,
      editable: false,
      autofocus: false,
      meetingName: meeting.meetingName,
      subtitle: meeting.formatStartDateTime(
        context,
        useLocalTimezone: true,
        twoLines: true,
      ),
      rRule: meeting.rRule,
      onDone: () {
        Navigator.of(context).pop();
      },
      onAdd: () {
        widget.dashboardBloc.add(
          AddScheduledMeetingToCalendarEvent(
            data: data,
            meetingLink: meetingLink,
          ),
        );
      },
      onShare: () {
        widget.dashboardBloc.add(
          DownloadScheduledMeetingIcsEvent(
            data: data,
            meetingLink: meetingLink,
          ),
        );
      },
      onOpenOutlook: () {
        widget.dashboardBloc.add(
          OpenScheduledMeetingCalendarEvent(
            data: data,
            meetingLink: meetingLink,
            provider: CalendarProvider.outlook,
          ),
        );
      },
      onOpenGoogle: () {
        widget.dashboardBloc.add(
          OpenScheduledMeetingCalendarEvent(
            data: data,
            meetingLink: meetingLink,
            provider: CalendarProvider.google,
          ),
        );
      },
      onOpenProton: () {
        widget.dashboardBloc.add(
          OpenScheduledMeetingCalendarEvent(
            data: data,
            meetingLink: meetingLink,
            provider: CalendarProvider.proton,
          ),
        );
      },
    );
    widget.dashboardBloc.add(ClearScheduledMeetingSummaryEvent());
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => widget.authBloc),
        BlocProvider(create: (context) => widget.dashboardBloc),
      ],
      child: BlocSelector<AuthBloc, AuthState, AuthState>(
        selector: (state) => state,
        builder: (context, state) {
          return MultiBlocListener(
            listeners: [
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) {
                  final error = current.error;
                  if (error == null) return false;
                  return previous.error != current.error && error.isNotEmpty;
                },
                listener: (context, state) {
                  final error = state.error;
                  if (error != null &&
                      context.mounted &&
                      !PlatformInfoChannel.isInForceUpgradeState()) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted &&
                          !PlatformInfoChannel.isInForceUpgradeState()) {
                        showDashboardErrorBottomSheet(
                          context,
                          errorMessage: error,
                          errorDetails: (state.errorDetail?.isEmpty ?? true)
                              ? error
                              : state.errorDetail,
                          onRetry:
                              state.offerFetchUserStateRetry &&
                                  !state.hasDashboardMutationInProgress
                              ? () => widget.dashboardBloc.add(
                                  RetryDashboardLoadEvent(),
                                )
                              : null,
                        );
                      }
                    });
                  }
                },
              ),

              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) {
                  if (current.errorResponse == null) return false;
                  return previous.errorResponse != current.errorResponse;
                },
                listener: (context, state) {
                  final errorResponse = state.errorResponse;
                  if (errorResponse != null &&
                      context.mounted &&
                      !PlatformInfoChannel.isInForceUpgradeState()) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted &&
                          !PlatformInfoChannel.isInForceUpgradeState()) {
                        showDashboardErrorBottomSheet(
                          context,
                          errorMessage: errorResponse.error,
                          errorDetails: errorResponse.detailString,
                          onRetry:
                              state.offerFetchUserStateRetry &&
                                  !state.hasDashboardMutationInProgress
                              ? () => widget.dashboardBloc.add(
                                  RetryDashboardLoadEvent(),
                                )
                              : null,
                        );
                      }
                    });
                  }
                },
              ),

              BlocListener<AuthBloc, AuthState>(
                listenWhen: (previous, current) =>
                    previous.isSignedIn != current.isSignedIn,
                listener: (context, state) {
                  if (state.isSignedIn) {
                    // User logged in - fetch user state
                    widget.dashboardBloc.add(FetchUserStateEvent());
                  } else {
                    // User logged out - reset dashboard state
                    widget.dashboardBloc.add(ResetDashboardStateEvent());
                  }
                },
              ),

              BlocListener<AuthBloc, AuthState>(
                listenWhen: (previous, current) =>
                    previous.shouldShowFlutterSignIn !=
                        current.shouldShowFlutterSignIn &&
                    current.shouldShowFlutterSignIn,
                listener: (context, state) {
                  if (!PlatformInfoChannel.isInForceUpgradeState()) {
                    _showFlutterSignIn(context);
                  }
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.isLoadingCreateMeeting !=
                    current.isLoadingCreateMeeting,
                listener: (context, state) {
                  if (state.isLoadingCreateMeeting) {
                    if (!PlatformInfoChannel.isInForceUpgradeState()) {
                      EasyLoading.show(
                        status: context.local.creating_meeting,
                        maskType: EasyLoadingMaskType.black,
                        dismissOnTap: false,
                      );
                    }
                  } else {
                    EasyLoading.dismiss();
                  }
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.isLoadingDeleteMeeting !=
                    current.isLoadingDeleteMeeting,
                listener: (context, state) {
                  if (state.isLoadingDeleteMeeting) {
                    if (!PlatformInfoChannel.isInForceUpgradeState()) {
                      EasyLoading.show(
                        status: context.local.deleting_meeting,
                        maskType: EasyLoadingMaskType.black,
                        dismissOnTap: false,
                      );
                    }
                  } else {
                    EasyLoading.dismiss();
                    if (!PlatformInfoChannel.isInForceUpgradeState() &&
                        (state.error == null || state.error!.isEmpty) &&
                        state.errorResponse == null) {
                      LocalToast.showToast(
                        context,
                        toastType: ToastType.normlight,
                        state.upcomingTab == MeetUpcomingTab.myRooms
                            ? context.local.room_deleted
                            : context.local.meeting_deleted,
                      );
                    }
                  }
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.isLoadingUpdateMeeting !=
                    current.isLoadingUpdateMeeting,
                listener: (context, state) {
                  if (state.isLoadingUpdateMeeting) {
                    if (!PlatformInfoChannel.isInForceUpgradeState()) {
                      EasyLoading.show(
                        status: context.local.updating_meeting,
                        maskType: EasyLoadingMaskType.black,
                        dismissOnTap: false,
                      );
                    }
                  } else {
                    EasyLoading.dismiss();
                  }
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.isLoadingScheduleMeeting !=
                    current.isLoadingScheduleMeeting,
                listener: (context, state) {
                  if (state.isLoadingScheduleMeeting) {
                    if (!PlatformInfoChannel.isInForceUpgradeState()) {
                      EasyLoading.show(
                        status: context.local.scheduling_meeting,
                        maskType: EasyLoadingMaskType.black,
                        dismissOnTap: false,
                      );
                    }
                  } else {
                    EasyLoading.dismiss();
                  }
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.scheduledMeeting != current.scheduledMeeting &&
                    current.scheduledMeeting != null &&
                    current.scheduledMeetingData != null,
                listener: (context, state) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted &&
                        !PlatformInfoChannel.isInForceUpgradeState()) {
                      _showScheduledMeetingSummary(
                        context,
                        meeting: state.scheduledMeeting!,
                        data: state.scheduledMeetingData!,
                      );
                    }
                  });
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.scheduledMeetingIcsContent !=
                        current.scheduledMeetingIcsContent &&
                    current.scheduledMeetingIcsContent != null,
                listener: (context, state) async {
                  final content = state.scheduledMeetingIcsContent;
                  final title = state.scheduledMeetingIcsTitle;
                  if (content != null && title != null) {
                    await _saveIcsFile(content, title);
                    widget.dashboardBloc.add(ClearScheduledMeetingIcsEvent());
                  }
                },
              ),
              BlocListener<DashboardBloc, DashboardState>(
                listenWhen: (previous, current) =>
                    previous.createdMeetingLink != current.createdMeetingLink &&
                    current.createdMeetingLink != null &&
                    current.createdMeetingLink!.isNotEmpty,
                listener: (context, state) async {
                  final meetingLink = state.createdMeetingLink;
                  if (meetingLink != null && meetingLink.isNotEmpty) {
                    // Copy meeting link to clipboard
                    await Clipboard.setData(ClipboardData(text: meetingLink));
                    // Show toast
                    if (context.mounted &&
                        !PlatformInfoChannel.isInForceUpgradeState()) {
                      LocalToast.showToast(
                        context,
                        context.local.copied_to_clipboard,
                      );
                    }
                    // Clear the created meeting link
                    widget.dashboardBloc.add(ClearCreatedMeetingLinkEvent());
                  }
                },
              ),
            ],
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: context.colors.backgroundDark,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: SafeArea(
                      child: DashboardScreen(
                        bloc: widget.dashboardBloc,
                        authBloc: widget.authBloc,
                        onJoinMeetingWithLink: joinMeetingWithLink,
                        onStartSecureMeeting: startSecureMeeting,
                        onScheduleMeeting: _handleSchedule,
                        onPersonalMeeting: _handlePersonalMeeting,
                        onCreateRoom: _handleCreateRoom,
                        onShowFlutterSignIn: () => _showFlutterSignIn(context),
                        scrollController: _dashboardScrollController,
                        displayName: state.displayName,
                        isSignedIn: state.isSignedIn,
                        onSignInTap: () {
                          showSignInIntroSheet(
                            context,
                            versionDisplay: _versionDisplay,
                            onSignIn: () {
                              if (desktop) {
                                _showFlutterSignIn(context);
                              } else {
                                widget.authBloc.add(LoginWithNative());
                              }
                            },
                            onSignUp: () {
                              if (desktop) {
                                _showFlutterSignIn(context);
                              } else {
                                widget.authBloc.add(SignupWithNative());
                              }
                            },
                          );
                        },
                        onLogoutTap: () {
                          showAccountSwitcherBottomSheet(
                            context,
                            displayName: state.displayName,
                            email: state.email,
                            initials: state.initials,
                            versionDisplay: _versionDisplay,
                            onLogout: () {
                              widget.authBloc.add(SignOutUser());
                            },
                            onDeleteAccount: () =>
                                mobile ? _deleteAccount(context) : null,
                          );
                        },
                        onSettingsTap: () {
                          AppSettingsBottomSheet.show(
                            context,
                            authBloc: widget.authBloc,
                          );
                        },
                        onNavBarTitleChanged: (_) {
                          // Title is managed internally by DashboardScreen
                        },
                      ),
                    ),
                  ),
                  BlocBuilder<DashboardBloc, DashboardState>(
                    bloc: widget.dashboardBloc,
                    builder: (context, dashboardState) {
                      return SafeArea(
                        top: false,
                        left: false,
                        right: false,
                        child: FloatingStartButton(
                          onSchedule: _handleSchedule,
                          onCreateRoom: _handleCreateRoom,
                          onJoinLink: _handleJoinMeeting,
                          onInstant: _handleSecureMeetingPress,
                          onPersonalMeeting: _handlePersonalMeeting,
                          isScheduleInAdvanceEnabled: true,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    // Only show on mobile platforms
    if (mobile) {
      if (context.mounted) {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          enableDrag: false,
          builder: (context) => AccountDeletionView(authBloc: widget.authBloc),
        );
      }
    }
  }
}
