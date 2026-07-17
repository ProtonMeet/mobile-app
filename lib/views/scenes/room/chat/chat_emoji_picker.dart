import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';

/// Shows a modal emoji picker with search. Returns the chosen emoji, or null.
Future<String?> showChatEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.backgroundNorm,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ChatEmojiPicker(),
  );
}

class _ChatEmojiPicker extends StatefulWidget {
  const _ChatEmojiPicker();

  @override
  State<_ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

class _ChatEmojiPickerState extends State<_ChatEmojiPicker> {
  final TextEditingController _search = TextEditingController();
  final EmojiPickerController _pickerController = EmojiPickerController();
  final _utils = EmojiPickerUtils();
  String _query = '';
  List<CategoryEmoji> _categoryEmojis = [];
  List<Emoji> _searchResults = [];
  bool _emojiDataReady = false;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _pickerController.addListener(_persistCategory);
    _restoreSavedCategory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_emojiDataReady) {
      _loadEmojiData();
    }
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _pickerController.removeListener(_persistCategory);
    _search.dispose();
    _pickerController.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedCategory() async {
    final savedName = await ManagerFactory()
        .get<PreferencesManager>()
        .getChatEmojiPickerCategory();
    final category = _categoryFromStoredName(savedName);
    if (!mounted || category == null) return;
    if (_pickerController.currentCategory != category) {
      _pickerController.setCategory(category);
    }
  }

  void _persistCategory() {
    ManagerFactory()
        .get<PreferencesManager>()
        .setChatEmojiPickerCategory(_pickerController.currentCategory.name);
  }

  Category? _categoryFromStoredName(String? name) {
    if (name == null) return null;
    for (final category in Category.values) {
      if (category.name == name) return category;
    }
    return null;
  }

  Future<void> _loadEmojiData() async {
    final locale = Localizations.localeOf(context);
    final data = getDefaultEmojiLocale(locale);
    final filtered = await _utils.filterUnsupported(data);
    final recent = await _utils.getRecentEmojis();
    if (!mounted) return;
    setState(() {
      _categoryEmojis = [
        CategoryEmoji(
          Category.RECENT,
          recent.map((entry) => entry.emoji).toList(),
        ),
        ...filtered,
      ];
      _emojiDataReady = true;
    });
    if (_query.isNotEmpty) {
      _runSearch(_query);
    }
  }

  void _onSearchChanged() {
    final query = _search.text.trim();
    if (query == _query) return;
    setState(() => _query = query);
    _runSearch(query);
  }

