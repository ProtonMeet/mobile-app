import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/external.url.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/locale.provider.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/dropdown.button.v3.dart';
import 'package:meet/views/components/settings/settings_nav_row.dart';
import 'package:meet/views/components/settings/settings_preview_nav_row.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/scenes/settings/app_settings_bloc.dart';
import 'package:meet/views/scenes/settings/app_settings_event.dart';
import 'package:meet/views/scenes/settings/app_settings_state.dart';
import 'package:meet/views/scenes/settings/debug/debug_sections.dart';
import 'package:meet/views/scenes/settings/meetings/app_settings_meetings_section.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:provider/provider.dart';

class AppSettingsBottomSheet extends StatelessWidget {
  const AppSettingsBottomSheet({
    required this.maxHeight,
    required this.isLandscape,
    required this.appSettingsBloc,
    this.authBloc,
    super.key,
  });

  final double maxHeight;
  final bool isLandscape;
  final AppSettingsBloc appSettingsBloc;
  final AuthBloc? authBloc;

  static void show(
    BuildContext context, {
    required AppSettingsBloc appSettingsBloc,
    AuthBloc? authBloc,
  }) {
    // Re-read flags and the server-side waiting-room default on every open.
    appSettingsBloc.add(
      AppSettingsInitialized(isPaidUser: authBloc?.state.isPaidUser ?? false),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.clear,
      barrierColor: context.colors.black.withValues(alpha: 0.1),
      builder: (ctx) {
        final isLandscape = ctx.isLandscape;
        final maxHeight = isLandscape ? ctx.height - 20 : ctx.height - 100;
        return AppSettingsBottomSheet(
          maxHeight: maxHeight,
          isLandscape: isLandscape,
          appSettingsBloc: appSettingsBloc,
          authBloc: authBloc,
        );
      },
    );
  }

  Future<void> _onReportProblem() async {
    final bloc = authBloc;
    if (bloc == null) {
      ExternalUrl.shared.launchProtonHelpCenter();
      return;
    }
    await bloc.reportProblem();
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = authBloc?.state.isSignedIn ?? false;

    return BlocConsumer<AppSettingsBloc, AppSettingsState>(
      bloc: appSettingsBloc,
      listenWhen: (previous, current) =>
          current.waitingRoomError != null &&
          previous.waitingRoomError != current.waitingRoomError,
      listener: (context, state) {
        LocalToast.showToast(context, state.waitingRoomError!);
      },
      builder: (context, state) {
        return BaseBottomSheetV2.withPinnedSliverScroll(
          isLandscape: isLandscape,
          modalOnBackdropTap: () => Navigator.of(context).maybePop(),
          modalMaxHeight: maxHeight,
          innerEnableHandleDragPassthrough: false,
          outerEnableHandleDragPassthrough: true,
          borderSideAlpha: 0.04,
          toolbarHeight: _AppSettingsPinnedHeader.height(
            isLandscape: isLandscape,
          ),
          flexibleSpaceChild: _AppSettingsPinnedHeader(
            isLandscape: isLandscape,
          ),
          sheetBackgroundColor: context.colors.interActionWeakMinor3.withValues(
            alpha: 0.8,
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildGeneralSection(context, state),
                  AppSettingsMeetingsSection(
                    appSettingsBloc: appSettingsBloc,
                    isSignedIn: isSignedIn,
                  ),
                  _buildSupportSection(context, isSignedIn: isSignedIn),
                  _buildLegalSection(context),
                  if (kDebugMode)
                    ...AppSettingsDebugSection.items(context, authBloc),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGeneralSection(BuildContext context, AppSettingsState state) {
    return SettingsSection(
      title: context.local.settings_section_general,
      rows: [
        if (state.showPreviewSettings)
          SettingsPreviewNavRow(
            overline: context.local.appearance,
            title: context.local.appearance_dark,
          ),
        const _LanguageRow(),
      ],
    );
  }

  Widget _buildSupportSection(
    BuildContext context, {
    required bool isSignedIn,
  }) {
    return SettingsSection(
      title: context.local.settings_section_support,
      rows: [
        SettingsNavRow(
          title: context.local.knowledge_base,
          onTap: () => ExternalUrl.shared.launchProtonHelpCenter(),
        ),
        if (isSignedIn)
          SettingsNavRow(
            title: context.local.report_a_problem,
            onTap: _onReportProblem,
          ),
      ],
    );
  }

  Widget _buildLegalSection(BuildContext context) {
    return SettingsSection(
      title: context.local.settings_section_legal,
      rows: [
        SettingsNavRow(
          title: context.local.privacy_policy,
          onTap: () => ExternalUrl.shared.lanuchPrivacy(),
        ),
        SettingsNavRow(
          title: context.local.terms_and_conditions,
          onTap: () => ExternalUrl.shared.lanuchTerms(),
        ),
      ],
    );
  }
}

/// Drag handle + title, pinned so the title stays visible while sections scroll.
///
/// Pass [height] as the sheet's `toolbarHeight`: the pinned header is laid out
/// under tight constraints, so a mismatch overflows or clips.
class _AppSettingsPinnedHeader extends StatelessWidget {
  const _AppSettingsPinnedHeader({required this.isLandscape});

  /// Handle bar (4px bar + 8px vertical padding) above the title row.
  static const double _handleHeight = 20;

  /// Extra breathing room above the handle when the sheet is nearly full-height.
  static const double _landscapeHandleInset = 4;

  static const double _titleFontSize = 18;
  static const EdgeInsets _titlePadding = EdgeInsets.fromLTRB(24, 12, 24, 24);

  /// [ProtonStyles.headline] pins the line box to 24px at any font size.
  static const double _titleLineHeight = 24;

  static double height({required bool isLandscape}) =>
      _handleHeight +
      _titleLineHeight +
      _titlePadding.vertical +
      (isLandscape ? _landscapeHandleInset : 0);

  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: isLandscape ? _landscapeHandleInset : 0,
          ),
          child: const BottomSheetHandleBar(),
        ),
        Padding(
          padding: _titlePadding,
          child: Text(
            context.local.app_settings_title,
            style: ProtonStyles.headline(
              fontSize: _titleFontSize,
              color: context.colors.textNorm,
            ),
          ),
        ),
      ],
    );
  }
}

/// App language, backed by [LocaleProvider] since the locale is app-wide state.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow();

  /// Chinese locales are translated but not released yet.
  static Iterable<String> get _languageTags => S.supportedLocales
      .where((locale) => !locale.toLanguageTag().contains('zh'))
      .map((locale) => locale.toLanguageTag());

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final items = [LocaleProvider.systemDefault, ..._languageTags];
        final selected = items.contains(localeProvider.language)
            ? localeProvider.language
            : LocaleProvider.systemDefault;

        return SettingsNavRow(
          overline: context.local.languages,
          title: LocaleProvider.localeName(selected, context),
          onTap: () => DropdownButtonV3.showOptionsBottomSheet<String>(
            context,
            items: items,
            itemsText: items
                .map((tag) => LocaleProvider.localeName(tag, context))
                .toList(),
            selected: selected,
            onChanged: localeProvider.toggleChangeLocale,
            labelText: context.local.languages,
          ),
        );
      },
    );
  }
}
