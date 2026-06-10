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
    @State private var selectedGroupIDs: Set<UUID> = []
    @State private var showSettings = false
    @State private var showOrganizePrompt = false
    @State private var rootGpxCount = 0
    @State private var groupingMinutes: Double = 0
    @State private var showGroupingSlider = false

    let defaults = UserDefaults.standard
    let calendar = Calendar.current
    let settingsManager = SettingsManager.shared

    var body: some View {
        GeometryReader { geometry in
                VStack
                {
                    MapView(timelineObjects: $timelineObjects, selectedTimelineObjectID: $selectedTimelineObjectID,
                            selectedGroupIDs: $selectedGroupIDs,
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
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showGroupingSlider.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .padding(8)
                                .foregroundColor(groupingMinutes > 0 ? .orange : .blue)
                        }

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
                    if showGroupingSlider {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Slider(value: $groupingMinutes, in: 0...60, step: 1)
                            Image(systemName: "line.3.horizontal.decrease")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("\(Int(groupingMinutes))m")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .transition(.asymmetric(
                            insertion: .push(from: .top),
                            removal: .push(from: .bottom)
                        ))
                    }
                    TimelineView(
                        timelineObjects: $timelineObjects,
                        selectedTimelineObjectID: $selectedTimelineObjectID,
                        groupingMinutes: groupingMinutes,
                        onRefresh: refreshData,
                        onSelectItem: { item in
                            selectedTimelineObjectID = item.id
                            selectAndCenter(item)
                        },
                        onSelectGroup: { items in
                            selectAndCenterGroup(items)
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
                    checkForRootGpxFiles()
                }
                .fullScreenCover(isPresented: $showSettings) {
                    ManagementView()
                }
                .sheet(isPresented: $showOrganizePrompt) {
                    GpxOrganizePromptView(
                        fileCount: rootGpxCount,
                        onOrganize: { rememberChoice in
                            _ = FileManagerUtil.shared.organizeGpxFiles(
                                conflictResolution: SettingsManager.shared.effectiveGpxConflictResolution
                            )
                            if rememberChoice {
                                SettingsManager.shared.askToOrganizeGpxFiles = false
                            }
                            refreshData()
                        },
                        onDismiss: { rememberChoice in
                            if rememberChoice {
                                SettingsManager.shared.askToOrganizeGpxFiles = false
                            }
                        }
                    )
                    .presentationDetents([.height(280)])
                }
    }

    private func centerAllData() {
        let allCoordinates = timelineObjects.flatMap { $0.identifiableCoordinates.flatMap { $0.coordinates } }
        if !allCoordinates.isEmpty {
            withAnimation (.easeInOut(duration: 0.5)){
                recenterOn(coordinates: allCoordinates)
            }
            self.selectedTimelineObjectID = nil
            self.selectedGroupIDs = []
        }
    }
    
    private func selectAndCenter(_ item: TimelineObject) {
         for index in timelineObjects.indices {
             timelineObjects[index].selected = false
         }
         if let index = timelineObjects.firstIndex(where: { $0.id == item.id }) {
             timelineObjects[index].selected = true
             selectedTimelineObjectID = item.id
             selectedGroupIDs = []
             withAnimation (.easeInOut(duration: 0.5)){
                 recenterOn(coordinates: timelineObjects[index].identifiableCoordinates.flatMap { $0.coordinates })
             }
         }
     }
    
    private func selectAndCenterGroup(_ items: [TimelineObject]) {
        let groupIDs = Set(items.map { $0.id })
        for index in timelineObjects.indices {
            timelineObjects[index].selected = groupIDs.contains(timelineObjects[index].id)
        }
        selectedTimelineObjectID = nil
        selectedGroupIDs = groupIDs
        let allCoordinates = items.flatMap { $0.identifiableCoordinates.flatMap { $0.coordinates } }
        if !allCoordinates.isEmpty {
            withAnimation(.easeInOut(duration: 0.5)) {
                recenterOn(coordinates: allCoordinates)
            }
        }
    }
    
    private func recenterOn(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        let displayCoords = CoordinateConverter.forMapDisplay(coordinates)
        let centerLat = (displayCoords.map { $0.latitude }.max()! + displayCoords.map { $0.latitude }.min()!) / 2
        let centerLon = (displayCoords.map { $0.longitude }.max()! + displayCoords.map { $0.longitude }.min()!) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = calculateSpan(for: displayCoords)
        
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
    
    private func checkForRootGpxFiles() {
        guard SettingsManager.shared.askToOrganizeGpxFiles else { return }
        let files = FileManagerUtil.shared.gpxFilesInRoot()
        if !files.isEmpty {
            rootGpxCount = files.count
            showOrganizePrompt = true
        }
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

struct GpxOrganizePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rememberChoice = false
    
    let fileCount: Int
    let onOrganize: (Bool) -> Void
    let onDismiss: (Bool) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("Organize GPX Files")
                .font(.headline)
            
            Text("\(fileCount) GPX file\(fileCount == 1 ? "" : "s") found in the main folder. Would you like to organize them into year folders?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Toggle("Remember my choice", isOn: $rememberChoice)
                .padding(.horizontal, 30)
            
            HStack(spacing: 16) {
                Button("Not Now") {
                    onDismiss(rememberChoice)
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Organize") {
                    onOrganize(rememberChoice)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
}
