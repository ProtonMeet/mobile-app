import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/global_notification.dart';

/// Upcoming minimum Android SDK (Android 9 / API 28). Devices below this
/// threshold still work today but will be deprecated in a future release.
const int kAndroidFutureMinSdk = 28;

/// Returns `true` on Android when [sdkInt] is below [kAndroidFutureMinSdk]
/// (still supported for now, scheduled for deprecation).
Future<bool> isDeprecatedAndroidSdk({DeviceInfoPlugin? deviceInfo}) async {
  if (!android) return false;
  try {
    final androidInfo = await (deviceInfo ?? DeviceInfoPlugin()).androidInfo;
    return androidInfo.version.sdkInt < kAndroidFutureMinSdk;
  } on Object {
    return false;
  }
}

/// Inline warning copy shared by the in-room global notification and dashboard card.
class OldAndroidSdkWarningMessage extends StatelessWidget {
  const OldAndroidSdkWarningMessage({
    this.textAlign = TextAlign.center,
    super.key,
  });

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.local.old_android_sdk_warning_message,
      style: ProtonStyles.body2Medium(color: context.colors.textInverted),
      textAlign: textAlign,
    );
  }
}

/// Shows a persistent orange warning when [OldAndroidSdkWarning] is enabled on
/// a deprecated Android version.
void showOldAndroidSdkWarningNotification(BuildContext context) {
  GlobalNotification.show(
    contentWidget: const OldAndroidSdkWarningMessage(),
    backgroundColor: context.colors.signalWaning,
    duration: Duration.zero,
  );
}
