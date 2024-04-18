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
    @State private var selectedTimelineObjectID: UUID?

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
                        
                        HStack {
                            
                            VStack (alignment: .trailing ){
                                if let startDate = item.startDate {
                                    Text("\(formatDateToHoursMinutes(startDate))")
                                        .bold()
                                }
                                Text(item.duration)
                            }
                            .frame(minWidth:80, alignment: .trailing)
                            HStack {
                                VStack(alignment: .center)
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
                                .frame(width: 35, alignment: .center)
                            }

                            VStack (alignment: .leading)
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
                                        }
                                        else{
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
                                    
                                    
                                }
                                if item.numberOfPoints == 1 {
                                    Text("\(item.numberOfPoints) point")
                                        .font(.footnote)
                                } 
                                else if item.numberOfPoints > 1 {
                                    Text("\(item.numberOfPoints) points")
                                        .font(.footnote)
                                }
                            }
                        }
                        //.listRowSeparator(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading) // Extend HStack
                        .contentShape(Rectangle()) // Make the entire area tappable

                        .alignmentGuide(.listRowSeparatorLeading)
                            { viewDimensions in viewDimensions[.leading] }
                        //.background(item.id == selectedTimelineObjectID ? Color.blue.opacity(0.3) : Color.clear)
                        .onTapGesture {
                            withAnimation {
                                selectAndCenter(item)
                            }
                        }

                        .listRowBackground(item.id == selectedTimelineObjectID ? Color.blue.opacity(0.3) : Color.clear)

                    }
                    .refreshable {
                       refreshData()
                        
                    }
                    .listStyle(PlainListStyle())
                    
    
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
        let allCoordinates = timelineObjects.flatMap { $0.identifiableCoordinates.flatMap { $0.coordinates } }
        guard !allCoordinates.isEmpty else { return }

        let centerLat = (allCoordinates.map { $0.latitude }.max()! + allCoordinates.map { $0.latitude }.min()!) / 2
        let centerLon = (allCoordinates.map { $0.longitude }.max()! + allCoordinates.map { $0.longitude }.min()!) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = calculateSpan(for: allCoordinates)
        self.cameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: centerCoordinate, span: span))
    }
    
    private func selectAndCenter(_ item: TimelineObject) {
         // Deselect all and select the current one
         for index in timelineObjects.indices {
             timelineObjects[index].selected = false
         }
         if let index = timelineObjects.firstIndex(where: { $0.id == item.id }) {
             timelineObjects[index].selected = true
             selectedTimelineObjectID = item.id
             recenterOn(coordinates: timelineObjects[index].identifiableCoordinates.flatMap { $0.coordinates })
         }
     }
    
    private func recenterOn(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        let centerLat = (coordinates.map { $0.latitude }.max()! + coordinates.map { $0.latitude }.min()!) / 2
        let centerLon = (coordinates.map { $0.longitude }.max()! + coordinates.map { $0.longitude }.min()!) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = calculateSpan(for: coordinates)
        cameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: centerCoordinate, span: span))
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
    
    func calculateSpan(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateSpan {
        guard !coordinates.isEmpty else { return MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05) }

        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!

        let latDelta = max(maxLat - minLat, 0.001) * 1.4
        let lonDelta = max(maxLon - minLon, 0.001) * 1.4

        return MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
    }

}
