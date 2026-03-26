import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/search_button.dart';
import 'package:meet/views/components/sort_button.dart';
import 'package:meet/views/components/user_avatar_button.dart';

class AppNavBar extends StatelessWidget {
  const AppNavBar({
    required this.onSignInTap,
    required this.onSettingsTap,
    required this.onLogoutTap,
    required this.isSignedIn,
    required this.displayName,
    this.scrollController,
    this.hideActions = false,
    this.hideSettings = false,
    this.title,
    this.onSearchTap,
    this.pinned = true,
    this.isSearchMode = false,
    this.searchQuery = '',
    this.onSearchQueryChanged,
    this.onCancelSearch,
    this.onSortTap,
    this.searchBarReachedNavBar = false,
    super.key,
  });

  final VoidCallback onSignInTap;
  final VoidCallback onLogoutTap;
  final VoidCallback onSettingsTap;
  final bool isSignedIn;
  final String displayName;
  final ScrollController? scrollController;
  final bool hideActions;
  final bool hideSettings;
  final String? title;
  final VoidCallback? onSearchTap;
  final bool pinned;
  final bool isSearchMode;
  final String searchQuery;
  final ValueChanged<String>? onSearchQueryChanged;
  final VoidCallback? onCancelSearch;
  final VoidCallback? onSortTap;
  final bool searchBarReachedNavBar;

  @override
  Widget build(BuildContext context) {
    final controller = scrollController;
    if (controller == null) {
      return _buildSliverAppBar(context, false, null);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isScrolled = controller.hasClients && controller.offset > 0;
        final dividerOpacity = isScrolled ? 1.0 : 0.0;
        return _buildSliverAppBar(context, isScrolled, dividerOpacity);
      },
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    bool isScrolled,
    double? dividerOpacity,
  ) {
    final double blurSigma = isScrolled ? 6 : 0;
    final baseColor = context.colors.backgroundDark;
    final overlayColor = isScrolled
        ? baseColor.withValues(alpha: 0.4)
        : baseColor;
    final showTitle = title != null && title!.isNotEmpty;
    final topPadding = MediaQuery.of(context).padding.top;
    final totalHeight = kToolbarHeight + topPadding;

    return SliverPersistentHeader(
      pinned: pinned,
      delegate: _FixedNavBarDelegate(
        height: totalHeight,
        toolbarHeight: kToolbarHeight,
        topPadding: topPadding,
        blurSigma: blurSigma,
        overlayColor: overlayColor,
        dividerOpacity: dividerOpacity,
        showTitle: showTitle,
        title: title,
        hideSettings: hideSettings,
        hideActions: hideActions,
        onSettingsTap: onSettingsTap,
        onSearchTap: onSearchTap,
        isSignedIn: isSignedIn,
        displayName: displayName,
        onSignInTap: onSignInTap,
        onLogoutTap: onLogoutTap,
        isSearchMode: isSearchMode,
        searchQuery: searchQuery,
        onSearchQueryChanged: onSearchQueryChanged,
        onCancelSearch: onCancelSearch,
        isScrolled: isScrolled,
        onSortTap: onSortTap,
        searchBarReachedNavBar: searchBarReachedNavBar,
      ),
    );
  }
}

class _FixedNavBarDelegate extends SliverPersistentHeaderDelegate {
  _FixedNavBarDelegate({
    required this.height,
    required this.toolbarHeight,
    required this.topPadding,
    required this.blurSigma,
    required this.overlayColor,
    required this.dividerOpacity,
    required this.showTitle,
    required this.title,
    required this.hideSettings,
    required this.hideActions,
    required this.onSettingsTap,
    required this.onSearchTap,
    required this.isSignedIn,
    required this.displayName,
    required this.onSignInTap,
    required this.onLogoutTap,
    this.isSearchMode = false,
    this.searchQuery = '',
    this.onSearchQueryChanged,
    this.onCancelSearch,
    this.isScrolled = false,
    this.onSortTap,
    this.searchBarReachedNavBar = false,
  });

