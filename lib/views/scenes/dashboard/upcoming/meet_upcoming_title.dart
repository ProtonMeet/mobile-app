import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

enum MeetUpcomingTab { myMeetings, myRooms }

enum MeetUpcomingTabStyle { tabButton, tabText }

extension MeetUpcomingTabExtension on MeetUpcomingTab {
  int get index => this == MeetUpcomingTab.myMeetings ? 0 : 1;
}

class MeetUpcomingTitle extends StatefulWidget {
  const MeetUpcomingTitle({
    required this.myMeetingsCount,
    required this.myRoomsCount,
    this.onTabChanged,
    this.selectedTab = MeetUpcomingTab.myMeetings,
    this.tabStyle = MeetUpcomingTabStyle.tabText,
    this.showButton,
    this.onButtonTap,
    this.buttonIcon,
    this.isLoading = false,
    /// When non-null and [isLoading] is false, shows a reload icon (e.g. after fetch failure).
    this.onFetchReloadTap,
    super.key,
  });

  final int myMeetingsCount;
  final int myRoomsCount;
  final ValueChanged<MeetUpcomingTab>? onTabChanged;
  final MeetUpcomingTab selectedTab;
  final MeetUpcomingTabStyle tabStyle;
  /// Defaults to true if there is a loading indicator, reload, or custom action.
  final bool? showButton;
  final VoidCallback? onButtonTap;
  final Widget? buttonIcon;
  final bool isLoading;
  final VoidCallback? onFetchReloadTap;

  @override
  State<MeetUpcomingTitle> createState() => _MeetUpcomingTitleState();
}

class _MeetUpcomingTitleState extends State<MeetUpcomingTitle>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.selectedTab.index,
    );
    _tabController.addListener(_handleTabChange);
  }

  @override
  void didUpdateWidget(MeetUpcomingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _tabController.animateTo(widget.selectedTab.index);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      final newTab = MeetUpcomingTab.values[_tabController.index];
      widget.onTabChanged?.call(newTab);
    }
  }

  void _selectTab(MeetUpcomingTab tab) {
    if (widget.selectedTab == tab) {
      return;
    }
    _tabController.animateTo(tab.index);
  }

  Widget _buildTabButtons(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 300),
      padding: const EdgeInsets.all(4),
      height: 52,
      decoration: BoxDecoration(
        color: context.colors.backgroundNorm,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.backgroundSecondary),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: context.colors.protonBlue,
            borderRadius: BorderRadius.circular(999),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: context.colors.textInverted,
          unselectedLabelColor: context.colors.textWeak,
          labelStyle: ProtonStyles.body1Semibold(),
          unselectedLabelStyle: ProtonStyles.body2Semibold(),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          tabs: [
            Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.local.my_meetings_count),
                    const SizedBox(width: 6),
                    _CountBadge(
                      count: widget.myMeetingsCount,
                      isSelected:
                          widget.selectedTab == MeetUpcomingTab.myMeetings,
                    ),
                  ],
                ),
              ),
            ),
            Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.local.my_rooms_count),
                    const SizedBox(width: 6),
                    _CountBadge(
                      count: widget.myRoomsCount,
                      isSelected: widget.selectedTab == MeetUpcomingTab.myRooms,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextTabs(BuildContext context) {
    final myMeetingsLabel = context.local.my_meetings_count;
    final myRoomsLabel = context.local.my_rooms_count;
    final myMeetingsSelected = widget.selectedTab == MeetUpcomingTab.myMeetings;
    final myRoomsSelected = widget.selectedTab == MeetUpcomingTab.myRooms;

    return Container(
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TextTab(
            label: myMeetingsLabel,
            count: widget.myMeetingsCount,
            selected: myMeetingsSelected,
            onTap: () => _selectTab(MeetUpcomingTab.myMeetings),
          ),
          Container(
            width: 1,
            height: 20,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: context.colors.borderCard),
          ),
          _TextTab(
            label: myRoomsLabel,
            count: widget.myRoomsCount,
            selected: myRoomsSelected,
            onTap: () => _selectTab(MeetUpcomingTab.myRooms),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReload = !widget.isLoading && widget.onFetchReloadTap != null;
    final hasCustomAction =
        !widget.isLoading &&
        widget.onButtonTap != null &&
        widget.buttonIcon != null;
    final effectiveShowButton = widget.showButton ??
        (widget.isLoading || hasReload || hasCustomAction);

    return Container(
      padding: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 12),
      child: Row(
        children: [
          widget.tabStyle == MeetUpcomingTabStyle.tabButton
              ? _buildTabButtons(context)
              : _buildTextTabs(context),
          const Spacer(),
          if (effectiveShowButton) ...[
            const SizedBox(width: 16),
            _ActionButton(
              onTap: widget.isLoading
                  ? null
                  : hasReload
                  ? widget.onFetchReloadTap
                  : widget.onButtonTap,
              icon: widget.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : hasReload
                  ? Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: context.colors.interActionNorm,
                    )
                  : widget.buttonIcon,
            ),
          ],
        ],
      ),
    );
  }
}

class _TextTab extends StatelessWidget {
  const _TextTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? context.colors.textNorm
        : context.colors.textDisable;

    final textStyle = selected
        ? ProtonStyles.subheadline(color: textColor)
        : ProtonStyles.subheadline(color: textColor, fontSize: 18.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: textStyle),
              const SizedBox(width: 6),
              _CountBadge(count: count, isSelected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.isSelected});

  final int count;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: ShapeDecoration(
        color: isSelected ? Colors.white : context.colors.backgroundCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(200)),
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: isSelected
            ? ProtonStyles.captionSemibold(color: context.colors.textInverted)
            : ProtonStyles.captionSemibold(color: context.colors.textDisable),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({this.onTap, this.icon});

  final VoidCallback? onTap;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(200),
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(6),
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(200),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                SizedBox(width: 16, height: 16, child: icon)
              else
                Container(
                  width: 16,
                  height: 16,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: const Stack(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
