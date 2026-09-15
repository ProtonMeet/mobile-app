import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/desktop_meet_child_client_id.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/desktop.web.login.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/models/native.session.model.dart';
import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _pollInterval = Duration(seconds: 10);
  static const _pollIntervalAfterBrowserAuth = Duration(seconds: 2);

  String? _loginUrl;
  Timer? _pollTimer;
  String? _error;
  bool _isStarting = true;
  bool _browserAuthComplete = false;
  bool _pollInFlight = false;
  String? _expectedRedirectState;
  StreamSubscription<Uri>? _appLinkSub;
  DesktopWebLoginManager? _loginManager;

  AppCoreManager get _appCoreManager => ManagerFactory().get<AppCoreManager>();

  bool get _showSessionLoadingOverlay =>
      !_isStarting && _error == null && _browserAuthComplete;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    unawaited(_appLinkSub?.cancel());
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

      _loginUrl = start.loginUrl;
      _expectedRedirectState = start.browserRedirectState;
      _listenForBrowserRedirect();

      await _openLoginInSystemBrowser(start.loginUrl);

      setState(() => _isStarting = false);
      _startPolling();
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

  void _listenForBrowserRedirect() {
    final appLinks = AppLinks();

    unawaited(
      appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          _onBrowserRedirect(uri);
        }
      }),
    );

    _appLinkSub ??= appLinks.uriLinkStream.listen(_onBrowserRedirect);
  }

  void _onBrowserRedirect(Uri uri) {
    if (uri.scheme != 'protonmeet' || uri.host != 'login') {
      return;
    }

    final state = uri.queryParameters['state'];
    final expected = _expectedRedirectState;
    if (state == null || expected == null || state != expected) {
      logger.d('Desktop login redirect ignored: state mismatch');
      return;
    }

    _markBrowserAuthComplete();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = _browserAuthComplete
        ? _pollIntervalAfterBrowserAuth
        : _pollInterval;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(_poll()));
  }

  void _markBrowserAuthComplete() {
    if (_browserAuthComplete || !mounted) return;
    setState(() => _browserAuthComplete = true);
    _startPolling();
    unawaited(_poll());
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

      // Match password/native login: persist session first, then rebuild AppCore
      // from keychain. fetchUserState before save can refresh tokens in Rust while
      // we write the stale poll snapshot — breaks restore on next launch.
      final userInfo = UserInfo.fromProtonUserSession(session);
      await _appCoreManager.trySaveUserInfo(userInfo);
      await ManagerFactory().login(userInfo.userId);

      try {
        await _appCoreManager.appCore.fetchUserState(
          userId: userInfo.userId,
          forceRemote: true,
        );
      } catch (e, st) {
        logger.w(
          'Desktop web login fetchUserState after save failed: $e',
          stackTrace: st,
        );
      }

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
      _pollTimer?.cancel();
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _openLoginInSystemBrowser(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not open sign-in page');
    }
  }

  Future<void> _openBrowserAgain() async {
    final loginUrl = _loginUrl;
    if (loginUrl == null) return;
    await _openLoginInSystemBrowser(loginUrl);
  }

  Widget _buildSessionLoadingOverlay(BuildContext context) {
    return ColoredBox(
      color: context.colors.backgroundNorm.withValues(alpha: 0.92),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: context.colors.protonBlue),
              const SizedBox(height: 20),
              Text(
                'Finishing sign-in…',
                textAlign: TextAlign.center,
                style: ProtonStyles.body1Medium(color: context.colors.textNorm),
              ),
              const SizedBox(height: 8),
              Text(
                'Setting up your Proton Meet session.',
                textAlign: TextAlign.center,
                style: ProtonStyles.body2Regular(
                  color: context.colors.textWeak,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isStarting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return const SizedBox.shrink();
    }

    if (_showSessionLoadingOverlay) {
      return _buildSessionLoadingOverlay(context);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.local.desktop_login_complete_in_browser,
            textAlign: TextAlign.center,
            style: ProtonStyles.body1Medium(color: context.colors.textWeak),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => unawaited(_openBrowserAgain()),
            child: Text(
              context.local.desktop_login_open_browser_again,
              style: ProtonStyles.body2Medium(color: context.colors.protonBlue),
            ),
          ),
        ],
      ),
    );
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
                        context.local.sign_in_to_proton_title,
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
              Expanded(child: _buildContent(context)),
            ],
          ),
        ),
      ),
    );
  }
}
