import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/global_notification.dart';

/// Upcoming minimum iOS major version. Devices below this threshold still
/// work today but will be deprecated in a future release.
const int kIosFutureMinMajorVersion = 17;

/// Returns `true` on iOS when the major version is below [kIosFutureMinMajorVersion]
/// (still supported for now, scheduled for deprecation).
Future<bool> isDeprecatedIosVersion({DeviceInfoPlugin? deviceInfo}) async {
  if (!iOS) return false;
  try {
    final iosInfo = await (deviceInfo ?? DeviceInfoPlugin()).iosInfo;
    final majorVersion = int.tryParse(iosInfo.systemVersion.split('.').first);
    if (majorVersion == null) return false;
    return majorVersion < kIosFutureMinMajorVersion;
  } on Object {
    return false;
  }
}

/// Inline warning copy shared by the in-room global notification and dashboard card.
class OldIosSdkWarningMessage extends StatelessWidget {
  const OldIosSdkWarningMessage({this.textAlign = TextAlign.start, super.key});

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.local.old_ios_sdk_warning_message,
      style: ProtonStyles.body2Medium(color: context.colors.textInverted),
      textAlign: textAlign,
    );
  }
}

/// Shows a persistent orange warning when [OldIosSdkWarning] is enabled on
/// a deprecated iOS version.
void showOldIosSdkWarningNotification(BuildContext context) {
  GlobalNotification.show(
    contentWidget: const OldIosSdkWarningMessage(),
    backgroundColor: context.colors.signalWaning,
    duration: Duration.zero,
  );
}
