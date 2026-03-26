import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/info/info_row.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';

class _MeetingInfoPanelConstants {
  static const double headerHeight = 51.0;
  static const double horizontalPadding = 24.0;
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
  static const double borderColorAlpha = 0.03;
}

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

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(_MeetingInfoPanelConstants.borderRadiusMedium),
      topRight: Radius.circular(_MeetingInfoPanelConstants.borderRadiusMedium),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _MeetingInfoPanelConstants.borderColorAlpha,
        ),
      ),
      borderRadius: borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape && mobile;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(_MeetingInfoPanelConstants.borderRadiusLarge),
        topRight: Radius.circular(_MeetingInfoPanelConstants.borderRadiusLarge),
      ),
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: _buildContainerDecoration(context),
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: _buildScrollableContent(context, isLandscape),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent(BuildContext context, bool isLandscape) {
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight:
                  _MeetingInfoPanelConstants.headerHeight +
                  (!isLandscape ? 36.0 : 8.0),
              expandedHeight:
                  _MeetingInfoPanelConstants.headerHeight +
                  (!isLandscape ? 36.0 : 8.0),
              flexibleSpace: SizedBox.expand(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      _MeetingInfoPanelConstants.borderRadiusMedium,
                    ),
                    topRight: Radius.circular(
                      _MeetingInfoPanelConstants.borderRadiusMedium,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: context.colors.clear,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(
                              _MeetingInfoPanelConstants.borderRadiusMedium,
                            ),
                            topRight: Radius.circular(
                              _MeetingInfoPanelConstants.borderRadiusMedium,
                            ),
                          ),
                        ),
                      ),
                      child: _buildHeaderWithoutHandle(isLandscape),
                    ),
                  ),
                ),
              ),
            ),
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
                        borderRadius: BorderRadius.circular(24),
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
                        borderRadius: BorderRadius.circular(24),
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
        ),
        // Handle area that allows bottom sheet drag to work.
        // Wrap in AbsorbPointer so gestures bypass the content
        // and bubble up to the modal sheet for dragging.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height:
              _MeetingInfoPanelConstants.headerHeight +
              (!isLandscape ? 36.0 : 8.0),
          child: AbsorbPointer(
            child: Stack(
              children: [
                if (!isLandscape)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 36.0,
                    child: BottomSheetHandleBar(),
                  ),
                Positioned(
                  top: !isLandscape ? 36.0 : 8.0,
                  left: 0,
                  right: 0,
                  height: _MeetingInfoPanelConstants.headerHeight,
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: _MeetingInfoPanelConstants.horizontalPadding,
                      right: _MeetingInfoPanelConstants.horizontalPadding,
                      bottom: _MeetingInfoPanelConstants.horizontalPadding,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.local.meeting_info,
                        style: ProtonStyles.headline(
                          fontSize: 18,
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderWithoutHandle(bool isLandscape) {
    return Container(
      width: double.infinity,
      height:
          _MeetingInfoPanelConstants.headerHeight + (!isLandscape ? 36.0 : 8.0),
      padding: EdgeInsets.only(
        left: _MeetingInfoPanelConstants.horizontalPadding,
        right: _MeetingInfoPanelConstants.horizontalPadding,
        bottom: _MeetingInfoPanelConstants.horizontalPadding,
        top: !isLandscape ? 36.0 : 8.0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Info',
          style: ProtonStyles.headline(
            fontSize: 18,
            color: context.colors.textNorm,
          ),
        ),
      ),
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
