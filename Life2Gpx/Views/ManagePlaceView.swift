//
//  ManagePlaceView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 18.11.2024.
//

import SwiftUI
import MapKit
import CoreLocation

struct ManagePlacesView: View {
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var viewModel: ManagePlacesViewModel
    
    @State private var searchText = ""
    @State private var selectedPlace: Place?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var mapHeading: Double = 0.0
    @State private var lastRawMapHeading: Double?
    @State private var isMapLoaded = false
    @State private var cameraUpdateTask: Task<Void, Never>?
    
    // Sheet & Action states
    @State private var isEditingPlace = false
    @State private var isCreatingPlace = false
    @State private var placeToDelete: Place?
    @State private var showDeleteConfirmation = false
    
    // Resizable split view state
    @AppStorage("managePlacesMapHeightProportion") private var mapPanelHeightProportion: Double = 0.45
    @State private var mapPanelHeight: CGFloat?
    @State private var mapPanelDragOffset: CGFloat?
    
    private let mapHandleHeight: CGFloat = 28
    private let mapCollapseSafeZoneHeight: CGFloat = 60
    private let minimumBottomPanelHeight: CGFloat = 160
    private let mapSplitCoordinateSpace = "managePlacesSplit"
    private let maxMapMarkersLimit = 150
    
