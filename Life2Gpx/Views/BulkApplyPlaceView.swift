import SwiftUI
import MapKit

struct BulkApplyContext: Identifiable {
    let id = UUID()
    let place: Place
    let originalObject: TimelineObject
    let matchingObjects: [TimelineObject]
}

struct BulkApplyPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    
    let context: BulkApplyContext
    let onApply: ([TimelineObject]) -> Void
    
    @State private var selectedIds: Set<UUID>
    @State private var region: MKCoordinateRegion
    
    init(context: BulkApplyContext, onApply: @escaping ([TimelineObject]) -> Void) {
        self.context = context
        self.onApply = onApply
        
        // Default select all
        self._selectedIds = State(initialValue: Set(context.matchingObjects.map { $0.id }))
        
        // Initial region centered on the place
        let center = CoordinateConverter.forMapDisplay(context.place.centerCoordinate)
        
        // Calculate an appropriate span based on the items
        var maxLatDelta: CLLocationDegrees = 0.005
        var maxLonDelta: CLLocationDegrees = 0.005
        
        for object in context.matchingObjects {
            if let coord = object.identifiableCoordinates.first?.coordinates.first {
                let displayCoord = CoordinateConverter.forMapDisplay(coord)
                let latDelta = abs(displayCoord.latitude - center.latitude) * 2.2
                let lonDelta = abs(displayCoord.longitude - center.longitude) * 2.2
                maxLatDelta = max(maxLatDelta, latDelta)
                maxLonDelta = max(maxLonDelta, lonDelta)
            }
        }
        
        self._region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: maxLatDelta, longitudeDelta: maxLonDelta)
        ))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("The following unknown visits in this day also match this place:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                // Map View
                Map(position: .constant(.region(region))) {
                    let placeDisplayCoord = CoordinateConverter.forMapDisplay(context.place.centerCoordinate)
                    
                    // The main place
                    Annotation(context.place.name, coordinate: placeDisplayCoord) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                            Circle()
                                .fill(Color.orange)
                                .padding(4)
                        }
                        .frame(width: 24, height: 24)
                    }
                    
                    MapCircle(center: placeDisplayCoord, radius: context.place.radius)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                        .foregroundStyle(Color.orange.opacity(0.3))
                    
                    // The matching items
                    ForEach(context.matchingObjects) { object in
                        if let coord = object.identifiableCoordinates.first?.coordinates.first {
                            let isSelected = selectedIds.contains(object.id)
                            Annotation("", coordinate: CoordinateConverter.forMapDisplay(coord)) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(isSelected ? Color.blue : Color.gray)
                                        .padding(4)
                                }
                                .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Scrollable List
                List {
                    ForEach(context.matchingObjects) { object in
                        Button(action: {
                            toggleSelection(for: object.id)
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    if let startDate = object.startDate {
                                        Text(formatTime(startDate))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    if !object.duration.isEmpty {
                                        Text(object.duration)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Selection Circle
                                Image(systemName: selectedIds.contains(object.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedIds.contains(object.id) ? .blue : .gray)
                                    .font(.title2)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
                // Bottom Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        let selectedObjects = context.matchingObjects.filter { selectedIds.contains($0.id) }
                        onApply(selectedObjects)
                        dismiss()
                    }) {
                        Text("Apply place to selected items")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedIds.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                    }
                    .disabled(selectedIds.isEmpty)
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Do not apply")
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Apply to other visits?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func toggleSelection(for id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
