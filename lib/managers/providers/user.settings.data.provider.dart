// import 'dart:async';
// import 'dart:math';

// import 'package:sentry/sentry.dart';
// import 'package:meet/constants/app.config.dart';
// import 'package:meet/constants/constants.dart';
// import 'package:meet/helper/common.helper.dart';
// import 'package:meet/helper/extension/enum.extension.dart';
// import 'package:meet/helper/logger.dart';
// import 'package:meet/managers/preferences/preferences.keys.dart';
// import 'package:meet/managers/preferences/preferences.manager.dart';
// import 'package:meet/managers/providers/data.provider.manager.dart';
// import 'package:meet/managers/services/exchange.rate.service.dart';
// import 'package:meet/models/drift/db/app.database.dart';
// import 'package:meet/rust/api/api_service/settings_client.dart';
// import 'package:meet/rust/proton_api/exchange_rate.dart';
// import 'package:meet/rust/proton_api/user_settings.dart';

// class UserSettingDataUpdated extends DataState {
//   UserSettingDataUpdated();

//   @override
//   List<Object?> get props => [];
// }

// class FiatCurrencyDataUpdated extends DataState {
//   FiatCurrencyDataUpdated();

//   @override
//   List<Object?> get props => [];
// }

// class ExchangeRateDataUpdated extends DataState {
//   ExchangeRateDataUpdated();

//   @override
//   List<Object?> get props => [];
// }

// class BitcoinUnitDataUpdated extends DataState {
//   BitcoinUnitDataUpdated();

//   @override
//   List<Object?> get props => [];
// }

// class DisplayBalanceUpdated extends DataState {
//   DisplayBalanceUpdated();

//   @override
//   List<Object?> get props => [];
// }

// class UserSettingsDataProvider extends DataProvider {
//   /// user id
//   final String userID;

//   /// api client
//   final SettingsClient settingsClient;

//   /// shared preference
//   final PreferencesManager shared;

//   /// provider boolean flags
//   bool initializedExchangeRate = false;
//   bool displayBalance = true;

//   /// memory caches
//   int customStopgap = appConfig.stopGap;
//   ProtonExchangeRate exchangeRate = defaultExchangeRate;
//   BitcoinUnit bitcoinUnit = BitcoinUnit.btc;
//   FiatCurrency fiatCurrency = FiatCurrency.usd;

//   UserSettingsDataProvider(
//     this.userID,
//     this.settingsQueries,
//     this.settingsClient,
//     this.shared,
//   );

//   /// streams
//   final dataUpdateController = StreamController<UserSettingDataUpdated>();
//   final exchangeRateUpdateController =
//       StreamController<ExchangeRateDataUpdated>();
//   final fiatCurrencyUpdateController =
//       StreamController<FiatCurrencyDataUpdated>();
//   final bitcoinUnitUpdateController =
//       StreamController<BitcoinUnitDataUpdated>();
//   final displayBalanceUpdateController =
//       StreamController<DisplayBalanceUpdated>();

//   Future<void> loadFromServer() async {
//     try {
//       final apiSettings = await settingsClient.getUserSettings();
//       insertUpdate(apiSettings);
//     } catch (e, stacktrace) {
//       logger.e("error: $e, stacktrace: $stacktrace");
//     }
//   }

//   Future<void> setCustomStopgap(stopgap) async {
//     customStopgap = stopgap;
//     await shared.write(PreferenceKeys.customStopgapKey, stopgap);
//   }

//   Future<int> getCustomStopgap() async {
//     customStopgap =
//         await shared.read(PreferenceKeys.customStopgapKey) ?? appConfig.stopGap;

//     /// cap customStopgap in valid range (10, 200) to avoid abuse
//     customStopgap = min(max(customStopgap, 10), 200);
//     return customStopgap;
//   }

//   Future<void> setDisplayBalance(display) async {
//     displayBalance = display;
//     await shared.write(PreferenceKeys.displayBalanceKey, displayBalance);
//     displayBalanceUpdateController.add(DisplayBalanceUpdated());
//   }

//   Future<bool> getDisplayBalance() async {
//     displayBalance =
//         await shared.read(PreferenceKeys.displayBalanceKey) ?? true;
//     return displayBalance;
//   }

//   void updateBitcoinUnit(BitcoinUnit bitcoinUnit) {
//     this.bitcoinUnit = bitcoinUnit;
//     bitcoinUnitUpdateController.add(BitcoinUnitDataUpdated());
//   }

//   Future<void> acceptTermsAndConditions() async {
//     await settingsClient.acceptTermsAndConditions();

//     /// reload local db and cache
//     await loadFromServer();
//     settingsData = await _getFromDB();
//   }

//   Future<void> updateReceiveEmailIntegrationNotification(isEnable) async {
//     try {
//       await settingsClient.receiveNotificationEmail(
//           emailType: UserReceiveNotificationEmailTypes.emailIntegration,
//           isEnable: isEnable);
//     } catch (e, stacktrace) {
//       Sentry.captureException(e, stackTrace: stacktrace);
//     }

//     /// reload local db and cache
//     await loadFromServer();
//     settingsData = await _getFromDB();
//   }

//   Future<void> updateReceiveInviterNotification(isEnable) async {
//     try {
//       await settingsClient.receiveNotificationEmail(
//         emailType: UserReceiveNotificationEmailTypes.notificationToInviter,
//         isEnable: isEnable,
//       );
//     } catch (e, stacktrace) {
//       Sentry.captureException(e, stackTrace: stacktrace);
//     }

//     /// reload local db and cache
//     await loadFromServer();
//     settingsData = await _getFromDB();
//   }

//   void updateExchangeRate(ProtonExchangeRate exchangeRate) {
//     this.exchangeRate = exchangeRate;
//     exchangeRateUpdateController.add(ExchangeRateDataUpdated());
//   }

//   @override
//   Future<void> clear() async {
//     settingsQueries.clearTable();
//     dataUpdateController.close();
//     exchangeRateUpdateController.close();
//     fiatCurrencyUpdateController.close();
//     bitcoinUnitUpdateController.close();
//     displayBalanceUpdateController.close();
//   }

//   @override
//   Future<void> reload() async {}
// }
