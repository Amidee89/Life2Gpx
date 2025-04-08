import SwiftUI
import MapKit
import CoreGPX

struct EditTrackView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    let fileDate: Date
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var workingCopy: TimelineObject
    
    init(timelineObject: TimelineObject, fileDate: Date) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        _workingCopy = State(initialValue: TimelineObject(
            type: timelineObject.type,
            startDate: timelineObject.startDate,
            endDate: timelineObject.endDate,
            trackType: timelineObject.trackType,
            name: timelineObject.name,
            duration: timelineObject.duration,
            steps: timelineObject.steps,
            meters: timelineObject.meters,
            numberOfPoints: timelineObject.numberOfPoints,
            averageSpeed: timelineObject.averageSpeed,
            coordinates: timelineObject.identifiableCoordinates,
            points: timelineObject.points,
            customIcon: timelineObject.customIcon,
            track: timelineObject.track
        ))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Track Details") {
                    Picker("Track Type", selection: $workingCopy.trackType.toUnwrapped(defaultValue: "unknown")) {
                        Text("Walking").tag("walking")
                        Text("Running").tag("running")
                        Text("Cycling").tag("cycling")
                        Text("Automotive").tag("automotive")
                        Text("Unknown").tag("unknown")
                    }
                    
                    if workingCopy.track != nil {
                        LabeledContent("Number of Steps") {
                            TextField("", value: $workingCopy.steps, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section("Track Map") {
                    Map(position: $cameraPosition) {
                        if let track = workingCopy.track {
                            ForEach(track.segments, id: \.self) { segment in
                                let coordinates = segment.points.compactMap { point in
                                    point.latitude != nil && point.longitude != nil ?
                                        CLLocationCoordinate2D(latitude: point.latitude!, longitude: point.longitude!) : nil
                                }
                                MapPolyline(coordinates: coordinates)
                                    .stroke(.white,
                                           style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                                MapPolyline(coordinates: coordinates)
                                    .stroke(.black,
                                           style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                                MapPolyline(coordinates: coordinates)
                                    .stroke(trackTypeColorMapping[workingCopy.trackType ?? "unknown"] ?? .purple,
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                            }
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
                    // to be implemented
                    dismiss()
                }
            )
            .onAppear {
                let coordinates = workingCopy.identifiableCoordinates.flatMap { $0.coordinates }
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

//handle optional binding for the track type
extension Binding {
    func toUnwrapped<T>(defaultValue: T) -> Binding<T> where Value == Optional<T> {
        Binding<T>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
} 
