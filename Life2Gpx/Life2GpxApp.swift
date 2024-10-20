//
//  Life2GpxApp.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//

import SwiftUI

@main
struct Life2GpxApp: App {
    init() {
           // This ensures that `loadPlaces()` is called early on
           _ = PlaceManager.shared
       }
       
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
