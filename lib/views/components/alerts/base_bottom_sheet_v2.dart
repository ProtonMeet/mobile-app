import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

// --- Overview ---------------------------------------------------------------
//
// In-call style bottom sheets: frosted glass (BackdropFilter), rounded top
// corners, optional drag handle in a pinned sliver header.
//
// Typical stack when using [BaseBottomSheetV2.withPinnedSliverScroll] with
// modal props ([modalOnBackdropTap] + [modalMaxHeight]):
//
//   [showModalBottomSheet] (transparent background)
//     └─ [BaseBottomSheetV2ModalWrap] — full-screen tap-to-dismiss dim + sized slot
//          └─ [BaseBottomSheetV2] — blur + border + optional *outer* passthrough strip
//               └─ [_SliverScrollBody] — [CustomScrollView] + optional *inner* strip
//
// **Why two “handle drag passthrough” flags?**
//
// `showModalBottomSheet` + `isScrollControlled` moves the sheet when the user
// drags from the top. The scroll view’s [SliverAppBar] / [CustomScrollView]
// would otherwise win the gesture arena and absorb vertical drags on the handle.
//
// We overlay a transparent strip with [AbsorbPointer] so the scroll subtree does
// *not* receive those pointers; the gesture then participates with the modal
// route’s drag-to-dismiss behavior.
//
// - **`innerEnableHandleDragPassthrough`**: strip above the scroll view only
//   (height ≈ [toolbarHeight]). Use when the modal does not use outer passthrough.
// - **`outerEnableHandleDragPassthrough`**: strip on the whole blurred shell
//   ([handlePassthroughHeight]). Often combined with `inner` off so one layer
//   handles hit testing (see e.g. sign-in / left-meeting sheets).
//
// Tweak [outerHandlePassthroughHeight] if the handle feels hard to grab
// (landscape + extra padding on the handle).

/// Full-screen tap target plus a bottom-aligned slot for the sheet.
///
/// Used with `showModalBottomSheet(backgroundColor: Colors.transparent)` so the
/// barrier does not paint a full scrim; this widget provides the dim area and
/// [maxWidth] / [maxHeight] constraints for the sheet content.
class BaseBottomSheetV2ModalWrap extends StatelessWidget {
  const BaseBottomSheetV2ModalWrap({
    required this.onBackdropTap,
    required this.maxHeight,
    required this.sheet,
    super.key,
    this.maxWidth = maxMobileSheetWidth,
  });

  final VoidCallback onBackdropTap;
  final double maxHeight;
  final double maxWidth;
  final Widget sheet;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onBackdropTap,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: sheet,
          ),
        ),
      ],
    );
  }
}

/// Blurred sheet shell for in-call UI (side panels, modals).
///
/// **Simple content:** pass a single [child].
///
/// **Scrollable content + pinned drag handle:** use the factory
/// [BaseBottomSheetV2.withPinnedSliverScroll] and supply `slivers` (your body
/// as [SliverToBoxAdapter] / [SliverList] / etc.). The factory inserts a pinned
/// [SliverAppBar] whose flexible space is only [BottomSheetHandleBar].
///
/// Private widgets in this file ([_PinnedHandleHeader], [_SliverScrollBody])
/// implement that layout; callers should not depend on them.
class BaseBottomSheetV2 extends StatelessWidget {
  const BaseBottomSheetV2({
    required this.child,
    super.key,
    this.bottomPadding = 24,
    this.blurSigma = 10,
    this.topCornerRadius = 40,
    this.borderSideAlpha = 0.03,
    this.enableHandleDragPassthrough = false,
    this.handlePassthroughHeight = 88,
    this.sheetBackgroundColor,
    this.contentHorizontalPadding,
    this.modalOnBackdropTap,
    this.modalMaxHeight,
    this.modalMaxWidth = maxMobileSheetWidth,
  });

