import SwiftUI
import MapKit
import CoreGPX

struct EditTrackView: View {
    private let coordinateDisplayPrecision = 6
    private let elevationDisplayPrecision = 1
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    let fileDate: Date
    var onSaveChanges: () -> Void
    var customSaveAction: ((_ updatedTrack: GPXTrack) -> Void)? = nil
    
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
    @State private var originalPoint: GPXTrackPoint? = nil
    
    @State private var editedExtensions: [String: String] = [:]
    @State private var showAllFieldsAndExtensions = false
    
    @State private var showingDeleteConfirmation = false
    @State private var showingSecondsPicker = false
    @FocusState private var focusedField: String?
    @State private var scrollTarget: String? = nil
    
    private var hasVisibleExtensions: Bool {
        if showAllFieldsAndExtensions { return true }
        let settings = SettingsManager.shared.gpxExportSettings.trackpoints
        for key in GPXExtensionKey.trackpointCases {
            if settings.extensions[key.rawValue]?.visible == true {
                return true
            }
        }
        return false
    }
    
    init(timelineObject: TimelineObject, fileDate: Date, onSaveChanges: @escaping () -> Void, customSaveAction: ((_ updatedTrack: GPXTrack) -> Void)? = nil) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        self.onSaveChanges = onSaveChanges
        self.customSaveAction = customSaveAction
        
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
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                if !isEditing {
                    editTrackMapView
                        .frame(height: 300)
                }
                
