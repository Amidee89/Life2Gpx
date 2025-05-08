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
    // Instantiate the manager to start monitoring significant changes
    private let significantLocationChangeManager = SignificantLocationChangeManager()
    @Environment(\.scenePhase) private var scenePhase
    
    // Create the LocationManager instance using StateObject
    @StateObject private var locationManager = LocationManager()

    init() {
        // Initialize other singletons here
        _ = SettingsManager.shared
        _ = FileManagerUtil.shared
        _ = PlaceManager.shared // Initialize PlaceManager
        FileManagerUtil.logData(context: "AppLifecycle", content: "App Initialized.", verbosity: 2)
    }
       
    var body: some Scene {
        WindowGroup {
            // Pass the locationManager into the environment
            ContentView()
                .environmentObject(locationManager)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene became active.", verbosity: 3)
            case .inactive:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene became inactive.", verbosity: 3)
            case .background:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene moved to background.", verbosity: 3)
            @unknown default:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene entered unknown state.", verbosity: 2)
            }
        }
    }
}
