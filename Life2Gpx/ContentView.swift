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
    @State private var selectedDate = Date()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pathCoordinates: [CLLocationCoordinate2D] = []
    @State private var stopLocations: [IdentifiableCoordinate] = []
    @State private var hasDataForSelectedDate = true // Track if there's data for the selected date

    var body: some View {
        NavigationView {
            VStack {
                if hasDataForSelectedDate {
                    Map(
                        position: .constant(MapCameraPosition.region(region)),
                        interactionModes: .all
                    ) {
                        // Use MapPolyline to display the path
                        MapPolyline(coordinates: pathCoordinates)
                            .stroke(.blue, lineWidth: 8)
                        ForEach(stopLocations) { location in
                            Annotation("Stop", coordinate: location.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(Color.black)
                                        .padding(4)
                                }
                            }
                            /*MapCircle(center: location.coordinate, radius: CLLocationDistance(20))
                                .foregroundStyle(.white .opacity(1.0))
                            MapCircle(center: location.coordinate, radius: CLLocationDistance(15))
                                .foregroundStyle(.black .opacity(1.0))*/
                        }
                    }
                    .edgesIgnoringSafeArea(.all)
                } else {
                    Text("No data for this day")
                        .foregroundColor(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: recenter) {
                        Text("Recenter")
                    }
                    Spacer()
                }
                ToolbarItem() {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .onChange(of: selectedDate) { newDate in
                            refreshData()
                        }
                    Spacer() 
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        Text("Refresh")
                    }
                    
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            recenter()
            refreshData() // Load initial data for the current date
        }
    }

    private func recenter() {
        if let userLocation = locationManager.currentLocation {
            region.center = userLocation.coordinate
            region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        }
    }

    private func refreshData() {
        loadFileForDate(selectedDate)
    }
    
    private func loadFileForDate(_ date: Date) {
        GPXManager.shared.loadFile(forDate: date) { dataContainer in
            guard let dataContainer = dataContainer else {
                DispatchQueue.main.async {
                    self.hasDataForSelectedDate = false // Indicate no data for this day
                    self.pathCoordinates = [] // Clear any existing pathCoordinates
                }
                return
            }

            var allWaypoints: [Waypoint] = dataContainer.waypoints
            for track in dataContainer.tracks {
                allWaypoints += track.segments.flatMap { $0.trackPoints }
            }
            stopLocations = dataContainer.waypoints.map{IdentifiableCoordinate(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), name: $0.name ?? "Stop")}

            let sortedWaypoints = allWaypoints.sorted(by: { $0.time < $1.time })
            DispatchQueue.main.async {
                self.pathCoordinates = sortedWaypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                if let firstCoordinate = self.pathCoordinates.first {
                    self.region.center = firstCoordinate
                }
                self.hasDataForSelectedDate = true // Indicate data is available for this day
            }
        }
    }
}


struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var name: String
}
