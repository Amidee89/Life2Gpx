//
//  ContentView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//

import SwiftUI
import MapKit

import SwiftUI
import MapKit


struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pathCoordinates: [CLLocationCoordinate2D] = []
    @State private var stopLocations: [IdentifiableCoordinate] = []

    var body: some View {
        NavigationView {
            Map(
                coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: stopLocations
            ) { location in
                MapAnnotation(coordinate: location.coordinate) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                }
            }
            .onAppear {
                loadFileForDate(Date())
            }
            .edgesIgnoringSafeArea(.all)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Recenter the map view to the user's current position
                        if let userLocation = locationManager.currentLocation {
                            region.center = userLocation.coordinate
                        }
                    }) {
                        Text("Recenter")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Refresh the data and redraw the map
                        loadFileForDate(Date())
                    }) {
                        Text("Refresh")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func loadFileForDate(_ date: Date) {
        GPXManager.shared.loadFile(forDate: date) { dataContainer in
            guard let dataContainer = dataContainer else { return }

            var allWaypoints: [Waypoint] = dataContainer.waypoints
            for track in dataContainer.tracks {
                for segment in track.segments {
                    allWaypoints.append(contentsOf: segment.trackPoints)
                }
            }

            // Sort by time
            allWaypoints.sort(by: { $0.time < $1.time })

            // Extract coordinates and update UI elements
            DispatchQueue.main.async {
                self.pathCoordinates = allWaypoints.compactMap { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                self.stopLocations = dataContainer.waypoints.compactMap {
                    IdentifiableCoordinate(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                }

                // Set map region to first coordinate if available
                if let firstCoordinate = self.pathCoordinates.first {
                    self.region.center = firstCoordinate
                }
            }
        }
    }

}
struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
}
