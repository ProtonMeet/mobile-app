import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/core/view.navigatior.identifiers.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';

abstract class MeetHomeEvent {}

class MeetHomeInitialized extends MeetHomeEvent {
  final JoinArgs args;

  MeetHomeInitialized(this.args);
}

class MeetHomeLogout extends MeetHomeEvent {}

class MeetHomeNavigate extends MeetHomeEvent {
  final NavID destination;

  MeetHomeNavigate(this.destination);
}

class MeetHomeState {
  final JoinArgs args;
  final bool isLoading;
  final String? error;

  MeetHomeState({required this.args, this.isLoading = false, this.error});

  MeetHomeState copyWith({JoinArgs? args, bool? isLoading, String? error}) {
    return MeetHomeState(
      args: args ?? this.args,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MeetHomeBloc extends Bloc<MeetHomeEvent, MeetHomeState> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  MeetHomeBloc()
    : super(
        MeetHomeState(
          args: JoinArgs(
            e2eeKey: '',
            meetingLink: FrbUpcomingMeeting.defaultValues(),
          ),
        ),
      ) {
    on<MeetHomeInitialized>(_onInitialized);
    on<MeetHomeLogout>(_onLogout);
    on<MeetHomeNavigate>(_onNavigate);
  }

  void _onInitialized(MeetHomeInitialized event, Emitter<MeetHomeState> emit) {
    emit(state.copyWith(args: event.args));
  }

  void _onLogout(MeetHomeLogout event, Emitter<MeetHomeState> emit) {
    // Handle logout logic here
    // This would typically involve clearing user data, tokens, etc.
    emit(state.copyWith(isLoading: true));
    // After logout, you might want to navigate to a different screen
    navigatorKey.currentState?.pushReplacementNamed('/welcome');
  }

  void _onNavigate(MeetHomeNavigate event, Emitter<MeetHomeState> emit) {
    // Handle navigation based on the destination
    switch (event.destination) {
      // Add cases for different navigation destinations
      default:
        break;
    }
  }

  // Coordinator-like methods
  void pushReplacement(Widget view) {
    navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (context) => view),
    );
  }

  void push(Widget view) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (context) => view),
    );
  }

  void pop() {
    navigatorKey.currentState?.pop();
  }

  // // ViewModel-like methods
  // Future<void> loadData() async {
  //   // Load any necessary data
  //   emit(state.copyWith(isLoading: true));
  //   try {
  //     // Perform data loading operations
  //     emit(state.copyWith(isLoading: false));
  //   } catch (e) {
  //     emit(state.copyWith(
  //       isLoading: false,
  //       error: e.toString(),
  //     ));
  //   }
  // }

  @override
  Future<void> close() {
    // Clean up resources
    return super.close();
  }
}
