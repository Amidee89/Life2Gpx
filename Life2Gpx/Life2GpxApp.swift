//
//  Life2GpxApp.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//

import SwiftUI
import CoreLocation

@main
struct Life2GpxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let significantLocationChangeManager = SignificantLocationChangeManager()
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var locationManager = LocationManager()
    
    private let defaults = UserDefaults.standard
    private let settingsManager = SettingsManager.shared
    @AppStorage("disableTracking") private var disableTracking = SettingsManager.shared.disableTracking

    init() {
        // Singletons
        _ = SettingsManager.shared
        _ = FileManagerUtil.shared
        _ = PlaceManager.shared
        CoordinateConverter.restoreLastKnownDeviceLocation(from: CLLocationManager().location?.coordinate)
        LogManager.shared.logData(context: "AppLifecycle", content: "App Initialized.", verbosity: 2)
    }
       
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
        }
        .onChange(of: disableTracking) { _, newValue in
            if newValue {
                significantLocationChangeManager.stop()
                locationManager.stopAllTracking()
            } else {
                significantLocationChangeManager.start()
                locationManager.startAllTracking()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                let currentTime = Date()
                if !disableTracking {
                    locationManager.startHeadingUpdates()
                }
                LogManager.shared.logData(context: "AppLifecycle", content: "Scene became active at \(currentTime).", verbosity: 2)
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Scene phase \(oldPhase) -> active at \(currentTime)."
                )
                checkAndLoadTodayIfNeeded()
                iCloudBackupManager.shared.checkAndRunBackupIfNeeded()
            case .inactive:
                LogManager.shared.logData(context: "AppLifecycle", content: "Scene became inactive.", verbosity: 3)
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Scene phase \(oldPhase) -> inactive."
                )
                if oldPhase == .active {
                    let currentTime = Date()
                    defaults.set(currentTime, forKey: "LastActiveTime")
                    LogManager.shared.logData(context: "AppLifecycle", content: "Saved LastActiveTime: \(currentTime)", verbosity: 3)
                }
            case .background:
                let currentTime = Date()
                if !disableTracking {
                    locationManager.stopHeadingUpdates()
                }
                LogManager.shared.logData(context: "AppLifecycle", content: "Scene moved to background at \(currentTime).", verbosity: 2)
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Scene phase \(oldPhase) -> background at \(currentTime)."
                )
                defaults.set(currentTime, forKey: "LastActiveTime")
                LogManager.shared.logData(context: "AppLifecycle", content: "Saved LastActiveTime: \(currentTime)", verbosity: 3)
            @unknown default:
                LogManager.shared.logData(context: "AppLifecycle", content: "Scene entered unknown state.", verbosity: 2)
                ResourceDiagnostics.logRuntime(
                    context: "AppLifecycle",
                    detail: "Scene phase \(oldPhase) -> unknown."
                )
            }
        }
    }
    
    private func checkAndLoadTodayIfNeeded() {
        LogManager.shared.logData(context: "AppLifecycle", content: "Starting checkAndLoadTodayIfNeeded", verbosity: 2)
        
        let lastActiveDate = defaults.object(forKey: "LastActiveTime") as? Date
        let currentDate = Date()
        let autoRefreshInterval = settingsManager.loadCurrentDayOnRestoreAfterSeconds
        
        LogManager.shared.logData(context: "AppLifecycle", content: "Current time: \(currentDate)", verbosity: 5)
        LogManager.shared.logData(context: "AppLifecycle", content: "Last active time: \(lastActiveDate?.description ?? "nil")", verbosity: 5)
        LogManager.shared.logData(context: "AppLifecycle", content: "Auto refresh interval setting: \(autoRefreshInterval) seconds", verbosity: 5)
        
        let elapsedTime = currentDate.timeIntervalSince(lastActiveDate ?? Date.distantPast)
        LogManager.shared.logData(context: "AppLifecycle", content: "Elapsed time: \(elapsedTime) seconds", verbosity: 5)
        LogManager.shared.logData(context: "AppLifecycle", content: "Comparison: \(elapsedTime) > \(Double(autoRefreshInterval)) = \(elapsedTime > Double(autoRefreshInterval))", verbosity: 5)
        
        if elapsedTime > Double(autoRefreshInterval) {
            LogManager.shared.logData(context: "AppLifecycle", content: "✅ Elapsed time exceeded interval. Posting loadTodayData notification.", verbosity: 2)
            NotificationCenter.default.post(name: .loadTodayData, object: nil)
        } else {
            LogManager.shared.logData(context: "AppLifecycle", content: "❌ Elapsed time within interval. No need to load today.", verbosity: 5)
        }
        
        LogManager.shared.logData(context: "AppLifecycle", content: "Finished checkAndLoadTodayIfNeeded", verbosity: 5)
    }
}

extension Notification.Name {
    static let loadTodayData = Notification.Name("loadTodayData")
}
