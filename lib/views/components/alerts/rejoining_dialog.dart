import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/close_button_v1.dart';

typedef OnLeaveRoom = void Function();
typedef OnRejoin = void Function();
typedef OnClose = void Function();

class _RejoinDialogConstants {
  static const double headerHeight = 64.0;
  static const double handleHeight = 36.0;
  static const double borderRadiusLarge = 40.0;
}

double _calculateMaxHeight(bool isLandscape, double screenHeight) {
  return isLandscape ? screenHeight : screenHeight * 0.84;
}

Future<void> showRejoinFailedDialog(
  BuildContext context, {
  required String error,
  required OnLeaveRoom onLeaveRoom,
  required OnRejoin onRejoin,
  OnClose? onClose,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    routeSettings: const RouteSettings(name: 'rejoin_failed'),
    builder: (ctx) {
      final builderMedia = MediaQuery.of(ctx);
      final builderIsLandscape =
          builderMedia.size.width > builderMedia.size.height;
      final maxHeight = _calculateMaxHeight(
        builderIsLandscape,
        builderMedia.size.height,
      );

      return _RoundedRejoinSheet(
        maxHeight: maxHeight,
        isLandscape: builderIsLandscape,
        child: RejoinFailedDialog(
          error: error,
          onLeaveRoom: onLeaveRoom,
          onRejoin: onRejoin,
          onClose: onClose,
        ),
      );
    },
  ).then((_) {
    onClose?.call();
  });
}

class _RoundedRejoinSheet extends StatelessWidget {
  const _RoundedRejoinSheet({
    required this.child,
    required this.maxHeight,
    required this.isLandscape,
  });

  final Widget child;
  final double maxHeight;
  final bool isLandscape;

  BoxDecoration _buildDecoration(BuildContext context) {
    return BoxDecoration(
      color: context.colors.clear,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    );
  }

  Widget _buildSheetContent(BuildContext context) {
    final decoration = _buildDecoration(context);

    if (isLandscape) {
      return SizedBox(
        height: maxHeight,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(decoration: decoration, child: child),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: decoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Expanded(child: child)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childSize = isLandscape ? 1.0 : 0.95;

    return DraggableScrollableSheet(
      initialChildSize: childSize,
      minChildSize: childSize,
      maxChildSize: childSize,
      builder: (ctx, controller) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: _buildSheetContent(context),
        );
      },
    );
  }
}

class RejoinFailedDialog extends StatefulWidget {
  const RejoinFailedDialog({
    required this.error,
    required this.onLeaveRoom,
    required this.onRejoin,
    this.onClose,
    super.key,
  });

  final String error;
  final OnLeaveRoom onLeaveRoom;
  final OnRejoin onRejoin;
  final OnClose? onClose;

  @override
  State<RejoinFailedDialog> createState() => _RejoinFailedDialogState();
}

class _RejoinFailedDialogState extends State<RejoinFailedDialog> {
  void _onRejoin() {
    Navigator.of(context).pop();
    widget.onRejoin();
  }

  void _handleLeaveRoom() {
    Navigator.of(context).pop();
    widget.onLeaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.size.width > mediaQuery.size.height;
    final bottomInset = mediaQuery.viewInsets.bottom;
    final navBarHeight =
        _RejoinDialogConstants.headerHeight +
        (isLandscape ? 8 : _RejoinDialogConstants.handleHeight);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(bottom: bottomInset + 24),
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: context.colors.blurBottomSheetBackground,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.03)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(
                _RejoinDialogConstants.borderRadiusLarge,
              ),
              topRight: Radius.circular(
                _RejoinDialogConstants.borderRadiusLarge,
              ),
            ),
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.only(
                        top: navBarHeight,
                        bottom:
                            bottomInset +
                            148, // Space for buttons (60 + 8 + 60 + 20 padding)
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: context.images.iconErrorMessage.svg(
                              width: 72,
                              height: 72,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                Text(
                                  context.local.unable_to_reconnect,
                                  textAlign: TextAlign.center,
                                  style: ProtonStyles.headline(
                                    color: context.colors.textNorm,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  context.local.reconnection_failed_message,
                                  textAlign: TextAlign.center,
                                  style: ProtonStyles.body2Medium(
                                    color: context.colors.textWeak,
                                  ),
                                ),
                                Text(
                                  "Error: ${widget.error}",
                                  textAlign: TextAlign.center,
                                  style: ProtonStyles.body2Medium(
                                    color: context.colors.textWeak,
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: navBarHeight,
              child: AbsorbPointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isLandscape)
                      const BottomSheetHandleBar()
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: bottomInset,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.colors.blurBottomSheetBackground.withValues(
                        alpha: 0,
                      ),
                      context.colors.blurBottomSheetBackground,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _onRejoin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.interActionWeak,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(200),
                          ),
                        ),
                        child: Text(
                          context.local.rejoin_meeting,
                          style: ProtonStyles.body1Semibold(
                            color: context.colors.textNorm,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _handleLeaveRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.signalDangerMajor3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(200),
                          ),
                        ),
                        child: Text(
                          context.local.leave_meeting,
                          style: ProtonStyles.body1Semibold(
                            color: context.colors.textInverted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // add close button so user can close the dialog if they want
            Positioned(
              top: 24,
              right: 24,
              child: CloseButtonV1(
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