  /// Pinned handle header + [CustomScrollView] built from [slivers].
  ///
  /// Parameters [innerEnableHandleDragPassthrough] and
  /// [outerEnableHandleDragPassthrough] map to the inner/outer passthrough
  /// strips described in the library comment at the top of this file.
  ///
  /// **Modal usage:** pass [modalOnBackdropTap] and [modalMaxHeight] together to
  /// auto-wrap in [BaseBottomSheetV2ModalWrap] (tap outside dismiss + height cap).
  ///
  /// [scrollController] is optional; omit unless you need programmatic scrolling.
  ///
  /// [isLandscape] adjusts handle vertical padding only ([_PinnedHandleHeader]).
  factory BaseBottomSheetV2.withPinnedSliverScroll({
    required bool isLandscape,
    required List<Widget> slivers,
    ScrollController? scrollController,
    Key? key,
    bool showPinnedHeader = true,
    double toolbarHeight = 40,
    double innerCornerRadius = 24,
    bool innerEnableHandleDragPassthrough = true,
    double headerBlurSigma = 10,
    double bottomPadding = 24,
    double blurSigma = 10,
    double topCornerRadius = 40,
    double borderSideAlpha = 0.03,
    bool outerEnableHandleDragPassthrough = false,
    double outerHandlePassthroughHeight = 40,
    Color? sheetBackgroundColor,
    double? contentHorizontalPadding,
    VoidCallback? modalOnBackdropTap,
    double? modalMaxHeight,
    double modalMaxWidth = maxMobileSheetWidth,
  }) {
    final Widget flexChild = _PinnedHandleHeader(isLandscape: isLandscape);

    return BaseBottomSheetV2(
      key: key,
      bottomPadding: bottomPadding,
      blurSigma: blurSigma,
      topCornerRadius: topCornerRadius,
      borderSideAlpha: borderSideAlpha,
      enableHandleDragPassthrough: outerEnableHandleDragPassthrough,
      handlePassthroughHeight: outerHandlePassthroughHeight,
      sheetBackgroundColor: sheetBackgroundColor,
      contentHorizontalPadding: contentHorizontalPadding,
      modalOnBackdropTap: modalOnBackdropTap,
      modalMaxHeight: modalMaxHeight,
      modalMaxWidth: modalMaxWidth,
      child: _SliverScrollBody(
        controller: scrollController,
        showPinnedHeader: showPinnedHeader,
        toolbarHeight: toolbarHeight,
        innerCornerRadius: innerCornerRadius,
        flexibleSpaceChild: flexChild,
        enableHandleDragPassthrough: innerEnableHandleDragPassthrough,
        headerBlurSigma: headerBlurSigma,
        slivers: slivers,
      ),
    );
  }

  final Widget child;

  /// When set, used as the sheet fill instead of the theme’s default blur color.
  final Color? sheetBackgroundColor;

  /// Extra space below scrollable content inside the clipped sheet.
  final double bottomPadding;

  /// Blur strength for [BackdropFilter] (e.g. `10` vs `14` for heavier frosted glass).
  final double blurSigma;

  /// Radius of the top-left and top-right corners of the outer sheet shape.
  final double topCornerRadius;

  /// White border opacity on the outer [RoundedRectangleBorder] stroke.
  final double borderSideAlpha;

  /// When true, adds an *outer* transparent strip (height [handlePassthroughHeight])
  /// over the blurred shell so vertical drags on the handle region propagate to
  /// the modal bottom sheet route. See library doc above.
  final bool enableHandleDragPassthrough;

  /// Height of the outer passthrough strip from the top of the blurred shell.
  final double handlePassthroughHeight;

  /// Symmetric horizontal inset for [child]. Null means edge-to-edge inside the shell.
  final double? contentHorizontalPadding;

  /// If both this and [modalMaxHeight] are non-null, [child] is wrapped in
  /// [BaseBottomSheetV2ModalWrap] after the blur shell (and outer passthrough).
  final VoidCallback? modalOnBackdropTap;
  final double? modalMaxHeight;
  final double modalMaxWidth;

