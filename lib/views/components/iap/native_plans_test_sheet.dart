import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/flutter_session_for_native_plans.dart';
import 'package:meet/managers/channels/platform.channel.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/models/native.session.model.dart';

/// Dev-only entry to exercise native IAP via `me.proton.meet/native.views`
/// (`native.navigation.plan.subscription` / `.upgrade`), matching wallet app flow.
class NativePlansTestSheet extends StatelessWidget {
  const NativePlansTestSheet({required this.session, super.key});

  final FlutterSession? session;

  static Future<void> show(BuildContext context) async {
    try {
      final enabled = ManagerFactory()
          .get<DataProviderManager>()
          .unleashDataProvider
          .isMeetInAppPurchaseEnabled();
      if (!enabled) return;
    } on Object {
      return;
    }

    final storage = ManagerFactory().get<SecureStorageManager>();
    final session = await flutterSessionForNativePlansChannel(storage);
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NativePlansTestSheet(session: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final channel = ManagerFactory().get<PlatformChannelManager>();

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.backgroundDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.local.iap_native_test_title,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.textNorm,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: context.colors.textNorm,
                  ),
                ],
              ),
              Text(
                context.local.iap_native_test_body,
                style: ProtonStyles.body2Medium(color: context.colors.textHint),
              ),
              const SizedBox(height: 16),
              if (session == null)
                Text(
                  context.local.iap_native_test_sign_in_required,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.signalDanger,
                  ),
                )
              else ...[
                FilledButton(
                  onPressed: () async {
                    final s = session;
                    if (s == null) return;
                    await channel.switchToSubscription(s);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(context.local.iap_native_test_current_plan),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final s = session;
                    if (s == null) return;
                    await channel.switchToUpgrade(s);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(context.local.iap_native_test_upgrade),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
