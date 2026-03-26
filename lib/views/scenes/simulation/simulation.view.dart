import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/scenes/simulation/simulation.bloc.dart';
import 'package:meet/views/scenes/simulation/simulation.event.dart';
import 'package:meet/views/scenes/simulation/simulation.state.dart';

class SimulationView extends StatelessWidget {
  final SimulationBloc bloc;

  const SimulationView({required this.bloc, super.key});

  @override
  Widget build(BuildContext context) {
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final appBarHeight = isMacOS ? 80.0 : kToolbarHeight;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: AppBar(
          toolbarHeight: appBarHeight,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.colors.textNorm),
            onPressed: () async {
              final shouldClose = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(
                    'Close Simulation',
                    style: ProtonStyles.headline(
                      color: context.colors.textNorm,
                    ),
                  ),
                  content: Text(
                    'Are you sure you want to close all rooms and exit simulation mode?',
                    style: ProtonStyles.body1Regular(
                      color: context.colors.textNorm,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        'Cancel',
                        style: ProtonStyles.body1Medium(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        'Yes, Close All',
                        style: ProtonStyles.body1Medium(
                          color: context.colors.protonBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (shouldClose == true) {
                bloc.add(CloseAllRooms());
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
          title: Padding(
            padding: EdgeInsets.only(top: isMacOS ? 8.0 : 0.0),
            child: Text(
              'Simulation Mode',
              style: ProtonStyles.headline(
                color: context.colors.textNorm,
                fontSize: isMacOS ? 24.0 : 22.0,
              ),
            ),
          ),
          backgroundColor: context.colors.backgroundNorm,
        ),
      ),
      body: BlocProvider.value(
        value: bloc,
        child: BlocBuilder<SimulationBloc, SimulationState>(
          builder: (context, state) {
            return Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  'Create and manage simulated rooms for testing',
                  style: ProtonStyles.body2Regular(
                    color: context.colors.textWeak,
                  ),
                  textAlign: TextAlign.center,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'Simulated Rooms',
                          style: ProtonStyles.subheadline(
                            color: context.colors.textNorm,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...state.rooms.entries.map((entry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Room ${entry.key} (${entry.value.length} users)',
                                style: ProtonStyles.subheadline(
                                  color: context.colors.textNorm,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...entry.value.map((participantName) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.colors.backgroundNorm,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.person,
                                          color: context.colors.textNorm,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            participantName,
                                            style: ProtonStyles.body1Medium(
                                              color: context.colors.textNorm,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.backgroundNorm,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                labelText: 'Room ID',
                                border: OutlineInputBorder(),
                              ),
                              controller: TextEditingController(
                                text: state.roomId,
                              ),
                              onChanged: (value) {
                                bloc.add(RoomIdChanged(value));
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          DropdownButton<int>(
                            value: state.participantCount,
                            items: List.generate(20, (index) => index + 1)
                                .map(
                                  (number) => DropdownMenuItem(
                                    value: number,
                                    child: Text('$number'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                bloc.add(ParticipantCountChanged(value));
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: state.enableVideo,
                            onChanged: (value) {
                              if (value != null) {
                                bloc.add(VideoEnabledChanged(value));
                              }
                            },
                          ),
                          Text('Enable Video'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ButtonV5(
                        onPressed: state.isConnecting
                            ? null
                            : () {
                                bloc.add(
                                  AddParticipantAndConnect(
                                    displayName: 'Simulated User ',
                                    roomId: state.roomId,
                                    participantCount: state.participantCount,
                                    enableVideo: state.enableVideo,
                                  ),
                                );
                              },
                        text: state.isConnecting
                            ? 'Connecting...'
                            : 'Add Participant',
                        width: MediaQuery.of(context).size.width / 3,
                        backgroundColor: state.isConnecting
                            ? context.colors.protonBlue.withValues(alpha: 128)
                            : context.colors.protonBlue,
                        borderColor: context.colors.clear,
                        textStyle: ProtonStyles.body1Medium(
                          color: context.colors.textInverted,
                        ),
                        height: 55,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
