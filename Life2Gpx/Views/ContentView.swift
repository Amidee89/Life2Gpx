//
//  ContentView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.1.2024.
//
import SwiftUI
import MapKit
import CoreGPX
import UIKit

private let mapAutoZoomPaddingFactor: Double = 1.15
private let mapSelectionPaddingFactor: Double = 1.4

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var currentGpxShareURL: URL?
    @AppStorage("mapPanelHeightProportion") private var mapPanelHeightProportion: Double = -1.0
    @State private var mapPanelHeight: CGFloat?
    @State private var mapPanelDragOffset: CGFloat?
    @State private var lastMapSize: CGSize = .zero
    @State private var scrollPositions: [String: String] = [:]
    @State private var bulkApplyContext: BulkApplyContext?

    // Edit mode state
    @State private var isEditMode: Bool = false
    @State private var selectedEditItems: Set<UUID> = []
    @State private var savedGroupingMinutes: Double = 0
    @State private var showDeleteConfirmation = false
    @State private var showMergeTypePicker = false
    @State private var showMergeVisitLocationPicker = false
    @State private var mergedTrackTimelineObject: TimelineObject?
    @State private var mergedVisitTimelineObject: TimelineObject?
    @State private var editingWaypointFromNotification: TimelineObject? = nil
    @State private var mergeItemsContiguous: Bool = true

    let defaults = UserDefaults.standard
    let calendar = Calendar.current
    let settingsManager = SettingsManager.shared

    private let maxTimelineGroupingMinutes: Double = 60
    private let timelineGroupingStep: Double = 1
    private let unknownPlaceDeepLinkTimeThreshold: TimeInterval = 2.0

    private let mapTimelineHandleHeight: CGFloat = 36
    private let mapCollapseSafeZoneHeight: CGFloat = 72
    private let minimumBottomPanelHeight: CGFloat = 220
    private let mapTimelineSplitCoordinateSpace = "mapTimelineSplit"
    private let mapButtonInset: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            let currentMapHeight = resolvedMapHeight(in: geometry)
            let isMapCollapsed = currentMapHeight <= 0
            let safeAreaTop = geometry.safeAreaInsets.top
            let topSlotHeight = isMapCollapsed ? safeAreaTop + mapTimelineHandleHeight : currentMapHeight
            let handleCenterY = topSlotHeight - safeAreaTop - 10
            let mapFrameHeight = isMapCollapsed ? 1 : currentMapHeight
            let isMapVisible = !isMapCollapsed

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        MapView(timelineObjects: $timelineObjects, selectedTimelineObjectID: $selectedTimelineObjectID,
                                selectedGroupIDs: $selectedGroupIDs,
                                cameraPosition: $cameraPosition,
                                selectedDate: $selectedDate,
                                safeAreaTop: safeAreaTop
                        )
                        .overlay(
                            MapControlsView(
                                onRefresh: refreshData,
                                onCenter: centerAllData,
                                onSelectToday: { selectedDate = Date() },
                                selectedDate: $selectedDate,
                                timelineObjects: $timelineObjects,
                                safeAreaTop: safeAreaTop
                            )
                        )
                        .onChange(of: isMapVisible) { _, newValue in
                            let detail = "Map visibility changed. visible=\(newValue), scenePhase=\(scenePhase), isMapCollapsed=\(isMapCollapsed), currentMapHeight=\(optionalCGFloatDescription(currentMapHeight)), mapFrameHeight=\(optionalCGFloatDescription(mapFrameHeight)), topSlotHeight=\(optionalCGFloatDescription(topSlotHeight))"
                            DiagnosticsStateStore.shared.update(section: "MapRender", detail: detail)
                            FileManagerUtil.logData(
                                context: "ContentView",
                                content: detail,
                                verbosity: 4
                            )
                        }
                        .frame(height: mapFrameHeight)
                        .clipped()
                        .opacity(isMapVisible ? 1 : 0)
                        .allowsHitTesting(isMapVisible)
                        .ignoresSafeArea(.container, edges: .top)
                        .zIndex(0)
                        .onChange(of: currentMapHeight) {
                            if isMapVisible {
                                lastMapSize = CGSize(width: geometry.size.width, height: currentMapHeight)
                            }
                            DiagnosticsStateStore.shared.update(
                                section: "MapLayout",
                                detail: "currentMapHeight=\(optionalCGFloatDescription(currentMapHeight)), mapFrameHeight=\(optionalCGFloatDescription(mapFrameHeight)), topSlotHeight=\(optionalCGFloatDescription(topSlotHeight)), lastMapSize=\(sizeDescription(lastMapSize)), isMapVisible=\(isMapVisible), scenePhase=\(scenePhase)"
                            )
                        }
                        .onAppear {
                            if isMapVisible {
                                lastMapSize = CGSize(width: geometry.size.width, height: currentMapHeight)
                            }
                            DiagnosticsStateStore.shared.update(
                                section: "MapLayout",
                                detail: "Map container appeared. currentMapHeight=\(optionalCGFloatDescription(currentMapHeight)), mapFrameHeight=\(optionalCGFloatDescription(mapFrameHeight)), topSlotHeight=\(optionalCGFloatDescription(topSlotHeight)), lastMapSize=\(sizeDescription(lastMapSize)), isMapVisible=\(isMapVisible), scenePhase=\(scenePhase)"
                            )
                        }
                    }
                    .frame(height: topSlotHeight)

                    VStack(spacing: 0) {
                        
                        HStack(spacing: 2) {
                            Spacer(minLength: 0)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showGroupingSlider.toggle()
                                }
                            }) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .frame(minWidth: 32, minHeight: 32)
                                    .contentShape(Rectangle())
                                    .foregroundColor(groupingMinutes > 0 ? .orange : .blue)
                            }
                            .disabled(isEditMode)
                            .opacity(isEditMode ? 0.4 : 1)

                            Button(action: {
                                toggleEditMode()
                            }) {
                                Image(systemName: "square.and.pencil")
                                    .frame(minWidth: 32, minHeight: 32)
                                    .contentShape(Rectangle())
                                    .foregroundColor(isEditMode ? .orange : .blue)
                            }
                            
                            Button(action: {
                                self.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: self.selectedDate)!
                            }) {
                                Image(systemName: "chevron.left")
                                    .frame(minWidth: 32, minHeight: 32)
                                    .contentShape(Rectangle())
                                    .foregroundColor(Calendar.current.isDate(selectedDate, equalTo: minDate, toGranularity: .day) ? .gray : .blue)
                            }
                            .disabled(Calendar.current.isDate(selectedDate, equalTo: minDate, toGranularity: .day) || isEditMode)
                            .opacity(isEditMode ? 0.4 : 1)
                            
                            if isEditMode {
                                Text("\(selectedEditItems.count) selected")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 100)
                                    .multilineTextAlignment(.center)
                            } else {
                                DatePicker("", selection: $selectedDate, in: minDate...maxDate, displayedComponents: .date)
                                    .onChange(of: selectedDate) {
                                        refreshData()
                                        centerAllData()
                                    }
                                    .fixedSize()
                                    .labelsHidden()
                            }
                            
                            Button(action: {
                                self.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: self.selectedDate)!
                            }) {
                                Image(systemName: "chevron.right")
                                    .frame(minWidth: 32, minHeight: 32)
                                    .contentShape(Rectangle())
                                    .foregroundColor(Calendar.current.isDate(selectedDate, equalTo: maxDate, toGranularity: .day) ? .gray : .blue)
                            }
                            .disabled(Calendar.current.isDate(selectedDate, equalTo: maxDate, toGranularity: .day) || isEditMode)
                            .opacity(isEditMode ? 0.4 : 1)

                            Button(action: {
                                self.showSettings = true
                            }) {
                                Image(systemName: "gearshape")
                                    .frame(minWidth: 32, minHeight: 32)
                                    .contentShape(Rectangle())
                                    .foregroundColor(.blue)
                            }
                            .disabled(isEditMode)
                            .opacity(isEditMode ? 0.4 : 1)
                            
                            Button(action: {
                                shareCurrentGpx()
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(minWidth: 32, minHeight: 32)
                                    .contentShape(Rectangle())
                                    .foregroundColor(currentGpxShareURL == nil ? .gray : .blue)
                            }
                            .disabled(currentGpxShareURL == nil || isEditMode)
                            .opacity(isEditMode ? 0.4 : 1)
                            .accessibilityLabel(currentGpxShareURL == nil ? "Share GPX unavailable" : "Share GPX")
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        if showGroupingSlider && !isEditMode {
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Slider(value: $groupingMinutes, in: 0...maxTimelineGroupingMinutes, step: timelineGroupingStep)
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
                            scrollPositions: $scrollPositions,
                            groupingMinutes: isEditMode ? 0 : groupingMinutes,
                            onRefresh: refreshData,
                            onSelectItem: { item in
                                selectedTimelineObjectID = item.id
                                selectAndCenter(item)
                            },
                            onSelectGroup: { items in
                                selectAndCenterGroup(items)
                            },
                            selectedDate: selectedDate,
                            onEditVisit: handleVisitEdit,
                            onRecenter: centerAllData,
                            isEditMode: isEditMode,
                            selectedEditItems: $selectedEditItems
                        )

                        // Bottom action bar for edit mode
                        if isEditMode && !selectedEditItems.isEmpty {
                            HStack(spacing: 16) {
                                let selectedItem = selectedEditItems.count == 1 ? timelineObjects.first(where: { $0.id == selectedEditItems.first }) : nil
                                let canConvert = selectedItem?.type == .track

                                Button(action: {
                                    if canConvert {
                                        showMergeVisitLocationPicker = true
                                    } else {
                                        mergeItemsContiguous = MergeHelpers.areItemsContiguous(
                                            selectedIDs: selectedEditItems,
                                            allItems: timelineObjects
                                        )
                                        showMergeTypePicker = true
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: canConvert ? "arrow.triangle.2.circlepath" : "arrow.triangle.merge")
                                        Text(canConvert ? "Convert" : "Merge")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(selectedEditItems.count < 2 && !canConvert)

                                Button(action: {
                                    showDeleteConfirmation = true
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground).shadow(color: .black.opacity(0.1), radius: 4, y: -2))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .ignoresSafeArea(.container, edges: .top)

                MapTimelineHandleView(isMapCollapsed: isMapCollapsed)
                    .frame(width: geometry.size.width, height: mapTimelineHandleHeight)
                    .position(x: geometry.size.width / 2, y: handleCenterY)
                    .zIndex(1)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(mapTimelineSplitCoordinateSpace))
                            .onChanged { value in
                                updateMapPanelHeight(for: value.location.y, in: geometry)
                            }
                            .onEnded { value in
                                finishMapPanelHeightDrag(at: value.location.y, in: geometry)
                            }
                    )
            }
            .coordinateSpace(name: mapTimelineSplitCoordinateSpace)
            .onReceive(locationManager.$dataHasBeenUpdated) { needsRefresh in
                if needsRefresh {
                    refreshData()
                    locationManager.dataHasBeenUpdated = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .loadTodayData)) { _ in
                let currentTime = Date()
                FileManagerUtil.logData(context: "ContentView", content: "🔔 Received loadTodayData notification at \(currentTime). Current selectedDate: \(selectedDate), switching to today's date.", verbosity: 1)
                logContentSnapshot("Before handling loadTodayData notification")
                selectedDate = Date()
                scrollPositions.removeAll()
                showSettings = false
                showOrganizePrompt = false
                exitEditMode()
                refreshData()
                centerAllData()
                logContentSnapshot("After handling loadTodayData notification")
                FileManagerUtil.logData(context: "ContentView", content: "✅ Completed loading today's data.", verbosity: 1)
            }
        }
        .onAppear {
            _ = FileManagerUtil.shared
            logContentSnapshot("ContentView appeared")
            refreshData()
            centerAllData()
            checkForRootGpxFiles()
            checkPendingNotification()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openEditVisitForUnknownPlace)) { _ in
            checkPendingNotification()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            logContentSnapshot("ContentView scene phase \(oldPhase) -> \(newPhase)")
        }
        .fullScreenCover(isPresented: $showSettings) {
            ManagementView()
        }
        .sheet(item: $bulkApplyContext) { context in
            BulkApplyPlaceView(context: context) { selectedObjects in
                for object in selectedObjects {
                    if let originalWaypoint = object.points.first {
                        // Create updated waypoint from a deep copy so we don't mutate the original before matching
                        let workingCopy = GPXUtils.deepCopyPoint(originalWaypoint)
                        let updated = GPXUtils.updateWaypointMetadataFromPlace(updatedWaypoint: workingCopy, place: context.place)
                        GPXManager.shared.updateWaypoint(originalWaypoint: originalWaypoint, updatedWaypoint: updated, forDate: selectedDate)
                    }
                }
                refreshData()
                centerAllData()
            }
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
        .alert("Delete \(selectedEditItems.count) item\(selectedEditItems.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                performBulkDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected items. A backup will be created first.")
        }
        .sheet(isPresented: $showMergeTypePicker) {
            MergeTypePickerView(
                isContiguous: mergeItemsContiguous,
                onSelect: { mergeType in
                    showMergeTypePicker = false
                    let selectedItems = timelineObjects.filter { selectedEditItems.contains($0.id) }
                    switch mergeType {
                    case .track:
                        let mergedObject = MergeHelpers.buildMergedTrackTimelineObject(from: selectedItems)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            mergedTrackTimelineObject = mergedObject
                        }
                    case .visit:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showMergeVisitLocationPicker = true
                        }
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $mergedTrackTimelineObject, onDismiss: {
            mergedTrackTimelineObject = nil
        }) { mergedObject in
            EditTrackView(
                timelineObject: mergedObject,
                fileDate: selectedDate,
                onSaveChanges: {},
                customSaveAction: { updatedTrack in
                    performMergeTrackSave(updatedTrack: updatedTrack)
                }
            )
        }
        .sheet(isPresented: $showMergeVisitLocationPicker) {
            let selectedItems = timelineObjects.filter { selectedEditItems.contains($0.id) }
            MergeLocationPickerView(
                items: selectedItems,
                onSelect: { selectedPoint in
                    showMergeVisitLocationPicker = false
                    let items = timelineObjects.filter { selectedEditItems.contains($0.id) }
                    let mergedObject = MergeHelpers.buildMergedVisitTimelineObject(at: selectedPoint, from: items)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        mergedVisitTimelineObject = mergedObject
                    }
                }
            )
        }
        .sheet(item: $mergedVisitTimelineObject, onDismiss: {
            mergedVisitTimelineObject = nil
        }) { mergedObject in
            EditVisitView(
                timelineObject: mergedObject,
                fileDate: selectedDate,
                onSave: { _, _ in },
                customSaveAction: { updatedWaypoint, place, wasUnknown in
                    performMergeVisitSave(updatedWaypoint: updatedWaypoint)
                }
            )
        }
        .sheet(item: $editingWaypointFromNotification, onDismiss: {
            editingWaypointFromNotification = nil
        }) { timelineObject in
            EditVisitView(
                timelineObject: timelineObject,
                fileDate: selectedDate,
                onSave: { place, wasUnknown in
                    handleVisitEdit(timelineObject: timelineObject, place: place, wasUnknown: wasUnknown)
                }
            )
        }
    }

    private func resolvedMapHeight(in geometry: GeometryProxy) -> CGFloat {
        let maxHeight = maximumMapPanelHeight(in: geometry)
        guard maxHeight > 0 else { return 0 }

        let effectiveHeight: CGFloat
        if let mapPanelHeight {
            effectiveHeight = mapPanelHeight
        } else if mapPanelHeightProportion >= 0 {
            effectiveHeight = maxHeight * CGFloat(mapPanelHeightProportion)
        } else {
            effectiveHeight = geometry.size.height * 0.45
        }

        if effectiveHeight <= mapCollapseThreshold(in: geometry) {
            return 0
        }

        return min(effectiveHeight, maxHeight)
    }

    private func updateMapPanelHeight(for fingerY: CGFloat, in geometry: GeometryProxy) {
        beginMapPanelDragIfNeeded(at: fingerY, in: geometry)
        mapPanelHeight = clampedMapPanelHeight(adjustedMapPanelSplitY(for: fingerY), in: geometry)
    }

    private func finishMapPanelHeightDrag(at fingerY: CGFloat, in geometry: GeometryProxy) {
        beginMapPanelDragIfNeeded(at: fingerY, in: geometry)
        let clamped = clampedMapPanelHeight(adjustedMapPanelSplitY(for: fingerY), in: geometry)
        mapPanelDragOffset = nil
        let maxHeight = maximumMapPanelHeight(in: geometry)
        let proportion = maxHeight > 0 ? Double(clamped / maxHeight) : -1.0
        
        if clamped <= 0 {
            // Skip animation when collapsing to avoid mid-animation layout conflicts
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mapPanelHeight = clamped
                mapPanelHeightProportion = proportion
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                mapPanelHeight = clamped
                mapPanelHeightProportion = proportion
            }
        }
    }

    private func beginMapPanelDragIfNeeded(at fingerY: CGFloat, in geometry: GeometryProxy) {
        guard mapPanelDragOffset == nil else { return }
        mapPanelDragOffset = resolvedMapHeight(in: geometry) - fingerY
    }

    private func adjustedMapPanelSplitY(for fingerY: CGFloat) -> CGFloat {
        fingerY + (mapPanelDragOffset ?? 0)
    }

    private func clampedMapPanelHeight(_ proposedHeight: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        let maxHeight = maximumMapPanelHeight(in: geometry)
        guard maxHeight > 0 else { return 0 }

        if proposedHeight <= mapCollapseThreshold(in: geometry) {
            return 0
        }

        return min(proposedHeight, maxHeight)
    }

    private func maximumMapPanelHeight(in geometry: GeometryProxy) -> CGFloat {
        max(0, geometry.size.height - minimumBottomPanelHeight)
    }

    private func mapCollapseThreshold(in geometry: GeometryProxy) -> CGFloat {
        max(mapCollapseSafeZoneHeight, geometry.safeAreaInsets.top + 44)
    }

    private func centerAllData() {
        let allCoordinates = timelineObjects.flatMap { $0.identifiableCoordinates.flatMap { $0.coordinates } }
        FileManagerUtil.logData(
            context: "ContentView",
            content: "centerAllData called. coordinateCount=\(allCoordinates.count), lastMapSize=\(sizeDescription(lastMapSize)), network={\(NetworkDiagnostics.shared.snapshot())}",
            verbosity: 5
        )
        if !allCoordinates.isEmpty {
            withAnimation (.easeInOut(duration: 0.5)){
                recenterOn(coordinates: allCoordinates, mapSize: lastMapSize)
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
                 recenterOn(coordinates: timelineObjects[index].identifiableCoordinates.flatMap { $0.coordinates }, mapSize: lastMapSize)
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
                recenterOn(coordinates: allCoordinates, mapSize: lastMapSize)
            }
        }
    }
    
    private func recenterOn(coordinates: [CLLocationCoordinate2D], mapSize: CGSize) {
        guard !coordinates.isEmpty else { return }
        let displayCoords = CoordinateConverter.forMapDisplay(coordinates)
        let centerLat = (displayCoords.map { $0.latitude }.max()! + displayCoords.map { $0.latitude }.min()!) / 2
        let centerLon = (displayCoords.map { $0.longitude }.max()! + displayCoords.map { $0.longitude }.min()!) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = calculateSpan(for: displayCoords, mapSize: mapSize, buttonInset: mapButtonInset)
        
        cameraPosition = MapCameraPosition.region(MKCoordinateRegion(center: centerCoordinate, span: span))
        FileManagerUtil.logData(
            context: "ContentView",
            content: "Map recentered. coordinateCount=\(coordinates.count), center=(\(centerCoordinate.latitude),\(centerCoordinate.longitude)), span=(\(span.latitudeDelta),\(span.longitudeDelta)), mapSize=\(sizeDescription(mapSize))",
            verbosity: 5
        )
        
    }

    
    
    private func refreshData() {
        let requestedDate = selectedDate
        let startedAt = Date()
        logContentSnapshot("refreshData started for \(requestedDate)")
        updateCurrentGpxShareURL()
        GPXManager.shared.getDateRange { earliest, latest in
            if let earliestDate = earliest, let latestDate = latest {
                minDate = earliestDate
                maxDate = latestDate
                FileManagerUtil.logData(
                    context: "ContentView",
                    content: "Date range refreshed for \(requestedDate). minDate=\(earliestDate), maxDate=\(latestDate)",
                    verbosity: 5
                )
            } else {
                FileManagerUtil.logData(
                    context: "ContentView",
                    content: "Date range refresh returned empty range for \(requestedDate).",
                    verbosity: 5
                )
            }
        }
        loadTimelineForDate(requestedDate) { timelineObjects in
            self.timelineObjects = timelineObjects
            let elapsed = Date().timeIntervalSince(startedAt)
            let trackCount = timelineObjects.filter { $0.type == .track }.count
            let waypointCount = timelineObjects.filter { $0.type == .waypoint }.count
            let totalTrackPoints = timelineObjects
                .filter { $0.type == .track }
                .flatMap(\.identifiableCoordinates)
                .reduce(0) { $0 + $1.coordinates.count }
            FileManagerUtil.logData(
                context: "ContentView",
                content: "refreshData finished for \(requestedDate) in \(String(format: "%.3f", elapsed))s. objects=\(timelineObjects.count), tracks=\(trackCount), waypoints=\(waypointCount), totalTrackPoints=\(totalTrackPoints), currentSelectedDate=\(selectedDate), \(ResourceDiagnostics.memorySnapshot()), network={\(NetworkDiagnostics.shared.snapshot())}",
                verbosity: 4
            )
        }
    }

    private func logContentSnapshot(_ reason: String, verbosity: Int = 4) {
        let trackCount = timelineObjects.filter { $0.type == .track }.count
        let waypointCount = timelineObjects.filter { $0.type == .waypoint }.count
        let totalTrackPoints = timelineObjects
            .filter { $0.type == .track }
            .flatMap(\.identifiableCoordinates)
            .reduce(0) { $0 + $1.coordinates.count }

        let snapshot = "\(reason). scenePhase=\(scenePhase), selectedDate=\(selectedDate), objects=\(timelineObjects.count), tracks=\(trackCount), waypoints=\(waypointCount), totalTrackPoints=\(totalTrackPoints), selectedObject=\(selectedTimelineObjectID?.uuidString ?? "nil"), selectedGroups=\(selectedGroupIDs.count), settingsSheet=\(showSettings), organizePrompt=\(showOrganizePrompt), editMode=\(isEditMode), selectedEditItems=\(selectedEditItems.count), mapPanelHeight=\(optionalCGFloatDescription(mapPanelHeight)), lastMapSize=\(sizeDescription(lastMapSize)), \(ResourceDiagnostics.memorySnapshot()), network={\(NetworkDiagnostics.shared.snapshot())}"
        DiagnosticsStateStore.shared.update(section: "ContentView", detail: snapshot)
        FileManagerUtil.logData(
            context: "ContentView",
            content: snapshot,
            verbosity: verbosity
        )
    }

    private func optionalCGFloatDescription(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.1f", value)
    }

    private func sizeDescription(_ size: CGSize) -> String {
        "\(String(format: "%.1f", size.width))x\(String(format: "%.1f", size.height))"
    }
    
    private func handleVisitEdit(timelineObject: TimelineObject, place: Place?, wasUnknown: Bool) {
        if wasUnknown, let place = place {
            // Find other unknown waypoint objects in the current timeline that match geographically
            let matchingObjects = timelineObjects.filter { obj in
                guard obj.type == .waypoint, obj.id != timelineObject.id else { return false }
                guard obj.isUnknownPlace else { return false }
                
                if let coord = obj.identifiableCoordinates.first?.coordinates.first {
                    let displayCoord = CoordinateConverter.forMapDisplay(coord)
                    let placeCoord = CoordinateConverter.forMapDisplay(place.centerCoordinate)
                    let clCoord = CLLocation(latitude: displayCoord.latitude, longitude: displayCoord.longitude)
                    let clPlaceCoord = CLLocation(latitude: placeCoord.latitude, longitude: placeCoord.longitude)
                    let distance = clCoord.distance(from: clPlaceCoord)
                    return distance <= place.radius
                }
                return false
            }
            
            if SettingsManager.shared.suggestApplyToOtherPlaces && !matchingObjects.isEmpty {
                bulkApplyContext = BulkApplyContext(place: place, originalObject: timelineObject, matchingObjects: matchingObjects)
            }
        }
        
        refreshData()
        centerAllData()
    }
    
    private func shareCurrentGpx() {
        guard let currentGpxShareURL else {
            return
        }

        presentShareSheet(for: currentGpxShareURL)
    }

    private func presentShareSheet(for fileURL: URL) {
        guard let presenter = topViewController() else {
            return
        }

        let configuration = UIActivityItemsConfiguration(objects: [fileURL as NSURL])
        configuration.supportedInteractions = [.share]
        configuration.metadataProvider = { key in
            if key == .title {
                return fileURL.lastPathComponent
            }
            if #available(iOS 18.0, *), key == .collaborationModeRestrictions {
                return [UIActivityViewController.CollaborationModeRestriction(disabledMode: .collaborate)]
            }
            return nil
        }

        let controller = UIActivityViewController(activityItemsConfiguration: configuration)

        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(controller, animated: true)
    }

    private func checkForRootGpxFiles() {
        guard SettingsManager.shared.askToOrganizeGpxFiles else { return }
        let files = FileManagerUtil.shared.gpxFilesInRoot()
        if !files.isEmpty {
            rootGpxCount = files.count
            showOrganizePrompt = true
        }
    }

    private func updateCurrentGpxShareURL() {
        let resolvedURL = GPXManager.shared.resolvedFileURL(forDate: selectedDate)
        currentGpxShareURL = FileManager.default.fileExists(atPath: resolvedURL.path) ? resolvedURL : nil
    }

    // MARK: - Edit Mode

    private func toggleEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if isEditMode {
                exitEditMode()
            } else {
                isEditMode = true
                selectedEditItems.removeAll()
                selectedTimelineObjectID = nil
                selectedGroupIDs = []
            }
        }
    }

    private func exitEditMode() {
        isEditMode = false
        selectedEditItems.removeAll()
    }

    private func performBulkDelete() {
        let selectedItems = timelineObjects.filter { selectedEditItems.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        do {
            try FileManagerUtil.shared.backupFile(forDate: selectedDate)
        } catch {
            print("Error backing up GPX file: \(error)")
            return
        }

        let (waypoints, tracks) = MergeHelpers.collectItemsForDeletion(from: selectedItems)
        GPXManager.shared.deleteItems(waypointsToDelete: waypoints, tracksToDelete: tracks, forDate: selectedDate)

        exitEditMode()
        refreshData()
        centerAllData()
    }

    private func performMergeTrackSave(updatedTrack: GPXTrack) {
        let selectedItems = timelineObjects.filter { selectedEditItems.contains($0.id) }
        let (waypoints, tracks) = MergeHelpers.collectItemsForDeletion(from: selectedItems)

        do {
            try FileManagerUtil.shared.backupFile(forDate: selectedDate)
        } catch {
            print("Error backing up GPX file: \(error)")
            return
        }

        GPXManager.shared.replaceItems(
            deleteWaypoints: waypoints,
            deleteTracks: tracks,
            addWaypoint: nil,
            addTrack: updatedTrack,
            forDate: selectedDate
        )

        mergedTrackTimelineObject = nil
        exitEditMode()
        refreshData()
        centerAllData()
    }

    private func performMergeVisitSave(updatedWaypoint: GPXWaypoint) {
        let selectedItems = timelineObjects.filter { selectedEditItems.contains($0.id) }
        let (waypoints, tracks) = MergeHelpers.collectItemsForDeletion(from: selectedItems)

        do {
            try FileManagerUtil.shared.backupFile(forDate: selectedDate)
        } catch {
            print("Error backing up GPX file: \(error)")
            return
        }

        GPXManager.shared.replaceItems(
            deleteWaypoints: waypoints,
            deleteTracks: tracks,
            addWaypoint: updatedWaypoint,
            addTrack: nil,
            forDate: selectedDate
        )

        mergedVisitTimelineObject = nil
        exitEditMode()
        refreshData()
        centerAllData()
    }

    private func checkPendingNotification() {
        if let userInfo = NotificationManager.shared.pendingUnknownPlaceUserInfo {
            NotificationManager.shared.pendingUnknownPlaceUserInfo = nil
            handleIncomingUnknownPlaceNotification(userInfo: userInfo)
        }
    }

    private func handleIncomingUnknownPlaceNotification(userInfo: [AnyHashable: Any]) {
        guard let timestampVal = userInfo["waypointTimestamp"] as? TimeInterval else { return }
        let targetDate = Date(timeIntervalSince1970: timestampVal)
        
        FileManagerUtil.logData(context: "ContentView", content: "Handling unknown place notification for timestamp: \(targetDate)", verbosity: 3)
        
        // 1. Set the selected date to match the target date
        self.selectedDate = targetDate
        
        // 2. Fetch the timeline objects for this day
        loadTimelineForDate(targetDate) { loadedObjects in
            self.timelineObjects = loadedObjects
            
            // 3. Find the matching waypoint
            if let matchingObj = loadedObjects.first(where: { obj in
                guard obj.type == .waypoint, let start = obj.startDate else { return false }
                return abs(start.timeIntervalSince(targetDate)) < unknownPlaceDeepLinkTimeThreshold
            }) {
                // 4. Open the edit sheet
                self.editingWaypointFromNotification = matchingObj
                FileManagerUtil.logData(context: "ContentView", content: "Deep-linked to EditVisitView for waypoint: \(matchingObj.id)", verbosity: 3)
            } else {
                FileManagerUtil.logData(context: "ContentView", content: "Failed to find matching waypoint in loaded timeline for \(targetDate)", verbosity: 2)
            }
        }
    }
}

