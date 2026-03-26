import AVFoundation
import ActivityKit
import CommonCrypto
import CryptoKit
import Flutter
import ProtonCoreAuthentication
import ProtonCoreChallenge
import ProtonCoreCryptoGoImplementation
import ProtonCoreCryptoGoInterface
import ProtonCoreDataModel
import ProtonCoreFeatureFlags
import ProtonCoreFoundations
import ProtonCoreHumanVerification
import ProtonCoreLog
import ProtonCoreLogin
import ProtonCoreLoginUI
import ProtonCoreNetworking
import ProtonCorePayments
import ProtonCoreServices
import ProtonCoreSettings
import ProtonCoreUIFoundations
import Sentry
import UIKit
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    /// native code and this need to be refactored later
    private var apiService: PMAPIService?
    private var login: LoginAndSignup?
    private var paymentsManager: PaymentsManager?
    private var navigationChannel: FlutterMethodChannel?
    private var humanVerificationDelegate: HumanVerifyDelegate?
    private var authManager: AuthHelper?
    private let serviceDelegate = MeetApiServiceManager()

    private var getInAppTheme: () -> InAppTheme {
        return { .matchSystem }
    }

    /// Gets the root view controller from the active scene's window
    /// This is needed for UIScene-based apps where AppDelegate no longer manages the window
    private var rootViewController: UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            // Fallback: try to get any window from any connected scene
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene,
                    let window = windowScene.windows.first
                {
                    return window.rootViewController
                }
            }
            return nil
        }
        return window.rootViewController
    }

    override func application(
        _ app: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {

        // Handle App Intents from Dynamic Island
        if #available(iOS 16.2, *) {
            if userActivity.activityType.contains("ToggleMuteIntent") {
                _handleCallActivityAction("toggleMute")
                return true
            } else if userActivity.activityType.contains("ToggleSpeakerIntent") {
                _handleCallActivityAction("toggleSpeaker")
                return true
            } else if userActivity.activityType.contains("EndCallIntent") {
                _handleCallActivityAction("endCall")
                return true
            }
        }

        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else { return false }
        print("userActivity: \(url)")
        return true
    }

    private func _handleCallActivityAction(_ action: String) {
        // Send action to Flutter via method channel
        if let rootViewController = self.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "me.proton.meet/call_activity_action",
                binaryMessenger: rootViewController.binaryMessenger
            )

            switch action {
            case "toggleMute":
                channel.invokeMethod("toggleMute", arguments: nil)
            case "toggleSpeaker":
                channel.invokeMethod("toggleSpeaker", arguments: nil)
            case "endCall":
                channel.invokeMethod("endCall", arguments: nil)
            default:
                print("Unknown call activity action: \(action)")
            }
        }
    }

    // In AppDelegate.swift
    override func applicationDidEnterBackground(_ application: UIApplication) {
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        // End any active call activities when app terminates
        if #available(iOS 16.2, *) {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {  // <-- used detached here !!! magic
                print("Terminating live activities...")
                for activity in Activity<CallActivityWidgetAttributes>.activities {
                    print("Terminating live activity: \\(activity.id)")
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                semaphore.signal()
            }
            semaphore.wait()
            //            CallActivityManager.shared.endAll(immediately: true)
        }
    }

    override func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {

        if url.scheme == "protonmeet" && url.host == "call" {
            let action = url.pathComponents.last ?? ""
            print("Call activity action: \(action)")

            // Send action to Flutter via method channel
            if let rootViewController = self.rootViewController as? FlutterViewController {
                let channel = FlutterMethodChannel(
                    name: "me.proton.meet/call_activity_action",
                    binaryMessenger: rootViewController.binaryMessenger
                )

                switch action {
                case "toggleMute":
                    channel.invokeMethod("toggleMute", arguments: nil)
                case "toggleSpeaker":
                    channel.invokeMethod("toggleSpeaker", arguments: nil)
                case "endCall":
                    channel.invokeMethod("endCall", arguments: nil)
                default:
                    print("Unknown call activity action: \(action)")
                }
            }
            return true
        }

        // Determine who sent the URL.
        let sendingAppID = options[.sourceApplication]
        print("source application = \(sendingAppID ?? "Unknown")")

        // Process the URL.
        guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true),
            let albumPath = components.path,
            let params = components.queryItems
        else {
            print("Invalid URL or album path missing")
            return false
        }

        if let photoIndex = params.first(where: { $0.name == "index" })?.value {
            print("albumPath = \(albumPath)")
            print("photoIndex = \(photoIndex)")
            return true
        } else {
            print("Photo index missing")
            return false
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // SentrySDK.start { options in
        //     optionsdsn = "https://f430ab6a50234e50ab7fc57174de1cbc@sentry-new.protontech.ch/69"
        //     options.debug = true  // Enabled debug when first installing is always helpful
        //     // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
        //     options.tracesSampleRate = 1.0
        //     options.enableTracing = true
        // }

        // Inject crypto with the default implementation.
        injectDefaultCryptoImplementation()

        // FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        //     GeneratedPluginRegistrant.register(with: registry)
        // }
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
        }

        Brand.currentBrand = .wallet

        // Clean up any stale Live Activities on app launch
        if #available(iOS 16.2, *) {
            CallActivityManager.shared.cleanupStaleActivities()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CallActivityChannel")!
        CallActivityChannel.register(with: registrar)

        // Platform info channel for checking TestFlight status
        let platformInfoChannel = FlutterMethodChannel(
            name: "me.proton.meet/platform.info",
            binaryMessenger: engineBridge.applicationRegistrar.messenger())
        platformInfoChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "isFromTestFlight":
                result(Bundle.main.isFromTestFlight)
            case "isIOSAppOnMacOS":
                if #available(iOS 14.0, *) {
                    result(ProcessInfo.processInfo.isiOSAppOnMac)
                } else {
                    result(false)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let nativeViewChannel = FlutterMethodChannel(
            name: "me.proton.meet/native.views",
            binaryMessenger: engineBridge.applicationRegistrar.messenger())
        nativeViewChannel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            switch call.method {
            case "native.navigation.login", "native.navigation.signup":
                self.authManager = AuthHelper()
                apiService?.authDelegate = authManager
                if call.method == "native.navigation.login" {
                    print("Starting login.")
                    self.switchToSignIn()
                } else if call.method == "native.navigation.signup" {
                    print("Starting sign-up.")
                    self.switchToSignUp()
                }
            case "native.navigation.plan.upgrade":
                print("native.navigation.plan.upgrade")
                guard let arguments = call.arguments as? [Any] else {
                    PMLog.error("Call to native.navigation.plan.upgrade includes unknown arguments")
                    return
                }

                guard let sessionKey = arguments[0] as? String else {
                    PMLog.error("Call to native.navigation.plan.upgrade is missing session-key")
                    return
                }

                guard let authInfo = arguments[1] as? [String: Any] else {
                    PMLog.error(
                        "Call to native.navigation.plan.upgrade has malformed auth information")
                    return
                }

                self.showSubscriptionManagementScreen(
                    sessionKey: sessionKey,
                    authInfo: authInfo)
            case "native.initialize.core.environment":
                print("native.initialize.core.environment data:", call.arguments ?? "")
                if let arguments = call.arguments as? [String: Any] {
                    let environment = Environment(from: arguments)
                    AppVersionHeader.shared.parseFlutterData(from: arguments)
                    //                    PMLog.setEnvironment(environment: environment.type.title)
                    self.initAPIService(env: environment)
                    self.fetchUnauthFeatureFlags()
                } else {
                    result(
                        FlutterError(
                            code: "INVALID_ARGUMENTS",
                            message:
                                "Can't parse arguments. \"native.initialize.core.environment\" missing environment parameter.",
                            details: nil))
                }
            case "native.navigation.report":
                print("native.navigation.report triggered", call.arguments ?? "")
                if let arguments = call.arguments as? [String: Any],
                    let username = arguments["username"] as? String,
                    let email = arguments["email"] as? String
                {
                    self.switchToBugReport(
                        username: username,
                        email: email
                    )
                } else {
                    result(
                        FlutterError(
                            code: "INVALID_ARGUMENTS",
                            message:
                                "Can't parse arguments. \"native.nagivation.report\" missing username and email parameters.",
                            details: nil))
                }
            case "native.account.logout":
                self.authManager = AuthHelper()
                apiService?.authDelegate = authManager
                print("native.account.logout triggered")
                FeatureFlagsRepository.shared.clearUserId()
                FeatureFlagsRepository.shared.resetFlags()
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        navigationChannel = FlutterMethodChannel(
            name: "me.proton.meet/app.view",
            binaryMessenger: engineBridge.applicationRegistrar.messenger())

        //        // disable
        //        GeneratedPluginRegistrant.register(with: self)
        //
        //        let registrar = self.registrar(forPlugin: "CallActivityChannel")!
        //        CallActivityChannel.register(with: registrar)
        //
        // let channel = FlutterMethodChannel(
        //     name: "pip_channel",
        //     binaryMessenger: controller.binaryMessenger
        // )

        // Configure PiP with the Flutter root view
        // PipManager.shared.configureIfNeeded(rootView: controller.view)
        // channel.setMethodCallHandler { call, result in
        //     switch call.method {
        //     case "startPiP":
        //         guard let args = call.arguments as? [String: Any] else {
        //             result(
        //                 FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
        //             return
        //         }
        //         let remoteStreamId = args["remoteStreamId"] as? String ?? ""
        //         let peerConnectionId = args["peerConnectionId"] as? String ?? ""
        //         PipManager.shared.startPiP(
        //             peerConnectionId: peerConnectionId,
        //             remoteStreamId: remoteStreamId,
        //             result: result
        //         )

        //     case "stopPiP":
        //         PipManager.shared.stopPiP()
        //         result(true)

        //     case "disposePiP":
        //         PipManager.shared.disposePiP()
        //         result(true)

        //     default:
        //         result(FlutterMethodNotImplemented)
        //     }
        // }

    }
    func initAPIService(env: Environment) {
        PMAPIService.noTrustKit = true

        let challengeParametersProvider = ChallengeParametersProvider.forAPIService(
            clientApp: .wallet,
            challenge: PMChallenge())
        let apiService = PMAPIService.createAPIServiceWithoutSession(
            environment: env.toCoreEnv(),
            challengeParametersProvider: challengeParametersProvider)

        self.authManager = AuthHelper()
        self.humanVerificationDelegate = HumanCheckHelper(
            apiService: apiService,
            inAppTheme: getInAppTheme,
            clientApp: .wallet)
        apiService.authDelegate = authManager
        apiService.serviceDelegate = serviceDelegate
        apiService.humanDelegate = humanVerificationDelegate

        self.apiService = apiService
    }

    private func fetchUnauthFeatureFlags() {
        guard let apiService = self.apiService else {
            PMLog.error("APIService not set.")
            return
        }
        FeatureFlagsRepository.shared.setApiService(apiService)
        FeatureFlagsRepository.shared.setFlagOverride(CoreFeatureFlagType.dynamicPlan, true)

        Task {
            do {
                try await FeatureFlagsRepository.shared.fetchFlags()
            } catch {
                PMLog.error(error)
            }
        }
    }

    func initLoginAndSignup() {
        guard let apiService = self.apiService else {
            PMLog.error("APIService not set.")
            return
        }

        let appName = "Proton Meet"
        login = LoginAndSignup(
            appName: appName,
            clientApp: .wallet,
            apiService: apiService,
            minimumAccountType: .external,
            isCloseButtonAvailable: true,
            paymentsAvailability: .notAvailable,
            signupAvailability: getSignupAvailability
        )
    }

    private var getSignupAvailability: SignupAvailability {
        let signupAvailability: SignupAvailability
        let summaryScreenVariant: SummaryScreenVariant = .noSummaryScreen
        signupAvailability = .available(
            parameters: SignupParameters(
                separateDomainsButton: true,
                passwordRestrictions: .default,
                summaryScreenVariant: summaryScreenVariant))
        return signupAvailability
    }

    private var getShowWelcomeScreen: WelcomeScreenVariant? {
        return .wallet(
            .init(
                body:
                    "Create a new account or sign in with your existing Proton account to start using Proton Meet."
            ))
    }

    private var getAdditionalWork: WorkBeforeFlow? {
        return WorkBeforeFlow(stepName: "Additional work creation...") {
            loginData, flowCompletion in
            DispatchQueue.global(qos: .userInitiated).async {
                sleep(10)
                flowCompletion(.success(()))
            }
        }
    }

    func showAlert(
        title: String,
        message: String,
        actionTitle: String,
        actionBlock: @escaping () -> Void = {},
        over: UIViewController
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: actionTitle, style: .cancel,
                handler: { action in
                    actionBlock()
                    alert.dismiss(animated: true, completion: nil)
                }))
        over.present(alert, animated: true, completion: nil)
    }

    func onButtonTap() {
        //  switchToFlutterView()
    }

    private func sendDataToFlutter(jsonData: String) {
        navigationChannel?.invokeMethod("flutter.navigation.to.home", arguments: jsonData)
    }

    func switchToFlutterView(loginData: LoginData) {
        let jsonObject: [String: Any?] = [
            "sessionId": loginData.credential.sessionID,
            "userId": loginData.credential.userID,
            "userMail": loginData.user.email,
            "userName": loginData.user.name,
            "userDisplayName": loginData.user.displayName,
            "accessToken": loginData.credential.accessToken,
            "refreshToken": loginData.credential.refreshToken,
            "scopes": loginData.scopes.joined(separator: ","),
            "userKeyID": loginData.user.keys[0].keyID,
            "userPrivateKey": loginData.credential.privateKey,
            "userPassphraseSalt": loginData.salts[0].keySalt,
            "userPassphrase": loginData.passphrases[loginData.salts[0].ID],
            "mailboxpasswordKeySalt": loginData.credential.passwordKeySalt,
            "mailboxpassword": loginData.credential.mailboxpassword,
        ]

        let jsonData = try! JSONSerialization.data(
            withJSONObject: jsonObject, options: .prettyPrinted)
        let convertedString = String(data: jsonData, encoding: .utf8)!

        sendDataToFlutter(jsonData: convertedString)
    }

    func switchToSignIn() {
        guard let rootViewController = self.rootViewController else {
            PMLog.error("rootViewController must be set before calling \(#function)")
            return
        }

        print("Showing sign-in view")
        self.initLoginAndSignup()
        login?.presentLoginFlow(
            over: rootViewController,
            customization: LoginCustomizationOptions(
                performBeforeFlow: getAdditionalWork,
                inAppTheme: getInAppTheme
            ), updateBlock: processLoginResult)
    }

    func switchToSignUp() {
        guard let rootViewController = self.rootViewController else {
            PMLog.error("rootViewController must be set before calling \(#function)")
            return
        }

        print("Showing sign-up view")
        self.initLoginAndSignup()
        login?.presentSignupFlow(
            over: rootViewController,
            customization: LoginCustomizationOptions(
                performBeforeFlow: getAdditionalWork,
                inAppTheme: getInAppTheme
            ), updateBlock: processLoginResult)
    }

    func showSubscriptionManagementScreen(sessionKey: String, authInfo: [String: Any]) {
        guard let userId = authInfo["userId"] as? String else {
            PMLog.error("Cannot show subscription management screen.  Missing userId.")
            return
        }

        guard let apiService = self.apiService else {
            PMLog.error("Cannot show subscription management screen before APIService is set.")
            return
        }

        guard let accessToken = authInfo["accessToken"] as? String else {
            PMLog.error("Cannot show subscription management screen.  Missing userId.")
            return
        }

        guard let refreshToken = authInfo["refreshToken"] as? String else {
            PMLog.error("Cannot show subscription management screen.  Missing userId.")
            return
        }
        guard let userName = authInfo["userName"] as? String else {
            PMLog.error("Cannot show subscription management screen.  Missing userId.")
            return
        }
        guard let sessionId = authInfo["sessionId"] as? String else {
            PMLog.error("Cannot show subscription management screen.  Missing userId.")
            return
        }
        guard let scopes = authInfo["scopes"] as? [String] else {
            PMLog.error("Cannot show subscription management screen.  Missing userId.")
            return
        }
        apiService.setSessionUID(uid: sessionId)
        let auth = Credential(
            UID: sessionId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            userName: userName,
            userID: userId,
            scopes: scopes,
            mailboxPassword: "")
        let authDelegate = AuthHelper(credential: auth)
        apiService.authDelegate = authDelegate
        self.paymentsManager = PaymentsManager(
            storage: UserDefaults(),
            apiService: apiService,
            authManager: authDelegate)

        self.paymentsManager?.upgradeSubscription(completion: { [weak self] result in
            guard self != nil else { return }
            // nothing for now
        })
    }

    private func processLoginResult(_ result: LoginAndSignupResult) {
        switch result {
        case .loginStateChanged(.loginFinished):
            print("loginStateChanged(.loginFinished)")
        case .signupStateChanged(.signupFinished):
            print("signupStateChanged(.signupFinished)")
        case .loginStateChanged(.dataIsAvailable(let loginData)),
            .signupStateChanged(.dataIsAvailable(let loginData)):
            self.switchToFlutterView(loginData: loginData)
        case .dismissed:
            print("dismissed")
        }
    }

    func switchToBugReport(username: String, email: String) {
        guard let rootViewController = self.rootViewController else {
            PMLog.error("rootViewController must be set before calling \(#function)")
            return
        }
        guard let apiService else {
            PMLog.error("APIService not set.")
            return
        }
        let viewController = BugReportModule.makeBugReportViewController(
            apiService: apiService,
            username: username,
            email: email
        )
        rootViewController.present(viewController, animated: true)
    }

    func aMethodThatMightFail() throws {
        _ = try performRiskyOperation()
    }

    func performRiskyOperation() throws -> String {
        // Simulate a possible failure
        throw NSError(
            domain: "SimulatedErrorDomain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
    }

}
