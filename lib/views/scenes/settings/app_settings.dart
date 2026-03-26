import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

class _AppSettingsConstants {
  static const double headerHeight = 51.0;
  static const double handleHeight = 36.0;
  static const double spacingMedium = 8.0;
}

class AppSettingsBottomSheet extends StatelessWidget {
  const AppSettingsBottomSheet({
    this.dragScrollController,
    this.authBloc,
    super.key,
  });

  final ScrollController? dragScrollController;
  final AuthBloc? authBloc;

  static void show(BuildContext context, {AuthBloc? authBloc}) {
    final initialSize = 0.95;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: 0.6,
        maxChildSize: initialSize,
        builder: (context, dragScrollController) => SizedBox(
          height: context.height,
          child: AppSettingsBottomSheet(
            dragScrollController: dragScrollController,
            authBloc: authBloc,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(40),
        topRight: Radius.circular(40),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 24),
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: context.colors.interActionWeakMinor3.withValues(alpha: 0.8),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
            ),
          ),
          child: AppSettingsContent(
            dragScrollController: dragScrollController,
            authBloc: authBloc,
          ),
        ),
      ),
    );
  }
}

class AppSettingsContent extends StatefulWidget {
  const AppSettingsContent({
    this.dragScrollController,
    this.authBloc,
    super.key,
  });

  final ScrollController? dragScrollController;
  final AuthBloc? authBloc;

  @override
  State<AppSettingsContent> createState() => _AppSettingsContentState();
}

class _AppSettingsContentState extends State<AppSettingsContent> {
  late final ScrollController _contentScrollController;

  @override
  void initState() {
    super.initState();
    _contentScrollController = ScrollController();
  }

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navBarHeight =
        _AppSettingsConstants.headerHeight +
        _AppSettingsConstants.handleHeight +
        _AppSettingsConstants.spacingMedium;

    return Stack(
      children: [
        CustomScrollView(
          controller: _contentScrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight: navBarHeight,
              expandedHeight: navBarHeight,
              flexibleSpace: SizedBox.expand(
                child: ClipRRect(
                  child: DecoratedBox(
                    decoration: const ShapeDecoration(
                      color: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(40),
                          topRight: Radius.circular(40),
                        ),
                      ),
                    ),
                    child: _buildHeaderWithHandle(context),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // General section
                  _buildSectionHeader(context, 'General'),
                  _buildSelectableItem(
                    context,
                    label: 'Theme',
                    value: 'Dark',
                    onTap: () {},
                    isFirst: true,
                  ),
                  _buildSelectableItem(
                    context,
                    label: 'Language',
                    value: 'English',
                    onTap: () {},
                  ),
                  _buildActionItem(
                    context,
                    title: 'Clear local cache',
                    onTap: () {},
                    isLast: true,
                  ),

                  const SizedBox(height: 16),

                  // Support section
                  _buildSectionHeader(context, 'Support'),
                  _buildActionItem(
                    context,
                    title: 'Logs',
                    onTap: () {},
                    isFirst: true,
                  ),
                  _buildActionItem(
                    context,
                    title: 'Report a bug',
                    onTap: () {},
                  ),
                  _buildActionItem(
                    context,
                    title: 'Knowledge base',
                    onTap: () {},
                    isLast: true,
                  ),

                  const SizedBox(height: 16),

                  // Legal section
                  _buildSectionHeader(context, 'Legal'),
                  _buildActionItem(
                    context,
                    title: 'Privacy policy',
                    onTap: () {},
                    isFirst: true,
                  ),
                  _buildActionItem(
                    context,
                    title: 'Terms and conditions',
                    onTap: () {},
                    isLast: true,
                  ),
                ]),
              ),
            ),
          ],
        ),
        // Header area that allows bottom sheet drag to work.
        // Wrap in AbsorbPointer so gestures bypass the content
        // and bubble up to the DraggableScrollableSheet for dragging.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: navBarHeight,
          child: AbsorbPointer(child: _buildHeaderWithHandle(context)),
        ),
      ],
    );
  }

  Widget _buildHeaderWithHandle(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const BottomSheetHandleBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'App settings',
                style: ProtonStyles.headline(
                  fontSize: 18,
                  color: context.colors.textNorm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            title,
            style: ProtonStyles.body2Semibold(color: context.colors.textWeak),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableItem(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final borderRadius = isFirst && isLast
        ? BorderRadius.circular(24)
        : isFirst
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          )
        : isLast
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          )
        : BorderRadius.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          height: 76,
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.textWeak,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.textNorm,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Icon(
                Icons.chevron_right,
                color: context.colors.textNorm.withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
    bool isDanger = false,
  }) {
    final borderRadius = isFirst && isLast
        ? BorderRadius.circular(24)
        : isFirst
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          )
        : isLast
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          )
        : BorderRadius.zero;

    final showDangerIcon = isDanger;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          height: 64,
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: ProtonStyles.body1Medium(
                    color: isDanger
                        ? context.colors.notificationError
                        : context.colors.textNorm,
                  ),
                ),
              ),
              if (showDangerIcon)
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: const Color(0xFF3D2A3D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 16,
                  ),
                )
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}
