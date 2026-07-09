import UIKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var memoryWarningObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FileManagerUtil.logData(context: "AppLifecycle", content: "WillFinishLaunchingWithOptions called at \(Date())", verbosity: 1)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        FileManagerUtil.logData(context: "AppLifecycle", content: "DidFinishLaunchingWithOptions called at \(Date())", verbosity: 1)
        NetworkDiagnostics.shared.start()
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "Launch runtime snapshot."
        )
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

        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
                object: nil,
                queue: .main
            ) { _ in
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Protected data will become unavailable."
                )
            }
        )

        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: .main
            ) { _ in
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Protected data became available."
                )
            }
        )

        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Thermal state changed."
                )
            }
        )

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
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationWillTerminate runtime snapshot."
        )
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationDidEnterBackground called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationDidEnterBackground runtime snapshot."
        )
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationWillEnterForeground called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationWillEnterForeground runtime snapshot."
        )
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationDidBecomeActive called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationDidBecomeActive runtime snapshot."
        )
    }

    func applicationWillResignActive(_ application: UIApplication) {
        FileManagerUtil.logData(context: "AppLifecycle", content: "ApplicationWillResignActive called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationWillResignActive runtime snapshot."
        )
    }
    
    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        
        FileManagerUtil.logData(context: "AppLifecycle", content: "Notification received. Identifier: \(identifier)", verbosity: 3)
        
        if identifier == "UnknownPlaceCheckIn" {
            NotificationManager.shared.handleNotificationTap(userInfo: userInfo)
        }
        
        completionHandler()
    }
} 
