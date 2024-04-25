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
                    MapView(timelineObjects: $timelineObjects, selectedTimelineObjectID: $selectedTimelineObjectID,
                            cameraPosition: $cameraPosition
                    )
                    .overlay(
                        MapControlsView(
                            onRefresh: refreshData,
                            onCenter: centerAllData,
                            onSelectToday: { selectedDate = Date() },
                            selectedDate: $selectedDate,
                            timelineObjects: $timelineObjects
                        )
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
                                centerAllData()
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
                    TimelineView(
                        timelineObjects: $timelineObjects,
                        selectedTimelineObjectID: $selectedTimelineObjectID,
                        onRefresh: refreshData, 
                        onSelectItem: selectAndCenter
                    )
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .onAppear {
                refreshData()
                centerAllData()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }

    private func centerAllData() {
        let allCoordinates = timelineObjects.flatMap { $0.identifiableCoordinates.flatMap { $0.coordinates } }
        if !allCoordinates.isEmpty {
            withAnimation (.easeInOut(duration: 0.5)){
                recenterOn(coordinates: allCoordinates)
            }
            self.selectedTimelineObjectID = nil
        }
    }
    
    private func selectAndCenter(_ item: TimelineObject) {
         // Deselect all and select the current one
         for index in timelineObjects.indices {
             timelineObjects[index].selected = false
         }
         if let index = timelineObjects.firstIndex(where: { $0.id == item.id }) {
             timelineObjects[index].selected = true
             selectedTimelineObjectID = item.id
             withAnimation (.easeInOut(duration: 0.5)){
                 recenterOn(coordinates: timelineObjects[index].identifiableCoordinates.flatMap { $0.coordinates })
             }
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
    
   
}

public func formatDateToHoursMinutes(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm" // Hour:Minutes format
    return formatter.string(from: date)
}

public func calculateSpan(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateSpan {
    guard !coordinates.isEmpty else { return MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05) }

    let maxLat = coordinates.map { $0.latitude }.max()!
    let minLat = coordinates.map { $0.latitude }.min()!
    let maxLon = coordinates.map { $0.longitude }.max()!
    let minLon = coordinates.map { $0.longitude }.min()!

    let latDelta = max(maxLat - minLat, 0.001) * 1.4
    let lonDelta = max(maxLon - minLon, 0.001) * 1.4

    return MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
}
