import UIKit
import Flutter
import CoreLocation
import background_downloader

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.spacetime.app/settings", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { (call, result) in
        if call.method == "getBackgroundRefreshStatus" {
            let status = UIApplication.shared.backgroundRefreshStatus
            switch status {
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

}
