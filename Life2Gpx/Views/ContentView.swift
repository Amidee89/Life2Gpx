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
    @EnvironmentObject var locationManager: LocationManager

    @State private var selectedDate = Date()
    @State private var cameraPosition: MapCameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 360, longitudeDelta: 360)))
    @State private var minDate: Date = Date()
    @State private var maxDate: Date = Date()
    @State private var lastBackgroundTime: Date? = nil
    @State private var timelineObjects: [TimelineObject] = []
    @State private var selectedTimelineObjectID: UUID?
    @State private var showSettings = false

    let defaults = UserDefaults.standard
    let calendar = Calendar.current
    let settingsManager = SettingsManager.shared

    var body: some View {
        GeometryReader { geometry in
                VStack
                {
                    MapView(timelineObjects: $timelineObjects, selectedTimelineObjectID: $selectedTimelineObjectID,
                            cameraPosition: $cameraPosition,
                            selectedDate: $selectedDate
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
                        Spacer()
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

                        Button(action: {
                             self.showSettings = true
                         }) {
                             Image(systemName: "gearshape")
                                 .padding(8)
                                 .foregroundColor(.blue)
                         }
                        Spacer()
                    }
                    TimelineView(
                        timelineObjects: $timelineObjects,
                        selectedTimelineObjectID: $selectedTimelineObjectID,
                        onRefresh: refreshData,
                        onSelectItem: { item in
                            selectedTimelineObjectID = item.id
                            selectAndCenter(item)
                        },
                        onEditVisit: handleVisitEdit,
                        onRecenter: centerAllData
                    )
                }
                .onReceive(locationManager.$dataHasBeenUpdated) { needsRefresh in
                        if needsRefresh {
                            refreshData()
                            locationManager.dataHasBeenUpdated = false
                        }
                    }
                .onReceive(NotificationCenter.default.publisher(for: .loadTodayData)) { _ in
                    let currentTime = Date()
                    FileManagerUtil.logData(context: "ContentView", content: "🔔 Received loadTodayData notification at \(currentTime). Current selectedDate: \(selectedDate), switching to today's date.", verbosity: 1)
                    selectedDate = Date()
                    refreshData()
                    centerAllData()
                    FileManagerUtil.logData(context: "ContentView", content: "✅ Completed loading today's data.", verbosity: 1)
                }
                              }
                .onAppear {
                    _ = FileManagerUtil.shared
                    refreshData()
                    centerAllData()
                }
                .fullScreenCover(isPresented: $showSettings) {
                        ManagementView()
                    
                    
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
    
    private func handleVisitEdit(timelineObject: TimelineObject, place: Place?) {
        refreshData()
        centerAllData()
    }
}

public func formatDateToHoursMinutes(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
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

extension Date {
    func startOfDay() -> Date {
        return Calendar.current.startOfDay(for: self)
    }
}

#Preview {
    ContentView()
}
