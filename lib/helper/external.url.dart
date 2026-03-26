import 'package:flutter/foundation.dart';
import 'package:meet/constants/app.config.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalUrl {
  // Private constructor
  ExternalUrl._privateConstructor();

  // Static instance
  static final ExternalUrl _instance = ExternalUrl._privateConstructor();

  // Named constructor to return the singleton instance
  static ExternalUrl get shared => _instance;

  // Final variable for account URL
  final String accountUrl = "https://account.proton.me";
  final String mainSiteUrl = "https://proton.me/";
  final String supportCenterUrl = "https://proton.me/support/meet";
  final String terms = "https://proton.me/legal/terms";
  final String encryptionKeys =
      "https://account.proton.me/mail/encryption-keys";
  final String dataRecovery =
      "https://proton.me/support/recover-encrypted-messages-files";
  final String privacy = "https://proton.me/meet/privacy-policy";
  final String meetHomepage =
      appConfig.apiEnv.baseUrl; // "https://meet.proton.me";

  /// android app store url
  final String googlePlayUrl =
      "https://play.google.com/store/apps/details?id=proton.android.meet";

  /// ios app store url
  final String appStoreUrl = "https://apps.apple.com/app/id6745089447";

  final String upgradeRequired = "https://proton.me/support/update-required";

  final String protonMailGooglePlayUrl =
      "https://play.google.com/store/apps/details?id=ch.protonmail.android";

  final String protonCalendarGooglePlayUrl =
      "https://play.google.com/store/apps/details?id=me.proton.android.calendar";

  final String protonDriveGooglePlayUrl =
      "https://play.google.com/store/apps/details?id=me.proton.android.drive";

  final String protonPassGooglePlayUrl =
      "https://play.google.com/store/apps/details?id=proton.android.pass";

  final String protonMailAppStoreUrl =
      "https://apps.apple.com/us/app/proton-mail-encrypted-email/id979659905";

  final String protonCalendarAppStoreUrl =
      "https://apps.apple.com/us/app/proton-calendar-secure-events/id1514709943";

  final String protonDriveAppStoreUrl =
      "https://apps.apple.com/us/app/proton-drive-photo-backup/id1509667851";

  final String protonPassAppStoreUrl =
      "https://apps.apple.com/us/app/proton-pass-password-manager/id6443490629";

  final String protonMailUrl = "https://proton.me/mail";
  final String protonCalendarUrl = "https://proton.me/calendar";
  final String protonDriveUrl = "https://proton.me/drive";
  final String protonPassUrl = "https://proton.me/pass";
  final String protonMeetUrl = "https://proton.me/meet";
  final String protonWalletUrl = "https://proton.me/wallet";
  final String protonForBusinessUrl = "https://proton.me/business";

  // Method to launch a URL
  void launchString(String strUrl) {
    launchUrl(Uri.parse(strUrl), mode: LaunchMode.externalApplication);
  }

  void lanuchMainSite() {
    launchString(mainSiteUrl);
  }

  // Method to launch the Proton account URL
  void launchProtonAccount() {
    launchString(accountUrl);
  }

  void launchProtonHelpCenter() {
    launchString(supportCenterUrl);
  }

  void lanuchTerms() {
    launchString(terms);
  }

  void launchEncryptionKeys() {
    launchString(encryptionKeys);
  }

  void launchDataRecovery() {
    launchString(dataRecovery);
  }

  void lanuchPrivacy() {
    launchString(privacy);
  }

  void lanuchGooglePlay() {
    launchString(googlePlayUrl);
  }

  void lanuchAppStore() {
    launchString(appStoreUrl);
  }

  void launchProtonMail() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      launchString(protonMailGooglePlayUrl);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      launchString(protonMailAppStoreUrl);
    } else {
      launchString(protonMailUrl);
    }
  }

  void launchProtonCalendar() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      launchString(protonCalendarGooglePlayUrl);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      launchString(protonCalendarAppStoreUrl);
    } else {
      launchString(protonCalendarUrl);
    }
  }

  void launchProtonDrive() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      launchString(protonDriveGooglePlayUrl);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      launchString(protonDriveAppStoreUrl);
    } else {
      launchString(protonDriveUrl);
    }
  }

  void launchProtonPass() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      launchString(protonPassGooglePlayUrl);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      launchString(protonPassAppStoreUrl);
    } else {
      launchString(protonPassUrl);
    }
  }

  void launchProtonForBusiness() {
    launchString(protonForBusinessUrl);
  }

  void lanuchStore() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      lanuchGooglePlay();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      lanuchAppStore();
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      lanuchAppStore();
    } else {
      lanuchMainSite();
    }
  }

  void lanuchForceUpgradeLearnMore() {
    launchString(upgradeRequired);
  }
}
