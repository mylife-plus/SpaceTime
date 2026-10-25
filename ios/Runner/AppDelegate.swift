import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    /// Owned here (not by a storyboard) so the scene delegate can attach a
    /// FlutterViewController to it — required by the UIScene life cycle that
    /// the iOS 26+ SDK enforces.
    lazy var flutterEngine = FlutterEngine(name: "spacetime_main_engine")

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        flutterEngine.run()
        GeneratedPluginRegistrant.register(with: flutterEngine)

        let channel = FlutterMethodChannel(
            name: "com.spacetime.app/settings",
            binaryMessenger: flutterEngine.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            if call.method == "getBackgroundRefreshStatus" {
                switch UIApplication.shared.backgroundRefreshStatus {
                case .available:
                    result("available")
                case .denied:
                    result("denied")
                case .restricted:
                    result("restricted")
                @unknown default:
                    result("unknown")
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "flutter", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
