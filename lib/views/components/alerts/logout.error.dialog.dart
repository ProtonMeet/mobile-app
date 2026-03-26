import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/scenes/core/coordinator.dart';

void showLogoutErrorDialog(String errorMessage, VoidCallback onLogout) {
  final BuildContext? context = Coordinator.rootNavigatorKey.currentContext;
  if (context != null) {
    showDialog(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: context.colors.backgroundNorm,
          title: Center(child: Text(context.local.session_expired_title)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: Text(context.local.session_expired_content),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          actions: <Widget>[
            Center(
              child: SizedBox(
                height: 50,
                child: ButtonV5(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onLogout();
                  },
                  text: context.local.logout,
                  textStyle: ProtonStyles.body1Medium(
                    color: context.colors.textInverted,
                  ),
                  backgroundColor: context.colors.notificationError,
                  width: 300,
                  height: 55,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