    init(viewModel: ManagePlacesViewModel = ManagePlacesViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Filtered & Visible Places
    
    var searchedPlaces: [Place] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return viewModel.places
        } else {
            return viewModel.places.filter { place in
                place.name.localizedCaseInsensitiveContains(trimmed) ||
                (place.streetAddress?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
    }
    
    var visiblePlaces: [Place] {
        guard let region = visibleRegion else {
            return searchedPlaces
        }
        
        let deltaLat = region.span.latitudeDelta * 0.55
        let deltaLon = region.span.longitudeDelta * 0.55
        let minLat = region.center.latitude - deltaLat
        let maxLat = region.center.latitude + deltaLat
        let minLon = region.center.longitude - deltaLon
        let maxLon = region.center.longitude + deltaLon
        
        return searchedPlaces.filter { place in
            let displayCoord = CoordinateConverter.forMapDisplay(place.coordinate)
            let lat = displayCoord.latitude
            let lon = displayCoord.longitude
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
    }
    
    var displayedPlaces: [Place] {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isSearching ? searchedPlaces : visiblePlaces
    }
    
    var shouldShowOverlays: Bool {
        guard let region = visibleRegion else { return true }
        // Only draw circle/polygon vector overlays if zoomed in closer than ~30km span (0.3 degrees)
        // or if there are fewer than 35 places visible to keep MapKit GPU rendering smooth
        return region.span.latitudeDelta < 0.3 || visiblePlaces.count <= 35
    }
    
    var placesToRenderOnMap: [Place] {
        var places = visiblePlaces
        if places.count > maxMapMarkersLimit {
            // If zoomed out to the entire world with hundreds of places, prioritize favorites and cap count
            let favorites = places.filter { $0.isFavorite == true }
            let others = places.filter { $0.isFavorite != true }
            places = Array((favorites + others).prefix(maxMapMarkersLimit))
        }
        if let selected = selectedPlace, !places.contains(where: { $0.placeId == selected.placeId }) {
            places.append(selected)
        }
        return places
    }
    
    // MARK: - Main Body
    
    var body: some View {
        GeometryReader { geometry in
            let currentMapHeight = resolvedMapHeight(in: geometry)
            let isMapCollapsed = currentMapHeight <= 0
            let topSlotHeight = isMapCollapsed ? mapHandleHeight : currentMapHeight
            let mapFrameHeight = isMapCollapsed ? 1 : currentMapHeight
            let isMapVisible = !isMapCollapsed
            
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Top Map Container
                    ZStack(alignment: .top) {
                        mapView
                            .frame(height: mapFrameHeight)
                            .clipped()
                            .opacity(isMapVisible ? 1 : 0)
                            .allowsHitTesting(isMapVisible)
                    }
                    .frame(height: topSlotHeight)
                    
                    // Bottom Split Content: Status count header + Compact Places List
                    VStack(spacing: 0) {
                        placesStatusBar
                        placesListView
                    }
                }
                
                // Draggable Resize Handle
                PanelResizeHandleView(isCollapsed: isMapCollapsed)
                    .frame(width: geometry.size.width, height: mapHandleHeight)
                    .position(x: geometry.size.width / 2, y: topSlotHeight - (mapHandleHeight / 2))
                    .zIndex(2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(mapSplitCoordinateSpace))
                            .onChanged { value in
                                updateMapPanelHeight(for: value.location.y, in: geometry)
                            }
                            .onEnded { value in
                                finishMapPanelHeightDrag(at: value.location.y, in: geometry)
                            }
                    )
            }
            .coordinateSpace(name: mapSplitCoordinateSpace)
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isCreatingPlace = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
        .sheet(isPresented: $isEditingPlace) {
            if let selectedPlace {
                EditPlaceView(place: selectedPlace)
                    .onDisappear {
                        viewModel.loadPlaces()
                        if let updated = viewModel.places.first(where: { $0.placeId == selectedPlace.placeId }) {
                            self.selectedPlace = updated
                        } else {
                            self.selectedPlace = nil
                        }
                    }
            }
        }
        .sheet(isPresented: $isCreatingPlace) {
            let initialCoord = locationManager.currentRawLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            EditPlaceView(
                place: Place(
                    placeId: UUID().uuidString,
                    name: "",
                    center: Center(latitude: initialCoord.latitude, longitude: initialCoord.longitude),
                    radius: Double(SettingsManager.shared.defaultNewPlaceRadius),
                    secondsFromGMT: TimeZone.current.secondsFromGMT()
                ),
                isNewPlace: true
            )
            .onDisappear {
                viewModel.loadPlaces()
            }
        }
        .alert("Delete Place?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let place = placeToDelete {
                    try? PlaceManager.shared.deletePlace(place)
                    viewModel.loadPlaces()
                    if selectedPlace?.placeId == place.placeId {
                        selectedPlace = nil
                    }
                    placeToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                placeToDelete = nil
            }
        } message: {
            if let place = placeToDelete {
                Text("Are you sure you want to delete \"\(place.name)\"?")
            }
        }
        .onAppear {
            viewModel.loadPlaces()
            setupInitialCameraPosition()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadTodayData)) { _ in
            isEditingPlace = false
            isCreatingPlace = false
            selectedPlace = nil
            viewModel.loadPlaces()
        }
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        MapReader { mapProxy in
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
                // Places Overlays
                if isMapLoaded {
                    let renderOverlays = shouldShowOverlays
                    
                    ForEach(placesToRenderOnMap) { place in
                        let isSelected = selectedPlace?.placeId == place.placeId
                        let centerDisplayCoord = CoordinateConverter.forMapDisplay(place.coordinate)
                        
                        Annotation(place.name, coordinate: centerDisplayCoord) {
                            PlaceMapMarkerView(place: place, isSelected: isSelected)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectPlace(place, zoom: false)
                                    }
                                }
                        }
                        
                        // Render circle/polygon vector overlays when selected OR when zoomed in enough
                        if isSelected || renderOverlays {
                            if let polygonPoints = place.perimeterPolygonPoints, !polygonPoints.isEmpty {
                                let coords = polygonPoints.map {
                                    CoordinateConverter.forMapDisplay(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                                }
                                MapPolygon(coordinates: coords)
                                    .stroke(isSelected ? Color.purple : Color.red.opacity(0.85), lineWidth: isSelected ? 2.5 : 1.5)
                                    .foregroundStyle(isSelected ? Color.purple.opacity(0.35) : Color.orange.opacity(0.2))
                            } else {
                                MapCircle(center: centerDisplayCoord, radius: place.radius)
                                    .stroke(isSelected ? Color.purple : Color.red.opacity(0.85), lineWidth: isSelected ? 2.5 : 1.5)
                                    .foregroundStyle(isSelected ? Color.purple.opacity(0.35) : Color.orange.opacity(0.2))
                            }
                        }
                    }
                }
                
