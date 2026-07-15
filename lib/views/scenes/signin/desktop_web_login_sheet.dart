import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/desktop_login_browser.dart';
import 'package:meet/helper/desktop_meet_child_client_id.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/desktop.web.login.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/models/native.session.model.dart';
import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ignore: depend_on_referenced_packages
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

Future<void> showDesktopWebLoginSheet(
  BuildContext context, {
  required void Function(ProtonUser user) onLoginSuccess,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DesktopWebLoginSheet(onLoginSuccess: onLoginSuccess),
  );
}

class DesktopWebLoginSheet extends StatefulWidget {
  const DesktopWebLoginSheet({required this.onLoginSuccess, super.key});

  final void Function(ProtonUser user) onLoginSuccess;

  @override
  State<DesktopWebLoginSheet> createState() => _DesktopWebLoginSheetState();
}

class _DesktopWebLoginSheetState extends State<DesktopWebLoginSheet> {
  static const _pollInterval = Duration(seconds: 3);

  WebViewController? _controller;
  Timer? _pollTimer;
  String? _error;
  bool _isStarting = true;
  bool _useExternalBrowser = false;
  bool _pollInFlight = false;
  DesktopWebLoginManager? _loginManager;

  AppCoreManager get _appCoreManager => ManagerFactory().get<AppCoreManager>();

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    unawaited(_loginManager?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _loginManager = await DesktopWebLoginManager.create(_appCoreManager);
      final start = await _loginManager!.start(
        childClientId: desktopMeetChildClientId(),
      );

      if (!mounted) return;

      if (DesktopLoginBrowser.canUseInAppWebView) {
        await DesktopLoginBrowser.clearAccountWebViewData();
        if (!mounted) return;
        await _initializeWebView(start.loginUrl);
      } else {
        _useExternalBrowser = true;
        await DesktopLoginBrowser.openExternal(start.loginUrl);
      }

      setState(() => _isStarting = false);
      _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
      await _poll();
    } catch (e, st) {
      logger.e('Desktop web login start failed: $e', stackTrace: st);
      if (mounted) {
        setState(() {
          _isStarting = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _initializeWebView(String loginUrl) async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);
    await controller.clearCache();
    await controller.clearLocalStorage();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final host = Uri.tryParse(request.url)?.host ?? '';
            if (host.isEmpty ||
                host == 'account.proton.me' ||
                host.endsWith('.proton.black')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) async {
            logger.w('Desktop login WebView error: ${error.description}');
            if (_useExternalBrowser || !mounted) return;
            setState(() => _useExternalBrowser = true);
            await DesktopLoginBrowser.openExternal(loginUrl);
          },
        ),
      );
    await controller.loadRequest(Uri.parse(loginUrl));
    _controller = controller;
  }

  bool _isBenignPollRace(Object error) {
    final message = error.toString();
    return message.contains('Desktop web login was not started');
  }

  Future<void> _poll() async {
    if (_pollInFlight || _loginManager == null) return;
    _pollInFlight = true;
    try {
      final session = await _loginManager!.poll();
      if (!mounted || session == null) return;

      logger.d(
        'Desktop web login tokens:\n'
        '  sessionId: ${session.sessionId}\n'
        '  accessToken: ${session.accessToken}\n'
        '  refreshToken: ${session.refreshToken}\n'
        '  scopes: ${session.scopes}',
      );

      _pollTimer?.cancel();
      await _appCoreManager.appCore.fetchUserState(
        userId: session.userId,
        forceRemote: true,
      );

      final userInfo = UserInfo.fromProtonUserSession(session);
      await _appCoreManager.trySaveUserInfo(userInfo);
      await ManagerFactory().login(userInfo.userId);

      _loginManager = null;

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onLoginSuccess(
        ProtonUser(
          id: session.userId,
          name: session.userName,
          email: session.userMail,
          displayName: session.userDisplayName,
          usedSpace: BigInt.zero,
          currency: '',
          credit: 0,
          createTime: BigInt.zero,
          maxSpace: BigInt.zero,
          maxUpload: BigInt.zero,
          role: 0,
          private: 0,
          subscribed: 0,
          services: 0,
          delinquent: 0,
          mnemonicStatus: 0,
        ),
      );
    } catch (e, st) {
      if (_isBenignPollRace(e)) {
        logger.d('Desktop web login poll skipped: overlapping poll');
        return;
      }
      logger.e('Desktop web login poll failed: $e', stackTrace: st);
      if (!mounted) return;
      setState(() => _error = e.toString());
      // Keep polling — a transient network/API error must not stop detection
      // after the user has already signed in via the account WebView.
    } finally {
      _pollInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = context.height * 0.85;

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          color: context.colors.backgroundNorm,
        ),
        child: SafeArea(
          child: Column(
            children: [
              const BottomSheetHandleBar(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sign in to Proton',
                        style: ProtonStyles.headline(
                          fontSize: 18,
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error!,
                    style: ProtonStyles.body2Regular(
                      color: context.colors.notificationError,
                    ),
                  ),
                ),
              if (_useExternalBrowser && !_isStarting && _error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Complete sign-in in your browser, then return to Meet.',
                    style: ProtonStyles.body1Medium(
                      color: context.colors.textWeak,
                    ),
                  ),
                ),
              Expanded(
                child: _isStarting
                    ? const Center(child: CircularProgressIndicator())
                    : _controller != null && !_useExternalBrowser
                    ? WebViewWidget(controller: _controller!)
                    : Center(
                        child: Text(
                          _error == null ? 'Waiting for sign-in…' : '',
                          style: ProtonStyles.body1Medium(
                            color: context.colors.textWeak,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