  void _runSearch(String query) {
    if (query.isEmpty) {
      _searchRequestId++;
      setState(() => _searchResults = []);
      return;
    }
    if (!_emojiDataReady) return;

    final requestId = ++_searchRequestId;
    _utils.searchEmoji(query, _categoryEmojis).then((results) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchResults = results);
    });
  }

  void _onEmojiChosen(Emoji emoji) {
    Navigator.of(context).pop(emoji.emoji);
  }

  Config _buildConfig(BuildContext context, double maxHeight) {
    final background = context.colors.backgroundNorm;
    return Config(
      height: maxHeight,
      locale: Localizations.localeOf(context),
      checkPlatformCompatibility: true,
      emojiViewConfig: EmojiViewConfig(
        columns: 7,
        emojiSizeMax: 28,
        backgroundColor: background,
        verticalSpacing: 8,
        horizontalSpacing: 8,
        buttonMode: ButtonMode.NONE,
        noRecents: Center(
          child: Text(
            '—',
            style: ProtonStyles.body2Medium(
              color: context.colors.textDisable,
            ),
          ),
        ),
        loadingIndicator: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.textWeak,
            ),
          ),
        ),
      ),
      categoryViewConfig: CategoryViewConfig(
        initCategory: _pickerController.currentCategory,
        recentTabBehavior: RecentTabBehavior.RECENT,
        backgroundColor: background,
        indicatorColor: context.colors.textNorm,
        iconColor: context.colors.textWeak,
        iconColorSelected: context.colors.textNorm,
        dividerColor: Colors.transparent,
      ),
      bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.4;
    final config = _buildConfig(context, maxHeight);
    final showCategories = _query.isEmpty && _emojiDataReady;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.colors.textDisable,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: context.colors.textDisable),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textNorm,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: context.local.search,
                          hintStyle: ProtonStyles.body2Medium(
                            color: context.colors.textDisable,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: maxHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: _query.isEmpty
                          ? EmojiPicker(
                              controller: _pickerController,
                              onEmojiSelected: (_, emoji) =>
                                  _onEmojiChosen(emoji),
                              config: config,
                              customWidget:
                                  (pickerConfig, state, showSearchBar) {
                                return _ChatCategoryEmojiGrid(
                                  pickerConfig,
                                  state,
                                  showSearchBar,
                                );
                              },
                            )
                          : _ChatEmojiSearchGrid(
                              config: config,
                              results: _searchResults,
                              onEmojiSelected: _onEmojiChosen,
                            ),
                    ),
                    if (showCategories) ...[
                      const SizedBox(height: 8),
                      _ChatCategoryTabBar(
                        controller: _pickerController,
                        categories: _categoryEmojis,
                        config: config,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal category tabs (Recent, Smileys, …) for quick navigation.
class _ChatCategoryTabBar extends StatefulWidget {
  const _ChatCategoryTabBar({
    required this.controller,
    required this.categories,
    required this.config,
  });

  final EmojiPickerController controller;
  final List<CategoryEmoji> categories;
  final Config config;

  @override
  State<_ChatCategoryTabBar> createState() => _ChatCategoryTabBarState();
}

class _ChatCategoryTabBarState extends State<_ChatCategoryTabBar> {
  late final List<GlobalKey> _tabKeys;

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    widget.controller.addListener(_scrollSelectedIntoView);
  }

  @override
  void didUpdateWidget(covariant _ChatCategoryTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scrollSelectedIntoView);
      widget.controller.addListener(_scrollSelectedIntoView);
    }
    if (oldWidget.categories.length != widget.categories.length) {
      _tabKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollSelectedIntoView);
    super.dispose();
  }

  void _scrollSelectedIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.categories.indexWhere(
        (entry) => entry.category == widget.controller.currentCategory,
      );
      if (index == -1 || index >= _tabKeys.length) return;
      final tabContext = _tabKeys[index].currentContext;
      if (tabContext == null) return;
      Scrollable.ensureVisible(
        tabContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return SizedBox(
          height: 36,
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (var index = 0; index < widget.categories.length; index++) ...[
                  if (index > 0) const SizedBox(width: 4),
                  KeyedSubtree(
                    key: _tabKeys[index],
                    child: _ChatCategoryTab(
                      category: widget.categories[index].category,
                      selected: widget.controller.currentCategory ==
                          widget.categories[index].category,
                      config: widget.config,
                      onTap: () => widget.controller.setCategory(
                        widget.categories[index].category,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatCategoryTab extends StatelessWidget {
  const _ChatCategoryTab({
    required this.category,
    required this.selected,
    required this.config,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final Config config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = getIconForCategory(
      config.categoryViewConfig.categoryIcons,
      category,
    );
    final color = selected
        ? config.categoryViewConfig.iconColorSelected
        : config.categoryViewConfig.iconColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.interActionNorm
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

/// Category-scoped emoji grid synced with [_ChatCategoryTabBar].
class _ChatCategoryEmojiGrid extends EmojiPickerView {
  const _ChatCategoryEmojiGrid(super.config, super.state, super.showSearchBar);

  @override
  State<_ChatCategoryEmojiGrid> createState() => _ChatCategoryEmojiGridState();
}

class _ChatCategoryEmojiGridState extends State<_ChatCategoryEmojiGrid>
    with SingleTickerProviderStateMixin, SkinToneOverlayStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  final _scrollController = ScrollController();

  @override
  void initState() {
    final targetCategory = widget.state.currentCategory ??
        widget.config.categoryViewConfig.initCategory;
    var initIndex = widget.state.categoryEmoji
        .indexWhere((entry) => entry.category == targetCategory);
    if (initIndex == -1) {
      initIndex = 0;
    }
    _tabController = TabController(
      initialIndex: initIndex,
      length: widget.state.categoryEmoji.length,
      vsync: this,
    );
    _pageController = PageController(initialPage: initIndex)
      ..addListener(closeSkinToneOverlay);
    _scrollController.addListener(closeSkinToneOverlay);
    widget.state.categoryNavigationNotifier
        .addListener(_onCategoryNavigationChanged);
    super.initState();
  }

  void _onCategoryNavigationChanged() {
    final targetCategory = widget.state.categoryNavigationNotifier.value;
    if (targetCategory == null) return;

    final index = widget.state.categoryEmoji
        .indexWhere((entry) => entry.category == targetCategory);
    if (index == -1) return;

    final currentPage = _pageController.page?.round();
    if (index != currentPage) {
      _pageController.jumpToPage(index);
      if (_tabController.index != index) {
        _tabController.animateTo(index);
      }
    }
  }

  @override
  void dispose() {
    widget.state.categoryNavigationNotifier
        .removeListener(_onCategoryNavigationChanged);
    closeSkinToneOverlay();
    _tabController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize =
            widget.config.emojiViewConfig.getEmojiSize(constraints.maxWidth);
        final emojiBoxSize =
            widget.config.emojiViewConfig.getEmojiBoxSize(constraints.maxWidth);

        return EmojiContainer(
          color: widget.config.emojiViewConfig.backgroundColor,
          buttonMode: widget.config.emojiViewConfig.buttonMode,
          child: _buildEmojiView(emojiSize, emojiBoxSize),
        );
      },
    );
  }

  Widget _buildEmojiView(double emojiSize, double emojiBoxSize) {
    return PageView.builder(
      itemCount: widget.state.categoryEmoji.length,
      controller: _pageController,
      onPageChanged: (index) {
        _tabController.animateTo(
          index,
          duration: widget.config.categoryViewConfig.tabIndicatorAnimDuration,
        );
        if (index < widget.state.categoryEmoji.length) {
          widget.state.onCategoryChanged?.call(
            widget.state.categoryEmoji[index].category,
          );
        }
      },
      itemBuilder: (context, index) => _buildPage(
        emojiSize,
        emojiBoxSize,
        widget.state.categoryEmoji[index],
      ),
    );
  }

  Widget _buildPage(
    double emojiSize,
    double emojiBoxSize,
    CategoryEmoji categoryEmoji,
  ) {
    if (categoryEmoji.category == Category.RECENT &&
        categoryEmoji.emoji.isEmpty) {
      return Center(child: widget.config.emojiViewConfig.noRecents);
    }

    return GridView.builder(
      scrollDirection: Axis.vertical,
      controller: _scrollController,
      primary: false,
      padding: widget.config.emojiViewConfig.gridPadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        childAspectRatio: 1,
        crossAxisCount: widget.config.emojiViewConfig.columns,
        mainAxisSpacing: widget.config.emojiViewConfig.verticalSpacing,
        crossAxisSpacing: widget.config.emojiViewConfig.horizontalSpacing,
      ),
      itemCount: categoryEmoji.emoji.length,
      itemBuilder: (context, index) {
        final emoji = categoryEmoji.emoji[index];
        return addSkinToneTargetIfAvailable(
          hasSkinTone: emoji.hasSkinTone,
          linkKey: categoryEmoji.category.name + emoji.emoji,
          child: EmojiCell.fromConfig(
            emoji: emoji,
            emojiSize: emojiSize,
            emojiBoxSize: emojiBoxSize,
            categoryEmoji: categoryEmoji,
            onEmojiSelected: _onSkinTonedEmojiSelected,
            config: widget.config,
            onSkinToneDialogRequested: _openSkinToneDialog,
          ),
        );
      },
    );
  }

  void _openSkinToneDialog(
    Offset emojiBoxPosition,
    Emoji emoji,
    double emojiSize,
    CategoryEmoji? categoryEmoji,
  ) {
    closeSkinToneOverlay();
    if (!emoji.hasSkinTone || !widget.config.skinToneConfig.enabled) {
      return;
    }
    showSkinToneOverlay(
      emojiBoxPosition,
      emoji,
      emojiSize,
      categoryEmoji,
      widget.config,
      _onSkinTonedEmojiSelected,
      links[categoryEmoji!.category.name + emoji.emoji]!,
    );
  }

  void _onSkinTonedEmojiSelected(Category? category, Emoji emoji) {
    widget.state.onEmojiSelected(category, emoji);
    closeSkinToneOverlay();
  }
}

class _ChatEmojiSearchGrid extends StatefulWidget {
  const _ChatEmojiSearchGrid({
    required this.config,
    required this.results,
    required this.onEmojiSelected,
  });

  final Config config;
  final List<Emoji> results;
  final ValueChanged<Emoji> onEmojiSelected;

  @override
  State<_ChatEmojiSearchGrid> createState() => _ChatEmojiSearchGridState();
}

class _ChatEmojiSearchGridState extends State<_ChatEmojiSearchGrid>
    with SkinToneOverlayStateMixin {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize =
            widget.config.emojiViewConfig.getEmojiSize(constraints.maxWidth);
        final emojiBoxSize =
            widget.config.emojiViewConfig.getEmojiBoxSize(constraints.maxWidth);

        return EmojiContainer(
          color: widget.config.emojiViewConfig.backgroundColor,
          buttonMode: widget.config.emojiViewConfig.buttonMode,
          child: GridView.builder(
            padding: widget.config.emojiViewConfig.gridPadding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              childAspectRatio: 1,
              crossAxisCount: widget.config.emojiViewConfig.columns,
              mainAxisSpacing: widget.config.emojiViewConfig.verticalSpacing,
              crossAxisSpacing: widget.config.emojiViewConfig.horizontalSpacing,
            ),
            itemCount: widget.results.length,
            itemBuilder: (context, index) {
              final emoji = widget.results[index];
              return addSkinToneTargetIfAvailable(
                hasSkinTone: emoji.hasSkinTone,
                linkKey: 'search_${emoji.emoji}',
                child: EmojiCell.fromConfig(
                  emoji: emoji,
                  emojiSize: emojiSize,
                  emojiBoxSize: emojiBoxSize,
                  onEmojiSelected: (_, selected) {
                    widget.onEmojiSelected(selected);
                  },
                  config: widget.config,
                  onSkinToneDialogRequested: (
                    emojiBoxPosition,
                    selectedEmoji,
                    selectedEmojiSize,
                    categoryEmoji,
                  ) {
                    closeSkinToneOverlay();
                    if (!selectedEmoji.hasSkinTone ||
                        !widget.config.skinToneConfig.enabled) {
                      return;
                    }
                    showSkinToneOverlay(
                      emojiBoxPosition,
                      selectedEmoji,
                      selectedEmojiSize,
                      categoryEmoji,
                      widget.config,
                      (_, selected) => widget.onEmojiSelected(selected),
                      links['search_${selectedEmoji.emoji}']!,
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
