import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/external.url.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/locale.provider.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/dropdown.button.v3.dart';
import 'package:meet/views/scenes/settings/debug/debug_sections.dart';
import 'package:meet/views/scenes/settings/settings_action_item.dart';
import 'package:meet/views/scenes/settings/settings_section_header.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:provider/provider.dart';

class AppSettingsBottomSheet extends StatelessWidget {
  const AppSettingsBottomSheet({
    required this.maxHeight,
    required this.isLandscape,
    this.authBloc,
    super.key,
  });

  final double maxHeight;
  final bool isLandscape;
  final AuthBloc? authBloc;

  static void show(BuildContext context, {AuthBloc? authBloc}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (ctx) {
        final isLandscape = ctx.isLandscape;
        final maxHeight = isLandscape ? ctx.height - 20 : ctx.height - 100;
        return AppSettingsBottomSheet(
          maxHeight: maxHeight,
          isLandscape: isLandscape,
          authBloc: authBloc,
        );
      },
    );
  }

  Future<void> _onReportProblem(BuildContext context) async {
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

    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      modalOnBackdropTap: () => Navigator.of(context).maybePop(),
      modalMaxHeight: maxHeight,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      borderSideAlpha: 0.04,
      sheetBackgroundColor: context.colors.interActionWeakMinor3.withValues(
        alpha: 0.8,
      ),
      slivers: [
        SliverToBoxAdapter(child: _buildTitle(context)),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              SettingsSectionHeader(
                title: context.local.settings_section_general,
              ),
              _buildLanguageCard(context),
              const SizedBox(height: 16),
              SettingsSectionHeader(
                title: context.local.settings_section_support,
              ),
              if (isSignedIn) ...[
                SettingsActionItem(
                  title: context.local.report_a_problem,
                  onTap: () => _onReportProblem(context),
                  isFirst: true,
                  suffix: Icon(
                    Icons.bug_report_outlined,
                    color: context.colors.textNorm.withValues(alpha: 0.5),
                    size: 22,
                  ),
                ),
                const SizedBox(height: 1),
              ],
              SettingsActionItem(
                title: context.local.knowledge_base,
                onTap: () => ExternalUrl.shared.launchProtonHelpCenter(),
                isFirst: !isSignedIn,
                isLast: true,
              ),
              const SizedBox(height: 16),
              SettingsSectionHeader(
                title: context.local.settings_section_legal,
              ),
              SettingsActionItem(
                title: context.local.privacy_policy,
                onTap: () => ExternalUrl.shared.lanuchPrivacy(),
                isFirst: true,
              ),
              const SizedBox(height: 1),
              SettingsActionItem(
                title: context.local.terms_and_conditions,
                onTap: () => ExternalUrl.shared.lanuchTerms(),
                isLast: true,
              ),

              if (kDebugMode) ...[
                ...AppSettingsDebugSection.items(context, authBloc),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageCard(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          final localeItems = [
            LocaleProvider.systemDefault,
            ...S.supportedLocales
                .where((e) => !e.toLanguageTag().contains('zh'))
                .map((e) => e.toLanguageTag()),
          ];
          final selected = localeItems.contains(localeProvider.language)
              ? localeProvider.language
              : LocaleProvider.systemDefault;
          final itemsText = [
            LocaleProvider.localeName(LocaleProvider.systemDefault, context),
            ...S.supportedLocales
                .where((e) => !e.toLanguageTag().contains('zh'))
                .map(
                  (e) => LocaleProvider.localeName(e.toLanguageTag(), context),
                ),
          ];

          return Material(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                DropdownButtonV3.showOptionsBottomSheet<String>(
                  context,
                  items: localeItems,
                  itemsText: itemsText,
                  selected: selected,
                  onChanged: localeProvider.toggleChangeLocale,
                  labelText: context.local.languages,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.local.languages,
                            style: ProtonStyles.body2Medium(
                              color: context.colors.textWeak,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            LocaleProvider.localeName(selected, context),
                            style: ProtonStyles.body1Medium(
                              color: context.colors.textNorm,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: context.colors.textWeak,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          context.local.app_settings_title,
          style: ProtonStyles.headline(
            fontSize: 18,
            color: context.colors.textNorm,
          ),
        ),
      ),
    );
  }
}
