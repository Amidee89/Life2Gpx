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
    @State private var cameraPosition: MapCameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
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
                        position: $cameraPosition,
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
                            recenter()
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
            refreshData()
            recenter()
        }
    }

    private func recenter() {
        // Combine all coordinates from tracks and stop locations
        let allCoordinates = tracks.flatMap { $0.coordinates } + stopLocations.map { $0.coordinate }

        guard !allCoordinates.isEmpty else { return }
        print ("recentering")


        // Find the max and min latitudes and longitudes
        let maxLat = allCoordinates.map { $0.latitude }.max()!
        let minLat = allCoordinates.map { $0.latitude }.min()!
        let maxLon = allCoordinates.map { $0.longitude }.max()!
        let minLon = allCoordinates.map { $0.longitude }.min()!

        // Calculate the span to include all points
        let latDelta = maxLat - minLat
        let lonDelta = maxLon - minLon

        //Calculate the center. Does this work if we pass from -180 to +180? I guess Fiji users will find out nicely.
        let centerLat = (maxLat + minLat) / 2
        let centerLon = (maxLon + minLon) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

        
        // Increase the span slightly to ensure all points are comfortably within view
        let span = MKCoordinateSpan(latitudeDelta: latDelta * 1.4, longitudeDelta: lonDelta * 1.4)
        self.cameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: centerCoordinate, span: span))
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
                self.hasDataForSelectedDate = false // Indicate no data for this day
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
                
                trackDataArray.append(TrackData(coordinates: trackCoordinates, trackType: track.type ?? ""))
            }
            self.tracks = trackDataArray
            self.hasDataForSelectedDate = true // Indicate data is available for this day

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
