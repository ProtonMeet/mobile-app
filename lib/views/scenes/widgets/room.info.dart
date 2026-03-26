import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/button.inline.dart';
import 'package:meet/views/components/textfield.text.v2.dart';

class RoomInfo extends StatefulWidget {
  final String roomId;
  final void Function(BuildContext) showAllStats;

  const RoomInfo({required this.roomId, required this.showAllStats, super.key});

  @override
  State<RoomInfo> createState() => _RoomInfoState();
}

class _RoomInfoState extends State<RoomInfo> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.backgroundNorm,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  // Message list
                  const SizedBox(height: 70),
                  Expanded(child: _buildRoomInfo(context)),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.backgroundNorm.withValues(
                          alpha: 0.3,
                        ),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFF2E2E2E)),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ButtonInline(
                            text: context.local.invite_participant,
                            onPressed: () {},
                            width: constraints.maxWidth,
                            height: 48,
                            borderRadius: 40,
                            textColor: context.colors.textInverted,
                            backgroundColor: context.colors.protonBlue,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Chat header
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.backgroundNorm.withValues(alpha: 0.7),
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFF2E2E2E)),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: _buildHeader(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Text(
          context.local.meeting_detail,
          style: ProtonStyles.body1Semibold(color: context.colors.textNorm),
        ),
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
        ),
      ],
    );
  }

  Widget _buildRoomInfo(BuildContext context) {
    final meetingUrl = appConfig.apiEnv.baseUrl;
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 16),
          TextFieldTextV2(
            textController: TextEditingController(text: widget.roomId),
            myFocusNode: FocusNode(),
            labelText: context.local.meeting_link,
            backgroundColor: context.colors.backgroundNorm,
            textInputAction: TextInputAction.done,
            validation: (String value) {
              return "";
            },
            showFinishButton: false,
            onFinish: () {},
            readOnly: true,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: "$meetingUrl?room_id=${widget.roomId}"),
                  ).then((_) {
                    if (context.mounted) {
                      LocalToast.showToast(
                        context,
                        context.local.copied_to_clipboard,
                      );
                    }
                  });
                },
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: context.colors.backgroundNorm,
                  child: Icon(
                    Icons.copy,
                    color: context.colors.textNorm,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              return ButtonInline(
                text: "Show all stats (debug mode)",
                onPressed: () {
                  widget.showAllStats(context);
                },
                width: constraints.maxWidth - 32,
                height: 48,
                borderRadius: 40,
                textColor: context.colors.textInverted,
                backgroundColor: context.colors.protonBlue,
              );
            },
          ),
        ],
      ),
    );
  }
}
