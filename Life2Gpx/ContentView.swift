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
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var locationManager = LocationManager()

    @State private var selectedDate = Date()
    @State private var cameraPosition: MapCameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
    @State private var minDate: Date = Date()
    @State private var maxDate: Date = Date()
    @State private var lastBackgroundTime: Date? = nil
    @State private var timelineObjects: [TimelineObject] = []
    
    let defaults = UserDefaults.standard
    let calendar = Calendar.current

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
                        ForEach(timelineObjects.filter { $0.type == .track }, id: \.id) { trackObject in
                              ForEach(trackObject.identifiableCoordinates, id: \.id) { identifiableCoordinates in
                                  MapPolyline(coordinates: identifiableCoordinates.coordinates)
                                      .stroke(trackTypeColorMapping[trackObject.trackType?.lowercased() ?? "unknown"] ?? .purple, 
                                              style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                              }
                        }
                        
                        ForEach(timelineObjects.filter { $0.type == .waypoint }, id: \.id) { waypointObject in
                            if let coordinate = waypointObject.identifiableCoordinates.first?.coordinates.first
                            {
                                Annotation(waypointObject.name ?? "Stop", coordinate: coordinate)
                                {
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
                                if timelineObjects.isEmpty{
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
                            .frame(minWidth: 30)

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
                                HStack{
                                    if item.meters > 0 {
                                        if item.meters < 1000{
                                            Text("\(item.meters) m")
                                                .font(.footnote)
                                        }else{
                                            Text("\(item.meters/1000) km")
                                                .font(.footnote)
                                        }
                                    }
                                    if item.steps > 0{
                                        Text("\(item.steps) steps")
                                            .font(.footnote)
                                    }
                                    if item.averageSpeed > 0 {
                                        Text("\(String(format: "%.1f", item.averageSpeed)) km/h")
                                            .font(.footnote)
                                    }
                                    if item.numberOfPoints == 1 {
                                        Text("\(item.numberOfPoints) point")
                                            .font(.footnote)
                                    } else if item.numberOfPoints > 1 {
                                        Text("\(item.numberOfPoints) points")
                                            .font(.footnote)
                                    }
                                    
                                }
                            }.padding(3)

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
        let allCoordinates = timelineObjects.flatMap { $0.identifiableCoordinates.flatMap {$0.coordinates} }
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
        loadTimelineForDate(selectedDate) { timelineObjects in
            self.timelineObjects = timelineObjects
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
            refreshData()
        }
    }
    
    private func formatDateToHoursMinutes(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // Hour:Minutes format
        return formatter.string(from: date)
    }
}
