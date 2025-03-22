import SwiftUI
import CoreLocation

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (Place?) -> Void
    
    @State private var selectedPlace: Place?
    @State private var nearbyPlaces: [Place] = []
    @State private var searchText: String = ""
    @State private var showingNewPlaceSheet = false
    
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
                Section {
                    TextField("Search places", text: $searchText)
                }
                
                Section(searchText.isEmpty ? "Nearby Places" : "Search Results") {
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
                
                Section {
                    Button(action: {
                        showingNewPlaceSheet = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add New Place")
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
        }
        .onAppear {
            if let firstPoint = timelineObject.points.first {
                let coordinate = CLLocationCoordinate2D(
                    latitude: firstPoint.latitude ?? 0,
                    longitude: firstPoint.longitude ?? 0
                )
                nearbyPlaces = PlaceManager.shared.findClosePlaces(to: coordinate)
            }
        }
    }
} 