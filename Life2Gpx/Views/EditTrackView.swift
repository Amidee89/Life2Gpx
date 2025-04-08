import SwiftUI
import MapKit
import CoreGPX

struct EditTrackView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    let fileDate: Date
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedTrackType: String
    
    init(timelineObject: TimelineObject, fileDate: Date) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        _selectedTrackType = State(initialValue: timelineObject.trackType ?? "unknown")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Track Details") {
                    Picker("Track Type", selection: $selectedTrackType) {
                        Text("Walking").tag("walking")
                        Text("Running").tag("running")
                        Text("Cycling").tag("cycling")
                        Text("Automotive").tag("automotive")
                        Text("Unknown").tag("unknown")
                    }
                    
                    if let track = timelineObject.track {
                        Text("Segments: \(track.segments.count)")
                        Text("Total Points: \(timelineObject.numberOfPoints)")
                        if timelineObject.steps > 0 {
                            Text("Steps: \(timelineObject.steps)")
                        }
                        if timelineObject.meters > 0 {
                            Text("Distance: \(String(format: "%.1f km", Double(timelineObject.meters) / 1000))")
                        }
                        if timelineObject.averageSpeed > 0 {
                            Text("Average Speed: \(String(format: "%.1f km/h", timelineObject.averageSpeed))")
                        }
                    }
                }
                
                Section("Track Map") {
                    Map(position: $cameraPosition) {
                        ForEach(timelineObject.identifiableCoordinates, id: \.id) { identifiableCoordinates in
                            MapPolyline(coordinates: identifiableCoordinates.coordinates)
                                .stroke(.white,
                                       style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                            MapPolyline(coordinates: identifiableCoordinates.coordinates)
                                .stroke(.black,
                                       style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                            MapPolyline(coordinates: identifiableCoordinates.coordinates)
                                .stroke(trackTypeColorMapping[selectedTrackType] ?? .purple,
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .navigationTitle("Edit Track")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    // We'll implement the save functionality later
                    dismiss()
                }
            )
            .onAppear {
                let coordinates = timelineObject.identifiableCoordinates.flatMap { $0.coordinates }
                if !coordinates.isEmpty {
                    let span = calculateSpan(for: coordinates)
                    let center = coordinates[coordinates.count / 2]
                    cameraPosition = .region(MKCoordinateRegion(
                        center: center,
                        span: span
                    ))
                }
            }
        }
    }
} 