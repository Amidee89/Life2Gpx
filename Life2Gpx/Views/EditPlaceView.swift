import SwiftUI
import MapKit

struct EditPlaceView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var editablePlace: Place.EditableCopy
    @State private var name: String
    @State private var streetAddress: String
    @State private var radius: Int
    @State private var center: CLLocationCoordinate2D
    @State private var cameraPosition: MapCameraPosition
    @State private var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(),  
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var isFavorite: Bool
    @State private var lastVisited: Date
    @State private var customIcon: String
    @State private var facebookPlaceId: String
    @State private var mapboxPlaceId: String
    @State private var foursquareVenueId: String
    @State private var foursquareCategoryId: String
    @State private var latitudeString: String
    @State private var longitudeString: String
    @State private var newPreviousId: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    private let originalPlace: Place

    @State private var editedPlaceId: String

    @State private var showingDeleteConfirmation = false

    @State private var isIdentifiersSectionExpanded = false

    @State private var showingIconPicker = false
    @State private var searchText = ""

    let isNewPlace: Bool
    let onSave: ((Place) -> Void)?

    init(place: Place, isNewPlace: Bool = false, onSave: ((Place) -> Void)? = nil) {
        self.originalPlace = place
        self.isNewPlace = isNewPlace
        self.onSave = onSave
        _editablePlace = State(initialValue: Place.EditableCopy(from: place))
        _editedPlaceId = State(initialValue: place.placeId)
        _name = State(initialValue: place.name)
        _streetAddress = State(initialValue: place.streetAddress ?? "")
        _radius = State(initialValue: Int(place.radius))
        _center = State(initialValue: place.centerCoordinate)
        
        let radiusInDegrees = (Double(place.radius) * 2.2) / 111000 // Convert meters to degrees
        let minimumSpan = 10.0 / 111000 
        let span = max(radiusInDegrees, minimumSpan)
        
        _currentRegion = State(initialValue: MKCoordinateRegion(
            center: place.centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        ))
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: place.centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
        
        // Initialize additional fields
        _facebookPlaceId = State(initialValue: place.facebookPlaceId ?? "")
        _mapboxPlaceId = State(initialValue: place.mapboxPlaceId ?? "")
        _foursquareVenueId = State(initialValue: place.foursquareVenueId ?? "")
        _foursquareCategoryId = State(initialValue: place.foursquareCategoryId ?? "")
        
        // Initialize lat/lon strings
        _latitudeString = State(initialValue: String(format: "%.6f", place.centerCoordinate.latitude))
        _longitudeString = State(initialValue: String(format: "%.6f", place.centerCoordinate.longitude))

        _isFavorite = State(initialValue: place.isFavorite ?? false)
        _customIcon = State(initialValue: place.customIcon ?? "")
        _lastVisited = State(initialValue: place.lastVisited ?? Date())
    }

    // Add these helper functions at the top of the view struct
    private func logSliderValue(from radius: Int) -> Double {
        // Convert radius to log scale (using natural log)
        let minRadius = 5.0
        let maxRadius = 2000.0
        let minLog = log(minRadius)
        let maxLog = log(maxRadius)
        
        return (log(Double(radius)) - minLog) / (maxLog - minLog)
    }

    private func radiusFromLogSlider(_ value: Double) -> Int {
        // Convert slider value back to radius using exponential
        let minRadius = 5.0
        let maxRadius = 2000.0
        let minLog = log(minRadius)
        let maxLog = log(maxRadius)
        
        let logValue = minLog + (value * (maxLog - minLog))
        return Int(round(exp(logValue)))
    }

    private var filteredIcons: [String] {
        let allIcons = ["mappin", "house", "building", "cart", "bag", "fork.knife", 
                        "cup.and.saucer", "airplane", "car", "tram", "bicycle", 
                        "figure.walk", "figure.run", "basketball", "dumbbell", 
                        "cross", "pills", "books.vertical", "graduationcap", 
                        "briefcase", "building.2", "leaf", "tree", "pawprint", 
                        "music.note", "theatermasks", "gamecontroller", "paintbrush", 
                        "camera", "wrench.and.screwdriver", "scissors", "cart.fill.badge.plus"]
        
        if searchText.isEmpty {
            return allIcons
        }
        return allIcons.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            Form {
                // Map Section
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        MapReader { reader in
                            Map(position: $cameraPosition, interactionModes: .all) {
                                Annotation(editablePlace.name, coordinate: center) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                }
                                MapCircle(center: center, radius: Double(radius))
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                                    .foregroundStyle(Color.orange.opacity(0.5))
                            }
                            .frame(height: 300)
                            .onTapGesture { screenCoord in
                                if let coordinate = reader.convert(screenCoord, from: .local) {
                                    center = coordinate
                                    latitudeString = String(format: "%.6f", coordinate.latitude)
                                    longitudeString = String(format: "%.6f", coordinate.longitude)
                                }
                                
                            }
                        }

                        // Map Control Buttons
                        VStack(spacing: 10) {
                            // Center on selected point button
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
                                        let radiusInDegrees = (Double(radius) * 2.2) / 111000
                                        let minimumSpan = 10.0 / 111000
                                        let span = max(radiusInDegrees, minimumSpan)
                                        
                                        currentRegion = MKCoordinateRegion(
                                            center: center,
                                            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                                        )
                                        cameraPosition = .region(currentRegion)
                                    }
                                }
                            
                            // Center on user location button
                            Image(systemName: "location")
                                .font(.title)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.blue)
                                .clipShape(Circle())
                                .shadow(radius: 3)
                                .scaleEffect(0.8)
                                .contentShape(Circle())
                                .onTapGesture {
                                    withAnimation {
                                        cameraPosition = .userLocation(followsHeading: false, fallback: .region(currentRegion))
                                    }
                                }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .allowsHitTesting(true)
                        .zIndex(1)
                    }
                    .listRowInsets(EdgeInsets())
                }
                
                // Basic Details Section
                Section(header: Text("Basic Details")) {
                    TextField("Name", text: $name)
                    
                    TextField("Latitude", text: $latitudeString)
                        .keyboardType(.decimalPad)
                        .onChange(of: latitudeString) { newValue in
                            if let lat = Double(newValue), lat >= -90, lat <= 90 {
                                center = CLLocationCoordinate2D(
                                    latitude: lat,
                                    longitude: center.longitude
                                )
                            }
                        }
                    
                    TextField("Longitude", text: $longitudeString)
                        .keyboardType(.decimalPad)
                        .onChange(of: longitudeString) { newValue in
                            if let lon = Double(newValue), lon >= -180, lon <= 180 {
                                center = CLLocationCoordinate2D(
                                    latitude: center.latitude,
                                    longitude: lon
                                )
                            }
                        }
                    
                    VStack {
                        Text("Radius: \(radius) meters")
                        Slider(
                            value: Binding(
                                get: { logSliderValue(from: radius) },
                                set: { radius = radiusFromLogSlider($0) }
                            ),
                            in: 0...1
                        )
                    }
                }
                
                // Address Section
                Section(header: Text("Address")) {
                    TextField("Street Address", text: $streetAddress)
                }
                
                // Icon Picker Section
                Section(header: Text("Icon")) {
                    HStack {
                        Image(systemName: customIcon.isEmpty ? "mappin.circle.fill" : customIcon)
                            .font(.title2)
                        Spacer()
                        Button("Choose Icon") {
                            showingIconPicker = true
                        }
                    }
                }
                
                // Last Visited Section
                Section(header: Text("Last Visited")) {
                    DatePicker(
                        "Last Visited",
                        selection: $lastVisited,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                
                // External IDs Section
                Section(header: Text("External IDs")) {
                    VStack(alignment: .leading) {
                        Text("Facebook Place ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Facebook Place ID", text: $facebookPlaceId)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Mapbox Place ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Mapbox Place ID", text: $mapboxPlaceId)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Foursquare Venue ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Foursquare Venue ID", text: $foursquareVenueId)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Foursquare Category ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Foursquare Category ID", text: $foursquareCategoryId)
                    }
                }
                
                // Identifiers Section
                DisclosureGroup(
                    isExpanded: $isIdentifiersSectionExpanded,
                    content: {
                        TextField("Place ID", text: $editedPlaceId)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Previous IDs")
                                .foregroundColor(.secondary)
                            
                            ForEach(editablePlace.previousIds ?? [], id: \.self) { previousId in
                                if let id = previousId {
                                    Text(id)
                                        .padding(.vertical, 4)
                                }
                            }
                            
                            HStack {
                                TextField("Add previous ID", text: $newPreviousId)
                                Button(action: {
                                    if !newPreviousId.isEmpty {
                                        var updatedPreviousIds = editablePlace.previousIds ?? []
                                        updatedPreviousIds.append(newPreviousId)
                                        editablePlace.previousIds = updatedPreviousIds
                                        newPreviousId = ""
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    },
                    label: {
                        HStack {
                            Text("Identifiers")
                            Text("(edit at own risk)")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                )
                
                // Only show delete button for existing places
                if !isNewPlace {
                    Section {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Spacer()
                                Text("Delete Place")
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.red)
                        .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle(isNewPlace ? "New Place" : "Edit Place")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        isFavorite.toggle()
                    }) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? .red : .gray)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePlace()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            // Add this modifier after the Form
            .confirmationDialog(
                "Are you sure you want to delete this place?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deletePlace()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showingIconPicker) {
                NavigationView {
                    List {
                        ForEach(filteredIcons, id: \.self) { iconName in
                            Button(action: {
                                customIcon = iconName
                                showingIconPicker = false
                            }) {
                                HStack {
                                    Image(systemName: iconName)
                                        .font(.title2)
                                    Text(iconName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if customIcon == iconName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search icons")
                    .navigationTitle("Choose Icon")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Cancel") {
                                showingIconPicker = false
                            }
                        }
                    }
                }
            }
        }
    }

    private func savePlace() {
        let updatedPlace = Place(
            placeId: editedPlaceId.trim(),
            name: name.trim(),
            center: Center(latitude: Double(latitudeString.trim()) ?? 0,
                          longitude: Double(longitudeString.trim()) ?? 0),
            radius: Double(radius),
            streetAddress: streetAddress.isEmpty ? nil : streetAddress.trim(),
            secondsFromGMT: editablePlace.secondsFromGMT,
            lastSaved: ISO8601DateFormatter().string(from: Date()),
            facebookPlaceId: facebookPlaceId.isEmpty ? nil : facebookPlaceId.trim(),
            mapboxPlaceId: mapboxPlaceId.isEmpty ? nil : mapboxPlaceId.trim(),
            foursquareVenueId: foursquareVenueId.isEmpty ? nil : foursquareVenueId.trim(),
            foursquareCategoryId: foursquareCategoryId.isEmpty ? nil : foursquareCategoryId.trim(),
            previousIds: editablePlace.previousIds,
            lastVisited: editablePlace.lastVisited,
            isFavorite: isFavorite ? true : nil,
            customIcon: customIcon.isEmpty ? nil : customIcon.trim()
        )
        
        do {
            if isNewPlace {
                try PlaceManager.shared.addPlace(updatedPlace)
                onSave?(updatedPlace)
            } else {
                try PlaceManager.shared.editPlace(original: originalPlace, edited: updatedPlace)
                onSave?(updatedPlace)
            }
            presentationMode.wrappedValue.dismiss()
        } catch PlaceError.invalidPlaceId(let message),
                PlaceError.invalidName(let message),
                PlaceError.invalidLatitude(let message),
                PlaceError.invalidLongitude(let message) {
            errorMessage = message
            showingError = true
        } catch {
            errorMessage = "Failed to \(isNewPlace ? "create" : "save") place: \(error.localizedDescription)"
            showingError = true
        }
    }

    // Add this new function
    private func deletePlace() {
        do {
            try PlaceManager.shared.deletePlace(originalPlace)
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = "Failed to delete place: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct EditPlaceView_Previews: PreviewProvider {
    static var previews: some View {
        EditPlaceView(place: Place(
            placeId: "1", 
            name: "Central Park", 
            center: Center(latitude: 40.785091, longitude: -73.968285), 
            radius: 200, 
            streetAddress: "New York, NY", 
            secondsFromGMT: -18000, 
            lastSaved: "2024-10-18", 
            facebookPlaceId: nil, 
            mapboxPlaceId: nil, 
            foursquareVenueId: nil, 
            foursquareCategoryId: nil, 
            previousIds: [nil],
            lastVisited: nil,
            isFavorite: nil,
            customIcon: nil))
    }
}
