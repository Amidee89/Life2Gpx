import SwiftUI
import CoreLocation

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (Place?) -> Void
    
    @State private var selectedPlace: Place?
    @State private var placeName: String = ""
    @State private var nearbyPlaces: [Place] = []
    @State private var searchText: String = ""
    
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
        
        // Sort by distance and take first 10
        return filtered
            .sorted { coordinate.distance(to: $0.centerCoordinate) < coordinate.distance(to: $1.centerCoordinate) }
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
                            placeName = place.name
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
                    }
                }
                
                Section("Custom Name") {
                    TextField("Place name", text: $placeName)
                }
            }
            .navigationTitle("Edit Visit")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    if selectedPlace == nil {
                        let customPlace = Place(
                            placeId: UUID().uuidString,
                            name: placeName,
                            center: Center(
                                latitude: timelineObject.points.first?.latitude ?? 0,
                                longitude: timelineObject.points.first?.longitude ?? 0
                            ),
                            radius: 50,
                            streetAddress: nil,
                            secondsFromGMT: nil,
                            lastSaved: nil,
                            facebookPlaceId: nil,
                            mapboxPlaceId: nil,
                            foursquareVenueId: nil,
                            foursquareCategoryId: nil,
                            previousIds: nil,
                            lastVisited: Date(),
                            isFavorite: nil,
                            customIcon: nil
                        )
                        onSave(customPlace)
                    } else {
                        onSave(selectedPlace)
                    }
                    dismiss()
                }
            )
        }
        .onAppear {
            placeName = timelineObject.name ?? ""
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