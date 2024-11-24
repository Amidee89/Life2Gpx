import SwiftUI
import MapKit

struct EditPlaceView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var place: Place
    @State private var name: String
    @State private var streetAddress: String
    @State private var radius: Int
    @State private var center: CLLocationCoordinate2D
    @State private var cameraPosition: MapCameraPosition
    
    // Add new state variables for additional fields
    @State private var facebookPlaceId: String
    @State private var mapboxPlaceId: String
    @State private var foursquareVenueId: String
    @State private var foursquareCategoryId: String
    
    init(place: Place) {
        _place = State(initialValue: place)
        _name = State(initialValue: place.name)
        _streetAddress = State(initialValue: place.streetAddress ?? "")
        _radius = State(initialValue: Int(place.radius))
        _center = State(initialValue: place.centerCoordinate)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: place.centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
        
        // Initialize additional fields
        _facebookPlaceId = State(initialValue: place.facebookPlaceId ?? "")
        _mapboxPlaceId = State(initialValue: place.mapboxPlaceId ?? "")
        _foursquareVenueId = State(initialValue: place.foursquareVenueId ?? "")
        _foursquareCategoryId = State(initialValue: place.foursquareCategoryId ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                // Map Section
                Section {
                    Map(position: $cameraPosition, interactionModes: .all) {
                        Annotation("Center", coordinate: center) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                        }
                        MapCircle(center: center, radius: Double(radius))
                            .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                            .foregroundStyle(Color.orange.opacity(0.5))
                    }
                    .frame(height: 300)
                    
                    Button("Center Map") {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: center,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
                
                // Basic Details Section
                Section(header: Text("Basic Details")) {
                    TextField("Name", text: $name)
                    HStack {
                        Text("Latitude: \(center.latitude, specifier: "%.6f")")
                        Spacer()
                        Text("Longitude: \(center.longitude, specifier: "%.6f")")
                    }
                    Stepper(value: $radius, in: 0...2000, step: 10) {
                        Text("Radius: \(radius) meters")
                    }
                }
                
                // Address Section
                Section(header: Text("Address")) {
                    TextField("Street Address", text: $streetAddress)
                }
                
                // External IDs Section
                Section(header: Text("External IDs")) {
                    TextField("Facebook Place ID", text: $facebookPlaceId)
                    TextField("Mapbox Place ID", text: $mapboxPlaceId)
                    TextField("Foursquare Venue ID", text: $foursquareVenueId)
                    TextField("Foursquare Category ID", text: $foursquareCategoryId)
                }
            }
            .navigationTitle("Edit Place")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePlace()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
