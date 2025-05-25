import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FileManagerUtil.logData(context: "AppLifecycle", content: "Application willFinishLaunchingWithOptions.", verbosity: 2)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FileManagerUtil.logData(context: "AppLifecycle", content: "Application didFinishLaunchingWithOptions.", verbosity: 2)
        if let options = launchOptions, options[.location] != nil {
            FileManagerUtil.logData(context: "AppLifecycle", content: "App launched due to location update.", verbosity: 2)
        }
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "Application will terminate.", verbosity: 1)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
         FileManagerUtil.logData(context: "AppLifecycle", content: "Application did enter background (AppDelegate).", verbosity: 3)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
         FileManagerUtil.logData(context: "AppLifecycle", content: "Application will enter foreground (AppDelegate).", verbosity: 3)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "Application did become active (AppDelegate).", verbosity: 3)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "Application will resign active (AppDelegate).", verbosity: 3)
    }
} 
