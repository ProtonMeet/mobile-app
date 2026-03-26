//
abstract class NavigationFlowInterface {
  Future<void> move(NavID to);
}

enum NavID {
  root,
  setupBackup,
  setupReady,

  // Home and Welcome
  welcome,
  home,

  // Home sub views
  acceptTermsConditionDialog,
  protonProducts,
  upgrade,
  sendInvite,
  importSuccess,

  // Transactions
  send,
  sendReview,
  receive,
  history,
  historyDetails,
  // buy
  buy,
  buyUnavailable,
  rampExternal,
  banaxExternal,
  moonpayExternal,

  // upgrade
  nativeUpgrade,
  // Report bugs
  natvieReportBugs,

  // Security
  passphrase,
  twoFactorAuthSetup,
  twoFactorAuthDisable,
  securitySetting,
  recovery,

  // Mail integration
  mailList,
  mailEdit,

  // Auth/Login/Signup
  nativeSignin,
  nativeSignup,
  signin,
  signup,
  logout,

  // Feeds
  discover,

  // RBF
  rbf,

  // Settings
  settings,
  logs,

  newuser,
}
