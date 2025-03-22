import SwiftUI
import CoreLocation

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (String) -> Void
    
    @State private var placeName: String = ""
    @State private var nearbyPlaces: [Place] = []
    @State private var searchText: String = ""
    
    private var filteredPlaces: [Place] {
        if searchText.isEmpty {
            return nearbyPlaces
        }
        return nearbyPlaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("Search places", text: $searchText)
                }
                
                Section("Nearby Places") {
                    ForEach(filteredPlaces) { place in
                        Button(action: {
                            placeName = place.name
                        }) {
                            VStack(alignment: .leading) {
                                Text(place.name)
                                    .foregroundColor(.primary)
                                if let address = place.streetAddress {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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
                    onSave(placeName)
                    dismiss()
                }
            )
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