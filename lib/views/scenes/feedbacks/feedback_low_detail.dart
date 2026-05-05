import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/managers/services/call.quality.form.dart';

/// Low-rating body (stars row, checklist, optional comment, submit / skip).
///
/// Body is a [SliverToBoxAdapter] so the sheet scrolls when the keyboard opens.
/// [optionalCommentFocus] focuses the optional comment field when expanded.
/// [submitButtonKey] is used to scroll the submit control into view above the keyboard.
List<Widget> buildLeftMeetingLowFeedbackSlivers({
  required BuildContext context,
  required int? rating,
  required Set<String> selectedLabels,
  required void Function(String label) onOptionToggled,
  required bool optionalDetailsExpanded,
  required VoidCallback onToggleOptionalDetails,
  required void Function(String text) onCommentChanged,
  required bool submitting,
  required VoidCallback onSubmit,
  required VoidCallback onSkip,
  required FocusNode optionalCommentFocus,
  required GlobalKey submitButtonKey,
}) {
  final options = meetingFeedbackAllOptionLabels(context);
  return [
    SliverToBoxAdapter(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final value = i + 1;
                  final r = rating;
                  final on = r != null && value <= r;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: on
                        ? context.images.iconFeedbackStar.svg24()
                        : context.images.iconFeedbackStarBorder.svg24(),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Text(
                context.local.call_quality_what_went_wrong,
                textAlign: TextAlign.center,
                style: ProtonStyles.headline(color: context.colors.textNorm),
              ),
              const SizedBox(height: 8),
              Text(
                context.local.call_quality_problem_subtitle,
                textAlign: TextAlign.center,
                style: ProtonStyles.body2Medium(color: context.colors.textWeak),
              ),
              const SizedBox(height: 24),
              ...options.map(
                (label) => _LowFeedbackOptionRow(
                  label: label,
                  selected: selectedLabels.contains(label),
                  onTap: () => onOptionToggled(label),
                ),
              ),
              InkWell(
                onTap: onToggleOptionalDetails,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                  child: Row(
                    children: [
                      Icon(
                        optionalDetailsExpanded ? Icons.remove : Icons.add,
                        size: 16,
                        color: context.colors.interActionNorm,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.local.call_quality_add_optional_details,
                        style: ProtonStyles.body2Semibold(
                          color: context.colors.interActionNorm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (optionalDetailsExpanded)
                SizedBox(
                  height: 120,
                  child: TextField(
                    focusNode: optionalCommentFocus,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: onCommentChanged,
                    style: ProtonStyles.body2Regular(
                      color: context.colors.textNorm,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      hintText: context.local.call_quality_share_more_details,
                      hintStyle: ProtonStyles.body2Regular(
                        color: context.colors.textWeak,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: context.colors.borderCard,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: context.colors.borderCard,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                key: submitButtonKey,
                height: 60,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.interActionNormMajor1,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.16),
                  ),
                  onPressed: submitting ? null : onSubmit,
                  child: submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          context.local.submit,
                          style: ProtonStyles.body1Semibold(
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                width: double.infinity,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    borderRadius: BorderRadius.circular(200),
                  ),
                  child: InkWell(
                    onTap: submitting ? null : onSkip,
                    borderRadius: BorderRadius.circular(200),
                    child: Center(
                      child: Text(
                        context.local.skip,
                        style: ProtonStyles.body1Semibold(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  ];
}

class _LowFeedbackOptionRow extends StatelessWidget {
  const _LowFeedbackOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 52,
        child: Material(
          color: selected ? context.colors.interActionWeak : Colors.transparent,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: context.colors.borderCard),
            borderRadius: BorderRadius.circular(24),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textNorm,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
