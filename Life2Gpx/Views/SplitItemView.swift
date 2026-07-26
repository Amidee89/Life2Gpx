import SwiftUI
import MapKit
import CoreGPX

struct SplitItemView: View {
    enum EditTarget: Identifiable {
        case first
        case second
        var id: Int { self == .first ? 1 : 2 }
    }
    
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    let fileDate: Date
    var onSaveChanges: () -> Void
    
    @State private var splitTime: Date
    @State private var showingSecondsPicker = false
    @State private var showSplitError = false
    @State private var splitErrorMessage = ""
    @State private var retainMetadataInFirst = true
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    @State private var customWP1: GPXWaypoint?
    @State private var customWP2: GPXWaypoint?
    @State private var customTrack1: GPXTrack?
    @State private var customTrack2: GPXTrack?
    @State private var editTarget: EditTarget?
    
    private let calendar = Calendar.current
    
    private var minTime: Date
    private var maxTime: Date
    
    init(timelineObject: TimelineObject, fileDate: Date, onSaveChanges: @escaping () -> Void) {
        self.timelineObject = timelineObject
        self.fileDate = fileDate
        self.onSaveChanges = onSaveChanges
        
        var minT = Date.distantFuture
        var maxT = Date.distantPast
        
        if timelineObject.type == .waypoint, let point = timelineObject.points.first {
            minT = timelineObject.startDate ?? point.time ?? Date()
            maxT = timelineObject.endDate ?? point.time ?? minT.addingTimeInterval(3600)
            if minT == maxT {
                maxT = minT.addingTimeInterval(3600)
            }
        } else if timelineObject.type == .track, let track = timelineObject.track {
            for segment in track.segments {
                for point in segment.points {
                    if let t = point.time {
                        if t < minT { minT = t }
                        if t > maxT { maxT = t }
                    }
                }
            }
            if minT > maxT { // Fallback if track points have no time
                minT = Date()
                maxT = Date().addingTimeInterval(3600)
            }
        }
        
        self.minTime = minT
        self.maxTime = maxT
        let middle = minT.addingTimeInterval(maxT.timeIntervalSince(minT) / 2)
        _splitTime = State(initialValue: middle)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Split Time")) {
                    VStack {
                        Slider(value: Binding(
                            get: { splitTime.timeIntervalSince1970 },
                            set: { splitTime = Date(timeIntervalSince1970: $0) }
                        ), in: minTime.timeIntervalSince1970...maxTime.timeIntervalSince1970)
                        
                        HStack {
                            Text(minTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(maxTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    HStack {
                        DatePicker("Time", selection: $splitTime, in: minTime...maxTime, displayedComponents: [.hourAndMinute])
                        
                        let seconds = calendar.component(.second, from: splitTime)
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
                                        from: splitTime
                                    )
                                    components.second = newSeconds
                                    if let newDate = calendar.date(from: components) {
                                        splitTime = min(max(newDate, minTime), maxTime)
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
                }
                
                if timelineObject.type == .waypoint {
                    visitPreviewSection
                } else {
                    trackPreviewSection
                }
                
            }
            .navigationTitle(timelineObject.type == .waypoint ? "Split Visit" : "Split Track")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") { saveSplit() }
            )
            .onAppear {
                if timelineObject.type == .track, let track = timelineObject.track {
                    let coordinates = track.segments.flatMap { $0.points }.compactMap { point -> CLLocationCoordinate2D? in
                        if let lat = point.latitude, let lon = point.longitude {
                            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        }
                        return nil
                    }
                    if !coordinates.isEmpty {
                        cameraPosition = .automatic // Map will automatically frame all points
                    }
                }
            }
            .errorBanner(isPresented: $showSplitError, message: splitErrorMessage)
            .sheet(item: $editTarget) { target in
                let isFirst = target == .first
                let tempObject = getTemporaryTimelineObject(for: target)
                
                if timelineObject.type == .waypoint {
                    EditVisitView(
                        timelineObject: tempObject,
                        fileDate: fileDate,
                        onSave: { _, _ in },
                        customSaveAction: { updatedWaypoint, _, _ in
                            if isFirst {
                                customWP1 = updatedWaypoint
                            } else {
                                customWP2 = updatedWaypoint
                            }
                            editTarget = nil
                        }
                    )
                } else {
                    EditTrackView(
                        timelineObject: tempObject,
                        fileDate: fileDate,
                        onSaveChanges: { },
                        customSaveAction: { updatedTrack in
                            if isFirst {
                                customTrack1 = updatedTrack
                            } else {
                                customTrack2 = updatedTrack
                            }
                            editTarget = nil
                        }
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .loadTodayData)) { _ in
                dismiss()
            }
        }
    }
    
    // MARK: - Temporary TimelineObject logic
    private func getTemporaryTimelineObject(for target: EditTarget) -> TimelineObject {
        let isFirst = target == .first
        
        if timelineObject.type == .waypoint, let originalWaypoint = timelineObject.points.first {
            let (wp1, wp2) = GPXUtils.splitWaypoint(originalWaypoint, at: splitTime, retainMetadataInFirst: retainMetadataInFirst)
            let wp = isFirst ? wp1 : wp2
            let customWP = isFirst ? customWP1 : customWP2
            
            if let customWP = customWP {
                wp.name = customWP.name
                wp.desc = customWP.desc
                wp.extensions = customWP.extensions
            }
            return TimelineObject(type: .waypoint, startDate: wp.time, endDate: wp.time, points: [wp])
            
        } else if timelineObject.type == .track, let originalTrack = timelineObject.track {
            let (tr1, tr2) = GPXUtils.splitTrack(originalTrack, at: splitTime)
            let tr = isFirst ? tr1 : tr2
            let customTr = isFirst ? customTrack1 : customTrack2
            
            if let customTr = customTr {
                tr.name = customTr.name
                tr.type = customTr.type
                tr.desc = customTr.desc
                tr.source = customTr.source
            }
            
            var tMin: Date? = nil
            var tMax: Date? = nil
            for segment in tr.segments {
                for pt in segment.points {
                    if let t = pt.time {
                        if tMin == nil || t < tMin! { tMin = t }
                        if tMax == nil || t > tMax! { tMax = t }
                    }
                }
            }
            return TimelineObject(type: .track, startDate: tMin, endDate: tMax, trackType: tr.type, name: tr.name, track: tr)
        }
        return timelineObject
    }
    
    // MARK: - Visit Preview
    private var visitPreviewSection: some View {
        Section(header: Text("Resulting Visits")) {
            VStack(spacing: 16) {
                visitPreviewRow(isFirst: true)
                
                Button(action: {
                    withAnimation {
                        retainMetadataInFirst.toggle()
                        let temp = customWP1
                        customWP1 = customWP2
                        customWP2 = temp
                    }
                }) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                visitPreviewRow(isFirst: false)
            }
        }
    }
    
    private func visitPreviewRow(isFirst: Bool) -> some View {
        let isRetaining = isFirst ? retainMetadataInFirst : !retainMetadataInFirst
        let customWP = isFirst ? customWP1 : customWP2
        let defaultName = isRetaining ? (timelineObject.name ?? "Visit") : "Unknown Place"
        let name = customWP?.name ?? defaultName
        let timeText = isFirst ? 
            "\(minTime.formatted(date: .omitted, time: .shortened)) - \(splitTime.formatted(date: .omitted, time: .shortened))" : 
            "\(splitTime.formatted(date: .omitted, time: .shortened)) - \(maxTime.formatted(date: .omitted, time: .shortened))"
            
        return HStack {
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(timeText).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { editTarget = isFirst ? .first : .second }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Track Preview
    private var trackPreviewSection: some View {
        Section(header: Text("Resulting Tracks")) {
            if let originalTrack = timelineObject.track {
                let splitTracks = GPXUtils.splitTrack(originalTrack, at: splitTime)
                
                Map(position: $cameraPosition) {
                    // Track 1
                    ForEach(Array(splitTracks.0.segments.enumerated()), id: \.offset) { _, segment in
                        let coords = segment.points.compactMap {
                            $0.latitude != nil && $0.longitude != nil ? CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) : nil
                        }
                        MapPolyline(coordinates: coords)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Track 2
                    ForEach(Array(splitTracks.1.segments.enumerated()), id: \.offset) { _, segment in
                        let coords = segment.points.compactMap {
                            $0.latitude != nil && $0.longitude != nil ? CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) : nil
                        }
                        MapPolyline(coordinates: coords)
                            .stroke(.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 250)
                .cornerRadius(10)
                .listRowInsets(EdgeInsets())
                
                let pts1 = splitTracks.0.segments.reduce(0) { $0 + $1.points.count }
                let pts2 = splitTracks.1.segments.reduce(0) { $0 + $1.points.count }
                
                trackPreviewRow(isFirst: true, pointsCount: pts1, defaultName: timelineObject.name ?? "Track 1", trackType: timelineObject.trackType)
                trackPreviewRow(isFirst: false, pointsCount: pts2, defaultName: timelineObject.name ?? "Track 2", trackType: timelineObject.trackType)
            }
        }
    }
    
    private func trackPreviewRow(isFirst: Bool, pointsCount: Int, defaultName: String, trackType: String?) -> some View {
        let customTr = isFirst ? customTrack1 : customTrack2
        let name = customTr?.name ?? defaultName
        let type = customTr?.type ?? trackType ?? "Unknown Activity"
        
        return HStack {
            Circle().fill(isFirst ? Color.blue : Color.green).frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text("\(type) • \(pointsCount) points").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { editTarget = isFirst ? .first : .second }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(isFirst ? .blue : .green)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Save Logic
    private func saveSplit() {
        if timelineObject.type == .waypoint, let waypoint = timelineObject.points.first {
            let (wp1, wp2) = GPXUtils.splitWaypoint(waypoint, at: splitTime, retainMetadataInFirst: retainMetadataInFirst)
            
            if let c1 = customWP1 {
                wp1.name = c1.name
                wp1.desc = c1.desc
                wp1.extensions = c1.extensions
            }
            if let c2 = customWP2 {
                wp2.name = c2.name
                wp2.desc = c2.desc
                wp2.extensions = c2.extensions
            }
            
            GPXManager.shared.replaceItemWithMultiple(
                deleteWaypoints: [waypoint],
                deleteTracks: [],
                addWaypoints: [wp1, wp2],
                addTracks: [],
                forDate: fileDate
            ) { success in
                DispatchQueue.main.async {
                    if success {
                        self.onSaveChanges()
                        self.dismiss()
                    } else {
                        self.splitErrorMessage = "Failed to match the selected item in the file. The file may have been modified. Please refresh and try again."
                        self.showSplitError = true
                    }
                }
            }
        } else if timelineObject.type == .track, let track = timelineObject.track {
            let (tr1, tr2) = GPXUtils.splitTrack(track, at: splitTime)
            
            if let c1 = customTrack1 {
                tr1.name = c1.name
                tr1.type = c1.type
                tr1.desc = c1.desc
                tr1.source = c1.source
            }
            if let c2 = customTrack2 {
                tr2.name = c2.name
                tr2.type = c2.type
                tr2.desc = c2.desc
                tr2.source = c2.source
            }
            
            GPXManager.shared.replaceItemWithMultiple(
                deleteWaypoints: [],
                deleteTracks: [track],
                addWaypoints: [],
                addTracks: [tr1, tr2],
                forDate: fileDate
            ) { success in
                DispatchQueue.main.async {
                    if success {
                        self.onSaveChanges()
                        self.dismiss()
                    } else {
                        self.splitErrorMessage = "Failed to match the selected item in the file. The file may have been modified. Please refresh and try again."
                        self.showSplitError = true
                    }
                }
            }
        }
    }
}
