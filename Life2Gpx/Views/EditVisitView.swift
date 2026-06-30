import SwiftUI
import CoreLocation
import MapKit
import CoreGPX

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (Place?, Bool) -> Void
    let fileDate: Date
    
    @State private var selectedPlace: Place?
    @State private var nearbyPlaces: [Place] = []
    @State private var searchText: String = ""
    @State private var showingNewPlaceSheet = false
    @State private var showingEditPlaceSheet = false
    @State private var region: MKCoordinateRegion = MKCoordinateRegion()
    @State private var visitDate: Date
    @State private var latitudeString: String = ""
    @State private var longitudeString: String = ""
    @State private var elevationString: String = ""
    @State private var stepsString: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var workingWaypoint: GPXWaypoint?
    @State private var showingPlaceSearch = false
    @State private var showingNewPlaceFromSearch = false
    @State private var pendingSearchResult: PlaceSearchResult?
    @State private var wasOriginallyUnknown: Bool = false
    
    private var originalLatitude: Double?
    private var originalLongitude: Double?
    private var originalElevation: Double?
    private var originalTime: Date?
    private var originalWaypoint: GPXWaypoint?
    
    init(timelineObject: TimelineObject, fileDate: Date, onSave: @escaping (Place?, Bool) -> Void) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        self.onSave = onSave
        
        // Store the original waypoint and its values
        if let firstPoint = timelineObject.points.first {
            self.originalWaypoint = firstPoint
        }
        
        _wasOriginallyUnknown = State(initialValue: timelineObject.isUnknownPlace)
        
        _visitDate = State(initialValue: timelineObject.startDate ?? Date())
        _latitudeString = State(initialValue: String(format: "%.6f", self.originalWaypoint?.latitude ?? 0))
        _longitudeString = State(initialValue: String(format: "%.6f", self.originalWaypoint?.longitude ?? 0))
        _elevationString = State(initialValue: String(format: "%.1f", self.originalWaypoint?.elevation ?? 0))
        _stepsString = State(initialValue: self.originalWaypoint?.extensions?.get(from: nil)?["Steps"] ?? "0")
        
        // Create a working copy of the waypoint (but need to assign it in onAppear)
        _workingWaypoint = State(initialValue: nil)
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        guard let waypoint = workingWaypoint else { return nil }
        return CLLocationCoordinate2D(
            latitude: waypoint.latitude ?? 0,
            longitude: waypoint.longitude ?? 0
        )
    }

    private var filteredPlaces: [Place] {
        guard let coordinate = currentCoordinate else { return [] }
        
        let allPlaces = searchText.isEmpty ? nearbyPlaces : PlaceManager.shared.getAllPlaces()
        let filtered = searchText.isEmpty ? allPlaces : allPlaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        
        return filtered
            .sorted { place1, place2 in
                if place1 == selectedPlace { return true }
                if place2 == selectedPlace { return false }
                return coordinate.distance(to: place1.centerCoordinate) < coordinate.distance(to: place2.centerCoordinate)
            }
            .prefix(10)
            .map { $0 }
    }

    private func formattedDistance(to place: Place) -> String {
        guard let coordinate = currentCoordinate else { return "" }
        let distance = coordinate.distance(to: place.centerCoordinate)
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                List {
                    if let coordinate = currentCoordinate {
                        Section("Visit Details") {
                            // Split the date and time components
                            HStack {
                                // Date picker
                                DatePicker("Date", 
                                     selection: $visitDate,
                                     displayedComponents: [.date])
                            }
                            
                            // Time and seconds picker combined
                            HStack {
                                // Hour:minute picker
                                DatePicker("Time", 
                                     selection: $visitDate,
                                     displayedComponents: [.hourAndMinute])
                                
                                // Seconds component
                                let calendar = Calendar.current
                                let seconds = calendar.component(.second, from: visitDate)
                                Text(":")
                                    .font(.system(size: 17, weight: .regular))
                                Menu {
                                    Picker("", selection: Binding(
                                        get: { seconds },
                                        set: { newSeconds in
                                            // Preserve date and hour/minute while changing seconds
                                            var components = calendar.dateComponents(
                                                [.year, .month, .day, .hour, .minute],
                                                from: visitDate
                                            )
                                            components.second = newSeconds
                                            
                                            if let newDate = calendar.date(from: components) {
                                                visitDate = newDate
                                                
                                                // Update the waypoint time
                                                if let waypoint = workingWaypoint {
                                                    waypoint.time = newDate
                                                }
                                            }
                                        }
                                    )) {
                                        ForEach(0..<60) { second in
                                            Text("\(second)").tag(second)
                                        }
                                    }
                                } label: {
                                    Text(String(format: "%02d", seconds))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            LabeledContent("Latitude:") {
                                TextField("", text: $latitudeString)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            LabeledContent("Longitude:") {
                                TextField("", text: $longitudeString)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            LabeledContent("Elevation (m):") {
                                TextField("", text: $elevationString)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            LabeledContent("Steps:") {
                                TextField("", text: $stepsString)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            if let place = selectedPlace {
                                Button(action: {
                                    // Update coordinates with place's coordinates
                                    latitudeString = String(format: "%.6f", place.centerCoordinate.latitude)
                                    longitudeString = String(format: "%.6f", place.centerCoordinate.longitude)
                                    
                                    // Update the waypoint coordinates
                                    if let waypoint = workingWaypoint {
                                        waypoint.latitude = place.centerCoordinate.latitude
                                        waypoint.longitude = place.centerCoordinate.longitude
                                    }
                                    
                                    // Update the map region to center on the place
                                    withAnimation {
                                        region = MKCoordinateRegion(
                                            center: CoordinateConverter.forMapDisplay(place.centerCoordinate),
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                        )
                                    }
                                }) {
                                    Label("Use Place Coordinates", systemImage: "location.fill")
                                        .foregroundColor(.blue)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        
                        placeDetailsSection
                        
                        changePlaceSection(coordinate: coordinate)
                    }

                    // Add this new section at the end of the List
                    Section {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Spacer()
                                Text("Delete Visit")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                    .listRowBackground(Color.red.opacity(0.1))
                }
            }
            .navigationTitle("Edit Visit")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    // First, backup the current GPX file
                    do {
                        try FileManagerUtil.shared.backupFile(forDate: fileDate)
                    } catch {
                        print("Error backing up GPX file: \(error)")
                        return
                    }
                    
                    timelineObject.startDate = visitDate
                    
                    // Update the working waypoint with the latest values
                    if let waypoint = workingWaypoint {
                        waypoint.latitude = Double(latitudeString) ?? 0
                        waypoint.longitude = Double(longitudeString) ?? 0
                        waypoint.time = visitDate
                        waypoint.elevation = Double(elevationString) ?? 0
                        
                        if let steps = Int(stepsString), steps > 0 {
                            if waypoint.extensions == nil {
                                waypoint.extensions = GPXExtensions()
                            }
                            waypoint.extensions?.append(at: nil, contents: ["Steps": stepsString])
                        }
                        
                        if let selectedPlace {
                            let updated = GPXUtils.updateWaypointMetadataFromPlace(updatedWaypoint: waypoint, place: selectedPlace)
                            if let originalWaypoint = self.originalWaypoint {
                                GPXManager.shared.updateWaypoint(originalWaypoint: originalWaypoint, updatedWaypoint: updated, forDate: fileDate)
                            }
                        } else {
                            waypoint.name = nil
                            let placeKeys: Set<String> = [
                                "PlaceId", "Address", "FacebookPlaceId", "MapboxPlaceId",
                                "FoursquareVenueId", "FoursquareCategoryId", "GooglePlacesId",
                                "YelpId", "ApplePlaceId", "OsmNodeId", "HerePlaceId", "GaodePlaceId"
                            ]
                            if let existingExtensions = waypoint.extensions {
                                var remainingData = [String: String]()
                                for child in existingExtensions.children {
                                    if !placeKeys.contains(child.name), let value = child.text, !child.name.isEmpty {
                                        remainingData[child.name] = value
                                    }
                                }
                                if remainingData.isEmpty {
                                    waypoint.extensions = nil
                                } else {
                                    let newExtensions = GPXExtensions()
                                    newExtensions.append(at: nil, contents: remainingData)
                                    waypoint.extensions = newExtensions
                                }
                            }
                            if let originalWaypoint = self.originalWaypoint {
                                GPXManager.shared.updateWaypoint(originalWaypoint: originalWaypoint, updatedWaypoint: waypoint, forDate: fileDate)
                            }
                        }
                    }
                    
                    onSave(selectedPlace, wasOriginallyUnknown)
                    dismiss()
                }
            )
            .sheet(isPresented: $showingNewPlaceSheet) {
                if let coordinate = currentCoordinate {
                    let initialElevation = timelineObject.points.first?.elevation

                    EditPlaceView(
                        place: Place(
                            placeId: UUID().uuidString,
                            name: "",
                            center: Center(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            ),
                            radius: Double(SettingsManager.shared.defaultNewPlaceRadius),
                            streetAddress: nil,
                            secondsFromGMT: TimeZone.current.secondsFromGMT(),
                            lastSaved: ISO8601DateFormatter().string(from: Date()),
                            facebookPlaceId: nil,
                            mapboxPlaceId: nil,
                            foursquareVenueId: nil,
                            foursquareCategoryId: nil,
                            previousIds: nil,
                            lastVisited: nil,
                            isFavorite: nil,
                            customIcon: nil,
                            elevation: initialElevation
                        ),
                        isNewPlace: true,
                        isFromEditVisit: true,
                        onSave: { newPlace in
                            // Set the new place as the currently selected place
                            self.selectedPlace = newPlace
                            
                            // Refresh nearby places list
                            if let coordinate = self.currentCoordinate {
                                self.nearbyPlaces = PlaceManager.shared.findClosePlaces(to: coordinate)
                            }
                            
                            // Dismiss the new place sheet
                            self.showingNewPlaceSheet = false
                        }
                    )
                }
            }
            .sheet(isPresented: $showingEditPlaceSheet) {
                if let place = selectedPlace {
                    EditPlaceView(
                        place: place,
                        isFromEditVisit: true,
                        onSave: { updatedPlace in
                            selectedPlace = updatedPlace
                        }
                    )
                }
            }
            .sheet(isPresented: $showingNewPlaceFromSearch) {
                if let result = pendingSearchResult, currentCoordinate != nil {
                    let initialElevation = timelineObject.points.first?.elevation
                    EditPlaceView(
                        place: Place(
                            placeId: UUID().uuidString,
                            name: result.name,
                            center: Center(latitude: result.latitude, longitude: result.longitude),
                            radius: Double(SettingsManager.shared.defaultNewPlaceRadius),
                            streetAddress: result.address,
                            secondsFromGMT: TimeZone.current.secondsFromGMT(),
                            lastSaved: ISO8601DateFormatter().string(from: Date()),
                            facebookPlaceId: nil,
                            mapboxPlaceId: result.provider == .mapbox ? result.id : nil,
                            foursquareVenueId: result.provider == .foursquare ? result.id : nil,
                            foursquareCategoryId: result.foursquareCategoryId,
                            googlePlacesId: result.provider == .google ? result.id : nil,
                            yelpId: result.provider == .yelp ? result.id : nil,
                            applePlaceId: result.provider == .apple ? result.id : nil,
                            osmNodeId: result.provider == .openStreetMap ? result.id : nil,
                            herePlaceId: result.provider == .here ? result.id : nil,
                            gaodePlaceId: result.provider == .gaode ? result.id : nil,
                            previousIds: nil,
                            lastVisited: nil,
                            isFavorite: nil,
                            customIcon: result.resolvedIcon,
                            elevation: initialElevation
                        ),
                        isNewPlace: true,
                        isFromEditVisit: true,
                        onSave: { newPlace in
                            self.selectedPlace = newPlace
                            if let coord = self.currentCoordinate {
                                self.nearbyPlaces = PlaceManager.shared.findClosePlaces(to: coord)
                            }
                            self.showingNewPlaceFromSearch = false
                        }
                    )
                }
            }
        }
        .alert(
            "Are you sure you want to delete this visit?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Visit", role: .destructive) {
                // First, backup the current GPX file
                do {
                    try FileManagerUtil.shared.backupFile(forDate: fileDate)
                } catch {
                    print("Error backing up GPX file: \(error)")
                    return
                }
                
                // Delete the waypoint using the original waypoint
                if let originalWaypoint = self.originalWaypoint {
                    GPXManager.shared.deleteWaypoint(originalWaypoint: originalWaypoint, forDate: fileDate)
                }
                
                onSave(nil, false)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            // Create a deep copy of the waypoint for editing
            if let firstPoint = timelineObject.points.first {
                self.workingWaypoint = GPXUtils.deepCopyPoint(firstPoint)
            }
            
            if let coordinate = currentCoordinate {
                region = MKCoordinateRegion(
                    center: CoordinateConverter.forMapDisplay(coordinate),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                
                nearbyPlaces = PlaceManager.shared.findClosePlaces(to: coordinate)
                
                if let visitName = timelineObject.name {
                    selectedPlace = nearbyPlaces.first { $0.name == visitName }
                }
            }
        }
        .onChange(of: selectedPlace) { _, newPlace in
            if let place = newPlace, let coordinate = currentCoordinate {
                let displayCoord = CoordinateConverter.forMapDisplay(coordinate)
                let displayPlace = CoordinateConverter.forMapDisplay(place.centerCoordinate)
                let radiusInDegrees = (place.radius * 2.2) / 111000.0
                let minimumSpan = 0.005 
                
                let latDelta = max(
                    abs(displayCoord.latitude - displayPlace.latitude) * 2.2,
                    radiusInDegrees,
                    minimumSpan
                )
                let lonDelta = max(
                    abs(displayCoord.longitude - displayPlace.longitude) * 2.2,
                    radiusInDegrees,
                    minimumSpan
                )
                
                let center = CLLocationCoordinate2D(
                    latitude: (displayCoord.latitude + displayPlace.latitude) / 2,
                    longitude: (displayCoord.longitude + displayPlace.longitude) / 2
                )
                
                region = MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(
                        latitudeDelta: latDelta,
                        longitudeDelta: lonDelta
                    )
                )
            }
        }
    }

    // MARK: - Extracted Subviews

    private var placeDetailsSection: some View {
        Section("Place Details") {
            ZStack(alignment: .bottomTrailing) {
                MapReader { reader in
                    Map(position: .constant(.region(region))) {
                        if let coordinate = currentCoordinate {
                            Annotation("Visit Location", coordinate: CoordinateConverter.forMapDisplay(coordinate)) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(Color.black)
                                        .padding(4)
                                }
                                .frame(width: 24, height: 24)
                            }
                        }

                        if let place = selectedPlace {
                            let placeDisplayCoord = CoordinateConverter.forMapDisplay(place.centerCoordinate)
                            Annotation(place.name, coordinate: placeDisplayCoord) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(Color.orange)
                                        .padding(4)
                                }
                                .frame(width: 24, height: 24)
                            }

                            MapCircle(center: placeDisplayCoord, radius: place.radius)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                                .foregroundStyle(Color.orange.opacity(0.5))
                        }
                    }
                    .onTapGesture { screenCoord in
                        if let mapCoordinate = reader.convert(screenCoord, from: .local) {
                            let coordinate = CoordinateConverter.fromMapDisplay(mapCoordinate)
                            if let waypoint = workingWaypoint {
                                waypoint.latitude = coordinate.latitude
                                waypoint.longitude = coordinate.longitude
                                latitudeString = String(format: "%.6f", coordinate.latitude)
                                longitudeString = String(format: "%.6f", coordinate.longitude)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Image(systemName: "location.viewfinder")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .shadow(radius: 3)
                    .scaleEffect(0.8)
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation {
                            region = MKCoordinateRegion(
                                center: CoordinateConverter.forMapDisplay(currentCoordinate ?? CLLocationCoordinate2D()),
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            )
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }

            if let place = selectedPlace {
                selectedPlaceRow(place: place)
            }
        }
    }

    private func selectedPlaceRow(place: Place) -> some View {
        VStack(spacing: 0) {
            HStack {
                PlaceIconView(icon: place.customIcon, font: .title2, fallbackColor: .blue)

                VStack(alignment: .leading) {
                    Text(place.name)
                        .font(.headline)
                    if let address = place.streetAddress {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text("Radius: \(Int(place.radius))m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    showingEditPlaceSheet = true
                }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }

            Button(action: { selectedPlace = nil }) {
                Text("Clear Place")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .padding(.top, 8)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func changePlaceSection(coordinate: CLLocationCoordinate2D) -> some View {
        Section("Change Place") {
            changePlaceButtons

            if showingPlaceSearch {
                PlaceSearchView(
                    coordinate: coordinate,
                    selectedIds: [:],
                    onSelect: { result in
                        if let existingPlace = PlaceSearchService.shared.findExistingPlace(for: result) {
                            selectedPlace = existingPlace
                            showingPlaceSearch = false
                        } else {
                            pendingSearchResult = result
                            showingPlaceSearch = false
                            showingNewPlaceFromSearch = true
                        }
                    },
                    onDone: {
                        showingPlaceSearch = false
                    }
                )
                .frame(height: UIScreen.main.bounds.height * 0.5)
            } else {
                TextField("Search places", text: $searchText)

                ForEach(filteredPlaces) { place in
                    placeRow(place: place)
                }
            }
        }
    }

    private var changePlaceButtons: some View {
        HStack {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add New Place")
            }
            .foregroundColor(.blue)
            .onTapGesture {
                showingPlaceSearch = false
                showingNewPlaceSheet = true
            }

            Spacer()

            HStack {
                Image(systemName: "magnifyingglass.circle.fill")
                Text("Find Place")
            }
            .foregroundColor(.purple)
            .onTapGesture {
                showingPlaceSearch.toggle()
            }
        }
    }

    private func placeRow(place: Place) -> some View {
        Button(action: {
            selectedPlace = place
        }) {
            HStack {
                PlaceIconView(icon: place.customIcon, font: .body, fallbackColor: .gray)
                    .frame(width: 24)
                VStack(alignment: .leading) {
                    Text(place.name)
                        .foregroundColor(.primary)
                    if let address = place.streetAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(formattedDistance(to: place))
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .listRowBackground(place == selectedPlace ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

struct EditVisitView_Previews: PreviewProvider {
    static var previews: some View {
        let point = CoreGPX.GPXWaypoint(latitude: 40.785091, longitude: -73.968285)
        let previewTimelineObject = TimelineObject(
            type: .waypoint,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            name: "Central Park",  // Match the place name
            coordinates: [
                IdentifiableCoordinates(coordinates: [
                    CLLocationCoordinate2D(latitude: 40.785091, longitude: -73.968285)
                ])
            ],
            points: [point]
        )
        
        
        NavigationView {
            EditVisitView(
                timelineObject: previewTimelineObject,
                fileDate: Date(),
                onSave: { _, _ in }
            )
        }
    }
} 
