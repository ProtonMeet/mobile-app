import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/external.url.dart';
import 'package:meet/helper/global_notification.dart';

/// Inline warning copy shared by the in-room global notification and dashboard card.
class MobileUpgradeWarningMessage extends StatefulWidget {
  const MobileUpgradeWarningMessage({
    this.textAlign = TextAlign.center,
    super.key,
  });

  final TextAlign textAlign;

  @override
  State<MobileUpgradeWarningMessage> createState() =>
      _MobileUpgradeWarningMessageState();
}

class _MobileUpgradeWarningMessageState
    extends State<MobileUpgradeWarningMessage> {
  late final TapGestureRecognizer _linkRecognizer;

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()
      ..onTap = ExternalUrl.shared.lanuchStore;
  }

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = ProtonStyles.body2Medium(
      color: context.colors.textInverted,
    );
    final linkStyle = ProtonStyles.body2Medium(color: const Color(0xff0047AB));

    return Text.rich(
      TextSpan(
        style: textStyle,
        children: [
          TextSpan(text: context.local.mobile_upgrade_warning_prefix),
          TextSpan(
            text: context.local.mobile_upgrade_warning_link,
            style: linkStyle,
            recognizer: _linkRecognizer,
          ),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}

/// Shows a persistent orange warning when [MeetMobileUpgradeWarning] is enabled.
void showMobileUpgradeWarningNotification(BuildContext context) {
  GlobalNotification.show(
    contentWidget: const MobileUpgradeWarningMessage(),
    backgroundColor: context.colors.signalWaning,
    duration: Duration.zero,
  );
}
