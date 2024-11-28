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
        center: CLLocationCoordinate2D(),  // This will be set in init
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    // Add new state variables for additional fields
    @State private var facebookPlaceId: String
    @State private var mapboxPlaceId: String
    @State private var foursquareVenueId: String
    @State private var foursquareCategoryId: String
    
    // Add separate state variables for lat/lon input
    @State private var latitudeString: String
    @State private var longitudeString: String
    
    // Add new state variable
    @State private var newPreviousId: String = ""
    
    init(place: Place) {
        _editablePlace = State(initialValue: Place.EditableCopy(from: place))
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
                
                // Identifiers Section
                Section(header: Text("Identifiers")) {
                    HStack {
                        Text("Place ID")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(editablePlace.placeId)
                    }
                    
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
            }
            .navigationTitle("Edit Place")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Convert editablePlace back to Place and pass to save handler
                        let updatedPlace = editablePlace.toPlace()
                        // Add your save logic here using updatedPlace
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func savePlace() {
        print("Saved Place: \(name), \(streetAddress), \(radius), \(center)")
        // Placeholder for save logic
    }
}

struct EditPlaceView_Previews: PreviewProvider {
    static var previews: some View {
        EditPlaceView(place: Place(placeId: "1", name: "Central Park", center: Center(latitude: 40.785091, longitude: -73.968285), radius: 200, streetAddress: "New York, NY", secondsFromGMT: -18000, lastSaved: "2024-10-18", facebookPlaceId: nil, mapboxPlaceId: nil, foursquareVenueId: nil, foursquareCategoryId: nil, previousIds: [nil]))
    }
}
