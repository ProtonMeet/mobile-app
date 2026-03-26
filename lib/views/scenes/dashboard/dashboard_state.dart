import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/dashboard/dashboard_event.dart'
    show FetchUserStateEvent;

import 'schedule/schedule_meeting_dialog.dart';
import 'search/sort_sheet.dart';
import 'upcoming/meet_upcoming_title.dart';

class DashboardCard extends Equatable {
  final String id;
  final int backgroundColorValue;
  final String title;
  final String subtitle;
  final String iconKey;

  const DashboardCard({
    required this.id,
    required this.backgroundColorValue,
    required this.title,
    required this.subtitle,
    required this.iconKey,
  });

  Color get backgroundColor => Color(backgroundColorValue);

  @override
  List<Object?> get props => [
    id,
    backgroundColorValue,
    title,
    subtitle,
    iconKey,
  ];
}

class DashboardState extends Equatable {
  final bool isLoading;
  // meeting is loaded at least onece
  final bool isLoaded;
  final bool isLoadingUpcomingMeetings;
  final bool isLoadingPersonalMeeting;
  final bool isLoadingScheduledMeetings;
  final bool isLoadingSecureMeeting;
  final bool isLoadingCreateMeeting;
  final bool isLoadingDeleteMeeting;
  final bool isLoadingUpdateMeeting;
  final bool isLoadingScheduleMeeting;

  final bool goPersonalMeeting;
  final bool goSecureMeeting;
  final String joinMeetingWithLinkUrl;
  final bool showEarlyAccessDialog;
  final String? error;
  final String? errorDetail;
  final ResponseError? errorResponse;
  final List<String> data;
  final List<FrbUpcomingMeeting> meetinsDisplay;
  final FrbUpcomingMeeting? personalMeeting;
  final List<DashboardCard> infoCards;

  final MeetUpcomingTab upcomingTab;
  final int myMeetingsCount;
  final int myRoomsCount;

  final List<FrbUpcomingMeeting> upcomingMeetings;
  final String? createdMeetingLink;

  ///
  final ScheduleMeetingData? scheduledMeetingData;
  final FrbUpcomingMeeting? scheduledMeeting;
  final String? scheduledMeetingIcsContent;
  final String? scheduledMeetingIcsTitle;

  final bool isSearchMode;
  final String searchQuery;
  final List<FrbUpcomingMeeting> searchResults;

  final SortOptionMyRooms sortOptionMyRooms;
  final SortOptionMyMeetings sortOptionMyMeetings;

  final bool showSignInCard;
  final bool isAnonymousUser;

  /// When true, the dashboard error sheet shows Retry (full dashboard fetch / initial load).
  /// Must not be set for other operations (create room, calendar, etc.).
  final bool offerFetchUserStateRetry;

  const DashboardState({
    this.upcomingTab = MeetUpcomingTab.myMeetings,
    this.myMeetingsCount = 0,
    this.myRoomsCount = 0,
    this.isLoading = false,
    this.isLoaded = false,
    this.isLoadingUpcomingMeetings = false,
    this.isLoadingPersonalMeeting = false,
    this.isLoadingCreateMeeting = false,
    this.isLoadingDeleteMeeting = false,
    this.isLoadingUpdateMeeting = false,
    this.isLoadingScheduleMeeting = false,
    this.goPersonalMeeting = false,
    this.goSecureMeeting = false,
    this.showEarlyAccessDialog = false,
    this.isLoadingScheduledMeetings = false,
    this.isLoadingSecureMeeting = false,
    this.error,
    this.errorDetail,
    this.errorResponse,
    this.data = const [],
    this.upcomingMeetings = const [],
    this.meetinsDisplay = const [],
    this.personalMeeting,
    this.joinMeetingWithLinkUrl = '',
    this.infoCards = const [],
    this.createdMeetingLink,
    this.scheduledMeetingData,
    this.scheduledMeeting,
    this.scheduledMeetingIcsContent,
    this.scheduledMeetingIcsTitle,
    this.isSearchMode = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.sortOptionMyRooms = SortOptionMyRooms.newCreated,
    this.sortOptionMyMeetings = SortOptionMyMeetings.upcoming,
    this.showSignInCard = false,
    this.isAnonymousUser = false,
    this.offerFetchUserStateRetry = false,
  });

  /// Spinner in the upcoming tabs header: main dashboard fetch or list refresh.
  bool get isDashboardFetchUiBusy =>
      (isLoadingPersonalMeeting && isLoadingScheduledMeetings) ||
      isLoadingUpcomingMeetings ||
      (isLoadingPersonalMeeting && !isLoadingScheduledMeetings && !isLoaded);

  /// Mutations that must not overlap with [FetchUserStateEvent] from the header / retry.
  bool get hasDashboardMutationInProgress =>
      isLoadingCreateMeeting ||
      isLoadingDeleteMeeting ||
      isLoadingUpdateMeeting ||
      isLoadingScheduleMeeting ||
      isLoadingSecureMeeting;

