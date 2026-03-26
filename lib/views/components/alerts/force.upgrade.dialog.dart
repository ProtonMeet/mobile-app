import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/external.url.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/views/components/button.v6.dart';
import 'package:meet/views/scenes/core/coordinator.dart';

Future<void> showUpgradeErrorDialog(
  String errorMessage,
  VoidCallback onLogout,
) async {
  EasyLoading.dismiss();
  final BuildContext? context = Coordinator.rootNavigatorKey.currentContext;
  if (context != null) {
    // Check if running from TestFlight
    final isTestFlight = await PlatformInfoChannel.isFromTestFlight();
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // user must tap button!
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: context.colors.backgroundNorm,
            title: Center(child: Text(context.local.force_upgrade)),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  SizedBox(
                    width: 300,
                    child: Text(
                      isTestFlight
                          ? 'Please update Proton Meet from TestFlight to continue using the app.'
                          : errorMessage,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            actions: <Widget>[
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    ButtonV6(
                      onPressed: () async {
                        if (isTestFlight) {
                          // For TestFlight, we can't directly open TestFlight app
                          // but we can still try to open App Store which will redirect
                          // or show a message. Actually, TestFlight users need to
                          // manually update from TestFlight app, so we'll just close
                          // the dialog and show the message.
                          Navigator.of(context).pop();
                        } else {
                          ExternalUrl.shared.lanuchStore();
                        }
                      },
                      text: isTestFlight ? 'OK' : context.local.upgrade,
                      textStyle: ProtonStyles.body1Medium(
                        color: context.colors.textInverted,
                      ),
                      backgroundColor: context.colors.protonBlue,
                      borderColor: context.colors.protonBlue,
                      width: 300,
                      height: 55,
                    ),
                    if (!isTestFlight) ...[
                      const SizedBox(height: 6),
                      ButtonV6(
                        onPressed: () async {
                          ExternalUrl.shared.lanuchForceUpgradeLearnMore();
                        },
                        text: context.local.learn_more,
                        backgroundColor: context.colors.interActionWeakDisable,
                        borderColor: context.colors.interActionWeakDisable,
                        textStyle: ProtonStyles.body1Medium(
                          color: context.colors.textNorm,
                        ),
                        width: 300,
                        height: 55,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      );
    }
  }
}
