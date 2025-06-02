//
//  Life2GpxApp.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//

import SwiftUI

@main
struct Life2GpxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let significantLocationChangeManager = SignificantLocationChangeManager()
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var locationManager = LocationManager()
    
    private let defaults = UserDefaults.standard
    private let settingsManager = SettingsManager.shared

    init() {
        // Singletons
        _ = SettingsManager.shared
        _ = FileManagerUtil.shared
        _ = PlaceManager.shared
        FileManagerUtil.logData(context: "AppLifecycle", content: "App Initialized.", verbosity: 2)
    }
       
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                let currentTime = Date()
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene became active at \(currentTime).", verbosity: 2)
                checkAndLoadTodayIfNeeded()
            case .inactive:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene became inactive.", verbosity: 3)
            case .background:
                let currentTime = Date()
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene moved to background at \(currentTime).", verbosity: 2)
                defaults.set(currentTime, forKey: "LastActiveTime")
                FileManagerUtil.logData(context: "AppLifecycle", content: "Saved LastActiveTime: \(currentTime)", verbosity: 3)
            @unknown default:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene entered unknown state.", verbosity: 2)
            }
        }
    }
    
    private func checkAndLoadTodayIfNeeded() {
        FileManagerUtil.logData(context: "AppLifecycle", content: "Starting checkAndLoadTodayIfNeeded", verbosity: 2)
        
        let lastActiveDate = defaults.object(forKey: "LastActiveTime") as? Date
        let currentDate = Date()
        let autoRefreshInterval = settingsManager.loadCurrentDayOnRestoreAfterSeconds
        
        FileManagerUtil.logData(context: "AppLifecycle", content: "Current time: \(currentDate)", verbosity: 5)
        FileManagerUtil.logData(context: "AppLifecycle", content: "Last active time: \(lastActiveDate?.description ?? "nil")", verbosity: 5)
        FileManagerUtil.logData(context: "AppLifecycle", content: "Auto refresh interval setting: \(autoRefreshInterval) seconds", verbosity: 5)
        
        let elapsedTime = currentDate.timeIntervalSince(lastActiveDate ?? Date.distantPast)
        FileManagerUtil.logData(context: "AppLifecycle", content: "Elapsed time: \(elapsedTime) seconds", verbosity: 5)
        FileManagerUtil.logData(context: "AppLifecycle", content: "Comparison: \(elapsedTime) > \(Double(autoRefreshInterval)) = \(elapsedTime > Double(autoRefreshInterval))", verbosity: 5)
        
        if elapsedTime > Double(autoRefreshInterval) {
            FileManagerUtil.logData(context: "AppLifecycle", content: "✅ Elapsed time exceeded interval. Posting loadTodayData notification.", verbosity: 2)
            NotificationCenter.default.post(name: .loadTodayData, object: nil)
        } else {
            FileManagerUtil.logData(context: "AppLifecycle", content: "❌ Elapsed time within interval. No need to load today.", verbosity: 5)
        }
        
        FileManagerUtil.logData(context: "AppLifecycle", content: "Finished checkAndLoadTodayIfNeeded", verbosity: 5)
    }
}

extension Notification.Name {
    static let loadTodayData = Notification.Name("loadTodayData")
}
