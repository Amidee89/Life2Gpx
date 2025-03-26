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
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var latitudeString: String = ""
    @State private var longitudeString: String = ""
    
    init(timelineObject: TimelineObject, onSave: @escaping (Place?) -> Void) {
        self.timelineObject = timelineObject
        self.onSave = onSave
        _startDate = State(initialValue: timelineObject.startDate ?? Date())
        _endDate = State(initialValue: timelineObject.endDate ?? Date())
        _latitudeString = State(initialValue: String(format: "%.6f", 
            timelineObject.points.first?.latitude ?? 0))
        _longitudeString = State(initialValue: String(format: "%.6f", 
            timelineObject.points.first?.longitude ?? 0))
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
        
        // Sort by selection first, then distance and take first 10
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
                    Section("Current Visit") {
                        ZStack(alignment: .bottomTrailing) {
                            MapReader { reader in
                                Map(position: .constant(.region(region))) {
                                    if let coordinate = currentCoordinate {
                                        // Current visit location
                                        Annotation("Current Location", coordinate: coordinate) {
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
                                        // Selected place
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
                                        // Update the first point's coordinates
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

                            // Map Control Button
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

                        // Coordinate fields with proper labels
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Latitude")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Latitude", text: $latitudeString)
                                    .keyboardType(.decimalPad)
                                    .onChange(of: latitudeString) { newValue in
                                        if let lat = Double(newValue), lat >= -90, lat <= 90,
                                           let firstPoint = timelineObject.points.first {
                                            firstPoint.latitude = lat
                                        }
                                    }
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Longitude")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Longitude", text: $longitudeString)
                                    .keyboardType(.decimalPad)
                                    .onChange(of: longitudeString) { newValue in
                                        if let lon = Double(newValue), lon >= -180, lon <= 180,
                                           let firstPoint = timelineObject.points.first {
                                            firstPoint.longitude = lon
                                        }
                                    }
                            }
                        }

                        // Selected place information with edit button
                        if let place = selectedPlace {
                            HStack {
                                // Place icon
                                Image(systemName: place.customIcon ?? "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                
                                // Place details
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
                                
                                // Edit button
                                Button(action: {
                                    showingEditPlaceSheet = true
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Clear place data button
                        Button(role: .destructive) {
                            selectedPlace = nil
                        } label: {
                            HStack {
                                Spacer()
                                Text("Clear Place Data")
                                Spacer()
                            }
                        }
                    }
                    
                    Section("Visit Time") {
                        DatePicker("", 
                                 selection: $startDate,
                                 displayedComponents: [.date, .hourAndMinute])
                            .font(.subheadline)
                    }

                    Section("Change Place") {
                        Button(action: {
                            showingNewPlaceSheet = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add New Place")
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
                    // Update the timeline object's dates
                    timelineObject.startDate = startDate
                    timelineObject.endDate = endDate
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
