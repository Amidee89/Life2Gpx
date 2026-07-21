import SwiftUI
import CoreLocation
import MapKit
import CoreGPX

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (Place?, Bool) -> Void
    var customSaveAction: ((_ updatedWaypoint: GPXWaypoint, _ place: Place?, _ wasUnknown: Bool) -> Void)? = nil
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
    @State private var showingDeleteConfirmation = false
    @State private var workingWaypoint: GPXWaypoint?
    @State private var showingPlaceSearch = false
    @State private var showingNewPlaceFromSearch = false
    @State private var pendingSearchResult: PlaceSearchResult?
    @State private var wasOriginallyUnknown: Bool = false
    @State private var showingSecondsPicker = false
    @State private var editedExtensions: [String: String] = [:]
    @State private var showingAllExtensions = false
    @FocusState private var isInputActive: Bool
    
    @State private var showingRadiusIncreaseAlert = false
    @State private var requiredRadius: Double = 0.0
    @State private var radiusIncreaseWarning: String? = nil
    
    private var originalLatitude: Double?
    private var originalLongitude: Double?
    private var originalElevation: Double?
    private var originalTime: Date?
    private var originalWaypoint: GPXWaypoint?
    
    
    private var hasVisibleExtensions: Bool {
        if showingAllExtensions { return true }
        let settings = SettingsManager.shared.gpxExportSettings.waypoints
        for key in GPXExtensionKey.waypointCases {
            if settings.extensions[key.rawValue]?.visible == true {
                return true
            }
        }
        return false
    }
    
    init(timelineObject: TimelineObject, fileDate: Date, onSave: @escaping (Place?, Bool) -> Void, customSaveAction: ((_ updatedWaypoint: GPXWaypoint, _ place: Place?, _ wasUnknown: Bool) -> Void)? = nil) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        self.onSave = onSave
        self.customSaveAction = customSaveAction
        
        // Store the original waypoint and its values
        if let firstPoint = timelineObject.points.first {
            self.originalWaypoint = firstPoint
        }
        
        _wasOriginallyUnknown = State(initialValue: timelineObject.isUnknownPlace)
        
        _visitDate = State(initialValue: timelineObject.startDate ?? Date())
        _latitudeString = State(initialValue: String(format: "%.6f", self.originalWaypoint?.latitude ?? 0))
        _longitudeString = State(initialValue: String(format: "%.6f", self.originalWaypoint?.longitude ?? 0))
        _elevationString = State(initialValue: String(format: "%.1f", self.originalWaypoint?.elevation ?? 0))
        
        var extDict = [String: String]()
        if let extensions = self.originalWaypoint?.extensions {
            for child in extensions.children {
                if let text = child.text {
                    extDict[child.name] = text
                }
            }
        }
        if extDict[GPXExtensionKey.timezoneOffset.rawValue] == nil {
            extDict[GPXExtensionKey.timezoneOffset.rawValue] = String(TimeZone.current.secondsFromGMT())
        }
        _editedExtensions = State(initialValue: extDict)
        
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
            .prefix(SettingsManager.shared.findClosePlacesLimit)
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
                        
                        HStack {
                            DatePicker("Time", 
                                 selection: $visitDate,
                                 displayedComponents: [.hourAndMinute])
                            
                            let seconds = calendar.component(.second, from: visitDate)
                            Text(":")
                                .font(.system(size: 17, weight: .regular))
                            
                            Button(action: {
                                showingSecondsPicker = true
                            }) {
                                Text(String(format: "%02d", seconds))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(UIColor.tertiarySystemFill))
                                    .cornerRadius(6)
                                    .foregroundColor(.primary)
                            }
                            .popover(isPresented: $showingSecondsPicker) {
                                Picker("Seconds", selection: Binding(
                                    get: { seconds },
                                    set: { newSeconds in
                                        var components = calendar.dateComponents(
                                            [.year, .month, .day, .hour, .minute],
                                            from: visitDate
                                        )
                                        components.second = newSeconds
                                        
                                        if let newDate = calendar.date(from: components) {
                                            visitDate = newDate
                                            if let waypoint = workingWaypoint {
                                                waypoint.time = newDate
                                            }
                                        }
                                    }
                                )) {
                                    ForEach(0..<60) { second in
                                        Text(String(format: "%02d", second)).tag(second)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .labelsHidden()
                                .frame(width: 80, height: 120)
                                .padding(.vertical, 16)
                            .padding(.horizontal, 8)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                    
                    HStack {
                        Text("Timezone")
                        Spacer()
                        let binding = Binding<String>(
                            get: { editedExtensions[GPXExtensionKey.timezoneOffset.rawValue] ?? "" },
                            set: { editedExtensions[GPXExtensionKey.timezoneOffset.rawValue] = $0 }
                        )
                        SimpleTimezoneEditor(secondsOffsetString: binding, referenceDate: visitDate)
                    }
                    
                    LabeledContent("Latitude:") {
                            TextField("", text: $latitudeString)
                                .keyboardType(.decimalPad)
                                .focused($isInputActive)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        LabeledContent("Longitude:") {
                            TextField("", text: $longitudeString)
                                .keyboardType(.decimalPad)
                                .focused($isInputActive)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        LabeledContent("Elevation (m):") {
                            TextField("", text: $elevationString)
                                .keyboardType(.decimalPad)
                                .focused($isInputActive)
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
                        
                        basicFieldsList
                        
                        if hasVisibleExtensions {
                            Text("Extensions")
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                
                            extensionsList
                        }
                        
                        Toggle("Show all fields and extensions", isOn: $showingAllExtensions.animation())
                            .padding(.vertical, 8)
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
            .navigationTitle("Edit Visit")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    // Update the working waypoint with the latest values
                    guard let waypoint = workingWaypoint else { return }
                    let newLat = Double(latitudeString) ?? 0
                    let newLon = Double(longitudeString) ?? 0
                    waypoint.latitude = newLat
                    waypoint.longitude = newLon
                    waypoint.time = visitDate
                    waypoint.elevation = Double(elevationString) ?? 0
                    
                    if SettingsManager.shared.suggestIncreasePlaceRadius, let place = selectedPlace {
                        let visitLocation = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
                        let distance = visitLocation.distance(to: place.centerCoordinate)
                        if distance > place.radius {
                            requiredRadius = distance
                            let increase = distance - place.radius
                            
                            if increase > 500 {
                                radiusIncreaseWarning = "This will increase the radius by more than 500m (from \(Int(place.radius))m to \(Int(distance))m)."
                            } else if distance > place.radius * 2 {
                                radiusIncreaseWarning = "This will more than double the radius (from \(Int(place.radius))m to \(Int(distance))m)."
                            } else {
                                radiusIncreaseWarning = nil
                            }
                            
                            showingRadiusIncreaseAlert = true
                            return
                        }
                    }
                    
                    performSave()
                }
            )
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isInputActive = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
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
                            lastSaved: nil,
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
                            lastSaved: nil,
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
                // Delete the waypoint using the original waypoint
                if let originalWaypoint = self.originalWaypoint {
                    GPXManager.shared.deleteWaypoint(originalWaypoint: originalWaypoint, forDate: fileDate)
                }
                
                onSave(nil, false)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Increase Place Radius?",
            isPresented: $showingRadiusIncreaseAlert
        ) {
            Button("Yes") {
                performSave(updatePlaceRadius: true)
            }
            Button("No") {
                performSave(updatePlaceRadius: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let warning = radiusIncreaseWarning {
                Text("The visit location is outside the radius of the place.\n\nWarning: \(warning)\n\nDo you want to increase the radius to include this visit?")
            } else {
                Text("The visit location is outside the radius of the place. Do you want to increase the radius to include this visit?")
            }
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
                
                let allPlaces = PlaceManager.shared.getAllPlaces()
                let waypointPlaceId = self.originalWaypoint?.extensions?["PlaceId"].text
                
                if let waypointPlaceId = waypointPlaceId, let matchingPlace = allPlaces.first(where: { $0.placeId == waypointPlaceId }) {
                    selectedPlace = matchingPlace
                } else if waypointPlaceId == "-1" {
                    // Reconstruct the one-time place metadata from GPX extensions
                    selectedPlace = Place(
                        placeId: "-1",
                        name: timelineObject.name ?? self.originalWaypoint?.name ?? "",
                        center: Center(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        radius: Double(SettingsManager.shared.defaultNewPlaceRadius),
                        streetAddress: self.originalWaypoint?.extensions?["Address"].text,
                        secondsFromGMT: TimeZone.current.secondsFromGMT(),
                        lastSaved: nil,
                        facebookPlaceId: self.originalWaypoint?.extensions?["FacebookPlaceId"].text,
                        mapboxPlaceId: self.originalWaypoint?.extensions?["MapboxPlaceId"].text,
                        foursquareVenueId: self.originalWaypoint?.extensions?["FoursquareVenueId"].text,
                        foursquareCategoryId: self.originalWaypoint?.extensions?["FoursquareCategoryId"].text,
                        googlePlacesId: self.originalWaypoint?.extensions?["GooglePlacesId"].text,
                        yelpId: self.originalWaypoint?.extensions?["YelpId"].text,
                        applePlaceId: self.originalWaypoint?.extensions?["ApplePlaceId"].text,
                        osmNodeId: self.originalWaypoint?.extensions?["OsmNodeId"].text,
                        herePlaceId: self.originalWaypoint?.extensions?["HerePlaceId"].text,
                        gaodePlaceId: self.originalWaypoint?.extensions?["GaodePlaceId"].text,
                        previousIds: nil,
                        lastVisited: nil,
                        isFavorite: nil,
                        customIcon: nil,
                        elevation: self.originalWaypoint?.elevation
                    )
                } else if let visitName = timelineObject.name {
                    selectedPlace = nearbyPlaces.first { $0.name == visitName }
                }
            }
        }
        .onChange(of: selectedPlace) { _, newPlace in
            let placeRelatedKeys = [
                GPXExtensionKey.placeId.rawValue,
                GPXExtensionKey.address.rawValue,
                GPXExtensionKey.facebookPlaceId.rawValue,
                GPXExtensionKey.mapboxPlaceId.rawValue,
                GPXExtensionKey.foursquareVenueId.rawValue,
                GPXExtensionKey.foursquareCategoryId.rawValue,
                GPXExtensionKey.googlePlacesId.rawValue,
                GPXExtensionKey.yelpId.rawValue,
                GPXExtensionKey.applePlaceId.rawValue,
                GPXExtensionKey.osmNodeId.rawValue,
                GPXExtensionKey.herePlaceId.rawValue,
                GPXExtensionKey.gaodePlaceId.rawValue
            ]
            
            for key in placeRelatedKeys {
                editedExtensions.removeValue(forKey: key)
            }
            
            if let place = newPlace {
                editedExtensions[GPXExtensionKey.placeId.rawValue] = place.placeId
                if let address = place.streetAddress { editedExtensions[GPXExtensionKey.address.rawValue] = address }
                if let fbId = place.facebookPlaceId { editedExtensions[GPXExtensionKey.facebookPlaceId.rawValue] = fbId }
                if let mapboxId = place.mapboxPlaceId { editedExtensions[GPXExtensionKey.mapboxPlaceId.rawValue] = mapboxId }
                if let foursquareId = place.foursquareVenueId { editedExtensions[GPXExtensionKey.foursquareVenueId.rawValue] = foursquareId }
                if let categoryId = place.foursquareCategoryId { editedExtensions[GPXExtensionKey.foursquareCategoryId.rawValue] = categoryId }
                if let googleId = place.googlePlacesId { editedExtensions[GPXExtensionKey.googlePlacesId.rawValue] = googleId }
                if let yelpId = place.yelpId { editedExtensions[GPXExtensionKey.yelpId.rawValue] = yelpId }
                if let appleId = place.applePlaceId { editedExtensions[GPXExtensionKey.applePlaceId.rawValue] = appleId }
                if let osmId = place.osmNodeId { editedExtensions[GPXExtensionKey.osmNodeId.rawValue] = osmId }
                if let hereId = place.herePlaceId { editedExtensions[GPXExtensionKey.herePlaceId.rawValue] = hereId }
                if let gaodeId = place.gaodePlaceId { editedExtensions[GPXExtensionKey.gaodePlaceId.rawValue] = gaodeId }
            }

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

    private func performSave(updatePlaceRadius: Bool = false) {
        guard let waypoint = workingWaypoint else { return }
        
        waypoint.extensions = nil
        if !editedExtensions.isEmpty {
            let newExtensions = GPXExtensions()
            newExtensions.append(at: nil, contents: editedExtensions)
            waypoint.extensions = newExtensions
        }
        
        var finalPlace = selectedPlace
        
        if updatePlaceRadius, let place = finalPlace {
            let updatedPlace = Place(
                placeId: place.placeId,
                name: place.name,
                center: place.center,
                radius: requiredRadius,
                streetAddress: place.streetAddress,
                secondsFromGMT: place.secondsFromGMT,
                lastSaved: place.lastSaved,
                facebookPlaceId: place.facebookPlaceId,
                mapboxPlaceId: place.mapboxPlaceId,
                foursquareVenueId: place.foursquareVenueId,
                foursquareCategoryId: place.foursquareCategoryId,
                googlePlacesId: place.googlePlacesId,
                yelpId: place.yelpId,
                applePlaceId: place.applePlaceId,
                osmNodeId: place.osmNodeId,
                herePlaceId: place.herePlaceId,
                gaodePlaceId: place.gaodePlaceId,
                previousIds: place.previousIds,
                lastVisited: place.lastVisited,
                isFavorite: place.isFavorite,
                customIcon: place.customIcon,
                elevation: place.elevation,
                isActive: place.isActive
            )
            do {
                try PlaceManager.shared.editPlace(original: place, edited: updatedPlace)
                finalPlace = updatedPlace
                selectedPlace = updatedPlace
            } catch {
                print("Failed to update place radius: \(error)")
            }
        }
        
        let finalWaypoint: GPXWaypoint
        if let place = finalPlace {
            finalWaypoint = GPXUtils.updateWaypointMetadataFromPlace(updatedWaypoint: waypoint, place: place)
        } else {
            waypoint.name = nil
            finalWaypoint = waypoint
        }
        
        if let customSave = customSaveAction {
            customSave(finalWaypoint, finalPlace, wasOriginallyUnknown)
        } else {
            timelineObject.startDate = visitDate
            
            if let originalWaypoint = self.originalWaypoint {
                GPXManager.shared.updateWaypoint(originalWaypoint: originalWaypoint, updatedWaypoint: finalWaypoint, forDate: fileDate)
            }
            
            onSave(finalPlace, wasOriginallyUnknown)
        }
        dismiss()
    }

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
    
    @ViewBuilder
    private var basicFieldsList: some View {
        if let point = workingWaypoint {
            let settings = SettingsManager.shared.gpxExportSettings.waypoints

            if settings.magneticVariation.visible || showingAllExtensions {
                let binding = Binding<Double>(
                    get: { point.magneticVariation ?? 0.0 },
                    set: { newValue in
                        workingWaypoint?.magneticVariation = newValue
                    }
                )
                LabeledContent("Magnetic Variation:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.geoidHeight.visible || showingAllExtensions {
                let binding = Binding<Double>(
                    get: { point.geoidHeight ?? 0.0 },
                    set: { newValue in
                        workingWaypoint?.geoidHeight = newValue
                    }
                )
                LabeledContent("Geoid Height:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.name.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.name ?? "" },
                    set: { newValue in
                        workingWaypoint?.name = newValue.isEmpty ? nil : newValue
                    }
                )
                LabeledContent("Name:") {
                    TextField("", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.comment.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.comment ?? "" },
                    set: { newValue in
                        workingWaypoint?.comment = newValue.isEmpty ? nil : newValue
                    }
                )
                LabeledContent("Comment:") {
                    TextField("", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.desc.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.desc ?? "" },
                    set: { newValue in
                        workingWaypoint?.desc = newValue.isEmpty ? nil : newValue
                    }
                )
                LabeledContent("Description:") {
                    TextField("", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.source.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.source ?? "" },
                    set: { newValue in
                        workingWaypoint?.source = newValue.isEmpty ? nil : newValue
                    }
                )
                LabeledContent("Source:") {
                    TextField("", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.symbol.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.symbol ?? "" },
                    set: { newValue in
                        workingWaypoint?.symbol = newValue.isEmpty ? nil : newValue
                    }
                )
                LabeledContent("Symbol:") {
                    TextField("", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.type.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.type ?? "" },
                    set: { newValue in
                        workingWaypoint?.type = newValue.isEmpty ? nil : newValue
                    }
                )
                LabeledContent("Type:") {
                    TextField("", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.satellites.visible || showingAllExtensions {
                let binding = Binding<Int>(
                    get: { point.satellites ?? 0 },
                    set: { newValue in
                        workingWaypoint?.satellites = newValue
                    }
                )
                LabeledContent("Satellites:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.horizontalDilution.visible || showingAllExtensions {
                let binding = Binding<Double>(
                    get: { point.horizontalDilution ?? 0.0 },
                    set: { newValue in
                        workingWaypoint?.horizontalDilution = newValue
                    }
                )
                LabeledContent("Horizontal Dilution:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.verticalDilution.visible || showingAllExtensions {
                let binding = Binding<Double>(
                    get: { point.verticalDilution ?? 0.0 },
                    set: { newValue in
                        workingWaypoint?.verticalDilution = newValue
                    }
                )
                LabeledContent("Vertical Dilution:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.positionDilution.visible || showingAllExtensions {
                let binding = Binding<Double>(
                    get: { point.positionDilution ?? 0.0 },
                    set: { newValue in
                        workingWaypoint?.positionDilution = newValue
                    }
                )
                LabeledContent("Position Dilution:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.ageofDGPSData.visible || showingAllExtensions {
                let binding = Binding<Double>(
                    get: { point.ageofDGPSData ?? 0.0 },
                    set: { newValue in
                        workingWaypoint?.ageofDGPSData = newValue
                    }
                )
                LabeledContent("Age of DGPS Data:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.DGPSid.visible || showingAllExtensions {
                let binding = Binding<Int>(
                    get: { point.DGPSid ?? 0 },
                    set: { newValue in
                        workingWaypoint?.DGPSid = newValue
                    }
                )
                LabeledContent("DGPS ID:") {
                    TextField("", value: binding, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
            if settings.fix.visible || showingAllExtensions {
                let binding = Binding<String>(
                    get: { point.fix?.rawValue ?? "" },
                    set: { newValue in
                        if let fix = GPXFix(rawValue: newValue) {
                            workingWaypoint?.fix = fix
                        } else if newValue.isEmpty {
                            workingWaypoint?.fix = nil
                        }
                    }
                )
                LabeledContent("Fix:") {
                    TextField("none, 2d, 3d, dgps, pps", text: binding)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var extensionsList: some View {
        ForEach(GPXExtensionKey.waypointCases, id: \.self) { (key: GPXExtensionKey) in
            let hasValue = editedExtensions.keys.contains(key.rawValue)
            let isVisible = SettingsManager.shared.gpxExportSettings.waypoints.extensions[key.rawValue]?.visible == true
            if isVisible || showingAllExtensions {
                let binding = Binding<String>(
                get: { editedExtensions[key.rawValue] ?? "" },
                set: { newValue in
                    if newValue.isEmpty {
                        editedExtensions.removeValue(forKey: key.rawValue)
                    } else {
                        editedExtensions[key.rawValue] = newValue
                    }
                }
            )
            
            HStack {
                if hasValue {
                    Button(action: {
                        editedExtensions.removeValue(forKey: key.rawValue)
                    }) {
                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                } else {
                    Button(action: {
                        if key == .timezoneOffset {
                            editedExtensions[key.rawValue] = String(TimeZone.current.secondsFromGMT())
                        } else {
                            switch key.valueType {
                            case .boolean:
                                editedExtensions[key.rawValue] = "True"
                            case .activityConfidence:
                                editedExtensions[key.rawValue] = ActivityConfidenceValue.high.rawValue
                            case .integer:
                                editedExtensions[key.rawValue] = "0"
                            case .double:
                                editedExtensions[key.rawValue] = "0.0"
                            default:
                                editedExtensions[key.rawValue] = "New Value"
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.green)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                LabeledContent(key.rawValue) {
                    if !hasValue {
                        Text("nil").foregroundColor(.secondary)
                    } else if key == .timezoneOffset {
                        SimpleTimezoneEditor(secondsOffsetString: binding, referenceDate: visitDate)
                    } else {
                        switch key.valueType {
                        case .boolean:
                            Picker("", selection: binding) {
                                Text("True").tag("True")
                                Text("False").tag("False")
                            }
                            .pickerStyle(MenuPickerStyle())
                        case .activityConfidence:
                            Picker("", selection: binding) {
                                ForEach(ActivityConfidenceValue.allCases) { conf in
                                    Text(conf.rawValue).tag(conf.rawValue)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        default:
                            TextField("Value", text: binding)
                                .focused($isInputActive)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                                .keyboardType(key.valueType == .double || key.valueType == .integer ? .numbersAndPunctuation : .default)
                        }
                    }
                }
            }
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
                    .focused($isInputActive)

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

struct SimpleTimezoneEditor: View {
    @Binding var secondsOffsetString: String
    var referenceDate: Date?
    
    @FocusState private var isInputActive: Bool
    @State private var showingPicker = false
    
    private var commonOffsets: [Int] {
        let allOffsets = TimeZone.knownTimeZoneIdentifiers.compactMap { TimeZone(identifier: $0)?.secondsFromGMT() }
        return Array(Set(allOffsets)).sorted()
    }
    
    private func formatOffset(_ offset: Int) -> String {
        let hours = offset / 3600
        let minutes = abs((offset % 3600) / 60)
        let sign = hours >= 0 && offset >= 0 ? "+" : ""
        if minutes == 0 {
            return "GMT\(sign)\(hours)"
        } else {
            return String(format: "GMT%@%d:%02d", sign, hours, minutes)
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                TextField("Seconds", text: $secondsOffsetString)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .focused($isInputActive)
                
                Button(action: {
                    showingPicker = true
                }) {
                    HStack(spacing: 4) {
                        if let offset = Int(secondsOffsetString) {
                            if commonOffsets.contains(offset) || offset % 3600 == 0 {
                                Text("\(formatOffset(offset))")
                            } else {
                                Text("Custom")
                            }
                        } else if !secondsOffsetString.isEmpty {
                            Text("Invalid")
                        } else {
                            Text("Select")
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(6)
                    .foregroundColor(.primary)
                }
                .buttonStyle(BorderlessButtonStyle())
                .popover(isPresented: $showingPicker) {
                    Picker("GMT Offset", selection: Binding(
                        get: { Int(secondsOffsetString) ?? TimeZone.current.secondsFromGMT() },
                        set: { secondsOffsetString = String($0) }
                    )) {
                        ForEach(commonOffsets, id: \.self) { offset in
                            Text(formatOffset(offset)).tag(offset)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(width: 150, height: 180)
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
            }
            if let date = referenceDate, let offset = Int(secondsOffsetString), let tz = TimeZone(secondsFromGMT: offset) {
                Text("local time: \(formattedDate(date, timeZone: tz))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formattedDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
