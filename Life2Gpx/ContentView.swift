//
//  ContentView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//
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
                position: .constant(MapCameraPosition.region(region)),
                interactionModes: .all
            ) {
                ForEach(stopLocations) { location in
                    Annotation("Stop", coordinate: location.coordinate) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: recenter) {
                        Text("Recenter")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        Text("Refresh")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func recenter() {
        if let userLocation = locationManager.currentLocation {
            region.center = userLocation.coordinate
        }
    }
    
    private func refreshData() {
        loadFileForDate(Date())
    }
    
    private func loadFileForDate(_ date: Date) {
        GPXManager.shared.loadFile(forDate: date) { dataContainer in
            guard let dataContainer = dataContainer else { return }

            var allWaypoints: [Waypoint] = dataContainer.waypoints
            for track in dataContainer.tracks {
                allWaypoints += track.segments.flatMap { $0.trackPoints }
            }

            // Sort by time and update UI
            let sortedWaypoints = allWaypoints.sorted(by: { $0.time < $1.time })
            DispatchQueue.main.async {
                self.pathCoordinates = sortedWaypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                self.stopLocations = sortedWaypoints.map {
                    IdentifiableCoordinate(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                }
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
