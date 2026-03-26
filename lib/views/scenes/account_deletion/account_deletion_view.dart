import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_event.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Import for Android features.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Import for iOS features.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'account_deletion_bloc.dart';
import 'account_deletion_event.dart';
import 'account_deletion_state.dart';

class AccountDeletionView extends StatefulWidget {
  final AuthBloc? authBloc;

  const AccountDeletionView({this.authBloc, super.key});

  @override
  State<AccountDeletionView> createState() => _AccountDeletionViewState();
}

class _AccountDeletionViewState extends State<AccountDeletionView> {
  WebViewController? _controller;

  void _initializeWebView(String checkoutUrl) {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (request) {
        request.grant();
      },
    );

    if (_controller!.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      (_controller!.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    // Match the WKScriptMessageHandler name
    var channelName = 'iOS';
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Match the AndroidInterface name
      channelName = 'AndroidInterface';
    }

    _controller!
      ..clearCache()
      ..clearLocalStorage()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        channelName,
        onMessageReceived: (JavaScriptMessage message) {
          _handleMessage(message.message);
        },
      )
      ..setBackgroundColor(context.colors.backgroundNorm)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {
            //
          },
          onPageFinished: (String url) {
            EasyLoading.dismiss();
          },
          onHttpError: (HttpResponseError error) {
            EasyLoading.dismiss();
          },
          onWebResourceError: (WebResourceError error) {
            EasyLoading.dismiss();
            _showErrorDialog('Failed to load page: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.parse(request.url);
            if (uri.host == 'account.proton.me') {
              return NavigationDecision.navigate;
            }
            logger.w('Blocked navigation to untrusted domain: ${uri.host}');
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(checkoutUrl));
  }

  /// Handles messages from the WebView
  void _handleMessage(String message) {
    try {
      final parsedMessage = jsonDecode(message);
      final type = parsedMessage['type'];
      final payload = parsedMessage['payload'];
      switch (type) {
        case 'SUCCESS':
          _handleSuccess();
        case 'ERROR':
          final errorMessage = payload?['message'] ?? 'Unknown error';
          _handleError(errorMessage);
        case 'CLOSE':
          _handleClose();
        default:
          logger.i('Unknown message type: $type');
      }
    } catch (e) {
      _showErrorDialog('Failed to parse message: $message');
    }
  }

  /// Handle success scenario
  void _handleSuccess() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account deletion successful')),
    );
    // Trigger logout after successful account deletion
    if (widget.authBloc != null) {
      widget.authBloc!.add(SignOutUser());
    }
  }

  /// Handle error scenario
  void _handleError(String errorMessage) {
    _showErrorDialog(errorMessage);
  }

  /// Handle close action
  void _handleClose() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account deletion canceled by user')),
    );
  }

  /// Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Close account deletion view when error dialog is closed
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AccountDeletionBloc>(
      create: (context) =>
          AccountDeletionBloc(managerFactory: ManagerFactory())
            ..add(StartAccountDeletion()),
      child: BlocListener<AccountDeletionBloc, AccountDeletionState>(
        listenWhen: (previous, current) =>
            previous.error != current.error ||
            previous.checkoutUrl != current.checkoutUrl,
        listener: (context, state) {
          // Handle error state
          if (state.error != null) {
            _showErrorDialog('${state.error}\nPlease try again.');
          }
          // Initialize webview when checkoutUrl is available
          else if (state.checkoutUrl != null && _controller == null) {
            _initializeWebView(state.checkoutUrl!);
          }
        },
        child: BlocBuilder<AccountDeletionBloc, AccountDeletionState>(
          builder: (context, state) {
            return Scaffold(
              body: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24.0),
                  ),
                  color: context.colors.backgroundNorm,
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      const BottomSheetHandleBar(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Account Deletion',
                              style: ProtonStyles.headline(
                                fontSize: 18,
                                color: context.colors.textNorm,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                context.read<AccountDeletionBloc>().add(
                                  CloseAccountDeletion(),
                                );
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: state.isLoading
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Loading account...',
                                      style: ProtonStyles.body1Medium(
                                        color: context.colors.textNorm,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : state.checkoutUrl != null && _controller != null
                            ? WebViewWidget(controller: _controller!)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