  @override
  Widget build(BuildContext context) {
    final paddedChild = contentHorizontalPadding != null
        ? Padding(
            padding: EdgeInsets.symmetric(
              horizontal: contentHorizontalPadding!,
            ),
            child: child,
          )
        : child;

    final body = Container(
      width: double.infinity,
      padding: EdgeInsets.only(bottom: bottomPadding),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: sheetBackgroundColor ?? context.colors.blurBottomSheetBackground,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: borderSideAlpha),
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(topCornerRadius),
            topRight: Radius.circular(topCornerRadius),
          ),
        ),
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: paddedChild,
          ),
        ),
      ),
    );

    Widget result = body;
    if (enableHandleDragPassthrough) {
      // Keep hit target; block scroll/descendants from taking the drag.
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: handlePassthroughHeight,
            child: AbsorbPointer(child: Container(color: Colors.transparent)),
          ),
        ],
      );
    }

    if (modalOnBackdropTap != null && modalMaxHeight != null) {
      return BaseBottomSheetV2ModalWrap(
        onBackdropTap: modalOnBackdropTap!,
        maxHeight: modalMaxHeight!,
        maxWidth: modalMaxWidth,
        sheet: SizedBox(height: modalMaxHeight!, child: result),
      );
    }

    return result;
  }
}

// --- Private layout pieces ---------------------------------------------------

/// Visual drag handle centered in the pinned app bar’s flexible space.
class _PinnedHandleHeader extends StatelessWidget {
  const _PinnedHandleHeader({required this.isLandscape});

  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: isLandscape ? 4 : 0),
            child: const BottomSheetHandleBar(),
          ),
        ),
      ),
    );
  }
}

/// [CustomScrollView] with optional pinned [SliverAppBar] (handle + inner blur).
///
/// When [enableHandleDragPassthrough] is true, an [AbsorbPointer] overlay matches
/// [toolbarHeight] so the handle row does not scroll the list when the user
/// intends to drag-dismiss the modal.
class _SliverScrollBody extends StatelessWidget {
  const _SliverScrollBody({
    required this.slivers,
    this.controller,
    this.showPinnedHeader = true,
    this.toolbarHeight = 87,
    this.innerCornerRadius = 24,
    this.flexibleSpaceChild,
    this.enableHandleDragPassthrough = true,
    this.headerBlurSigma = 10,
  });

  final ScrollController? controller;
  final List<Widget> slivers;
  final bool showPinnedHeader;
  final double toolbarHeight;
  final double innerCornerRadius;
  final Widget? flexibleSpaceChild;
  final bool enableHandleDragPassthrough;
  final double headerBlurSigma;

  @override
  Widget build(BuildContext context) {
    final scrollSlivers = <Widget>[
      if (showPinnedHeader)
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: toolbarHeight,
          expandedHeight: toolbarHeight,
          flexibleSpace: SizedBox.expand(
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(innerCornerRadius),
                topRight: Radius.circular(innerCornerRadius),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: headerBlurSigma,
                  sigmaY: headerBlurSigma,
                ),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: context.colors.clear,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(innerCornerRadius),
                        topRight: Radius.circular(innerCornerRadius),
                      ),
                    ),
                  ),
                  child: flexibleSpaceChild!,
                ),
              ),
            ),
          ),
        ),
      ...slivers,
    ];

    final scrollView = CustomScrollView(
      controller: controller,
      physics: const ClampingScrollPhysics(),
      slivers: scrollSlivers,
    );

    if (showPinnedHeader && enableHandleDragPassthrough) {
      return Stack(
        children: [
          scrollView,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: toolbarHeight,
            child: AbsorbPointer(child: Container(color: Colors.transparent)),
          ),
        ],
      );
    }

    return scrollView;
  }
}
