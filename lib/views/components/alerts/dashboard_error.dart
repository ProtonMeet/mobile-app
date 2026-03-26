import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

/// Parses an error message to extract a clean message and details
({String message, String? details}) _parseErrorMessage(String error) {
  // Try to extract a clean message from common error formats
  // Check for common error patterns
  if (error.contains('Exception:')) {
    final parts = error.split('Exception:');
    if (parts.length > 1) {
      return (
        message: parts[0].trim().isEmpty
            ? 'An error occurred'
            : parts[0].trim(),
        details: parts.sublist(1).join('Exception:').trim(),
      );
    }
  }

  // Check for error: pattern
  if (error.contains('Error:') || error.contains('error:')) {
    final regex = RegExp(r'(?:Error|error):\s*(.+?)(?:\n|$)');
    final match = regex.firstMatch(error);
    if (match != null) {
      final cleanMessage = match.group(1)?.trim() ?? error;
      return (
        message: cleanMessage.length > 100
            ? '${cleanMessage.substring(0, 100)}...'
            : cleanMessage,
        details: error,
      );
    }
  }

  // If error is very long, truncate for display
  if (error.length > 150) {
    return (message: '${error.substring(0, 150)}...', details: error);
  }

  // Default: use the error as message
  return (message: error, details: null);
}

Future<void> showDashboardErrorBottomSheet(
  BuildContext context, {
  required String errorMessage,
  String? errorDetails,
  VoidCallback? onRetry,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DashboardErrorModal(
      errorMessage: errorMessage,
      errorDetails: errorDetails,
      onRetry: onRetry,
    ),
  );
}

class DashboardErrorModal extends StatefulWidget {
  const DashboardErrorModal({
    required this.errorMessage,
    this.errorDetails,
    this.onRetry,
    super.key,
  });

  final String errorMessage;
  final String? errorDetails;
  /// When set, shows a primary "Retry" action (e.g. re-run dashboard load).
  final VoidCallback? onRetry;

  @override
  State<DashboardErrorModal> createState() => _DashboardErrorModalState();
}

class _DashboardErrorModalState extends State<DashboardErrorModal> {
  bool _isExpanded = false;
  late final ({String message, String? details}) _parsedError;

  @override
  void initState() {
    super.initState();
    _parsedError = _parseErrorMessage(widget.errorMessage);
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _onCopy() {
    // Copy error details: message + details if available
    final errorDetails = widget.errorDetails ?? _parsedError.details;
    final textToCopy = errorDetails != null
        ? '${_parsedError.message}\n\nError details:\n$errorDetails'
        : widget.errorMessage;

    Clipboard.setData(ClipboardData(text: textToCopy));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.local.link_copied_to_clipboard)),
      );
    }
  }

  void _onClose() {
    Navigator.of(context).pop();
  }

  void _onRetry() {
    final retry = widget.onRetry;
    Navigator.of(context).pop();
    retry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final borderNorm = context.colors.appBorderNorm;
    final padding =
        EdgeInsets.only(bottom: bottomInset) +
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16);

    final hasDetails =
        (widget.errorDetails != null && widget.errorDetails!.isNotEmpty) ||
        _parsedError.details != null;
    final errorDetailsText = widget.errorDetails ?? _parsedError.details;
    final canExpand = showExpandableErrorDetails && hasDetails;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        padding: padding,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxMobileSheetWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: context.colors.blurBottomSheetBackground,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: borderNorm),
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          /// Close button
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: CloseButtonV1(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.08,
                                ),
                                onPressed: _onClose,
                              ),
                            ),
                          ),

                          /// Error icon
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: context.images.iconInvalidLink.svg(
                              width: 72,
                              height: 72,
                              fit: BoxFit.fitWidth,
                            ),
                          ),

                          /// Title & error message
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                Text(
                                  'Error',
                                  textAlign: TextAlign.center,
                                  style: ProtonStyles.headline(
                                    color: context.colors.textNorm,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _parsedError.message,
                                  textAlign: TextAlign.center,
                                  style: ProtonStyles.body2Medium(
                                    color: context.colors.textWeak,
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          /// Expandable error details
                          if (canExpand) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: _toggleExpanded,
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: context.colors.backgroundNorm,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: borderNorm),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Error details',
                                              style: ProtonStyles.body2Medium(
                                                color: context.colors.textNorm,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            _isExpanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                            color: context.colors.textWeak,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_isExpanded) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: context.colors.backgroundNorm,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(color: borderNorm),
                                      ),
                                      child: Text(
                                        errorDetailsText ?? '',
                                        style: ProtonStyles.body2Regular(
                                          color: context.colors.textWeak,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          /// Action buttons
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.onRetry != null) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    height: 60,
                                    child: ElevatedButton(
                                      onPressed: _onRetry,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            context.colors.interActionNorm,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            200,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        context.local.retry,
                                        style: ProtonStyles.body1Semibold(
                                          color: context.colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                /// Copy button
                                SizedBox(
                                  width: double.infinity,
                                  height: 60,
                                  child: ElevatedButton(
                                    onPressed: _onCopy,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          context.colors.interActionWeak,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          200,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.copy_rounded,
                                          size: 20,
                                          color: context.colors.textNorm,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Copy error details',
                                          style: ProtonStyles.body1Semibold(
                                            color: context.colors.textNorm,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
          ),
        ),
      ),
    );
  }
}
