import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';

String formatMeetingExpiryDuration(Duration duration) {
  final total = duration.inSeconds.clamp(0, double.maxFinite.toInt());
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;

  String pad(int n) => n.toString().padLeft(2, '0');

  if (h > 0) {
    return '${pad(h)}:${pad(m)}:${pad(s)}';
  }
  return '${pad(m)}:${pad(s)}';
}

class MeetingExpiryBanner extends StatefulWidget {
  final DateTime expirationTime;
  final VoidCallback? onDismiss;

  const MeetingExpiryBanner({
    required this.expirationTime,
    super.key,
    this.onDismiss,
  });

  @override
  State<MeetingExpiryBanner> createState() => _MeetingExpiryBannerState();
}

class _MeetingExpiryBannerState extends State<MeetingExpiryBanner> {
  late Timer _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final diff = widget.expirationTime.difference(DateTime.now());
    setState(() {
      _timeLeft = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.backgroundSecondary,
        border: Border.all(color: context.colors.appBorderNorm),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.onDismiss != null)
            Positioned(
              right: 0,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: context.colors.textNorm,
                ),
                onPressed: widget.onDismiss,
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              context.local.meeting_expiry_banner_title_prefix,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.textNorm,
                          ),
                        ),
                        TextSpan(
                          text: formatMeetingExpiryDuration(_timeLeft),
                          style:
                              ProtonStyles.body2Medium(
                                color: context.colors.textNorm,
                              ).copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    context.local.meeting_expiry_banner_description,
                    textAlign: TextAlign.center,
                    style: ProtonStyles.bodySmallSemibold(
                      color: context.colors.textWeak,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Connects [MeetingExpiryBanner] to [RoomBloc] meeting expiration state.
class MeetingExpiryBannerHost extends StatefulWidget {
  const MeetingExpiryBannerHost({super.key});

  @override
  State<MeetingExpiryBannerHost> createState() =>
      _MeetingExpiryBannerHostState();
}

class _MeetingExpiryBannerHostState extends State<MeetingExpiryBannerHost> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<RoomBloc, RoomState, (DateTime?, bool, bool)>(
      selector: (state) => (
        state.meetingExpirationTime,
        state.isFreeMeeting,
        state.isRoomInitialized && state.isTrackInitialized,
      ),
      builder: (context, data) {
        final expirationTime = data.$1;
        final isFreeMeeting = data.$2;
        final isRoomReady = data.$3;

        if (!isRoomReady || !isFreeMeeting || expirationTime == null) {
          return const SizedBox.shrink();
        }

        final remaining = expirationTime.difference(DateTime.now());
        if (remaining <= Duration.zero ||
            remaining > kMeetingExpirationWarningThreshold) {
          return const SizedBox.shrink();
        }

        if (_dismissed) {
          return const SizedBox.shrink();
        }

        return MeetingExpiryBanner(
          expirationTime: expirationTime,
          onDismiss: () => setState(() => _dismissed = true),
        );
      },
    );
  }
}
