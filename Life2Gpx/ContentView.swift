//
//  ContentView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//
import SwiftUI
import MapKit
import CoreGPX

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var selectedDate = Date()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var tracks: [TrackData] = [] // Changed to store tracks with type information
    @State private var stopLocations: [IdentifiableCoordinate] = []
    @State private var hasDataForSelectedDate = false
    @State private var minDate: Date = Date()
    @State private var maxDate: Date = Date()


    var body: some View {
        NavigationView {
            VStack {
                if hasDataForSelectedDate {
                    Map(
                        position: .constant(MapCameraPosition.region(region)),
                        interactionModes: .all
                    ) {
                        
                        // Use MapPolyline to display the path
                        ForEach(tracks, id: \.id) { track in
                            MapPolyline(coordinates: track.coordinates)
                                .stroke(trackTypeColorMapping[track.trackType.lowercased()] ?? .purple,
                                        style: StrokeStyle(lineWidth: 8,lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        }
                        ForEach(stopLocations) { location in
                            Annotation(location.waypoint.name ?? "Stop", coordinate: location.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(Color.black)
                                        .padding(4)
                                }
                            }
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
                    DatePicker("", selection: $selectedDate, in: minDate...maxDate, displayedComponents: .date)
                        .onChange(of: selectedDate) {
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
        GPXManager.shared.getDateRange { earliest, latest in
            if let earliestDate = earliest, let latestDate = latest {
                minDate = earliestDate
                maxDate = latestDate
            }
        }
        loadFileForDate(selectedDate)
    }
    
    private func loadFileForDate(_ date: Date) {
        GPXManager.shared.loadFile(forDate: date) { gpxWaypoints, gpxTracks in
            if gpxWaypoints.isEmpty && gpxTracks.isEmpty {
                DispatchQueue.main.async {
                    self.hasDataForSelectedDate = false // Indicate no data for this day
                }
                return
            }

            stopLocations = gpxWaypoints.map { IdentifiableCoordinate(coordinate: CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!), waypoint: $0) }
            
            var trackDataArray: [TrackData] = []
            
            for (index, track) in gpxTracks.enumerated() {
                var trackCoordinates = track.segments.flatMap { $0.points }.map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) }
                
                // Check if this is not the last track and append the first point of the next track if necessary
                if index < gpxTracks.count - 1 {
                    let nextTrackFirstPoint = gpxTracks[index + 1].segments.first?.points.first
                    if let nextTrackFirstCoordinate = nextTrackFirstPoint {
                        trackCoordinates.append(CLLocationCoordinate2D(latitude: nextTrackFirstCoordinate.latitude!, longitude: nextTrackFirstCoordinate.longitude!))
                    }
                }
                
                let trackType = track.type // This should be adjusted based on your actual data model
                trackDataArray.append(TrackData(coordinates: trackCoordinates, trackType: trackType ?? ""))
            }

            DispatchQueue.main.async {
                self.tracks = trackDataArray
                if let firstTrack = trackDataArray.first, let firstCoordinate = firstTrack.coordinates.first {
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
    var waypoint: GPXWaypoint
}
struct TrackData: Identifiable {
    let id = UUID()
    var coordinates: [CLLocationCoordinate2D]
    var trackType: String // "walking", etc.
}