  final double height;
  final double toolbarHeight;
  final double topPadding;
  final double blurSigma;
  final Color overlayColor;
  final double? dividerOpacity;
  final bool showTitle;
  final String? title;
  final bool hideSettings;
  final bool hideActions;
  final VoidCallback onSettingsTap;
  final VoidCallback? onSearchTap;
  final bool isSignedIn;
  final String displayName;
  final VoidCallback onSignInTap;
  final VoidCallback onLogoutTap;
  final bool isSearchMode;
  final String searchQuery;
  final ValueChanged<String>? onSearchQueryChanged;
  final VoidCallback? onCancelSearch;
  final bool isScrolled;
  final VoidCallback? onSortTap;
  final bool searchBarReachedNavBar;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: height,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              Positioned.fill(child: Container(color: overlayColor)),
              SafeArea(
                bottom: false,
                child: Container(
                  height: toolbarHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: isSearchMode
                      ? _SearchModeContent(
                          searchQuery: searchQuery,
                          onSearchQueryChanged: onSearchQueryChanged,
                          onCancelSearch: onCancelSearch,
                        )
                      : _NormalModeContent(
                          showTitle: showTitle,
                          title: title,
                          hideSettings: hideSettings,
                          hideActions: hideActions,
                          onSettingsTap: onSettingsTap,
                          searchBarReachedNavBar: searchBarReachedNavBar,
                          onSearchTap: onSearchTap,
                          onSortTap: onSortTap,
                          isSignedIn: isSignedIn,
                          displayName: displayName,
                          onLogoutTap: onLogoutTap,
                          onSignInTap: onSignInTap,
                        ),
                ),
              ),
              if (dividerOpacity != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: dividerOpacity!,
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: context.colors.appBorderNorm,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_FixedNavBarDelegate oldDelegate) {
    return height != oldDelegate.height ||
        toolbarHeight != oldDelegate.toolbarHeight ||
        topPadding != oldDelegate.topPadding ||
        blurSigma != oldDelegate.blurSigma ||
        overlayColor != oldDelegate.overlayColor ||
        dividerOpacity != oldDelegate.dividerOpacity ||
        showTitle != oldDelegate.showTitle ||
        title != oldDelegate.title ||
        hideSettings != oldDelegate.hideSettings ||
        hideActions != oldDelegate.hideActions ||
        isSignedIn != oldDelegate.isSignedIn ||
        displayName != oldDelegate.displayName ||
        isSearchMode != oldDelegate.isSearchMode ||
        searchQuery != oldDelegate.searchQuery ||
        isScrolled != oldDelegate.isScrolled ||
        onSortTap != oldDelegate.onSortTap ||
        searchBarReachedNavBar != oldDelegate.searchBarReachedNavBar;
  }
}

/// Private class for the normal mode content.
class _NormalModeContent extends StatelessWidget {
  const _NormalModeContent({
    required this.showTitle,
    required this.title,
    required this.hideSettings,
    required this.hideActions,
    required this.onSettingsTap,
    required this.searchBarReachedNavBar,
    required this.onSearchTap,
    required this.onSortTap,
    required this.isSignedIn,
    required this.displayName,
    required this.onLogoutTap,
    required this.onSignInTap,
  });

  final bool showTitle;
  final String? title;
  final bool hideSettings;
  final bool hideActions;
  final VoidCallback onSettingsTap;
  final bool searchBarReachedNavBar;
  final VoidCallback? onSearchTap;
  final VoidCallback? onSortTap;
  final bool isSignedIn;
  final String displayName;
  final VoidCallback onLogoutTap;
  final VoidCallback onSignInTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: showTitle
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        textAlign: TextAlign.left,
                        title!,
                        key: const ValueKey('title'),
                        style: ProtonStyles.body1Semibold(
                          color: context.colors.textNorm,
                        ),
                      ),
                    )
                  : Row(
                      key: const ValueKey('logo'),
                      children: [
                        context.images.iconLeaveMeetingGuest.svg40(),
                        const SizedBox(width: 12),
                        Text(
                          // context.local.app_name,
                          "Meet",
                          style: ProtonStyles.body1Semibold(
                            color: context.colors.textNorm,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (!hideSettings) _SettingsButton(onTap: onSettingsTap),
        if (!hideActions) ...[
          const SizedBox(width: 8),
          if (searchBarReachedNavBar &&
              (onSearchTap != null || onSortTap != null)) ...[
            if (onSearchTap != null) SearchButton(onTap: onSearchTap!),
            if (onSearchTap != null && onSortTap != null)
              const SizedBox(width: 6),
            if (onSortTap != null) SortButton(onTap: onSortTap!),
          ] else if (isSignedIn)
            UserAvatarButton(displayName: displayName, onTap: onLogoutTap)
          else
            _SignInButton(onTap: onSignInTap),
          const SizedBox(width: 12),
        ],
      ],
    );
  }
}

/// Private class for the search mode content.
class _SearchModeContent extends StatelessWidget {
  const _SearchModeContent({
    required this.searchQuery,
    required this.onSearchQueryChanged,
    required this.onCancelSearch,
  });

  final String searchQuery;
  final ValueChanged<String>? onSearchQueryChanged;
  final VoidCallback? onCancelSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: context.colors.backgroundCard,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: context.colors.borderCard),
                borderRadius: BorderRadius.circular(200),
              ),
            ),
            child: Align(
              child: TextField(
                key: ValueKey('search_$searchQuery'),
                controller: TextEditingController(text: searchQuery)
                  ..selection = TextSelection.collapsed(
                    offset: searchQuery.length,
                  ),
                autofocus: true,
                style: ProtonStyles.body2Medium(color: context.colors.textNorm),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: context.local.search,
                  hintStyle: ProtonStyles.body2Medium(
                    color: context.colors.textHint,
                  ),
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: onSearchQueryChanged,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onCancelSearch,
          child: Text(
            context.local.cancel,
            style: ProtonStyles.body2Medium(color: context.colors.textNorm),
          ),
        ),
      ],
    );
  }
}

/// Private class for the settings button.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: ShapeDecoration(
        color: context.colors.backgroundCard,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: context.colors.borderCard),
          borderRadius: BorderRadius.circular(200),
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: context.images.iconSettings.svg20(color: context.colors.textWeak),
      ),
    );
  }
}

/// Private class for the sign in button.
class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 75),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.appBorderNorm),
      ),
      child: TextButton(
        onPressed: onTap,
        child: Text(
          context.local.sign_in,
          style: ProtonStyles.body2Medium(color: colors.textWeak),
        ),
      ),
    );
  }
}
