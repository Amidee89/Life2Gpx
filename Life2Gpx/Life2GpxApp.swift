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

    init() {
           // This ensures that `loadPlaces()` is called early on
           _ = PlaceManager.shared
           FileManagerUtil.logData(context: "AppLifecycle", content: "App Initialized.")
       }
       
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene became active.")
            case .inactive:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene became inactive.")
            case .background:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene moved to background.")
            @unknown default:
                FileManagerUtil.logData(context: "AppLifecycle", content: "Scene entered unknown state.")
            }
        }
    }
}
