import 'package:flutter/material.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/models/live_captions/caption_languages.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

class _LiveCaptionLanguageSheetLayout {
  static const double topCornerRadius = 24;
  static const double horizontalPadding = 16;
  static const double itemBorderRadius = 12;
  static const double itemVerticalPadding = 14;
  static const double itemSpacing = 4;
  static const double maxHeightFraction = 0.85;
}

/// Dark spoken-language picker sheet with drag handle, selected-row highlight,
/// and trailing check icon (matches live captions design spec).
class LiveCaptionLanguageSheet extends StatelessWidget {
  const LiveCaptionLanguageSheet({
    required this.selectedLanguage,
    required this.onLanguageSelected,
    super.key,
  });

  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;

  String get _resolvedSelectedLanguage =>
      _resolveLanguageCode(selectedLanguage);

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.sizeOf(context).height *
        _LiveCaptionLanguageSheetLayout.maxHeightFraction;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomSheetHandleBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _LiveCaptionLanguageSheetLayout.horizontalPadding,
                24,
                _LiveCaptionLanguageSheetLayout.horizontalPadding,
                16,
              ),
              child: Text(
                context.local.live_captions_spoken_language,
                textAlign: TextAlign.center,
                style: ProtonStyles.body2Medium(color: context.colors.textWeak),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  _LiveCaptionLanguageSheetLayout.horizontalPadding,
                  0,
                  _LiveCaptionLanguageSheetLayout.horizontalPadding,
                  16,
                ),
                itemCount: supportedCaptionLanguages.length,
                separatorBuilder: (_, __) => const SizedBox(
                  height: _LiveCaptionLanguageSheetLayout.itemSpacing,
                ),
                itemBuilder: (context, index) {
                  final option = supportedCaptionLanguages[index];
                  final isSelected = option.code == _resolvedSelectedLanguage;
                  return _LanguageOptionTile(
                    label: option.displayName,
                    isSelected: isSelected,
                    onTap: () => onLanguageSelected(option.code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? context.colors.interActionNormMinor3
          : Colors.transparent,
      borderRadius: BorderRadius.circular(
        _LiveCaptionLanguageSheetLayout.itemBorderRadius,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(
          _LiveCaptionLanguageSheetLayout.itemBorderRadius,
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _LiveCaptionLanguageSheetLayout.horizontalPadding,
            vertical: _LiveCaptionLanguageSheetLayout.itemVerticalPadding,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: ProtonStyles.body2Regular(
                    color: context.colors.textNorm,
                  ),
                ),
              ),
              if (isSelected)
                context.images.iconCheckmark.svg20(
                  color: context.colors.interActionNormMajor1,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the spoken-language bottom sheet.
void showLiveCaptionLanguageSheet(
  BuildContext context, {
  required String selectedLanguage,
  required Future<void> Function(String language) onLanguageSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.backgroundDark,
    isScrollControlled: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(_LiveCaptionLanguageSheetLayout.topCornerRadius),
      ),
    ),
    builder: (sheetContext) {
      return LiveCaptionLanguageSheet(
        selectedLanguage: selectedLanguage,
        onLanguageSelected: (language) {
          Navigator.of(sheetContext).pop();
          onLanguageSelected(language);
        },
      );
    },
  );
}

String _resolveLanguageCode(String language) {
  final codes = supportedCaptionLanguages
      .map((option) => option.code)
      .toList(growable: false);
  if (codes.contains(language)) {
    return language;
  }
  return LiveCaptionsConstants.defaultCaptionLanguage;
}
