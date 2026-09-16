import 'package:flutter/material.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/models/live_captions/caption_languages.dart';
import 'package:meet/views/scenes/room/live_captions/live_caption_language_sheet.dart';

/// Opens the spoken-language picker sheet.
///
/// Shared by the meeting settings row and the captions sheet header.
void showLiveCaptionLanguagePicker(
  BuildContext context, {
  required String selectedLanguage,
  required Future<void> Function(String language) onLanguageSelected,
}) {
  showLiveCaptionLanguageSheet(
    context,
    selectedLanguage: selectedLanguage,
    onLanguageSelected: onLanguageSelected,
  );
}

/// Spoken-language row inside the meeting settings video section.
class LiveCaptionLanguageSettingRow extends StatelessWidget {
  const LiveCaptionLanguageSettingRow({
    required this.selectedLanguage,
    required this.onLanguageSelected,
    this.isWriteInFlight = false,
    super.key,
  });

  final String selectedLanguage;
  final bool isWriteInFlight;
  final Future<void> Function(String language) onLanguageSelected;

  String get _resolvedSelectedLanguage =>
      isSupportedCaptionLanguageCode(selectedLanguage)
      ? selectedLanguage
      : LiveCaptionsConstants.defaultCaptionLanguage;

  String _displayLanguageLabel(String code) =>
      captionLanguageOptionForCode(code)?.displayName ??
      LiveCaptionsConstants.displayCaptionLanguage(code);

  void _openLanguagePicker(BuildContext context) {
    if (isWriteInFlight) {
      return;
    }
    showLiveCaptionLanguagePicker(
      context,
      selectedLanguage: selectedLanguage,
      onLanguageSelected: onLanguageSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openLanguagePicker(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.local.live_captions_spoken_language,
                  style: ProtonStyles.body2Regular(
                    color: context.colors.textWeak,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _displayLanguageLabel(_resolvedSelectedLanguage),
                  style: ProtonStyles.body1Medium(
                    color: context.colors.textNorm,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: context.colors.textWeak,
            size: 24,
          ),
        ],
      ),
    );
  }
}
