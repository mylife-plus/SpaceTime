import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Register after super so Flutter has created `window` / root VC.
        let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.spacetime.app/settings",
                binaryMessenger: controller.binaryMessenger
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
        }

        return launched
    }
}
