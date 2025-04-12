import SwiftUI
import MapKit
import CoreGPX

struct EditTrackView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    let fileDate: Date
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var workingCopy: TimelineObject
    @State private var selectedPointIndex: Int? = nil
    @State private var selectedSegmentIndex: Int? = nil
    @State private var isEditing: Bool = false
    
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
                Section("") {
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
                
                
                
                    Map(position: $cameraPosition) {
                        if let track = workingCopy.track {
                            ForEach(Array(track.segments.enumerated()), id: \.offset) { segmentIndex, segment in
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
                                
                                // First render all non-selected points
                                ForEach(Array(segment.points.enumerated()), id: \.offset) { index, point in
                                    if let lat = point.latitude, let lon = point.longitude, 
                                       !(index == selectedPointIndex && segmentIndex == selectedSegmentIndex) {
                                        
                                        // Skip points that are too close to the selected point to avoid overlap
                                        let shouldSkip = selectedPointIndex != nil && selectedSegmentIndex != nil &&
                                            isPointTooCloseToSelected(
                                                lat: lat, 
                                                lon: lon, 
                                                selectedSegmentIndex: selectedSegmentIndex!, 
                                                selectedPointIndex: selectedPointIndex!,
                                                track: track
                                            )
                                        
                                        if !shouldSkip {
                                            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                            let timeLabel = point.time?.formatted(date: .omitted, time: .shortened) ?? "No time"
                                            
                                            // Non-selected points (smaller, blue)
                                            Annotation(timeLabel, coordinate: coordinate) {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color.white)
                                                        .frame(width: 16, height: 16)
                                                    Circle()
                                                        .fill(Color.blue)
                                                        .frame(width: 10, height: 10)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Render the selected point last to ensure it's on top
                            if let selectedSegmentIndex = selectedSegmentIndex, 
                               let selectedPointIndex = selectedPointIndex,
                               track.segments.indices.contains(selectedSegmentIndex),
                               track.segments[selectedSegmentIndex].points.indices.contains(selectedPointIndex) {
                                
                                let point = track.segments[selectedSegmentIndex].points[selectedPointIndex]
                                if let lat = point.latitude, let lon = point.longitude {
                                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                                    let timeLabel = point.time?.formatted(date: .omitted, time: .shortened) ?? "No time"
                                    
                                    // Selected point (larger, orange)
                                    Annotation(timeLabel, coordinate: coordinate) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 24, height: 24)
                                            Circle()
                                                .fill(Color.orange)
                                                .frame(width: 16, height: 16)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                if let track = workingCopy.track {
                    ForEach(Array(track.segments.enumerated()), id: \.offset) { segmentIndex, segment in
                        if !isEditing || (isEditing && selectedPointIndex != nil && selectedSegmentIndex == segmentIndex) {
                            Section("Segment \(segmentIndex + 1)") {
                                if isEditing && selectedPointIndex != nil && selectedSegmentIndex == segmentIndex {
                                    // Only show the selected point when editing
                                    let pointIndex = selectedPointIndex!
                                    if segment.points.indices.contains(pointIndex) {
                                        let point = segment.points[pointIndex]
                                        
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Cancel and Done buttons at the top
                                            HStack {
                                                Button("Cancel") {
                                                    isEditing = false
                                                }
                                                .foregroundColor(.red)
                                                
                                                Spacer()
                                                
                                                Button("Done") {
                                                    isEditing = false
                                                }
                                                .foregroundColor(.blue)
                                            }
                                            .padding(.bottom, 8)
                                            
                                            // Date and Time
                                            if let pointTime = point.time {
                                                let calendar = Calendar.current
                                                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: pointTime)
                                                
                                                // Date picker
                                                DatePicker("Date", selection: Binding(
                                                    get: { pointTime },
                                                    set: { newDate in
                                                        // Preserve time while changing date
                                                        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: pointTime)
                                                        let dateComponents = calendar.dateComponents([.year, .month, .day], from: newDate)
                                                        
                                                        var mergedComponents = DateComponents()
                                                        mergedComponents.year = dateComponents.year
                                                        mergedComponents.month = dateComponents.month
                                                        mergedComponents.day = dateComponents.day
                                                        mergedComponents.hour = timeComponents.hour
                                                        mergedComponents.minute = timeComponents.minute
                                                        mergedComponents.second = timeComponents.second
                                                        
                                                        if let mergedDate = calendar.date(from: mergedComponents) {
                                                            segment.points[pointIndex].time = mergedDate
                                                        }
                                                    }
                                                ), displayedComponents: .date)
                                                
                                                // Time picker
                                                DatePicker("Time", selection: Binding(
                                                    get: { pointTime },
                                                    set: { newTime in
                                                        // Preserve date while changing time
                                                        let dateComponents = calendar.dateComponents([.year, .month, .day], from: pointTime)
                                                        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: newTime)
                                                        
                                                        var mergedComponents = DateComponents()
                                                        mergedComponents.year = dateComponents.year
                                                        mergedComponents.month = dateComponents.month
                                                        mergedComponents.day = dateComponents.day
                                                        mergedComponents.hour = timeComponents.hour
                                                        mergedComponents.minute = timeComponents.minute
                                                        mergedComponents.second = timeComponents.second
                                                        
                                                        if let mergedDate = calendar.date(from: mergedComponents) {
                                                            segment.points[pointIndex].time = mergedDate
                                                        }
                                                    }
                                                ), displayedComponents: .hourAndMinute)
                                            } else {
                                                Text("No time data available")
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            // Coordinates
                                            Group {
                                                HStack {
                                                    Text("Latitude:")
                                                    TextField("Latitude", value: Binding(
                                                        get: { point.latitude ?? 0.0 },
                                                        set: { segment.points[pointIndex].latitude = $0 }
                                                    ), format: .number.precision(.fractionLength(6)))
                                                    .keyboardType(.decimalPad)
                                                }
                                                
                                                HStack {
                                                    Text("Longitude:")
                                                    TextField("Longitude", value: Binding(
                                                        get: { point.longitude ?? 0.0 },
                                                        set: { segment.points[pointIndex].longitude = $0 }
                                                    ), format: .number.precision(.fractionLength(6)))
                                                    .keyboardType(.decimalPad)
                                                }
                                                
                                                HStack {
                                                    Text("Elevation:")
                                                    TextField("Elevation (m)", value: Binding(
                                                        get: { point.elevation ?? 0.0 },
                                                        set: { segment.points[pointIndex].elevation = $0 }
                                                    ), format: .number.precision(.fractionLength(1)))
                                                    .keyboardType(.decimalPad)
                                                }
                                            }
                                            
                                            // Delete button at the bottom
                                            Button(action: {
                                                // For now, just close edit mode
                                                isEditing = false
                                            }) {
                                                HStack {
                                                    Image(systemName: "trash")
                                                    Text("Delete Point")
                                                }
                                                .foregroundColor(.red)
                                                .frame(maxWidth: .infinity)
                                            }
                                            .padding(.top, 12)
                                        }
                                        .padding(.vertical, 8)
                                    }
                                } else {
                                    // Show all points when not editing
                                    ForEach(Array(segment.points.enumerated()), id: \.offset) { pointIndex, point in
                                        HStack {
                                            Text(point.time?.formatted(date: .numeric, time: .complete) ?? "No time")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            if selectedPointIndex == pointIndex && selectedSegmentIndex == segmentIndex {
                                                Button(action: {
                                                    isEditing = true
                                                }) {
                                                    Image(systemName: "square.and.pencil")
                                                        .foregroundColor(.blue)
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation {
                                                if selectedPointIndex == pointIndex && selectedSegmentIndex == segmentIndex {
                                                    selectedPointIndex = nil
                                                    selectedSegmentIndex = nil
                                                } else {
                                                    selectedPointIndex = pointIndex
                                                    selectedSegmentIndex = segmentIndex
                                                    isEditing = false
                                                }
                                            }
                                        }
                                        .listRowBackground(selectedPointIndex == pointIndex && selectedSegmentIndex == segmentIndex && !isEditing ? Color.blue.opacity(0.3) : Color.clear)
                                    }
                                }
                            }
                        }
                    }
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
    
    // Helper function to determine if a point is too close to the selected point
    private func isPointTooCloseToSelected(lat: Double, lon: Double, selectedSegmentIndex: Int, selectedPointIndex: Int, track: GPXTrack) -> Bool {
        guard track.segments.indices.contains(selectedSegmentIndex),
              track.segments[selectedSegmentIndex].points.indices.contains(selectedPointIndex),
              let selectedLat = track.segments[selectedSegmentIndex].points[selectedPointIndex].latitude,
              let selectedLon = track.segments[selectedSegmentIndex].points[selectedPointIndex].longitude else {
            return false
        }
        
        // Calculate distance between points using Haversine formula
        let earthRadius = 6371000.0 // Earth radius in meters
        let dLat = (selectedLat - lat) * .pi / 180
        let dLon = (selectedLon - lon) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat * .pi / 180) * cos(selectedLat * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        let distance = earthRadius * c
        
        // Skip points that are within a certain distance (e.g., 50 meters)
        // This threshold can be adjusted based on your map zoom level
        return distance < 50
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

// Add preview provider at the bottom of the file
#Preview {
    EditTrackView(timelineObject: TimelineObject.previewTrack, fileDate: Date())
} 

// Add this extension at the bottom of the file
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
