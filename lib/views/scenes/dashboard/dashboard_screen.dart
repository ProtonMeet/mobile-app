import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/views/components/alerts/early_access_dialog.dart';
import 'package:meet/views/components/app_nav_bar.dart';
import 'package:meet/views/scenes/dashboard/join/join_meeting_dialog.dart';
import 'package:meet/views/scenes/dashboard/search/search_bar.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_event.dart';

import 'dashboard_bloc.dart';
import 'dashboard_cards.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'search/sort_sheet.dart';
import 'search_results_view.dart';
import 'sign_in_card.dart';
import 'upcoming/meet_upcoming_title.dart';
import 'upcoming/upcoming_meeting_list.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.bloc,
    required this.authBloc,
    required this.onJoinMeetingWithLink,
    required this.onStartSecureMeeting,
    required this.onScheduleMeeting,
    required this.onPersonalMeeting,
    required this.onCreateRoom,
    required this.onShowFlutterSignIn,
    required this.scrollController,
    required this.onSignInTap,
    required this.onSettingsTap,
    required this.onLogoutTap,
    required this.isSignedIn,
    required this.displayName,
    this.onNavBarTitleChanged,
    super.key,
  });

  @protected
  final DashboardBloc bloc;
  final AuthBloc authBloc;
  final void Function(String roomId, String password, String meetingLink)
  onJoinMeetingWithLink;
  final VoidCallback onStartSecureMeeting;
  final VoidCallback onScheduleMeeting;
  final VoidCallback onPersonalMeeting;
  final VoidCallback onCreateRoom;
  final VoidCallback onShowFlutterSignIn;
  final ScrollController scrollController;
  final VoidCallback onSignInTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogoutTap;
  final bool isSignedIn;
  final String displayName;
  final ValueChanged<String?>? onNavBarTitleChanged;

  @override
  State<DashboardScreen> createState() {
    return DashboardScreenState();
  }
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _handledInitialLink = false;
  final GlobalKey _upcomingTitleKey = GlobalKey();
  final GlobalKey _searchBarKey = GlobalKey();
  String? _navBarTitle;
  bool _searchBarReachedNavBar = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppLinks()
          .getInitialLink()
          .then((value) {
            if (!mounted) return;
            // Ensure this runs only once per widget instance. for cold start
            if (_handledInitialLink) return;
            _handledInitialLink = true;

            // Block initial deeplink when in force upgrade state
            final appStateManager = ManagerFactory().get<AppStateManager>();
            final currentState = appStateManager.state;
            if (currentState is AppForceUpgradeState) {
              l.logger.i(
                'Initial deeplink blocked: app is in force upgrade state',
              );
              return;
            }

            if (value != null) {
              final cxt = context;
              if (cxt.mounted) {
                showJoinMeetingDialog(
                  cxt,
                  bloc: widget.bloc,
                  onJoin: widget.onJoinMeetingWithLink,
                  initialUrl: value.toString(),
                  autofocus: false,
                );
              }
            }
          })
          .catchError((error) {
            l.logger.e('Error getting initial link: $error');
          });
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSignedIn != widget.isSignedIn) {
      if (widget.isSignedIn) {
        // Hide sign-in card when user signs in
        widget.bloc.add(DismissSignInCardEvent());
      } else {
        // Load sign-in card visibility when user signs out
        widget.bloc.add(LoadSignInCardVisibilityEvent());
      }
    }
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients || !mounted) return;

    final titleContext = _upcomingTitleKey.currentContext;
    if (titleContext == null) return;

    final RenderBox? renderBox = titleContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Get the position of the widget relative to the viewport
    final appBarHeight = MediaQuery.of(titleContext).padding.top;

    // Get the position of the widget in global coordinates (relative to screen)
    final position = renderBox.localToGlobal(Offset.zero);

    // The widget is under the navbar if its top is above or at the navbar bottom
    // position.dy is relative to screen top, so if it's less than or equal to appBarHeight,
    // it means it's scrolled under the navbar
    final isUnderNavBar = position.dy <= appBarHeight;

    if (isUnderNavBar) {
      // Get the title text based on selected tab
      final dashboardState = widget.bloc.state;
      final titleText = dashboardState.upcomingTab == MeetUpcomingTab.myMeetings
          ? titleContext.local.my_meetings_count
          : titleContext.local.my_rooms_count;

      if (_navBarTitle != titleText) {
        setState(() {
          _navBarTitle = titleText;
        });
        widget.onNavBarTitleChanged?.call(titleText);
      }
    } else {
      if (_navBarTitle != null) {
        setState(() {
          _navBarTitle = null;
        });
        widget.onNavBarTitleChanged?.call(null);
      }
    }

    // Check if search bar has reached the nav bar
    final searchBarContext = _searchBarKey.currentContext;
    if (searchBarContext != null && mounted) {
      final searchBarRenderBox =
          searchBarContext.findRenderObject() as RenderBox?;
      if (searchBarRenderBox != null) {
        final searchBarPosition = searchBarRenderBox.localToGlobal(Offset.zero);
        final topPadding = MediaQuery.of(searchBarContext).padding.top;
        final navBarBottom = topPadding + kToolbarHeight;
        final searchBarReachedNavBar = searchBarPosition.dy <= navBarBottom;

        if (_searchBarReachedNavBar != searchBarReachedNavBar) {
          setState(() {
            _searchBarReachedNavBar = searchBarReachedNavBar;
          });
        }
      }
    }
  }

  Widget _buildGuestPersonalMeetingEntry(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPersonalMeeting,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              context.images.iconPersonalMeeting.svg40(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: 0.90,
                      child: Text(
                        context.local.personal_meeting_room,
                        style: ProtonStyles.body1Semibold(
                          color: context.colors.interActionNorm,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.local.personal_meeting_description,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.textHint,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              context.images.iconPinAngled.svg20(
                color: context.colors.protonBlue,
              ),
              const SizedBox(width: 2,),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<DashboardBloc, DashboardState, DashboardState>(
      selector: (state) => state,
      builder: (BuildContext context, DashboardState currentState) {
        return MultiBlocListener(
          listeners: [
            BlocListener<DashboardBloc, DashboardState>(
              listenWhen: (previous, current) =>
                  previous.goSecureMeeting != current.goSecureMeeting &&
                  current.goSecureMeeting,
              listener: (context, state) {
                widget.onStartSecureMeeting();
              },
            ),
            BlocListener<DashboardBloc, DashboardState>(
              listenWhen: (previous, current) =>
                  previous.goPersonalMeeting != current.goPersonalMeeting &&
                  current.goPersonalMeeting,
              listener: (context, state) {
                showJoinPersonalMeetingDialog(
                  context,
                  onJoin: widget.onJoinMeetingWithLink,
                  editable: false,
                  initialUrl: state.personalMeeting?.formatMeetingLink() ?? '',
                  bloc: widget.bloc,
                  onRegenerateLink: () {
                    widget.bloc.add(RotatePersonalMeetingLinkEvent());
                  },
                );
              },
            ),
            BlocListener<DashboardBloc, DashboardState>(
              listenWhen: (previous, current) =>
                  previous.joinMeetingWithLinkUrl !=
                      current.joinMeetingWithLinkUrl &&
                  current.joinMeetingWithLinkUrl.isNotEmpty,
              listener: (context, state) {
                // Only show the dialog if Dashboard is the top-most route.
                // If user is already in another screen (e.g. in-room), ignore silently.
                if (!context.isTopMostRoute) return;
                showJoinMeetingDialog(
                  context,
                  bloc: widget.bloc,
                  onJoin: widget.onJoinMeetingWithLink,
                  initialUrl: state.joinMeetingWithLinkUrl,
                  autofocus: false,
                );
              },
            ),
            BlocListener<DashboardBloc, DashboardState>(
              listenWhen: (previous, current) =>
                  previous.showEarlyAccessDialog !=
                      current.showEarlyAccessDialog &&
                  current.showEarlyAccessDialog,
              listener: (context, state) {
                showUserLoginCheckBottomSheet(
                  context,
                  onLogin: widget.authBloc.state.isSignedIn
                      ? null
                      : () {
                          if (desktop) {
                            widget.onShowFlutterSignIn();
                          } else {
                            widget.authBloc.add(LoginWithNative());
                          }
                        },
                  isLoggedIn: widget.authBloc.state.isSignedIn,
                );
                widget.bloc.add(ResetEarlyAccessDialogEvent());
              },
            ),
            BlocListener<DashboardBloc, DashboardState>(
              listenWhen: (previous, current) =>
                  previous.isSearchMode != current.isSearchMode &&
                  !current.isSearchMode,
              listener: (context, state) {
                // Recalculate nav bar state based on current scroll position
                // Use postFrameCallback to ensure widgets are rebuilt first
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  // Trigger scroll listener to recalculate nav bar state
                  _onScroll();
                });
              },
            ),
          ],
          child: CustomScrollView(
            controller: widget.scrollController,
            slivers: [
              AppNavBar(
                displayName: widget.displayName,
                isSignedIn: widget.isSignedIn,
                scrollController: widget.scrollController,
                title: _navBarTitle,
                searchBarReachedNavBar: _searchBarReachedNavBar,
                onSearchTap: () {
                  widget.bloc.add(EnterSearchModeEvent());
                },
                isSearchMode: currentState.isSearchMode,
                searchQuery: currentState.searchQuery,
                onSearchQueryChanged: (query) {
                  widget.bloc.add(UpdateSearchQueryEvent(query: query));
                },
                onCancelSearch: () {
                  widget.bloc.add(ExitSearchModeEvent());
                },
                onSortTap: () {
                  final currentTab = currentState.upcomingTab;
                  final selectedOption =
                      currentTab == MeetUpcomingTab.myMeetings
                      ? currentState.sortOptionMyMeetings
                      : currentState.sortOptionMyRooms;
                  showSortSheet(
                    context,
                    currentTab: currentTab,
                    selectedOption: selectedOption,
                    onSelect: (option) {
                      if (currentTab == MeetUpcomingTab.myMeetings) {
                        widget.bloc.add(
                          UpdateSortOptionMyMeetingsEvent(
                            sortOption: option as SortOptionMyMeetings,
                          ),
                        );
                      } else {
                        widget.bloc.add(
                          UpdateSortOptionMyRoomsEvent(
                            sortOption: option as SortOptionMyRooms,
                          ),
                        );
                      }
                    },
                  );
                },
                onSignInTap: widget.onSignInTap,
                onLogoutTap: widget.onLogoutTap,
                hideSettings: true,
                onSettingsTap: widget.onSettingsTap,
              ),

              if (!currentState.isSearchMode)
                SliverToBoxAdapter(
                  child: DashboarCards(
                    cards: currentState.infoCards,
                    onDismiss: (id) =>
                        widget.bloc.add(DismissDashboardInfoCardEvent(id: id)),
                  ),
                ),

              // if (currentState.infoCards.isEmpty)
              //   SliverToBoxAdapter(child: const SizedBox(height: 16)),
              if (currentState.isSearchMode) ...[
                SearchResultsView(
                  searchQuery: currentState.searchQuery,
                  searchResults: currentState.searchResults,
                  onJoinMeetingWithLink: widget.onJoinMeetingWithLink,
                  currentTab: currentState.upcomingTab,
                ),
                SliverSafeArea(
                  top: false,
                  sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ] else ...[
                if (currentState.showSignInCard && !widget.isSignedIn)
                  SliverToBoxAdapter(
                    child: SignInCard(
                      onDismiss: () {
                        widget.bloc.add(DismissSignInCardEvent());
                      },
                      onSignInTap: widget.onSignInTap,
                    ),
                  ),

                /// Upcoming meetings title
                SliverToBoxAdapter(
                  child: Container(
                    key: _upcomingTitleKey,
                    child: MeetUpcomingTitle(
                      myMeetingsCount: currentState.myMeetingsCount,
                      myRoomsCount: currentState.myRoomsCount,
                      onTabChanged: (tab) => widget.bloc.add(
                        UpdateUpcomingStateEvent(upcomingTab: tab),
                      ),
                      selectedTab: currentState.upcomingTab,
                      isLoading: currentState.isDashboardFetchUiBusy,
                      onFetchReloadTap:
                          currentState.offerFetchUserStateRetry &&
                                  !currentState.hasDashboardMutationInProgress
                              ? () =>
                                    widget.bloc.add(FetchUserStateEvent())
                              : null,
                    ),
                  ),
                ),
                // show personal meeting link if not signed in and no personal meetings
                if (currentState.upcomingTab == MeetUpcomingTab.myRooms &&
                    !widget.isSignedIn &&
                    !currentState.meetinsDisplay.any(
                      (meeting) => meeting.isPersonalMeeting,
                    ))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildGuestPersonalMeetingEntry(context),
                    ),
                  ),
                if (currentState.meetinsDisplay.isNotEmpty &&
                    !currentState.meetinsDisplay.every(
                      (meeting) => meeting.isPersonalMeeting,
                    ))
                  SliverToBoxAdapter(
                    child: Container(
                      key: _searchBarKey,
                      child: DashboardSearchBar(
                        onTap: () {
                          widget.bloc.add(EnterSearchModeEvent());
                        },
                        onSortTap: () {
                          final currentTab = currentState.upcomingTab;
                          final selectedOption =
                              currentTab == MeetUpcomingTab.myMeetings
                              ? currentState.sortOptionMyMeetings
                              : currentState.sortOptionMyRooms;
                          showSortSheet(
                            context,
                            currentTab: currentTab,
                            selectedOption: selectedOption,
                            onSelect: (option) {
                              if (currentTab == MeetUpcomingTab.myMeetings) {
                                widget.bloc.add(
                                  UpdateSortOptionMyMeetingsEvent(
                                    sortOption: option as SortOptionMyMeetings,
                                  ),
                                );
                              } else {
                                widget.bloc.add(
                                  UpdateSortOptionMyRoomsEvent(
                                    sortOption: option as SortOptionMyRooms,
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ...buildUpcomingMeetingSlivers(
                  context: context,
                  upcomingTab: currentState.upcomingTab,
                  onJoinMeetingWithLink: widget.onJoinMeetingWithLink,
                  meetinsDisplay: currentState.meetinsDisplay,
                  isLoaded: currentState.isLoaded,
                  onSchedule: widget.onScheduleMeeting,
                  onCreateRoom: widget.onCreateRoom,
                  sortOption: currentState.sortOptionMyMeetings,
                  sortOptionMyRooms: currentState.sortOptionMyRooms,
                ),
              ],
              SliverSafeArea(
                top: false,
                sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],
          ),
        );
      },
    );
  }
}
