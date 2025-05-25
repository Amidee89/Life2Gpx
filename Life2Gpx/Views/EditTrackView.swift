import SwiftUI
import MapKit
import CoreGPX

struct EditTrackView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    let fileDate: Date
    var onSaveChanges: () -> Void
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject var workingCopy: TimelineObject
    @State private var selectedPointIndex: Int? = nil
    @State private var selectedSegmentIndex: Int? = nil
    @State private var isEditing: Bool = false
    @State private var selectedPointLatitude: Double = 0.0
    @State private var selectedPointLongitude: Double = 0.0
    @State private var selectedPointElevation: Double = 0.0
    @State private var shouldUpdateCamera: Bool = false
    
    @State private var originalPointLatitude: Double = 0.0
    @State private var originalPointLongitude: Double = 0.0
    @State private var originalPointElevation: Double = 0.0
    @State private var originalPointTime: Date? = nil
    @State private var originalExtensionsDict: [String: String] = [:]
    
    @State private var editedExtensions: [String: String] = [:]
    
    @State private var showingDeleteConfirmation = false
    
    init(timelineObject: TimelineObject, fileDate: Date, onSaveChanges: @escaping () -> Void) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        self.onSaveChanges = onSaveChanges
        
        let copy = TimelineObject(
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
            track: timelineObject.track != nil ? GPXUtils.deepCopyTrack(timelineObject.track!) : nil
        )
        
        _workingCopy = StateObject(wrappedValue: copy)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                editTrackMapView
                    .frame(height: 300)
                
                List {
                    if !isEditing {
                        Section("Track Info") {
                            Picker("Track Type", selection: $workingCopy.trackType.toUnwrapped(defaultValue: "unknown")) {
                                Text("Walking").tag("walking")
                                Text("Running").tag("running")
                                Text("Cycling").tag("cycling")
                                Text("Automotive").tag("automotive")
                                Text("Unknown").tag("unknown")
                            }
                            .onChange(of: workingCopy.trackType) { oldValue, newValue in
                                print("[EditTrackView] Picker selection changed: workingCopy.trackType is now \(newValue ?? "nil") (was \(oldValue ?? "nil"))")
                            }
                            
                            if workingCopy.track != nil {
                                LabeledContent("Total number of steps") {
                                    Text("\(totalCalculatedSteps)")
                                        .multilineTextAlignment(.trailing)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    if let track = workingCopy.track {
                        ForEach(Array(track.segments.enumerated()), id: \.offset) { segmentIndex, segment in
                            if !isEditing || (isEditing && selectedPointIndex != nil && selectedSegmentIndex == segmentIndex) {
                                Section("Segment \(segmentIndex + 1)") {
                                    if isEditing && selectedPointIndex != nil && selectedSegmentIndex == segmentIndex {
                                        let pointIndex = selectedPointIndex!
                                        if segment.points.indices.contains(pointIndex) {
                                            let point = segment.points[pointIndex]
                                            
                                            VStack(alignment: .leading, spacing: 12) {
                                                HStack {
                                                    Button("Cancel") {
                                                        if let segmentIndex = selectedSegmentIndex, 
                                                           let pointIndex = selectedPointIndex,
                                                           workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                           workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].latitude = originalPointLatitude
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].longitude = originalPointLongitude
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].elevation = originalPointElevation
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].time = originalPointTime
                                                            
                                                            editedExtensions = originalExtensionsDict

                                                            selectedPointLatitude = originalPointLatitude
                                                            selectedPointLongitude = originalPointLongitude
                                                            selectedPointElevation = originalPointElevation
                                                            print("Restored point values: Lat: \(selectedPointLatitude), Lon: \(selectedPointLongitude), Ele: \(selectedPointElevation)")
                                                        }
                                                        isEditing = false
                                                    }
                                                    .buttonStyle(BorderlessButtonStyle())
                                                    .foregroundColor(.red)
                                                    
                                                    Spacer()
                                                    
                                                    Button("Done") {
                                                        if let segmentIndex = selectedSegmentIndex, 
                                                           let pointIndex = selectedPointIndex,
                                                           workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                           workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                            print("Updating point values: Lat: \(selectedPointLatitude), Lon: \(selectedPointLongitude), Ele: \(selectedPointElevation)")
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].latitude = selectedPointLatitude
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].longitude = selectedPointLongitude
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].elevation = selectedPointElevation
                                                            
                                                            let newExtensions = GPXExtensions()
                                                            newExtensions.append(at: nil, contents: editedExtensions)
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].extensions = newExtensions.children.isEmpty ? nil : newExtensions

                                                            updateDisplayCoordinates()
                                                        }
                                                        isEditing = false
                                                    }
                                                    .buttonStyle(BorderlessButtonStyle())
                                                    .foregroundColor(.blue)
                                                }
                                                .padding(.bottom, 8)
                                                
                                                if let pointTime = point.time {
                                                    let calendar = Calendar.current
                                                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: pointTime)
                                                    
                                                    DatePicker("Date", selection: Binding(
                                                        get: { pointTime },
                                                        set: { newDate in
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
                                                    
                                                    HStack {
                                                        DatePicker("Time", selection: Binding(
                                                            get: { pointTime },
                                                            set: { newTime in
                                                                let dateComponents = calendar.dateComponents([.year, .month, .day], from: pointTime)
                                                                let timeComponents = calendar.dateComponents([.hour, .minute], from: newTime)
                                                                let seconds = calendar.component(.second, from: pointTime)
                                                                
                                                                var mergedComponents = DateComponents()
                                                                mergedComponents.year = dateComponents.year
                                                                mergedComponents.month = dateComponents.month
                                                                mergedComponents.day = dateComponents.day
                                                                mergedComponents.hour = timeComponents.hour
                                                                mergedComponents.minute = timeComponents.minute
                                                                mergedComponents.second = seconds
                                                                
                                                                if let mergedDate = calendar.date(from: mergedComponents) {
                                                                    segment.points[pointIndex].time = mergedDate
                                                                }
                                                            }
                                                        ), displayedComponents: .hourAndMinute)
                                                        
                                                        let seconds = calendar.component(.second, from: pointTime)
                                                        Text(":")
                                                            .font(.system(size: 17, weight: .regular))
                                                        Menu {
                                                            Picker("", selection: Binding(
                                                                get: { seconds },
                                                                set: { newSeconds in
                                                                    var components = calendar.dateComponents(
                                                                        [.year, .month, .day, .hour, .minute],
                                                                        from: pointTime
                                                                    )
                                                                    components.second = newSeconds
                                                                    
                                                                    if let newDate = calendar.date(from: components) {
                                                                        segment.points[pointIndex].time = newDate
                                                                    }
                                                                }
                                                            )) {
                                                                ForEach(0..<60) { second in
                                                                    Text("\(second)").tag(second)
                                                                }
                                                            }
                                                        } label: {
                                                            Text(String(format: "%02d", seconds))
                                                                .foregroundColor(.blue)
                                                        }
                                                    }
                                                    .padding(.bottom, 8)
                                                } else {
                                                    Text("No time data available")
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Group {
                                                    LabeledContent("Latitude:") {
                                                        TextField("", value: $selectedPointLatitude, format: .number.precision(.fractionLength(6)))
                                                            .keyboardType(.decimalPad)
                                                            .multilineTextAlignment(.trailing)
                                                            .onChange(of: selectedPointLatitude) { newValue in
                                                                if let segmentIndex = selectedSegmentIndex, 
                                                                   let pointIndex = selectedPointIndex,
                                                                   workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                                   workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                                    workingCopy.track?.segments[segmentIndex].points[pointIndex].latitude = newValue
                                                                }
                                                            }
                                                    }
                                                    
                                                    LabeledContent("Longitude:") {
                                                        TextField("", value: $selectedPointLongitude, format: .number.precision(.fractionLength(6)))
                                                            .keyboardType(.decimalPad)
                                                            .multilineTextAlignment(.trailing)
                                                            .onChange(of: selectedPointLongitude) { newValue in
                                                                if let segmentIndex = selectedSegmentIndex, 
                                                                   let pointIndex = selectedPointIndex,
                                                                   workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                                   workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                                    workingCopy.track?.segments[segmentIndex].points[pointIndex].longitude = newValue
                                                                }
                                                            }
                                                    }
                                                    
                                                    LabeledContent("Elevation:") {
                                                        TextField("", value: $selectedPointElevation, format: .number.precision(.fractionLength(1)))
                                                            .keyboardType(.decimalPad)
                                                            .multilineTextAlignment(.trailing)
                                                            .onChange(of: selectedPointElevation) { newValue in
                                                                if let segmentIndex = selectedSegmentIndex, 
                                                                   let pointIndex = selectedPointIndex,
                                                                   workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                                   workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                                    workingCopy.track?.segments[segmentIndex].points[pointIndex].elevation = newValue
                                                                }
                                                            }
                                                    }
                                                }
                                                
                                                if !editedExtensions.isEmpty {
                                                    Section {
                                                        ForEach(editedExtensions.keys.sorted(), id: \.self) { key in
                                                            let binding = Binding<String>( 
                                                                get: { editedExtensions[key] ?? "" },
                                                                set: { editedExtensions[key] = $0 }
                                                            )
                                                            LabeledContent(key) {
                                                                TextField("Value", text: binding)
                                                                    .multilineTextAlignment(.trailing)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                        }
                                                    } header: {
                                                        Text("Extensions")
                                                            .bold()
                                                            .frame(maxWidth: .infinity, alignment: .center)
                                                    }
                                                }
                                                
                                                Button(action: {
                                                    if let segmentIndex = selectedSegmentIndex,
                                                       let pointIndex = selectedPointIndex,
                                                       workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                       workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                        
                                                        workingCopy.track?.segments[segmentIndex].points.remove(at: pointIndex)
                                                        
                                                        // If the segment becomes empty after deleting the point, remove the segment
                                                        if workingCopy.track?.segments[segmentIndex].points.isEmpty == true {
                                                            workingCopy.track?.segments.remove(at: segmentIndex)
                                                        }
                                                        
                                                        updateDisplayCoordinates()
                                                        
                                                        // Reset selection and editing state
                                                        selectedPointIndex = nil
                                                        selectedSegmentIndex = nil
                                                        isEditing = false
                                                    }
                                                }) {
                                                    HStack {
                                                        Image(systemName: "trash")
                                                        Text("Delete Point")
                                                    }
                                                    .foregroundColor(.red)
                                                    .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                                .padding(.top, 12)
                                            }
                                            .padding(.vertical, 8)
                                        }
                                    } else {
                                        ForEach(Array(segment.points.enumerated()), id: \.offset) { pointIndex, point in
                                            HStack {
                                                if let pointTime = point.time {
                                                    Text(pointTime.formatted(.dateTime.year().month().day()))
                                                        .foregroundColor(.secondary)
                                                    Text(pointTime.formatted(.dateTime.hour().minute().second()))
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                } else {
                                                    Text("No time")
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                                
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
                                                        
                                                        if let point = track.segments[segmentIndex].points[safe: pointIndex] {
                                                            originalPointLatitude = point.latitude ?? 0.0
                                                            originalPointLongitude = point.longitude ?? 0.0
                                                            originalPointElevation = point.elevation ?? 0.0
                                                            originalPointTime = point.time
                                                            
                                                            originalExtensionsDict = [:]
                                                            if let extensions = point.extensions {
                                                                for child in extensions.children {
                                                                    if let value = child.text {
                                                                        originalExtensionsDict[child.name] = value
                                                                    }
                                                                }
                                                            }
                                                            editedExtensions = originalExtensionsDict

                                                            selectedPointLatitude = point.latitude ?? 0.0
                                                            selectedPointLongitude = point.longitude ?? 0.0
                                                            selectedPointElevation = point.elevation ?? 0.0
                                                            print("Selected point values: Lat: \(selectedPointLatitude), Lon: \(selectedPointLongitude), Ele: \(selectedPointElevation)")
                                                            shouldUpdateCamera = true
                                                        }
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
                    if !isEditing && workingCopy.track != nil {
                        Section {
                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Delete Track")
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                            }
                        }
                        .listRowBackground(Color.red.opacity(0.1))
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Edit Track")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    guard let originalTrack = timelineObject.track,
                          let updatedTrack = workingCopy.track else {
                        print("Error: Original or updated track is missing.")
                        dismiss()
                        return
                    }

                    do {
                        try FileManagerUtil.shared.backupFile(forDate: fileDate)
                    } catch {

                        return
                    }

                    workingCopy.track?.type = workingCopy.trackType

                    GPXManager.shared.updateTrack(originalTrack: originalTrack, updatedTrack: updatedTrack, forDate: fileDate)

                    onSaveChanges()

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
            .onChange(of: shouldUpdateCamera) { _ in
                if shouldUpdateCamera, 
                   let segmentIndex = selectedSegmentIndex, 
                   let pointIndex = selectedPointIndex,
                   let track = workingCopy.track,
                   track.segments.indices.contains(segmentIndex) {
                    
                    let segment = track.segments[segmentIndex]
                    
                    let selectedPoint = segment.points[pointIndex]
                    let prevPoint = segment.points[safe: pointIndex - 1]
                    let nextPoint = segment.points[safe: pointIndex + 1]
                    
                    var coordinates: [CLLocationCoordinate2D] = []
                    
                    if let lat = selectedPoint.latitude, let lon = selectedPoint.longitude {
                        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    
                    if let prevPoint = prevPoint, let lat = prevPoint.latitude, let lon = prevPoint.longitude {
                        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    
                    if let nextPoint = nextPoint, let lat = nextPoint.latitude, let lon = nextPoint.longitude {
                        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    
                    if !coordinates.isEmpty {
                        let span = calculateSpan(for: coordinates, withPadding: 1.5)
                        let center = coordinates[0] 
                        
                        withAnimation {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: center,
                                span: span
                            ))
                        }
                    }
                    
                    shouldUpdateCamera = false
                }
            }
        }
        .confirmationDialog(
            "Are you sure you want to delete this track?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Track", role: .destructive) {
                guard let originalTrack = timelineObject.track else {
                    print("Error: Original track is missing.")
                    return
                }

                do {
                    try FileManagerUtil.shared.backupFile(forDate: fileDate)
                } catch {
                    print("Error backing up GPX file: \(error)")
                    return
                }

                GPXManager.shared.deleteTrack(originalTrack: originalTrack, forDate: fileDate)

                onSaveChanges()

                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Calculated Properties
    private var totalCalculatedSteps: Int {
        guard let track = workingCopy.track else { return 0 }

        return track.segments.reduce(0) { segmentSum, segment in
            segmentSum + segment.points.reduce(0) { pointSum, point in
                if let extensions = point.extensions {
                    for child in extensions.children {
                        if child.name == "Steps", let stepsString = child.text, let steps = Int(stepsString) {
                            return pointSum + steps
                        }
                    }
                }
                return pointSum
            }
        }
    }
    
    // MARK: - Map View
    private var editTrackMapView: some View {
        MapReader { reader in
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
                        
                        ForEach(Array(segment.points.enumerated()), id: \.offset) { index, point in
                            if let lat = point.latitude, let lon = point.longitude, 
                               !(index == selectedPointIndex && segmentIndex == selectedSegmentIndex) {
                                
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
                    
                    if let selectedSegmentIndex = selectedSegmentIndex, 
                       let selectedPointIndex = selectedPointIndex,
                       track.segments.indices.contains(selectedSegmentIndex),
                       track.segments[selectedSegmentIndex].points.indices.contains(selectedPointIndex) {
                        
                        let point = track.segments[selectedSegmentIndex].points[selectedPointIndex]
                        if let lat = point.latitude, let lon = point.longitude {
                            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            let timeLabel = point.time?.formatted(date: .omitted, time: .shortened) ?? "No time"
                            
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
            .onTapGesture { screenCoord in
                if isEditing, 
                   let selectedSegmentIndex = selectedSegmentIndex, 
                   let selectedPointIndex = selectedPointIndex,
                   let track = workingCopy.track,
                   track.segments.indices.contains(selectedSegmentIndex),
                   track.segments[selectedSegmentIndex].points.indices.contains(selectedPointIndex),
                   let coordinate = reader.convert(screenCoord, from: .local) {
                    
                    track.segments[selectedSegmentIndex].points[selectedPointIndex].latitude = coordinate.latitude
                    track.segments[selectedSegmentIndex].points[selectedPointIndex].longitude = coordinate.longitude
                    
                    selectedPointLatitude = coordinate.latitude
                    selectedPointLongitude = coordinate.longitude
                    print("Selected point values: Lat: \(selectedPointLatitude), Lon: \(selectedPointLongitude), Ele: \(selectedPointElevation)")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func isPointTooCloseToSelected(lat: Double, lon: Double, selectedSegmentIndex: Int, selectedPointIndex: Int, track: GPXTrack) -> Bool {
        guard track.segments.indices.contains(selectedSegmentIndex),
              track.segments[selectedSegmentIndex].points.indices.contains(selectedPointIndex),
              let selectedLat = track.segments[selectedSegmentIndex].points[selectedPointIndex].latitude,
              let selectedLon = track.segments[selectedSegmentIndex].points[selectedPointIndex].longitude else {
            return false
        }
        
        let earthRadius = 6371000.0 // Earth radius in meters
        let dLat = (selectedLat - lat) * .pi / 180
        let dLon = (selectedLon - lon) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat * .pi / 180) * cos(selectedLat * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        let distance = earthRadius * c

        return distance < 30
    }
    
    private func calculateSpan(for coordinates: [CLLocationCoordinate2D], withPadding: Double = 1.0) -> MKCoordinateSpan {
        guard !coordinates.isEmpty else { return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let latDelta = (maxLat - minLat) * withPadding
        let lonDelta = (maxLon - minLon) * withPadding
        
        let minDelta = 0.002 

        return MKCoordinateSpan(
            latitudeDelta: max(latDelta, minDelta),
            longitudeDelta: max(lonDelta, minDelta)
        )
    }
    
    private func updateDisplayCoordinates() {
        if let track = workingCopy.track {
            let trackCoordinates = track.segments.flatMap { segment in
                segment.points.compactMap { point in
                    point.latitude != nil && point.longitude != nil ?
                        CLLocationCoordinate2D(latitude: point.latitude!, longitude: point.longitude!) : nil
                }
            }
            
            if !trackCoordinates.isEmpty {
                workingCopy.identifiableCoordinates = [IdentifiableCoordinates(coordinates: trackCoordinates)]
            }
            
            workingCopy.points = track.segments.flatMap { $0.points }
        }
    }
}

extension Binding {
    func toUnwrapped<T>(defaultValue: T) -> Binding<T> where Value == Optional<T> {
        Binding<T>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

#Preview {
    EditTrackView(timelineObject: TimelineObject.previewTrack, fileDate: Date(), onSaveChanges: {})
} 

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
