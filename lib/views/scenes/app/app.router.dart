import 'package:flutter/material.dart';
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/channels/platform.channel.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/services/simulation.service.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/app/app.splash.view.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/dashboard_event.dart';
import 'package:meet/views/scenes/dashboard/dashboard_page.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/prejoin/prejoin_bloc.dart';
import 'package:meet/views/scenes/prejoin/prejoin_page.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_event.dart';
import 'package:meet/views/scenes/simulation/simulation.bloc.dart';
import 'package:meet/views/scenes/simulation/simulation.view.dart';

enum RouteName { login, room, preJoin, simulation, dashboard }

extension RouteNameExt on RouteName {
  String get path => "/$name";
}

// App Router only handle the route navigation. sheets or dialogs should be handled by each view
class AppRouter {
  final ManagerFactory serviceManager;
  AppRouter(this.serviceManager);

  Route onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashView());
      case DashboardPage.routeName:
        final authBloc = AuthBloc(
          UserAgent(),
          serviceManager.get<PlatformChannelManager>(),
          serviceManager,
        )..add(AuthInitialized());
        final dashboardBloc = DashboardBloc()..add(InitDashboardEvent());
        return MaterialPageRoute(
          builder: (_) =>
              DashboardPage(dashboardBloc: dashboardBloc, authBloc: authBloc),
        );
      case PreJoinPage.routeName:
        final args = settings.arguments;

        if (args is Map<String, dynamic>) {
          final room = args['room'] as String;
          final password = args['password'] as String;
          final meetingLink = args['meetingLink'] as String;
          final displayName = args['displayName'] as String;
          final isVideoEnabled = args['isVideoEnabled'] as bool;
          final isE2EEEnabled = args['isE2EEEnabled'] as bool;
          final isAudioEnabled = args['isAudioEnabled'] as bool;
          final authBloc = args['authBloc'] as AuthBloc;

          final joinArgs = JoinArgs(
            meetingLink: FrbUpcomingMeeting.newForJoin(
              meetingLinkName: room,
              meetingPassword: password,
            ),
            meetingLinkUrl: meetingLink,
            displayName: displayName,
            e2eeKey: "e2eekey",
            isAudioEnabled: isAudioEnabled,
            isVideoEnabled: isVideoEnabled,
            e2ee: isE2EEEnabled,
          );

          final bloc = PreJoinBloc(UserAgent(), serviceManager);
          final view = PreJoinPage(
            bloc: bloc,
            authBloc: authBloc,
            joinArgs: joinArgs,
          );
          return MaterialPageRoute(
            builder: (_) => view,
            settings: RouteSettings(name: PreJoinPage.routeName),
          );
        }
        // Case 2: arguments is a custom object (e.g., MeetingArguments)
        final preJoinArgs = settings.arguments! as PreJoinArgs;
        final joinArgs = JoinArgs(
          type: PreJoinType.create,
          e2eeKey: "e2eekey",
          e2ee: true,
          meetingLink: null,
          isVideoEnabled: false,
          isAudioEnabled: false,
        );

        final bloc = PreJoinBloc(UserAgent(), serviceManager);
        final view = PreJoinPage(
          bloc: bloc,
          authBloc: preJoinArgs.authBloc,
          joinArgs: joinArgs,
        );
        return MaterialPageRoute(
          builder: (_) => view,
          settings: RouteSettings(name: PreJoinPage.routeName),
        );

      case '/simulation':
        final view = SimulationView(
          bloc: SimulationBloc(simulationService: SimulationService()),
        );

        return MaterialPageRoute(
          builder: (_) => view,
          settings: RouteSettings(name: "simulation"),
        );
      default:
        // Can't "skip" a default here: `onGenerateRoute` must return a Route.
        //
        // In some flows (e.g. inside an active meeting) we want unknown routes
        // to be ignored seamlessly (no UI interruption). Otherwise, show a dialog.
        final shouldIgnore = Coordinator.suppressUnknownRouteUi;
        return PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) {
            Future.microtask(() async {
              if (!context.mounted) return;

              if (!shouldIgnore) {
                final dialogContext =
                    Coordinator.rootNavigatorKey.currentContext ?? context;
                if (dialogContext.mounted) {
                  await showDialog<void>(
                    context: dialogContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Page not found'),
                      content: Text('Unknown route: ${settings.name}'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }

              // Pop the placeholder route immediately so the current UI stays.
              if (context.mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });

            return const SizedBox.shrink();
          },
          transitionsBuilder: (_, _, _, child) => child,
        );
    }
  }
}
