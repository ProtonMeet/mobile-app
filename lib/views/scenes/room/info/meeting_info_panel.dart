import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/scenes/room/info/info_row.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/side_panel_widget.dart';

class MeetingInfoPanel extends StatefulWidget {
  final String meetingTitle;
  final String? meetingDate;
  final String? meetingTime;
  final int? participantsCount;

  const MeetingInfoPanel({
    required this.meetingTitle,
    this.meetingDate,
    this.meetingTime,
    this.participantsCount,
    super.key,
  });

  @override
  State<MeetingInfoPanel> createState() => _MeetingInfoPanelState();
}

class _MeetingInfoPanelState extends State<MeetingInfoPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoomSidePanelScroll(
      scrollController: _scrollController,
      header: Text(
        context.local.meeting_info,
        style: ProtonStyles.headline(
          fontSize: 18,
          color: context.colors.textNorm,
        ),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              /// Meeting details section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                decoration: ShapeDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    borderRadius: BorderRadius.circular(
                      RoomSidePanelLayout.borderRadiusMedium,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.local.meeting_details_section,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.textNorm,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InfoRow(
                      label: context.local.title_label,
                      value: widget.meetingTitle,
                      showBottomBorder: true,
                    ),
                    if (widget.meetingDate != null &&
                        widget.meetingDate!.isNotEmpty)
                      InfoRow(
                        label: context.local.date_label,
                        value: widget.meetingDate!,
                        showBottomBorder: true,
                      ),
                    if (widget.meetingTime != null &&
                        widget.meetingTime!.isNotEmpty)
                      InfoRow(
                        label: context.local.time_label,
                        value: widget.meetingTime!,
                        showBottomBorder: true,
                      ),
                    BlocSelector<RoomBloc, RoomState, String>(
                      selector: (state) => state.meetingLink,
                      builder: (context, meetingLink) {
                        return InfoRow(
                          label: context.local.invite_link_label,
                          value: meetingLink,
                          isLink: true,
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              /// MLS section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                decoration: ShapeDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    borderRadius: BorderRadius.circular(
                      RoomSidePanelLayout.borderRadiusMedium,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.local.messaging_layer_security,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.textNorm,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSecurityCodeRow(),

                    /// Participants count
                    BlocSelector<RoomBloc, RoomState, int>(
                      selector: (state) {
                        return state.mlsGroupLen;
                      },
                      builder: (context, participantsCount) {
                        return InfoRow(
                          showBottomBorder: true,
                          showTopBorder: true,
                          label: context.local.participants_label,
                          value: participantsCount.toString(),
                        );
                      },
                    ),
                    BlocSelector<RoomBloc, RoomState, String>(
                      selector: (state) => state.epoch,
                      builder: (context, epoch) {
                        return InfoRow(
                          label: context.local.epoch_label,
                          value: epoch,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityCodeRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: BlocSelector<RoomBloc, RoomState, String>(
        selector: (state) => state.displayCode,
        builder: (context, displayCode) {
          final formattedCode = _formatSecurityCode(displayCode);
          // Split code into pairs and alternate colors
          final parts = formattedCode.split(' ');
          final textSpans = <TextSpan>[];

          for (int i = 0; i < parts.length; i++) {
            final isEven = i % 2 == 0;
            textSpans.add(
              TextSpan(
                text: i > 0 ? ' ${parts[i]}' : parts[i],
                style: ProtonStyles.body1Medium(
                  color: isEven
                      ? context.colors.textNorm
                      : context.colors.textWeak,
                ),
              ),
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  context.local.security_code_label,
                  style: ProtonStyles.body1Medium(
                    color: context.colors.textWeak,
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: displayCode));
                    if (context.mounted) {
                      LocalToast.showToast(
                        context,
                        context.local.copied_to_clipboard,
                      );
                    }
                  },
                  child: Text.rich(TextSpan(children: textSpans)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatSecurityCode(String code) {
    if (code.isEmpty) return '';
    // Format as pairs separated by spaces
    final buffer = StringBuffer();
    for (int i = 0; i < code.length; i += 4) {
      if (i > 0) buffer.write(' ');
      final end = (i + 4 < code.length) ? i + 4 : code.length;
      buffer.write(code.substring(i, end));
    }
    return buffer.toString();
  }
}
