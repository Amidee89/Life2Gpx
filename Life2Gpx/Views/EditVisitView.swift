import SwiftUI
import CoreLocation
import MapKit
import CoreGPX

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (Place?) -> Void
    
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
    
    // Add these properties to store original values
    private var originalLatitude: Double?
    private var originalLongitude: Double?
    private var originalElevation: Double?
    private var originalTime: Date?
    
    init(timelineObject: TimelineObject, onSave: @escaping (Place?) -> Void) {
        self.timelineObject = timelineObject
        self.onSave = onSave
        
        // Store the original waypoint values
        if let firstPoint = timelineObject.points.first {
            self.originalLatitude = firstPoint.latitude
            self.originalLongitude = firstPoint.longitude
            self.originalElevation = firstPoint.elevation
            self.originalTime = firstPoint.time
        }
        
        _visitDate = State(initialValue: timelineObject.startDate ?? Date())
        _latitudeString = State(initialValue: String(format: "%.6f", timelineObject.points.first?.latitude ?? 0))
        _longitudeString = State(initialValue: String(format: "%.6f", timelineObject.points.first?.longitude ?? 0))
        _elevationString = State(initialValue: String(format: "%.1f", timelineObject.points.first?.elevation ?? 0))
        _stepsString = State(initialValue: String(timelineObject.steps))
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        guard let firstPoint = timelineObject.points.first else { return nil }
        return CLLocationCoordinate2D(
            latitude: firstPoint.latitude ?? 0,
            longitude: firstPoint.longitude ?? 0
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
            List {
                if let coordinate = currentCoordinate {
                    Section("Visit Details") {
                        DatePicker("Visit time", 
                                 selection: $visitDate,
                                 displayedComponents: [.date, .hourAndMinute])
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Latitude")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Latitude", text: $latitudeString)
                                    .keyboardType(.decimalPad)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Longitude")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Longitude", text: $longitudeString)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Elevation (m)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Elevation", text: $elevationString)
                                    .keyboardType(.decimalPad)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Steps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Steps", text: $stepsString)
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                    
                    Section("Place Details") {
                        ZStack(alignment: .bottomTrailing) {
                            MapReader { reader in
                                Map(position: .constant(.region(region))) {
                                    if let coordinate = currentCoordinate {
                                        Annotation("Visit Location", coordinate: coordinate) {
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
                                        Annotation(place.name, coordinate: place.centerCoordinate) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.white)
                                                Circle()
                                                    .fill(Color.orange)
                                                    .padding(4)
                                            }
                                            .frame(width: 24, height: 24)
                                        }
                                        
                                        MapCircle(center: place.centerCoordinate, radius: place.radius)
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                                            .foregroundStyle(Color.orange.opacity(0.5))
                                    }
                                }
                                .onTapGesture { screenCoord in
                                    if let coordinate = reader.convert(screenCoord, from: .local) {
                                        if let firstPoint = timelineObject.points.first {
                                            firstPoint.latitude = coordinate.latitude
                                            firstPoint.longitude = coordinate.longitude
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
                                            center: currentCoordinate ?? CLLocationCoordinate2D(),
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                        )
                                    }
                                }
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                        }

                    
                        if let place = selectedPlace {
                            HStack {
                                Image(systemName: place.customIcon ?? "smallcircle.filled.circle")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                
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
                                
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Section("Change Place") {
                        HStack {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add New Place")
                            }
                            .foregroundColor(.blue)
                            .onTapGesture {
                                showingNewPlaceSheet = true
                            }
                            
                            Spacer()
                            
                            if selectedPlace != nil {
                                Text("Clear Place")
                                    .foregroundColor(.red)
                                    .onTapGesture {
                                        selectedPlace = nil
                                    }
                            }
                        }

                        TextField("Search places", text: $searchText)
                        
                        ForEach(filteredPlaces) { place in
                            Button(action: {
                                selectedPlace = place
                            }) {
                                HStack {
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
                }
            }
            .navigationTitle("Edit Visit")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    // Update the timeline object's date
                    timelineObject.startDate = visitDate
                    
                    // Update the waypoint coordinates and elevation from the text fields
                    if let firstPoint = timelineObject.points.first, let date = timelineObject.startDate {
                        // Create a new waypoint with the original values
                        let originalWaypoint = GPXWaypoint(latitude: originalLatitude ?? 0, 
                                                          longitude: originalLongitude ?? 0)
                        originalWaypoint.time = originalTime
                        originalWaypoint.elevation = originalElevation
                        
                        // Create an updated waypoint with the new data
                        let updatedWaypoint = GPXWaypoint(latitude: Double(latitudeString) ?? 0, 
                                                         longitude: Double(longitudeString) ?? 0)
                        updatedWaypoint.time = visitDate
                        updatedWaypoint.elevation = Double(elevationString) ?? 0
                        
                        // Add steps if they're not zero
                        if let steps = Int(stepsString), steps > 0 {
                            if updatedWaypoint.extensions == nil {
                                updatedWaypoint.extensions = GPXExtensions()
                            }
                            updatedWaypoint.extensions?.append(at: nil, contents: ["Steps": stepsString])
                        }
                        
                        // Update the waypoint with place data if a place is selected
                        let finalWaypoint = selectedPlace != nil ? 
                            GPXManager.shared.updateWaypointMetadataFromPlace(updatedWaypoint: updatedWaypoint, place: selectedPlace!) : 
                            updatedWaypoint
                        
                        // Save the changes using the existing GPXManager method
                        GPXManager.shared.updateWaypoint(originalWaypoint: originalWaypoint, updatedWaypoint: finalWaypoint, forDate: date)
                    }
                    
                    onSave(selectedPlace)
                    dismiss()
                }
            )
            .sheet(isPresented: $showingNewPlaceSheet) {
                if let coordinate = currentCoordinate {
                    EditPlaceView(
                        place: Place(
                            placeId: UUID().uuidString,
                            name: "",
                            center: Center(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            ),
                            radius: 40,
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
                            customIcon: nil
                        ),
                        isNewPlace: true,
                        isFromEditVisit: true,
                        onSave: { newPlace in
                            onSave(newPlace)
                            dismiss()
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
        }
        .onAppear {
            if let coordinate = currentCoordinate {
                region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                
                nearbyPlaces = PlaceManager.shared.findClosePlaces(to: coordinate)
                
                if let visitName = timelineObject.name {
                    selectedPlace = nearbyPlaces.first { $0.name == visitName }
                }
            }
        }
        .onChange(of: selectedPlace) { newPlace in
            if let place = newPlace, let coordinate = currentCoordinate {
                let radiusInDegrees = (place.radius * 2.2) / 111000.0
                let minimumSpan = 0.005 
                
                let latDelta = max(
                    abs(coordinate.latitude - place.centerCoordinate.latitude) * 2.2,
                    radiusInDegrees,
                    minimumSpan
                )
                let lonDelta = max(
                    abs(coordinate.longitude - place.centerCoordinate.longitude) * 2.2,
                    radiusInDegrees,
                    minimumSpan
                )
                
                let center = CLLocationCoordinate2D(
                    latitude: (coordinate.latitude + place.centerCoordinate.latitude) / 2,
                    longitude: (coordinate.longitude + place.centerCoordinate.longitude) / 2
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
                onSave: { _ in }
            )
        }
    }
} 