                // Live Current Location Marker with Heading Arrow
                if let location = locationManager.currentRawLocation?.coordinate {
                    Annotation(coordinate: CoordinateConverter.forMapDisplay(location)) {
                        ZStack {
                            Image(systemName: "location.north.fill")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.blue.opacity(0.8))
                                .offset(y: -14)
                                .rotationEffect(Angle(degrees: locationManager.heading - mapHeading))
                                .animation(.linear, value: locationManager.heading)
                                .animation(.linear, value: mapHeading)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                                .shadow(radius: 2)
                            
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 16, height: 16)
                        }
                    } label: {
                        EmptyView()
                    }
                    .mapOverlayLevel(level: .aboveRoads)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                // 1. Heading update for orientation arrow (lightweight, only updates if angle changed)
                let rawHeading = context.camera.heading
                if abs((lastRawMapHeading ?? 0) - rawHeading) > 0.5 {
                    if let lastRaw = lastRawMapHeading {
                        var diff = rawHeading - lastRaw
                        if diff > 180 { diff -= 360 }
                        else if diff < -180 { diff += 360 }
                        mapHeading += diff
                    } else {
                        mapHeading = rawHeading
                    }
                    lastRawMapHeading = rawHeading
                }
                
                // 2. Throttle visibleRegion update to at most once per 200ms during continuous pan/zoom gestures
                if cameraUpdateTask == nil {
                    cameraUpdateTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                        self.visibleRegion = context.region
                        self.isMapLoaded = true
                        self.cameraUpdateTask = nil
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Immediately commit visibleRegion when panning/zooming finishes
                cameraUpdateTask?.cancel()
                cameraUpdateTask = nil
                visibleRegion = context.region
                isMapLoaded = true
            }
            .onTapGesture { screenPoint in
                handleMapTap(at: screenPoint, proxy: mapProxy)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    // Floating button to recenter on current location
                    if locationManager.currentRawLocation?.coordinate != nil {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                if let currentCoord = locationManager.currentRawLocation?.coordinate {
                                    let region = MKCoordinateRegion(
                                        center: CoordinateConverter.forMapDisplay(currentCoord),
                                        latitudinalMeters: 2500,
                                        longitudinalMeters: 2500
                                    )
                                    cameraPosition = .region(region)
                                    visibleRegion = region
                                }
                            }
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        }
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
    }
    
    // MARK: - Status Bar
    
    private var placesStatusBar: some View {
        HStack {
            if !searchText.isEmpty {
                Text("\(displayedPlaces.count) \(displayedPlaces.count == 1 ? "place" : "places") found")
            } else {
                let total = viewModel.places.count
                let count = visiblePlaces.count
                if count < total {
                    Text("\(count) of \(total) places in view")
                } else {
                    Text("\(total) places in view")
                }
            }
            
            Spacer()
            
            if selectedPlace != nil {
                Button("Deselect") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPlace = nil
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.blue)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground).opacity(0.7))
    }
    
    // MARK: - Places List View
    
    private var placesListView: some View {
        ScrollViewReader { scrollProxy in
            List {
                if displayedPlaces.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(searchText.isEmpty ? "No places visible in this area" : "No places matching \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(displayedPlaces) { place in
                        let isSelected = selectedPlace?.placeId == place.placeId
                        
                        CompactPlaceRow(
                            place: place,
                            isSelected: isSelected,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    selectPlace(place, zoom: true)
                                }
                            },
                            onEdit: {
                                selectedPlace = place
                                isEditingPlace = true
                            },
                            onDelete: {
                                placeToDelete = place
                                showDeleteConfirmation = true
                            }
                        )
                        .id(place.placeId)
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: selectedPlace) { _, newPlace in
                if let newPlace = newPlace {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo(newPlace.placeId, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Map Tap & Selection Handling
    
    private func selectPlace(_ place: Place, zoom: Bool) {
        selectedPlace = place
        
        if zoom {
            let radiusInDegrees = (place.radius * 2.5) / 111000
            let minimumSpan = 15.0 / 111000
            let span = max(radiusInDegrees, minimumSpan)
            
            let region = MKCoordinateRegion(
                center: CoordinateConverter.forMapDisplay(place.coordinate),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            cameraPosition = .region(region)
            visibleRegion = region
        }
    }
    
    private func handleMapTap(at screenPoint: CGPoint, proxy: MapProxy) {
        guard let tappedCoordinate = proxy.convert(screenPoint, from: .local) else {
            return
        }
        
        let p1 = screenPoint
        let p2 = CGPoint(x: screenPoint.x + 28, y: screenPoint.y)
        let toleranceInMeters: Double
        if let c1 = proxy.convert(p1, from: .local),
           let c2 = proxy.convert(p2, from: .local) {
            toleranceInMeters = c1.distance(to: c2)
        } else {
            toleranceInMeters = 60.0
        }
        
        var candidatePlace: Place? = nil
        var minDistance: Double = Double.infinity
        
        for place in placesToRenderOnMap {
            let displayCenter = CoordinateConverter.forMapDisplay(place.coordinate)
            let distToCenter = tappedCoordinate.distance(to: displayCenter)
            
            // Check polygon
            if let polygonPoints = place.perimeterPolygonPoints, !polygonPoints.isEmpty {
                let displayPolygon = polygonPoints.map {
                    CoordinateConverter.forMapDisplay(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                }
                let polygonTuples = displayPolygon.map { ($0.latitude, $0.longitude) }
                if CoordinateConverter.pointInPolygon(lat: tappedCoordinate.latitude, lng: tappedCoordinate.longitude, polygon: polygonTuples) {
                    candidatePlace = place
                    minDistance = 0
                    break
                }
            }
            
            // Check circle radius or touch tolerance
            if distToCenter <= place.radius {
                if distToCenter < minDistance {
                    minDistance = distToCenter
                    candidatePlace = place
                }
            } else if distToCenter <= (place.radius + toleranceInMeters) || distToCenter <= toleranceInMeters {
                if distToCenter < minDistance {
                    minDistance = distToCenter
                    candidatePlace = place
                }
            }
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            if let place = candidatePlace {
                selectPlace(place, zoom: false)
            } else {
                selectedPlace = nil
            }
        }
    }
    
    private func setupInitialCameraPosition() {
        if let location = locationManager.currentRawLocation?.coordinate {
            let region = MKCoordinateRegion(
                center: CoordinateConverter.forMapDisplay(location),
                latitudinalMeters: 3000,
                longitudinalMeters: 3000
            )
            cameraPosition = .region(region)
            visibleRegion = region
        } else if let firstPlace = viewModel.places.first {
            let region = MKCoordinateRegion(
                center: CoordinateConverter.forMapDisplay(firstPlace.coordinate),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
            cameraPosition = .region(region)
            visibleRegion = region
        }
    }
    
    // MARK: - Panel Resizing Helpers
    
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
        max(mapCollapseSafeZoneHeight, 44)
    }
}

// MARK: - Compact Place Row

struct CompactPlaceRow: View {
    let place: Place
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var subtitleText: String {
        var parts: [String] = []
        if let address = place.streetAddress, !address.isEmpty {
            parts.append(address)
        }
        parts.append("\(Int(place.radius))m")
        if let elevation = place.elevation {
            parts.append(String(format: "%.0fm alt", elevation))
        }
        return parts.joined(separator: " • ")
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Place Icon
                PlaceIconView(icon: place.customIcon, font: .system(size: 15), fallbackColor: .accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Name & Metadata Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(place.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if place.isFavorite == true {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                if isSelected {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.purple.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowSeparator(.visible, edges: .bottom)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Map Marker View

struct PlaceMapMarkerView: View {
    let place: Place
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            if isSelected {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        PlaceIconView(icon: place.customIcon, font: .system(size: 11), fallbackColor: .white)
                        Text(place.name)
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.purple)
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                    )
                    
                    TriangleShape()
                        .fill(Color.purple)
                        .frame(width: 8, height: 5)
                        .offset(y: -1)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(place.isFavorite == true ? Color.orange : Color.red)
                        .frame(width: 18, height: 18)
                    
                    if let icon = place.customIcon, !icon.isEmpty {
                        PlaceIconView(icon: icon, font: .system(size: 9), fallbackColor: .white)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                )
            }
        }
    }
}

// MARK: - Triangle Shape for Selected Marker Pointer

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel Resize Handle View

struct PanelResizeHandleView: View {
    let isCollapsed: Bool
    
    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 40, height: 4.5)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
                
                if isCollapsed {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

struct ManagePlacesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ManagePlacesView(viewModel: ManagePlacesViewModel.preview)
        }
        .environmentObject(LocationManager())
    }
}
