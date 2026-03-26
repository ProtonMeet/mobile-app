import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

enum LinkStatus { empty, invalid, valid }

class LinkTextField extends StatelessWidget {
  const LinkTextField({
    required this.controller,
    required this.focusNode,
    required this.status,
    required this.hintText,
    required this.onSubmitted,
    required this.onCopy,
    this.message,
    this.editable = true,
    this.autofocus = true,
    this.displayColors,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final LinkStatus status;
  final String? message;
  final String hintText;
  final bool editable;
  final bool autofocus;
  final ParticipantDisplayColors? displayColors;
  final VoidCallback onSubmitted;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final borderNorm = context.colors.appBorderNorm;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: ShapeDecoration(
          color: context.colors.backgroundCard,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: status == LinkStatus.invalid
                  ? context.colors.signalDanger
                  : borderNorm,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.local.scheduled_meeting_link,
              style: ProtonStyles.body2Medium(
                color: context.colors.textDisable,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: editable,
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => onSubmitted(),
                    decoration: InputDecoration(
                      hintText: hintText,
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: ProtonStyles.body2Regular(
                      color: context.colors.textNorm,
                    ),
                  ),
                ),

                /// Copy button when not editable
                if (!editable) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: context.images.iconCopy.svg20(
                          color:
                              displayColors?.profileTextColor ??
                              context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            /// helper / error text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: status == LinkStatus.invalid && message != null
                  ? Text(
                      message!,
                      key: const ValueKey('link_text_field_error'),
                      style: ProtonStyles.captionSemibold(
                        color: context.colors.signalDangerMajor3,
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('link_text_field_empty'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
