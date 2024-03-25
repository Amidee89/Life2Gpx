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
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastBackgroundTime: Date? = nil
    let defaults = UserDefaults.standard
    let calendar = Calendar.current
    @State private var timelineHeight: CGFloat = 300
    @State private var timelineObjects: [TimelineObject] = []


    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                VStack
                {
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
                    .overlay(
                        VStack {
                            HStack{
                                Spacer()
                                if !calendar.isDate(selectedDate, inSameDayAs: Date()){
                                    Button(action: {
                                        self.selectedDate = Date()
                                    }
                                    ){
                                        Image(systemName: "forward")
                                            .font(.title)
                                            .padding()
                                            .background(Color.orange)
                                            .foregroundColor(.white)
                                            .clipShape(Circle())
                                            .shadow(radius: 3)
                                            .scaleEffect(0.8)
                                    }
                                    .padding(.trailing, 30)
                                    .padding(.top,30)
                                    .transition(.scale)
                                }
                            }                            
                            Group{
                                if !hasDataForSelectedDate{
                                    Text("No data for this day")
                                            .padding()
                                            .background(Color.black.opacity(0.8))
                                            .foregroundColor(Color.white)
                                            .cornerRadius(8)
                                            .padding()
                                }
                            }
                            Spacer()
                            HStack {
                                Button(action: recenter) {
                                    Image(systemName: "location.viewfinder")
                                        .font(.title)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                        .shadow(radius: 3)
                                        .scaleEffect(0.8)
                                }
                                .padding(.leading, 30)
                                .padding(.bottom, 30)
                                Spacer()
                                
                                Button(action: refreshData) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.title)
                                        .padding()
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                        .shadow(radius: 3)
                                        .scaleEffect(0.8)


                                }
                                .padding(.trailing, 30)
                                .padding(.bottom, 30)
                            }
                        },
                        alignment: .bottom
                    )
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            self.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: self.selectedDate)!
                        }) {
                            if (Calendar.current.isDate(selectedDate, equalTo: minDate, toGranularity: .day))
                            {
                                Image(systemName: "chevron.left")
                                    .padding(8)
                                    .foregroundColor(.gray)
                            }else
                            {
                                Image(systemName: "chevron.left")
                                    .padding(8)
                                    .foregroundColor(.blue)
                            }
                            
                        }
                        .disabled(Calendar.current.isDate(selectedDate, equalTo: minDate, toGranularity: .day))
                        
                        DatePicker("", selection: $selectedDate, in: minDate...maxDate, displayedComponents: .date)
                            .onChange(of: selectedDate) {
                                refreshData()
                                recenter()
                            }
                            .fixedSize()
                            .labelsHidden()
                        
                        Button(action: {
                            self.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: self.selectedDate)!
                        }) {

                            if (Calendar.current.isDate(selectedDate, equalTo: maxDate, toGranularity: .day))
                            {                            
                                Image(systemName: "chevron.right")
                                .padding(8)
                                .foregroundColor(.gray)

                            }else
                                {
                                Image(systemName: "chevron.right")
                                .padding(8)
                                .foregroundColor(.blue)

                            }
                        }
                        .disabled(Calendar.current.isDate(selectedDate, equalTo: maxDate, toGranularity: .day))

                        Spacer()
                    }
                    List(timelineObjects) { item in
                        HStack{
                            
                            VStack{
                                if let startDate = item.startDate {
                                    Text("\(formatDateToHoursMinutes(startDate))")
                                        .bold()
                                    
                                }
                                
                                Text(item.duration)
                                    
                                
                            }
                            .frame(minWidth: 90)
                            Group
                            {
                                if (item.type == .waypoint){
                                    
                                    Image(systemName: "smallcircle.filled.circle")
                                        .foregroundColor(.gray)
                                    
                                }
                                else
                                {
                                    switch item.trackType
                                    {
                                    case "cycling":
                                        Image(systemName: "figure.outdoor.cycle")
                                            .foregroundColor(trackTypeColorMapping[item.trackType ?? "cycling"])
                                        
                                    case "walking":
                                        Image(systemName: "figure.walk")
                                            .foregroundColor(trackTypeColorMapping[item.trackType ?? "walking"])
                                        
                                    case "running":
                                        Image(systemName: "figure.run")
                                            .foregroundColor(trackTypeColorMapping[item.trackType ?? "running"])
                                        
                                    case "automotive":
                                        Image(systemName: "car.fill")
                                            .foregroundColor(trackTypeColorMapping[item.trackType ?? "automotive"])
                                    default:
                                        Image(systemName: "arrow.down")
                                            .foregroundColor(trackTypeColorMapping[item.trackType ?? "unknown"])
                                    }
                                }
                            }    
                            .frame(minWidth: 20)

                            VStack (alignment:.leading)
                            {
                                if item.type == .waypoint
                                {
                                    Text(item.name ?? "Unknown place")
                                }
                                else
                                {
                                    Text(item.trackType?.capitalized ?? "Movement")
                                }
                                Text("Steps: \(item.steps)")

                            }

                        }
                    }
                    .refreshable {
                       refreshData()
                    }
                }

            }
            
            .navigationViewStyle(StackNavigationViewStyle())
            .onAppear {
                refreshData()
                recenter()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }

    private func recenter() {
        // Combine all coordinates from tracks and stop locations
        let allCoordinates = tracks.flatMap { $0.coordinates } + stopLocations.map { $0.coordinate }
        guard !allCoordinates.isEmpty else { return }

        // Find the max and min latitudes and longitudes
        let maxLat = allCoordinates.map { $0.latitude }.max()!
        let minLat = allCoordinates.map { $0.latitude }.min()!
        let maxLon = allCoordinates.map { $0.longitude }.max()!
        let minLon = allCoordinates.map { $0.longitude }.min()!

        // Calculate the span to include all points
        let latDelta = max(maxLat - minLat, 0.001) * 1.4
        let lonDelta = max(maxLon - minLon, 0.001) * 1.4

        //Calculate the center. Does this work if we pass from -180 to +180? I guess Fiji users will find out nicely.
        let centerLat = (maxLat + minLat) / 2
        let centerLon = (maxLon + minLon) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)

        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
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
                self.hasDataForSelectedDate = false
                self.tracks = []
                self.stopLocations = []
                return
            }

            stopLocations = gpxWaypoints.map {
                IdentifiableCoordinate(
                    coordinate: CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!),
                    waypoint: $0)
            }
            timelineObjects = gpxWaypoints.map {TimelineObject(
                type:.waypoint,
                startDate: $0.time,
                endDate: $0.time,
                name: $0.name,
                steps: Int($0.extensions?["Steps"].text ?? "0") ?? 0
                )
            }
            
            var trackDataArray: [TrackData] = []
            var steps = 0
            for (index, track) in gpxTracks.enumerated() {
                var trackCoordinates = track.segments.flatMap { $0.points }.map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) }
                
                // Check if this is not the last track and append the first point of the next track if necessary
                if index < gpxTracks.count - 1 {
                    let nextTrackFirstPoint = gpxTracks[index + 1].segments.first?.points.first
                    if let nextTrackFirstCoordinate = nextTrackFirstPoint {
                        trackCoordinates.append(CLLocationCoordinate2D(latitude: nextTrackFirstCoordinate.latitude!, longitude: nextTrackFirstCoordinate.longitude!))
                    }
                }
                let trackStartDate = track.segments.first?.points.first?.time ?? Date()
                //TODO here if day of date is different from day of track, put midnight of that day.
                let trackEndDate = track.segments.last?.points.last?.time ?? Date()
                for trackSegment in track.segments {
                    for trackPoint in trackSegment.points
                    {
                        steps += trackPoint.extensions?["Steps"] as? Int ?? 0
                    }
                }
                
                let trackObject = TimelineObject(type: .track, startDate: trackStartDate, endDate: trackEndDate, trackType: track.type, steps: steps)
                timelineObjects.append(trackObject)
                trackDataArray.append(TrackData(coordinates: trackCoordinates, trackType: track.type ?? ""))
            }
            self.timelineObjects = self.timelineObjects.sorted(by: { $0.startDate ?? Date.distantPast < $1.startDate ?? Date.distantPast })
            for (index, item) in timelineObjects.enumerated() {
                if item.type == .waypoint{
                    if index + 1 < timelineObjects.count {
                        item.endDate = timelineObjects[index + 1].startDate
                    } else
                    {
                        //TODO here if day of date is different from day of track, put midnight of that day.
                        item.endDate = Date()
                    }
                }
                if item.startDate != nil && item.endDate != nil
                {

                    item.duration = calculateDuration (from: item.startDate!, to: item.endDate!)
                }
            }
            
            self.tracks = trackDataArray
            self.hasDataForSelectedDate = true // Indicate data is available for this day
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            checkAndLoadTodayIfNeeded()
        case .background:
            defaults.set(Date(), forKey: "LastActiveTime")
        default:
            break
        }
    }
    
    private func checkAndLoadTodayIfNeeded() {
        guard let lastActiveDate = defaults.object(forKey: "LastActiveTime") as? Date else { return }
        let currentDate = Date()
        let elapsedTime = currentDate.timeIntervalSince(lastActiveDate)
        
        if elapsedTime > 3600 {
            selectedDate = currentDate
            loadFileForDate(selectedDate)
        }
    }
    
    private func formatDateToHoursMinutes(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // Hour:Minutes format
        return formatter.string(from: date)
    }
    
    private func calculateDuration(from startDate: Date, to endDate: Date) -> String {
        let interval = endDate.timeIntervalSince(startDate)
        let hours = Int(interval) / 3600 // Total seconds divided by number of seconds in an hour
        let minutes = Int(interval) % 3600 / 60 // Remainder of the above division, divided by number of seconds in a minute
        if (hours > 0){
            return String(format: "%01dh %01dm", hours, minutes)
        }else{
            return String(format: "%01dm",  minutes)

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