                List {
                    if isEditing {
                        editTrackMapView
                            .frame(height: 300)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    if !isEditing {
                        Section("Track Info") {
                            NavigationLink {
                                TrackTypePickerView(selectedId: $workingCopy.trackType.toUnwrapped(defaultValue: "unknown"))
                            } label: {
                                HStack {
                                    Text("Track Type")
                                    Spacer()
                                    if let currentType = PreferencesManager.shared.trackType(for: workingCopy.trackType) {
                                        PlaceIconView(icon: currentType.icon, fallbackColor: currentType.color)
                                            .frame(width: 20)
                                        Text(currentType.name)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(workingCopy.trackType ?? "Unknown")
                                            .foregroundColor(.secondary)
                                    }
                                }
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
                        ForEach(track.segments.indices, id: \.self) { segmentIndex in
                            let segment = track.segments[segmentIndex]
                            if !isEditing || (isEditing && selectedPointIndex != nil && selectedSegmentIndex == segmentIndex) {
                                Section("Segment \(segmentIndex + 1)") {
                                    if isEditing && selectedPointIndex != nil && selectedSegmentIndex == segmentIndex {
                                        let pointIndex = selectedPointIndex!
                                        if segment.points.indices.contains(pointIndex) {
                                            let point = segment.points[pointIndex]
                                            
                                            // Point editing rows
                                            HStack {
                                                Button("Cancel") {
                                                    if let segmentIndex = selectedSegmentIndex, 
                                                       let pointIndex = selectedPointIndex,
                                                       workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                       workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                        if let original = originalPoint {
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex] = original
                                                        }
                                                        
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
                                            
                                            if let pointTime = point.time {
                                                let calendar = Calendar.current
                                                
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
                                                    
                                                    Button(action: {
                                                        showingSecondsPicker = true
                                                    }) {
                                                        Text(String(format: "%02d", seconds))
                                                            .padding(.horizontal, 10)
                                                            .padding(.vertical, 6)
                                                            .background(Color(UIColor.tertiarySystemFill))
                                                            .cornerRadius(6)
                                                            .foregroundColor(.primary)
                                                    }
                                                    .buttonStyle(BorderlessButtonStyle())
                                                    .popover(isPresented: $showingSecondsPicker) {
                                                        Picker("Seconds", selection: Binding(
                                                            get: { seconds },
                                                            set: { newSeconds in
                                                                var components = calendar.dateComponents(
                                                                    [.year, .month, .day, .hour, .minute],
                                                                    from: pointTime
                                                                )
                                                                components.second = newSeconds
                                                                
                                                                if let newDate = calendar.date(from: components) {
                                                                    workingCopy.track?.segments[segmentIndex].points[pointIndex].time = newDate
                                                                }
                                                            }
                                                        )) {
                                                            ForEach(0..<60) { second in
                                                                Text(String(format: "%02d", second)).tag(second)
                                                            }
                                                        }
                                                        .pickerStyle(.wheel)
                                                        .labelsHidden()
                                                        .frame(width: 80, height: 120)
                                                        .padding(.vertical, 16)
                                                        .padding(.horizontal, 8)
                                                        .presentationCompactAdaptation(.popover)
                                                    }
                                                }
                                            } else {
                                                Text("No time data available")
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            LabeledContent("Latitude:") {
                                                TextField("", value: $selectedPointLatitude, format: .number.precision(.fractionLength(coordinateDisplayPrecision)))
                                                    .keyboardType(.decimalPad)
                                                    .focused($focusedField, equals: "latitude")
                                                    .id("latitude")
                                                    .multilineTextAlignment(.trailing)
                                                    .onChange(of: selectedPointLatitude) { _, newValue in
                                                        if let segmentIndex = selectedSegmentIndex, 
                                                           let pointIndex = selectedPointIndex,
                                                           workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                           workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].latitude = newValue
                                                        }
                                                    }
                                            }
                                            
                                            LabeledContent("Longitude:") {
                                                TextField("", value: $selectedPointLongitude, format: .number.precision(.fractionLength(coordinateDisplayPrecision)))
                                                    .keyboardType(.decimalPad)
                                                    .focused($focusedField, equals: "longitude")
                                                    .id("longitude")
                                                    .multilineTextAlignment(.trailing)
                                                    .onChange(of: selectedPointLongitude) { _, newValue in
                                                        if let segmentIndex = selectedSegmentIndex, 
                                                           let pointIndex = selectedPointIndex,
                                                           workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                           workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].longitude = newValue
                                                        }
                                                    }
                                            }
                                            
                                            LabeledContent("Elevation:") {
                                                TextField("", value: $selectedPointElevation, format: .number.precision(.fractionLength(elevationDisplayPrecision)))
                                                    .keyboardType(.decimalPad)
                                                    .focused($focusedField, equals: "elevation")
                                                    .id("elevation")
                                                    .multilineTextAlignment(.trailing)
                                                    .onChange(of: selectedPointElevation) { _, newValue in
                                                        if let segmentIndex = selectedSegmentIndex, 
                                                           let pointIndex = selectedPointIndex,
                                                           workingCopy.track?.segments.indices.contains(segmentIndex) == true,
                                                           workingCopy.track?.segments[segmentIndex].points.indices.contains(pointIndex) == true {
                                                            workingCopy.track?.segments[segmentIndex].points[pointIndex].elevation = newValue
                                                        }
                                                    }
                                            }
                                            
                                            basicFieldsList(for: point, segmentIndex: segmentIndex, pointIndex: pointIndex)

                                            if hasVisibleExtensions {
                                                Text("Extensions")
                                                    .bold()
                                                    .frame(maxWidth: .infinity, alignment: .center)
                                                    .padding(.top, 12)
                                                    .padding(.bottom, 4)
                                                    
                                                extensionsList(for: point)
                                            }
                                            
                                            Toggle("Show all fields and extensions", isOn: $showAllFieldsAndExtensions)
                                                .padding(.vertical, 8)
                                            
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
                                    } else {
                                        ForEach(segment.points.indices, id: \.self) { pointIndex in
                                            let point = segment.points[pointIndex]
                                            
                                            TrackPointRow(
                                                point: point,
                                                isSelected: selectedPointIndex == pointIndex && selectedSegmentIndex == segmentIndex,
                                                isEditing: isEditing,
                                                onSelect: {
                                                    handlePointSelection(segmentIndex: segmentIndex, pointIndex: pointIndex, track: track)
                                                },
                                                onEdit: {
                                                    isEditing = true
                                                }
                                            )
                                            .id("segment_\(segmentIndex)_point_\(pointIndex)")
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
                .listStyle(InsetGroupedListStyle())
                .onChange(of: scrollTarget) { _, newTarget in
                    if let target = newTarget {
                        withAnimation {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        scrollTarget = nil
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if focusedField != nil {
                        Color.clear.frame(height: 150)
                    }
                }
            } // closes VStack
            } // closes ScrollViewReader
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

                    if workingCopy.trackType == "unknown" {
                        workingCopy.track?.type = nil
                    } else {
                        workingCopy.track?.type = workingCopy.trackType
                    }

                    if let customSave = customSaveAction {
                        customSave(updatedTrack)
                    } else {
                        GPXManager.shared.updateTrack(originalTrack: originalTrack, updatedTrack: updatedTrack, forDate: fileDate) { success, errorMsg in
                            if !success {
                                let msg = errorMsg ?? "Failed to save track to GPX file."
                                NotificationCenter.default.post(name: .gpxSaveFailed, object: nil, userInfo: ["message": msg])
                            }
                        }
                        onSaveChanges()
                    }

                    dismiss()
                }
            )
            .toolbar {
                if workingCopy.track != nil {
                    ToolbarItem(placement: .principal) {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .onAppear {
                let coordinates = CoordinateConverter.forMapDisplay(workingCopy.identifiableCoordinates.flatMap { $0.coordinates })
                if !coordinates.isEmpty {
                    let span = calculateSpan(for: coordinates)
                    let center = coordinates[coordinates.count / 2]
                    cameraPosition = .region(MKCoordinateRegion(
                        center: center,
                        span: span
                    ))
                }
            }
            .onChange(of: shouldUpdateCamera) {
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
                        let displayCoords = CoordinateConverter.forMapDisplay(coordinates)
                        let span = calculateSpan(for: displayCoords, withPadding: 1.5)
                        let center = displayCoords[0] 
                        
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
        .alert(
            "Are you sure you want to delete this track?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Track", role: .destructive) {
                guard let originalTrack = timelineObject.track else {
                    print("Error: Original track is missing.")
                    return
                }

                GPXManager.shared.deleteTrack(originalTrack: originalTrack, forDate: fileDate)

                onSaveChanges()

                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Point Selection
    private func handlePointSelection(segmentIndex: Int, pointIndex: Int, track: GPXTrack, fromMap: Bool = false) {
        if fromMap && isEditing { return }
        
        withAnimation {
            if selectedPointIndex == pointIndex && selectedSegmentIndex == segmentIndex && !fromMap {
                selectedPointIndex = nil
                selectedSegmentIndex = nil
            } else {
                selectedPointIndex = pointIndex
                selectedSegmentIndex = segmentIndex
                isEditing = false
                
                if let safePoint = track.segments[segmentIndex].points[safe: pointIndex] {
                    originalPointLatitude = safePoint.latitude ?? 0.0
                    originalPointLongitude = safePoint.longitude ?? 0.0
                    originalPointElevation = safePoint.elevation ?? 0.0
                    originalPointTime = safePoint.time
                    originalPoint = GPXUtils.deepCopyPoint(safePoint) as? GPXTrackPoint
                    
                    originalExtensionsDict = [:]
                    if let extensions = safePoint.extensions {
                        for child in extensions.children {
                            if let value = child.text {
                                originalExtensionsDict[child.name] = value
                            }
                        }
                    }
                    editedExtensions = originalExtensionsDict

                    selectedPointLatitude = safePoint.latitude ?? 0.0
                    selectedPointLongitude = safePoint.longitude ?? 0.0
                    selectedPointElevation = safePoint.elevation ?? 0.0
                    
                    let source = fromMap ? "Map Selected" : "Selected"
                    print("\(source) point values: Lat: \(selectedPointLatitude), Lon: \(selectedPointLongitude), Ele: \(selectedPointElevation)")
                    shouldUpdateCamera = true
                }
            }
        }
        
        if fromMap {
            scrollTarget = "segment_\(segmentIndex)_point_\(pointIndex)"
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
                    ForEach(track.segments.indices, id: \.self) { segmentIndex in
                        let segment = track.segments[segmentIndex]
                        let coordinates = CoordinateConverter.forMapDisplay(segment.points.compactMap { point in
                            point.latitude != nil && point.longitude != nil ?
                                CLLocationCoordinate2D(latitude: point.latitude!, longitude: point.longitude!) : nil
                        })
                        MapPolyline(coordinates: coordinates)
                            .stroke(.white,
                                   style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        MapPolyline(coordinates: coordinates)
                            .stroke(.black,
                                   style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        MapPolyline(coordinates: coordinates)
                            .stroke(PreferencesManager.shared.color(for: workingCopy.trackType),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        
                        ForEach(segment.points.indices, id: \.self) { index in
                            let point = segment.points[index]
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
                                    let coordinate = CoordinateConverter.forMapDisplay(CLLocationCoordinate2D(latitude: lat, longitude: lon))
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
                                        .onTapGesture {
                                            handlePointSelection(segmentIndex: segmentIndex, pointIndex: index, track: track, fromMap: true)
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
                            let coordinate = CoordinateConverter.forMapDisplay(CLLocationCoordinate2D(latitude: lat, longitude: lon))
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
                   let mapCoordinate = reader.convert(screenCoord, from: .local) {
                    
                    let coordinate = CoordinateConverter.fromMapDisplay(mapCoordinate)
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
    
    @ViewBuilder
    private func basicFieldsList(for point: GPXTrackPoint, segmentIndex: Int, pointIndex: Int) -> some View {
        let settings = SettingsManager.shared.gpxExportSettings.trackpoints

        if settings.magneticVariation.visible || showAllFieldsAndExtensions {
            let binding = Binding<Double>(
                get: { point.magneticVariation ?? 0.0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].magneticVariation = newValue
                }
            )
            LabeledContent("Magnetic Variation:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.geoidHeight.visible || showAllFieldsAndExtensions {
            let binding = Binding<Double>(
                get: { point.geoidHeight ?? 0.0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].geoidHeight = newValue
                }
            )
            LabeledContent("Geoid Height:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.name.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.name ?? "" },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].name = newValue.isEmpty ? nil : newValue
                }
            )
            LabeledContent("Name:") {
                TextField("", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.comment.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.comment ?? "" },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].comment = newValue.isEmpty ? nil : newValue
                }
            )
            LabeledContent("Comment:") {
                TextField("", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.desc.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.desc ?? "" },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].desc = newValue.isEmpty ? nil : newValue
                }
            )
            LabeledContent("Description:") {
                TextField("", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.source.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.source ?? "" },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].source = newValue.isEmpty ? nil : newValue
                }
            )
            LabeledContent("Source:") {
                TextField("", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.symbol.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.symbol ?? "" },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].symbol = newValue.isEmpty ? nil : newValue
                }
            )
            LabeledContent("Symbol:") {
                TextField("", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.type.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.type ?? "" },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].type = newValue.isEmpty ? nil : newValue
                }
            )
            LabeledContent("Type:") {
                TextField("", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.satellites.visible || showAllFieldsAndExtensions {
            let binding = Binding<Int>(
                get: { point.satellites ?? 0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].satellites = newValue
                }
            )
            LabeledContent("Satellites:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.horizontalDilution.visible || showAllFieldsAndExtensions {
            let binding = Binding<Double>(
                get: { point.horizontalDilution ?? 0.0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].horizontalDilution = newValue
                }
            )
            LabeledContent("Horizontal Dilution:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.verticalDilution.visible || showAllFieldsAndExtensions {
            let binding = Binding<Double>(
                get: { point.verticalDilution ?? 0.0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].verticalDilution = newValue
                }
            )
            LabeledContent("Vertical Dilution:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.positionDilution.visible || showAllFieldsAndExtensions {
            let binding = Binding<Double>(
                get: { point.positionDilution ?? 0.0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].positionDilution = newValue
                }
            )
            LabeledContent("Position Dilution:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.ageofDGPSData.visible || showAllFieldsAndExtensions {
            let binding = Binding<Double>(
                get: { point.ageofDGPSData ?? 0.0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].ageofDGPSData = newValue
                }
            )
            LabeledContent("Age of DGPS Data:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.DGPSid.visible || showAllFieldsAndExtensions {
            let binding = Binding<Int>(
                get: { point.DGPSid ?? 0 },
                set: { newValue in
                    workingCopy.track?.segments[segmentIndex].points[pointIndex].DGPSid = newValue
                }
            )
            LabeledContent("DGPS ID:") {
                TextField("", value: binding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
        if settings.fix.visible || showAllFieldsAndExtensions {
            let binding = Binding<String>(
                get: { point.fix?.rawValue ?? "" },
                set: { newValue in
                    if let fix = GPXFix(rawValue: newValue) {
                        workingCopy.track?.segments[segmentIndex].points[pointIndex].fix = fix
                    } else if newValue.isEmpty {
                        workingCopy.track?.segments[segmentIndex].points[pointIndex].fix = nil
                    }
                }
            )
            LabeledContent("Fix:") {
                TextField("none, 2d, 3d, dgps, pps", text: binding)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func extensionsList(for point: GPXTrackPoint) -> some View {
        ForEach(GPXExtensionKey.trackpointCases, id: \.self) { (key: GPXExtensionKey) in
            let hasValue = editedExtensions.keys.contains(key.rawValue)
            let isVisible = SettingsManager.shared.gpxExportSettings.trackpoints.extensions[key.rawValue]?.visible == true
            if isVisible || showAllFieldsAndExtensions {
                let binding = Binding<String>(
                get: { editedExtensions[key.rawValue] ?? "" },
                set: { newValue in
                    if newValue.isEmpty {
                        editedExtensions.removeValue(forKey: key.rawValue)
                    } else {
                        editedExtensions[key.rawValue] = newValue
                    }
                }
            )
            
            HStack {
                if hasValue {
                    Button(action: {
                        editedExtensions.removeValue(forKey: key.rawValue)
                    }) {
                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                } else {
                    Button(action: {
                        if key == .timezoneOffset {
                            editedExtensions[key.rawValue] = String(TimeZone.current.secondsFromGMT())
                        } else {
                            switch key.valueType {
                            case .boolean:
                                editedExtensions[key.rawValue] = "True"
                            case .activityConfidence:
                                editedExtensions[key.rawValue] = ActivityConfidenceValue.high.rawValue
                            case .integer:
                                editedExtensions[key.rawValue] = "0"
                            case .double:
                                editedExtensions[key.rawValue] = "0.0"
                            default:
                                editedExtensions[key.rawValue] = "New Value"
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.green)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                LabeledContent(key.rawValue) {
                    if !hasValue {
                        Text("nil").foregroundColor(.secondary)
                    } else if key == .timezoneOffset {
                        SimpleTimezoneEditor(secondsOffsetString: binding, referenceDate: point.time)
                    } else {
                        switch key.valueType {
                        case .boolean:
                            Picker("", selection: binding) {
                                Text("True").tag("True")
                                Text("False").tag("False")
                            }
                            .pickerStyle(MenuPickerStyle())
                        case .activityConfidence:
                            Picker("", selection: binding) {
                                ForEach(ActivityConfidenceValue.allCases) { conf in
                                    Text(conf.rawValue).tag(conf.rawValue)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        default:
                            TextField("Value", text: binding)
                                .focused($focusedField, equals: "ext_\(key.rawValue)")
                                .id("ext_\(key.rawValue)")
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                                .keyboardType(key.valueType == .double || key.valueType == .integer ? .numbersAndPunctuation : .default)
                        }
                }
            }
            }
        }
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

struct TrackPointRow: View {
    let point: GPXTrackPoint
    let isSelected: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
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
            
            if isSelected {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .listRowBackground(isSelected && !isEditing ? Color.blue.opacity(0.3) : Color.clear)
    }
}