private struct MapTimelineHandleView: View {
    let isMapCollapsed: Bool

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 2) {
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 44, height: 5)
                    .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)

                if isMapCollapsed {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(isMapCollapsed ? "Show map" : "Resize map and timeline")
        .accessibilityHint("Drag vertically to adjust the map and timeline split")
    }
}

private func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let rootController: UIViewController? = {
        if let base = base {
            return base
        }

        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        return windowScene?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
    }()

    if let navigationController = rootController as? UINavigationController {
        return topViewController(base: navigationController.visibleViewController)
    }

    if let tabBarController = rootController as? UITabBarController {
        return topViewController(base: tabBarController.selectedViewController)
    }

    if let presentedViewController = rootController?.presentedViewController {
        return topViewController(base: presentedViewController)
    }

    return rootController
}

public func formatDateToHoursMinutes(_ date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = timeZone
    return formatter.string(from: date)
}

public func calculateSpan(for coordinates: [CLLocationCoordinate2D], mapSize: CGSize = .zero, buttonInset: CGFloat = 0) -> MKCoordinateSpan {
    guard !coordinates.isEmpty else { return MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05) }

    let maxLat = coordinates.map { $0.latitude }.max()!
    let minLat = coordinates.map { $0.latitude }.min()!
    let maxLon = coordinates.map { $0.longitude }.max()!
    let minLon = coordinates.map { $0.longitude }.min()!

    let rawLatDelta = max(maxLat - minLat, 0.001)
    let rawLonDelta = max(maxLon - minLon, 0.001)

    // If we know the map size, scale to account for button insets on all edges
    if mapSize.width > 0, mapSize.height > 0, buttonInset > 0 {
        let normalPadding = buttonInset * 2
        
        // Determine horizontal and vertical padding dynamically
        let verticalPadding: CGFloat
        let hStart = normalPadding * 2.0
        let hEnd = normalPadding
        if mapSize.height >= hStart {
            verticalPadding = normalPadding
        } else if mapSize.height <= hEnd {
            verticalPadding = 0
        } else {
            verticalPadding = mapSize.height - normalPadding
        }

        let horizontalPadding: CGFloat
        if mapSize.width >= hStart {
            horizontalPadding = normalPadding
        } else if mapSize.width <= hEnd {
            horizontalPadding = 0
        } else {
            horizontalPadding = mapSize.width - normalPadding
        }

        let usableWidth = max(mapSize.width - horizontalPadding, 1)
        let usableHeight = max(mapSize.height - verticalPadding, 1)
        let lonScale = mapSize.width / usableWidth
        let latScale = mapSize.height / usableHeight
        return MKCoordinateSpan(
            latitudeDelta: rawLatDelta * latScale * mapAutoZoomPaddingFactor,
            longitudeDelta: rawLonDelta * lonScale * mapAutoZoomPaddingFactor
        )
    }

    // Fallback: uniform padding
    return MKCoordinateSpan(latitudeDelta: rawLatDelta * mapSelectionPaddingFactor, longitudeDelta: rawLonDelta * mapSelectionPaddingFactor)
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