  DashboardState copyWith({
    bool resetError = false,
    bool? isLoading,
    bool? isLoaded,
    bool? isLoadingPersonalMeeting,
    bool? isLoadingSecureMeeting,
    bool? isLoadingScheduledMeetings,
    bool? isLoadingUpcomingMeetings,
    bool? isLoadingCreateMeeting,
    bool? isLoadingDeleteMeeting,
    bool? isLoadingUpdateMeeting,
    bool? isLoadingScheduleMeeting,
    bool? goPersonalMeeting,
    bool? goSecureMeeting,
    bool? showEarlyAccessDialog,
    String? error,
    String? errorDetail,
    ResponseError? errorResponse,
    List<String>? data,
    List<FrbUpcomingMeeting>? upcomingMeetings,
    FrbUpcomingMeeting? personalMeeting,
    bool clearPersonalMeeting = false,

    ///
    List<FrbUpcomingMeeting>? meetinsDisplay,
    String? joinMeetingWithLinkUrl,
    List<DashboardCard>? infoCards,
    MeetUpcomingTab? upcomingTab,
    int? myMeetingsCount,
    int? myRoomsCount,
    String? createdMeetingLink,
    ScheduleMeetingData? scheduledMeetingData,
    FrbUpcomingMeeting? scheduledMeeting,
    bool resetScheduledMeeting = false,
    String? scheduledMeetingIcsContent,
    String? scheduledMeetingIcsTitle,
    bool? isSearchMode,
    String? searchQuery,
    List<FrbUpcomingMeeting>? searchResults,
    SortOptionMyRooms? sortOptionMyRooms,
    SortOptionMyMeetings? sortOptionMyMeetings,
    bool? showSignInCard,
    bool? isAnonymousUser,
    bool? offerFetchUserStateRetry,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      isLoaded: isLoaded ?? this.isLoaded,
      isLoadingPersonalMeeting:
          isLoadingPersonalMeeting ?? this.isLoadingPersonalMeeting,
      isLoadingSecureMeeting:
          isLoadingSecureMeeting ?? this.isLoadingSecureMeeting,
      isLoadingUpcomingMeetings:
          isLoadingUpcomingMeetings ?? this.isLoadingUpcomingMeetings,
      goPersonalMeeting: goPersonalMeeting ?? this.goPersonalMeeting,
      goSecureMeeting: goSecureMeeting ?? this.goSecureMeeting,
      showEarlyAccessDialog:
          showEarlyAccessDialog ?? this.showEarlyAccessDialog,
      isLoadingScheduledMeetings:
          isLoadingScheduledMeetings ?? this.isLoadingScheduledMeetings,
      isLoadingCreateMeeting:
          isLoadingCreateMeeting ?? this.isLoadingCreateMeeting,
      isLoadingDeleteMeeting:
          isLoadingDeleteMeeting ?? this.isLoadingDeleteMeeting,
      isLoadingUpdateMeeting:
          isLoadingUpdateMeeting ?? this.isLoadingUpdateMeeting,
      isLoadingScheduleMeeting:
          isLoadingScheduleMeeting ?? this.isLoadingScheduleMeeting,
      error: error ?? (resetError ? "" : this.error),
      errorDetail: errorDetail ?? (resetError ? null : this.errorDetail),
      errorResponse: errorResponse ?? (resetError ? null : this.errorResponse),
      data: data ?? this.data,
      upcomingMeetings: upcomingMeetings ?? this.upcomingMeetings,
      meetinsDisplay: meetinsDisplay ?? this.meetinsDisplay,
      personalMeeting: clearPersonalMeeting
          ? null
          : (personalMeeting ?? this.personalMeeting),
      joinMeetingWithLinkUrl:
          joinMeetingWithLinkUrl ?? this.joinMeetingWithLinkUrl,
      infoCards: infoCards ?? this.infoCards,
      upcomingTab: upcomingTab ?? this.upcomingTab,
      myMeetingsCount: myMeetingsCount ?? this.myMeetingsCount,
      myRoomsCount: myRoomsCount ?? this.myRoomsCount,
      createdMeetingLink: createdMeetingLink ?? this.createdMeetingLink,
      scheduledMeetingData: resetScheduledMeeting
          ? null
          : scheduledMeetingData ?? this.scheduledMeetingData,
      scheduledMeeting: resetScheduledMeeting
          ? null
          : scheduledMeeting ?? this.scheduledMeeting,
      scheduledMeetingIcsContent:
          scheduledMeetingIcsContent ?? this.scheduledMeetingIcsContent,
      scheduledMeetingIcsTitle:
          scheduledMeetingIcsTitle ?? this.scheduledMeetingIcsTitle,
      isSearchMode: isSearchMode ?? this.isSearchMode,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      sortOptionMyRooms: sortOptionMyRooms ?? this.sortOptionMyRooms,
      sortOptionMyMeetings: sortOptionMyMeetings ?? this.sortOptionMyMeetings,
      showSignInCard: showSignInCard ?? this.showSignInCard,
      isAnonymousUser: isAnonymousUser ?? this.isAnonymousUser,
      offerFetchUserStateRetry:
          offerFetchUserStateRetry ??
          (resetError ? false : this.offerFetchUserStateRetry),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isLoaded,
    isLoadingPersonalMeeting,
    isLoadingScheduledMeetings,
    isLoadingSecureMeeting,
    isLoadingUpcomingMeetings,
    isLoadingCreateMeeting,
    isLoadingDeleteMeeting,
    isLoadingUpdateMeeting,
    goPersonalMeeting,
    goSecureMeeting,
    showEarlyAccessDialog,
    error,
    errorResponse,
    data,
    joinMeetingWithLinkUrl,
    infoCards,

    upcomingTab,
    meetinsDisplay,
    personalMeeting,
    upcomingMeetings,
    myMeetingsCount,
    myRoomsCount,
    createdMeetingLink,
    isLoadingScheduleMeeting,
    scheduledMeetingData,
    scheduledMeeting,
    scheduledMeetingIcsContent,
    scheduledMeetingIcsTitle,
    isSearchMode,
    searchQuery,
    searchResults,
    sortOptionMyRooms,
    sortOptionMyMeetings,
    showSignInCard,
    isAnonymousUser,
    offerFetchUserStateRetry,
  ];
}
