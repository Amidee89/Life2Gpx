import UIKit
import SwiftUI
import UserNotifications
import BackgroundTasks

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
        LogManager.shared.logData(context: "AppLifecycle", content: "WillFinishLaunchingWithOptions called at \(Date())", verbosity: 1)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        LogManager.shared.logData(context: "AppLifecycle", content: "DidFinishLaunchingWithOptions called at \(Date())", verbosity: 1)
        NetworkDiagnostics.shared.start()
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "Launch runtime snapshot."
        )
        if let options = launchOptions, options[.location] != nil {
            LogManager.shared.logData(context: "AppLifecycle", content: "App launched due to location update.", verbosity: 2)
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.DeltaCygniLabs.Life2Gpx.backup", using: nil) { task in
            self.handleBackupTask(task: task as! BGProcessingTask)
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
        LogManager.shared.logData(context: "AppLifecycle", content: "ApplicationWillTerminate called at \(Date())", verbosity: 1)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationWillTerminate runtime snapshot."
        )
        
        // Disable the Dead Man's Switch since this is a clean exit (e.g., user force quit)
        // This is NOT called on a crash, which is exactly what we want.
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["DeadMansSwitch"])
        LogManager.shared.logData(context: "AppLifecycle", content: "Cancelled DeadMansSwitch on manual termination.", verbosity: 2)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        LogManager.shared.logData(context: "AppLifecycle", content: "ApplicationDidEnterBackground called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationDidEnterBackground runtime snapshot."
        )
        
        scheduleBackupTask()
    }

    func scheduleBackupTask() {
        guard SettingsManager.shared.iCloudBackupEnabled else { return }
        
        let request = BGProcessingTaskRequest(identifier: "com.DeltaCygniLabs.Life2Gpx.backup")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        if iCloudBackupManager.shared.isBackupDue() {
            request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        } else {
            request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        }
        
        do {
            try BGTaskScheduler.shared.submit(request)
            LogManager.shared.logData(context: "iCloudBackup", content: "Scheduled backup task.", verbosity: 3)
        } catch {
            LogManager.shared.logData(context: "iCloudBackup", content: "Could not schedule backup task: \(error)", verbosity: 1)
        }
    }

    private func handleBackupTask(task: BGProcessingTask) {
        scheduleBackupTask()
        
        guard iCloudBackupManager.shared.isBackupDue() else {
            task.setTaskCompleted(success: true)
            return
        }
        
        let operation = Task {
            await iCloudBackupManager.shared.runBackup()
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        LogManager.shared.logData(context: "AppLifecycle", content: "ApplicationWillEnterForeground called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationWillEnterForeground runtime snapshot."
        )
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        LogManager.shared.logData(context: "AppLifecycle", content: "ApplicationDidBecomeActive called at \(Date())", verbosity: 2)
        ResourceDiagnostics.logRuntime(
            context: "AppLifecycle",
            detail: "ApplicationDidBecomeActive runtime snapshot."
        )
    }

    func applicationWillResignActive(_ application: UIApplication) {
        LogManager.shared.logData(context: "AppLifecycle", content: "ApplicationWillResignActive called at \(Date())", verbosity: 2)
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
        
        LogManager.shared.logData(context: "AppLifecycle", content: "Notification received. Identifier: \(identifier)", verbosity: 3)
        
        if identifier == "UnknownPlaceCheckIn" {
            NotificationManager.shared.handleNotificationTap(userInfo: userInfo)
        } else if identifier == "UnknownTrackType" || (userInfo["notificationType"] as? String) == "unknownTrack" {
            NotificationManager.shared.handleUnknownTrackNotificationTap(userInfo: userInfo)
        } else if identifier == "DailyActivityRecap" || identifier == "DailyUnknownItemsRecap" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .loadTodayData, object: nil)
            }
        }
        
        completionHandler()
    }
} 
