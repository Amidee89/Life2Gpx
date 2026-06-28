import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    private var memoryWarningObserver: NSObjectProtocol?

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FileManagerUtil.logData(context: "AppLifecycle", content: "WillFinishLaunchingWithOptions called at \(Date())", verbosity: 1)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FileManagerUtil.logData(context: "AppLifecycle", content: "DidFinishLaunchingWithOptions called at \(Date())", verbosity: 1)
        if let options = launchOptions, options[.location] != nil {
            FileManagerUtil.logData(context: "AppLifecycle", content: "App launched due to location update.", verbosity: 2)
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ResourceDiagnostics.logMemory(
                context: "AppLifecycle",
                detail: "Memory warning received — MapKit tiles and PhotoKit loads often stall under pressure."
            )
        }

        MemoryWatchdog.shared.start()

        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        ResourceDiagnostics.logMemory(
            context: "AppLifecycle",
            detail: "applicationDidReceiveMemoryWarning — system is reclaiming memory; graphics resources may fail to load."
        )
    }

    func applicationWillTerminate(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationWillTerminate called at \(Date())", verbosity: 1)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationDidEnterBackground called at \(Date())", verbosity: 2)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationWillEnterForeground called at \(Date())", verbosity: 2)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationDidBecomeActive called at \(Date())", verbosity: 2)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationWillResignActive called at \(Date())", verbosity: 2)
    }
} 
