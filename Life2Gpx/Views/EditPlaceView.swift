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
    @State private var googlePlacesId: String
    @State private var yelpId: String
    @State private var applePlaceId: String
    @State private var osmNodeId: String
    @State private var herePlaceId: String
    @State private var gaodePlaceId: String
    @State private var latitudeString: String
    @State private var longitudeString: String
    @State private var isPolygonMode: Bool
    @State private var polygonActionMode: Int = 0
    @State private var polygonPoints: [CLLocationCoordinate2D]
    @State private var selectedPointIndex: Int?
    @State private var drawingPoints: [CLLocationCoordinate2D] = []
    @State private var isDraggingPoint: Bool = false
    @State private var polygonHistory = UndoHistory<[CLLocationCoordinate2D]>()
    @State private var newPreviousId: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var elevationString: String
    @State private var isActive: Bool
    private let originalPlace: Place

    @State private var editedPlaceId: String

    @State private var showingDeleteConfirmation = false

    @State private var isIdentifiersSectionExpanded = false

    @State private var showingIconPicker = false
    @State private var showingPlaceSearch = false

    @State private var isOneTimeVisit: Bool = false
    @State private var isLookingUpAddress: Bool = false
    let isFromEditVisit: Bool

    let isNewPlace: Bool
    let onSave: ((Place) -> Void)?
    let onDelete: (() -> Void)?

    init(place: Place, isNewPlace: Bool = false, isFromEditVisit: Bool = false, onSave: ((Place) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.originalPlace = place
        self.isNewPlace = isNewPlace
        self.isFromEditVisit = isFromEditVisit
        self.onSave = onSave
        self.onDelete = onDelete
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
            center: CoordinateConverter.forMapDisplay(place.centerCoordinate),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        ))
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: CoordinateConverter.forMapDisplay(place.centerCoordinate),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
        
        _facebookPlaceId = State(initialValue: place.facebookPlaceId ?? "")
        _mapboxPlaceId = State(initialValue: place.mapboxPlaceId ?? "")
        _foursquareVenueId = State(initialValue: place.foursquareVenueId ?? "")
        _foursquareCategoryId = State(initialValue: place.foursquareCategoryId ?? "")
        _googlePlacesId = State(initialValue: place.googlePlacesId ?? "")
        _yelpId = State(initialValue: place.yelpId ?? "")
        _applePlaceId = State(initialValue: place.applePlaceId ?? "")
        _osmNodeId = State(initialValue: place.osmNodeId ?? "")
        _herePlaceId = State(initialValue: place.herePlaceId ?? "")
        _gaodePlaceId = State(initialValue: place.gaodePlaceId ?? "")
        
        _latitudeString = State(initialValue: String(format: "%.6f", place.centerCoordinate.latitude))
        _longitudeString = State(initialValue: String(format: "%.6f", place.centerCoordinate.longitude))

        if let elevation = place.elevation {
            _elevationString = State(initialValue: String(format: "%.1f", elevation))
        } else {
            _elevationString = State(initialValue: "")
        }

        _isActive = State(initialValue: place.isActive ?? true)
        _isFavorite = State(initialValue: place.isFavorite ?? false)
        _customIcon = State(initialValue: place.customIcon ?? "")
        _lastVisited = State(initialValue: place.lastVisited ?? Date())
        _isOneTimeVisit = State(initialValue: place.placeId == "-1")
        
        let hasPolygon = place.perimeterPolygonPoints != nil && !place.perimeterPolygonPoints!.isEmpty
        _isPolygonMode = State(initialValue: hasPolygon)
        if hasPolygon {
            _polygonPoints = State(initialValue: place.perimeterPolygonPoints!.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        } else {
            _polygonPoints = State(initialValue: [])
        }
        _selectedPointIndex = State(initialValue: nil)
    }

    private var selectedPlaceSearchIds: [PlaceProvider: String] {
        var ids = [PlaceProvider: String]()
        if !googlePlacesId.isEmpty { ids[.google] = googlePlacesId }
        if !foursquareVenueId.isEmpty { ids[.foursquare] = foursquareVenueId }
        if !yelpId.isEmpty { ids[.yelp] = yelpId }
        if !mapboxPlaceId.isEmpty { ids[.mapbox] = mapboxPlaceId }
        if !applePlaceId.isEmpty { ids[.apple] = applePlaceId }
        if !osmNodeId.isEmpty { ids[.openStreetMap] = osmNodeId }
        if !herePlaceId.isEmpty { ids[.here] = herePlaceId }
        if !gaodePlaceId.isEmpty { ids[.gaode] = gaodePlaceId }
        return ids
    }

    private func logSliderValue(from radius: Int) -> Double {
        let minRadius = 5.0
        let maxRadius = 2000.0
        let minLog = log(minRadius)
        let maxLog = log(maxRadius)
        
        return (log(Double(radius)) - minLog) / (maxLog - minLog)
    }

    private func radiusFromLogSlider(_ value: Double) -> Int {
        let minRadius = 5.0
        let maxRadius = 2000.0
        let minLog = log(minRadius)
        let maxLog = log(maxRadius)
        
        let logValue = minLog + (value * (maxLog - minLog))
        return Int(round(exp(logValue)))
    }

    private func updatePolygonCenter() {
        guard isPolygonMode, !polygonPoints.isEmpty else { return }
        let avgLat = polygonPoints.map(\.latitude).reduce(0, +) / Double(polygonPoints.count)
        let avgLng = polygonPoints.map(\.longitude).reduce(0, +) / Double(polygonPoints.count)
        center = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng)
        latitudeString = String(format: "%.6f", avgLat)
        longitudeString = String(format: "%.6f", avgLng)
        
        var maxDist = 5.0
        let centerLoc = CLLocation(latitude: avgLat, longitude: avgLng)
        for p in polygonPoints {
            let d = centerLoc.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if d > maxDist { maxDist = d }
        }
        radius = Int(ceil(maxDist))
    }

    var body: some View {
        NavigationView {
            Form {
                if !isActive {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Place is not active – it will not be automatically assigned to visits")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .listRowBackground(Color.blue.opacity(0.1))
                }
                
                Section {
                    Picker("Mode", selection: $isPolygonMode) {
                        Text("Radius").tag(false)
                        Text("Polygon").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: isPolygonMode) { _, newValue in
                        if newValue && polygonPoints.isEmpty {
                            let radiusDegrees = Double(radius) / 111320.0
                            polygonPoints = [
                                CLLocationCoordinate2D(latitude: center.latitude + radiusDegrees, longitude: center.longitude - radiusDegrees),
                                CLLocationCoordinate2D(latitude: center.latitude + radiusDegrees, longitude: center.longitude + radiusDegrees),
                                CLLocationCoordinate2D(latitude: center.latitude - radiusDegrees, longitude: center.longitude + radiusDegrees),
                                CLLocationCoordinate2D(latitude: center.latitude - radiusDegrees, longitude: center.longitude - radiusDegrees)
                            ]
                        }
                    }
                    ZStack(alignment: .top) {
                        MapReader { reader in
                            ZStack {
                                MapGestureConfigurator(isEnabled: isPolygonMode) { touchLoc, state in
                                    guard isPolygonMode else { return }
                                    
                                    if polygonActionMode == 0 { // Move Points
                                        if state == .began {
                                            isDraggingPoint = true
                                            var closestIdx: Int?
                                            var minDistance: CGFloat = 44.0
                                            for (idx, pt) in polygonPoints.enumerated() {
                                                let mapCoord = CoordinateConverter.forMapDisplay(pt)
                                                if let ptScreen = reader.convert(mapCoord, to: .local) {
                                                    let dx = ptScreen.x - touchLoc.x
                                                    let dy = ptScreen.y - touchLoc.y
                                                    let dist = sqrt(dx*dx + dy*dy)
                                                    if dist < minDistance {
                                                        minDistance = dist
                                                        closestIdx = idx
                                                    }
                                                }
                                            }
                                            if let closestIdx = closestIdx {
                                                selectedPointIndex = closestIdx
                                                polygonHistory.push(currentState: polygonPoints)
                                            }
                                        }
                                        
                                        if state == .began || state == .changed {
                                            if let idx = selectedPointIndex, let mapCoordinate = reader.convert(touchLoc, from: .local) {
                                                let coordinate = CoordinateConverter.fromMapDisplay(mapCoordinate)
                                                polygonPoints[idx] = coordinate
                                                updatePolygonCenter()
                                            }
                                        } else if state == .ended || state == .cancelled || state == .failed {
                                            isDraggingPoint = false
                                        }
                                        
                                    } else if polygonActionMode == 1 { // Draw Shape
                                        if state == .began {
                                            drawingPoints = []
                                            if let mapCoordinate = reader.convert(touchLoc, from: .local) {
                                                drawingPoints.append(CoordinateConverter.fromMapDisplay(mapCoordinate))
                                            }
                                        } else if state == .changed {
                                            if let mapCoordinate = reader.convert(touchLoc, from: .local) {
                                                let newPoint = CoordinateConverter.fromMapDisplay(mapCoordinate)
                                                if let lastPoint = drawingPoints.last {
                                                    let latDiff = abs(lastPoint.latitude - newPoint.latitude)
                                                    let lonDiff = abs(lastPoint.longitude - newPoint.longitude)
                                                    if latDiff > 0.00005 || lonDiff > 0.00005 {
                                                        drawingPoints.append(newPoint)
                                                    }
                                                } else {
                                                    drawingPoints.append(newPoint)
                                                }
                                            }
                                        } else if state == .ended || state == .cancelled || state == .failed {
                                            if drawingPoints.count > 2 {
                                                polygonHistory.push(currentState: polygonPoints)
                                                let newPoly = CoordinateConverter.simplifyPolygon(points: drawingPoints, maxPoints: 20)
                                                polygonPoints = newPoly
                                                updatePolygonCenter()
                                                selectedPointIndex = nil
                                            }
                                            drawingPoints = []
                                        }
                                    }
                                }
                                
                                Map(position: $cameraPosition, interactionModes: .all.subtracting(.pitch)) {
                                    Annotation(editablePlace.name, coordinate: CoordinateConverter.forMapDisplay(center)) {
                                        Circle()
                                            .fill(isPolygonMode ? Color.gray : Color.red)
                                            .frame(width: 10, height: 10)
                                    }
                                    if isPolygonMode {
                                        if !polygonPoints.isEmpty {
                                            let displayPoints = polygonPoints.map { CoordinateConverter.forMapDisplay($0) }
                                            MapPolygon(coordinates: displayPoints)
                                                .stroke(Color.blue.opacity(0.8), lineWidth: 2)
                                                .foregroundStyle(Color.orange.opacity(0.3))
                                            
                                            ForEach(Array(displayPoints.enumerated()), id: \.offset) { index, point in
                                                Annotation("", coordinate: point) {
                                                    Circle()
                                                        .fill(selectedPointIndex == index ? Color.green : Color.white)
                                                        .stroke(Color.black, lineWidth: 2)
                                                        .frame(width: 16, height: 16)
                                                }
                                            }
                                        }
                                        
                                        if !drawingPoints.isEmpty {
                                            let drawDisplayPoints = drawingPoints.map { CoordinateConverter.forMapDisplay($0) }
                                            MapPolyline(coordinates: drawDisplayPoints)
                                                .stroke(Color.red, lineWidth: 4)
                                        }
                                    } else {
                                        MapCircle(center: CoordinateConverter.forMapDisplay(center), radius: Double(radius))
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                                            .foregroundStyle(Color.orange.opacity(0.5))
                                    }
                                }
                                .onTapGesture { screenCoord in
                                    if !isPolygonMode {
                                        if let mapCoordinate = reader.convert(screenCoord, from: .local) {
                                            let coordinate = CoordinateConverter.fromMapDisplay(mapCoordinate)
                                            center = coordinate
                                            latitudeString = String(format: "%.6f", coordinate.latitude)
                                            longitudeString = String(format: "%.6f", coordinate.longitude)
                                        }
                                    }
                                }
                            }
                        }
                        
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 10) {
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
                                                    center: CoordinateConverter.forMapDisplay(center),
                                                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                                                )
                                                cameraPosition = .region(currentRegion)
                                            }
                                        }
                                    
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
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .allowsHitTesting(true)
                    }
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    
                    if isPolygonMode {
                        VStack(spacing: 8) {
                            Picker("Polygon Action", selection: $polygonActionMode) {
                                Text("Move Points").tag(0)
                                Text("Draw Shape").tag(1)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle")
                                Text("To move the map, use two finger gestures")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                        }
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                if let idx = selectedPointIndex {
                                    polygonHistory.push(currentState: polygonPoints)
                                    polygonPoints.remove(at: idx)
                                    selectedPointIndex = nil
                                    updatePolygonCenter()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "minus.circle.fill")
                                    Text("Remove")
                                }
                                .foregroundColor(selectedPointIndex != nil && polygonPoints.count > 3 && polygonActionMode == 0 ? .red : .gray)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(selectedPointIndex == nil || polygonPoints.count <= 3 || polygonActionMode != 0)
                            
                            Button(action: {
                                polygonHistory.push(currentState: polygonPoints)
                                let idx1 = selectedPointIndex ?? 0
                                let idx2 = (idx1 + 1) % polygonPoints.count
                                let p1 = polygonPoints[idx1]
                                let p2 = polygonPoints[idx2]
                                let newPoint = CLLocationCoordinate2D(
                                    latitude: (p1.latitude + p2.latitude) / 2.0,
                                    longitude: (p1.longitude + p2.longitude) / 2.0
                                )
                                polygonPoints.insert(newPoint, at: idx1 + 1)
                                selectedPointIndex = idx1 + 1
                                updatePolygonCenter()
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add")
                                }
                                .foregroundColor(polygonPoints.count < 20 && polygonActionMode == 0 ? .blue : .gray)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(polygonPoints.count >= 20 || polygonActionMode != 0)
                            
                            Spacer()
                            
                            Button(action: {
                                if let previous = polygonHistory.undo(currentState: polygonPoints) {
                                    polygonPoints = previous
                                    selectedPointIndex = nil
                                    updatePolygonCenter()
                                }
                            }) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(!polygonHistory.canUndo)
                            .foregroundColor(polygonHistory.canUndo ? .blue : .gray)
                            
                            Button(action: {
                                if let next = polygonHistory.redo(currentState: polygonPoints) {
                                    polygonPoints = next
                                    selectedPointIndex = nil
                                    updatePolygonCenter()
                                }
                            }) {
                                Image(systemName: "arrow.uturn.forward.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(!polygonHistory.canRedo)
                            .foregroundColor(polygonHistory.canRedo ? .blue : .gray)
                        }
                    }
                }
                

                Section(header: Text("Basic Details")) {
                    TextField("Name", text: $name)
                    
                    TextField("Latitude", text: $latitudeString)
                        .keyboardType(.decimalPad)
                        .disabled(isPolygonMode)
                        .onChange(of: latitudeString) { _, newValue in
                            if !isPolygonMode, let lat = Double(newValue), lat >= -90, lat <= 90 {
                                center = CLLocationCoordinate2D(
                                    latitude: lat,
                                    longitude: center.longitude
                                )
                            }
                        }
                    
                    TextField("Longitude", text: $longitudeString)
                        .keyboardType(.decimalPad)
                        .disabled(isPolygonMode)
                        .onChange(of: longitudeString) { _, newValue in
                            if !isPolygonMode, let lon = Double(newValue), lon >= -180, lon <= 180 {
                                center = CLLocationCoordinate2D(
                                    latitude: center.latitude,
                                    longitude: lon
                                )
                            }
                        }
                    
                    TextField("Elevation (meters)", text: $elevationString)
                        .keyboardType(.decimalPad)
                    
                    VStack {
                        Text("Radius: \(radius) meters")
                        Slider(
                            value: Binding(
                                get: { logSliderValue(from: radius) },
                                set: { radius = radiusFromLogSlider($0) }
                            ),
                            in: 0...1
                        )
                        .disabled(isPolygonMode)
                    }
                    if isPolygonMode {
                        Text("Location and radius are automatically calculated from the polygon.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if isFromEditVisit && (isNewPlace || originalPlace.placeId == "-1") {
                    Section {
                        Toggle(isOn: $isOneTimeVisit) {
                            VStack(alignment: .leading) {
                                Text("One-time Visit")
                                Text("Use this for non-recurring visits or brief stops")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Address")) {
                    HStack {
                        TextField("Street Address", text: $streetAddress)
                        
                        Button(action: {
                            performReverseLookup()
                        }) {
                            if isLookingUpAddress {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(isLookingUpAddress)
                    }
                }
                
                Section(header: Text("Icon")) {
                    HStack {
                        PlaceIconView(icon: customIcon.isEmpty ? nil : customIcon, font: .title2)
                        Spacer()
                        Button("Choose Icon") {
                            showingIconPicker = true
                        }
                    }
                }
                
                Section(header: Text("Last Visited")) {
                    DatePicker(
                        "Last Visited",
                        selection: $lastVisited,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                
                Section(header: Text("External IDs")) {
                    HStack {
                        Image(systemName: "magnifyingglass.circle.fill")
                        Text("Find Place IDs")
                    }
                    .foregroundColor(.purple)
                    .onTapGesture {
                        showingPlaceSearch = true
                    }

                    VStack(alignment: .leading) {
                        Text("Google Places ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Google Places ID", text: $googlePlacesId)
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

                    VStack(alignment: .leading) {
                        Text("Yelp ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Yelp ID", text: $yelpId)
                    }

                    VStack(alignment: .leading) {
                        Text("Mapbox Place ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Mapbox Place ID", text: $mapboxPlaceId)
                    }

                    VStack(alignment: .leading) {
                        Text("Apple Place ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Apple Place ID", text: $applePlaceId)
                    }

                    VStack(alignment: .leading) {
                        Text("OpenStreetMap ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter OSM ID (e.g. node/12345)", text: $osmNodeId)
                    }

                    VStack(alignment: .leading) {
                        Text("HERE Place ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter HERE Place ID", text: $herePlaceId)
                    }

                    VStack(alignment: .leading) {
                        Text("Gaode Place ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Gaode Place ID", text: $gaodePlaceId)
                    }
                }
                
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
                
                if !isNewPlace {
                    Section {
                        Toggle("Active Place", isOn: $isActive)
                            .tint(.blue)

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
            .scrollContentBackground(isActive ? .visible : .hidden)
            .background(isActive ? Color.clear : Color.blue.opacity(0.2))
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
            .alert(
                "Are you sure you want to delete this place?",
                isPresented: $showingDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    deletePlace()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $customIcon)
            }
            .sheet(isPresented: $showingPlaceSearch) {
                NavigationView {
                    PlaceSearchView(
                        coordinate: center,
                        selectedIds: selectedPlaceSearchIds,
                        onSelect: { result in
                            let hadNoPlaceId = selectedPlaceSearchIds.isEmpty
                            switch result.provider {
                            case .google:
                                googlePlacesId = result.id
                            case .foursquare:
                                foursquareVenueId = result.id
                                if let catId = result.foursquareCategoryId {
                                    foursquareCategoryId = catId
                                }
                            case .yelp:
                                yelpId = result.id
                            case .mapbox:
                                mapboxPlaceId = result.id
                            case .apple:
                                applePlaceId = result.id
                            case .openStreetMap:
                                osmNodeId = result.id
                            case .here:
                                herePlaceId = result.id
                            case .gaode:
                                gaodePlaceId = result.id
                            }
                            if name.isEmpty {
                                name = result.name
                            }
                            if let addr = result.address, !addr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                                if streetAddress.isEmpty {
                                    streetAddress = addr
                                } else if isNewPlace && hadNoPlaceId && SettingsManager.shared.overwriteExistingAddressOnNewPlaceCreation {
                                    streetAddress = addr
                                }
                            }
                            if customIcon.isEmpty, let icon = result.resolvedIcon {
                                customIcon = icon
                            }
                        },
                        onDone: {
                            showingPlaceSearch = false
                        },
                        onUnselect: { result in
                            switch result.provider {
                            case .google:
                                googlePlacesId = ""
                            case .foursquare:
                                foursquareVenueId = ""
                                foursquareCategoryId = ""
                            case .yelp:
                                yelpId = ""
                            case .mapbox:
                                mapboxPlaceId = ""
                            case .apple:
                                applePlaceId = ""
                            case .openStreetMap:
                                osmNodeId = ""
                            case .here:
                                herePlaceId = ""
                            case .gaode:
                                gaodePlaceId = ""
                            }
                        }
                    )
                    .navigationTitle("Find Place IDs")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private func performReverseLookup(completion: (() -> Void)? = nil) {
        guard let lat = Double(latitudeString.trim()), let lon = Double(longitudeString.trim()) else {
            completion?()
            return
        }
        isLookingUpAddress = true
        Task {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let address = await AddressLookupService.reverseGeocode(coordinate: coord)
            await MainActor.run {
                if let address = address {
                    streetAddress = address
                }
                isLookingUpAddress = false
                completion?()
            }
        }
    }

    private func savePlace() {
        if streetAddress.trim().isEmpty && SettingsManager.shared.autoReverseLookupUnknownVisits {
            performReverseLookup {
                self.completeSavePlace()
            }
            return
        }
        completeSavePlace()
    }

    private func completeSavePlace() {
        var finalPlaceId = editedPlaceId.trim()
        if isOneTimeVisit {
            finalPlaceId = "-1"
        } else if finalPlaceId == "-1" {
            // Toggled from one-time to permanent: generate a new ID
            finalPlaceId = UUID().uuidString
        }
        
        let updatedPlace = Place(
            placeId: finalPlaceId,
            name: name.trim(),
            center: Center(latitude: Double(latitudeString.trim()) ?? 0,
                          longitude: Double(longitudeString.trim()) ?? 0),
            radius: Double(radius),
            streetAddress: streetAddress.isEmpty ? nil : streetAddress.trim(),
            secondsFromGMT: editablePlace.secondsFromGMT,
            lastSaved: editablePlace.lastSaved,
            facebookPlaceId: facebookPlaceId.isEmpty ? nil : facebookPlaceId.trim(),
            mapboxPlaceId: mapboxPlaceId.isEmpty ? nil : mapboxPlaceId.trim(),
            foursquareVenueId: foursquareVenueId.isEmpty ? nil : foursquareVenueId.trim(),
            foursquareCategoryId: foursquareCategoryId.isEmpty ? nil : foursquareCategoryId.trim(),
            googlePlacesId: googlePlacesId.isEmpty ? nil : googlePlacesId.trim(),
            yelpId: yelpId.isEmpty ? nil : yelpId.trim(),
            applePlaceId: applePlaceId.isEmpty ? nil : applePlaceId.trim(),
            osmNodeId: osmNodeId.isEmpty ? nil : osmNodeId.trim(),
            herePlaceId: herePlaceId.isEmpty ? nil : herePlaceId.trim(),
            gaodePlaceId: gaodePlaceId.isEmpty ? nil : gaodePlaceId.trim(),
            previousIds: editablePlace.previousIds,
            lastVisited: editablePlace.lastVisited,
            isFavorite: isFavorite ? true : nil,
            customIcon: customIcon.isEmpty ? nil : customIcon.trim(),
            elevation: Double(elevationString.trim()),
            perimeterPolygonPoints: isPolygonMode ? polygonPoints.map { Center(latitude: $0.latitude, longitude: $0.longitude) } : nil,
            isActive: isActive
        )
        
        do {
            if isOneTimeVisit {
                onSave?(updatedPlace)
            } else if originalPlace.placeId == "-1" {
                // Toggled from one-time to permanent: add it to the database
                try PlaceManager.shared.addPlace(updatedPlace)
                onSave?(updatedPlace)
            } else if isNewPlace {
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

    private func deletePlace() {
        do {
            try PlaceManager.shared.deletePlace(originalPlace)
            onDelete?()
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = "Failed to delete place: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct EditPlaceView_Previews: PreviewProvider {
    static var previews: some View {
        let previewPlaceWithElevation = Place(
            placeId: "preview1", name: "Preview Place",
            center: Center(latitude: 40.0, longitude: -74.0), radius: 100,
            streetAddress: "123 Preview St", secondsFromGMT: -18000, lastSaved: nil,
            facebookPlaceId: nil, mapboxPlaceId: nil, foursquareVenueId: nil,
            foursquareCategoryId: nil, previousIds: nil, lastVisited: Date(),
            isFavorite: true, customIcon: "star.fill", elevation: 15.5
        )
        EditPlaceView(place: previewPlaceWithElevation)
    }
}
