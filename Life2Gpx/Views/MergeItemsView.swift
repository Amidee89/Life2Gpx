import SwiftUI
import MapKit
import CoreGPX
import CoreLocation

// MARK: - Merge Type Picker

enum MergeTargetType {
    case track
    case visit
}

struct MergeTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let isContiguous: Bool
    let onSelect: (MergeTargetType) -> Void

    @State private var showNonContiguousWarning = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if !isContiguous {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Selected items are not contiguous. Merging may create a non-chronological timeline.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

                VStack(spacing: 16) {
                    Button(action: {
                        handleMergeSelection(.track)
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.title2)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Merge to Track")
                                    .font(.headline)
                                Text("Combine all points into a single track")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        handleMergeSelection(.visit)
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title2)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Merge to Visit")
                                    .font(.headline)
                                Text("Choose a location point for the visit")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Merge Items")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Cancel") { dismiss() })
            .alert("Non-Contiguous Items", isPresented: $showNonContiguousWarning) {
                Button("Continue Anyway") {
                    // The last tapped button type needs to be tracked
                    // We'll use a small trick: store the pending type
                    onSelect(pendingMergeType)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The selected items are not next to each other in the timeline. Merging them may result in a non-chronological timeline order.")
            }
        }
    }

    // Track which merge type was last tapped for the warning flow
    @State private var pendingMergeType: MergeTargetType = .track

    private func handleMergeSelection(_ type: MergeTargetType) {
        pendingMergeType = type
        if !isContiguous {
            showNonContiguousWarning = true
        } else {
            onSelect(type)
        }
    }
}

// MARK: - Merge Location Picker (for Visit merge)

struct MergeLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [TimelineObject]
    let onSelect: (GPXWaypoint) -> Void

    @State private var selectedPointIndex: Int? = nil
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var candidatePoints: [(point: GPXWaypoint, label: String, isWaypoint: Bool)] {
        var results: [(point: GPXWaypoint, label: String, isWaypoint: Bool)] = []

        // Waypoints first
        for item in items where item.type == .waypoint {
            for point in item.points {
                let name = item.name ?? "Unknown Place"
                results.append((point: point, label: name, isWaypoint: true))
            }
        }

        // Then track points
        for item in items where item.type == .track {
            for point in item.points {
                let timeStr = point.time.map { formatDateToHoursMinutes($0) } ?? ""
                let label = "\(item.trackType?.capitalized ?? "Track") point \(timeStr)"
                results.append((point: point, label: label, isWaypoint: false))
            }
        }

        return results
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Map preview
                Map(position: $cameraPosition) {
                    ForEach(Array(candidatePoints.enumerated()), id: \.offset) { index, candidate in
                        if let lat = candidate.point.latitude, let lon = candidate.point.longitude {
                            let coord = CoordinateConverter.forMapDisplay(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            if index == selectedPointIndex {
                                Annotation("Selected", coordinate: coord) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white)
                                        Circle()
                                            .fill(Color.blue)
                                            .padding(3)
                                    }
                                    .frame(width: 24, height: 24)
                                }
                            }
                        }
                    }
                }
                .frame(height: 200)

                List {
                    Section("Choose Visit Location") {
                        ForEach(Array(candidatePoints.enumerated()), id: \.offset) { index, candidate in
                            Button(action: {
                                selectedPointIndex = index
                                if let lat = candidate.point.latitude, let lon = candidate.point.longitude {
                                    let displayCoord = CoordinateConverter.forMapDisplay(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                    withAnimation {
                                        cameraPosition = .region(MKCoordinateRegion(
                                            center: displayCoord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                        ))
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: candidate.isWaypoint ? "mappin.circle.fill" : "circle.fill")
                                        .foregroundColor(candidate.isWaypoint ? .orange : .blue)
                                        .font(.caption)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.label)
                                            .foregroundColor(.primary)
                                        if let lat = candidate.point.latitude, let lon = candidate.point.longitude {
                                            Text(String(format: "%.5f, %.5f", lat, lon))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if let time = candidate.point.time {
                                            Text(formatDateToHoursMinutes(time))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if index == selectedPointIndex {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .listRowBackground(index == selectedPointIndex ? Color.blue.opacity(0.1) : Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Next") {
                    if let index = selectedPointIndex {
                        onSelect(candidatePoints[index].point)
                    }
                }
                .disabled(selectedPointIndex == nil)
            )
            .onAppear {
                // Auto-select first waypoint if available
                if let firstWaypointIndex = candidatePoints.firstIndex(where: { $0.isWaypoint }) {
                    selectedPointIndex = firstWaypointIndex
                }

                // Center map on all points
                let allCoords = candidatePoints.compactMap { candidate -> CLLocationCoordinate2D? in
                    guard let lat = candidate.point.latitude, let lon = candidate.point.longitude else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                if !allCoords.isEmpty {
                    let displayCoords = CoordinateConverter.forMapDisplay(allCoords)
                    let span = calculateSpan(for: displayCoords)
                    let center = displayCoords[displayCoords.count / 2]
                    cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                }
            }
        }
    }
}

// MARK: - Merge Helpers

struct MergeHelpers {

    /// Check if selected items are contiguous in the timeline.
    static func areItemsContiguous(selectedIDs: Set<UUID>, allItems: [TimelineObject]) -> Bool {
        let selectedIndices = allItems.enumerated()
            .filter { selectedIDs.contains($0.element.id) }
            .map { $0.offset }

        guard selectedIndices.count > 1 else { return true }

        let sorted = selectedIndices.sorted()
        for i in 1..<sorted.count {
            if sorted[i] != sorted[i - 1] + 1 {
                return false
            }
        }
        return true
    }

    /// Build a merged track from selected timeline objects.
    /// All points are combined into a single track with one segment, sorted chronologically.
    static func buildMergedTrack(from items: [TimelineObject]) -> GPXTrack {
        let track = GPXTrack()
        let segment = GPXTrackSegment()

        // Collect all points from all items, sorted by time
        var allPoints: [GPXWaypoint] = []
        for item in items {
            allPoints.append(contentsOf: item.points)
        }
        allPoints.sort { ($0.time ?? Date.distantPast) < ($1.time ?? Date.distantPast) }

        for point in allPoints {
            let trackPoint = GPXTrackPoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
            trackPoint.elevation = point.elevation
            trackPoint.time = point.time
            trackPoint.extensions = GPXUtils.copyExtensions(point.extensions)
            segment.add(trackpoint: trackPoint)
        }

        track.add(trackSegment: segment)

        // Use the track type of the track with the most points
        let trackItems = items.filter { $0.type == .track }
        if let largestTrack = trackItems.max(by: { $0.points.count < $1.points.count }) {
            track.type = largestTrack.trackType
        } else {
            track.type = "walking"
        }

        return track
    }

    /// Build a TimelineObject wrapping a merged track, for use with EditTrackView.
    static func buildMergedTrackTimelineObject(from items: [TimelineObject]) -> TimelineObject {
        let mergedTrack = buildMergedTrack(from: items)
        let allPoints = mergedTrack.segments.flatMap { $0.points }
        let startDate = allPoints.first?.time
        let endDate = allPoints.last?.time

        var totalDistance: Double = 0
        var totalSteps = 0
        for i in 1..<allPoints.count {
            let prev = CLLocation(latitude: allPoints[i-1].latitude ?? 0, longitude: allPoints[i-1].longitude ?? 0)
            let curr = CLLocation(latitude: allPoints[i].latitude ?? 0, longitude: allPoints[i].longitude ?? 0)
            totalDistance += prev.distance(from: curr)
        }
        for point in allPoints {
            totalSteps += Int(point.extensions?["Steps"].text ?? "0") ?? 0
        }

        let duration: String
        if let start = startDate, let end = endDate {
            duration = calculateDuration(from: start, to: end)
        } else {
            duration = ""
        }

        let avgSpeed: Double
        if let start = startDate, let end = endDate, end.timeIntervalSince(start) > 0 {
            avgSpeed = (totalDistance / 1000) / (end.timeIntervalSince(start) / 3600)
        } else {
            avgSpeed = 0
        }

        let coordinates = allPoints.compactMap { point -> CLLocationCoordinate2D? in
            guard let lat = point.latitude, let lon = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        let waypoints = allPoints.map { GPXUtils.deepCopyPoint($0) }

        return TimelineObject(
            type: .track,
            startDate: startDate,
            endDate: endDate,
            trackType: mergedTrack.type ?? "walking",
            duration: duration,
            steps: totalSteps,
            meters: Int(totalDistance),
            numberOfPoints: allPoints.count,
            averageSpeed: avgSpeed,
            coordinates: [IdentifiableCoordinates(coordinates: coordinates)],
            points: waypoints,
            track: mergedTrack
        )
    }

    /// Build a TimelineObject wrapping a merged waypoint for use with EditVisitView.
    static func buildMergedVisitTimelineObject(at point: GPXWaypoint, from items: [TimelineObject]) -> TimelineObject {
        let mergedPoint = GPXUtils.deepCopyAsWaypoint(point)

        let earliestTime = items.compactMap { $0.startDate }.min()
        if let earliestTime = earliestTime {
            mergedPoint.time = earliestTime
        }

        var totalSteps = 0
        if SettingsManager.shared.mergeVisitAddSteps {
            for item in items {
                totalSteps += item.steps
            }
            if totalSteps > 0 {
                var newExtData = [String: String]()
                if let existing = mergedPoint.extensions {
                    for child in existing.children {
                        if child.name != "Steps", let text = child.text {
                            newExtData[child.name] = text
                        }
                    }
                }
                newExtData["Steps"] = String(totalSteps)
                let newExtensions = GPXExtensions()
                newExtensions.append(at: nil, contents: newExtData)
                mergedPoint.extensions = newExtensions
            }
        } else {
            totalSteps = Int(mergedPoint.extensions?["Steps"].text ?? "0") ?? 0
        }

        let coordinate = CLLocationCoordinate2D(
            latitude: mergedPoint.latitude ?? 0,
            longitude: mergedPoint.longitude ?? 0
        )

        return TimelineObject(
            type: .waypoint,
            startDate: mergedPoint.time,
            endDate: mergedPoint.time,
            name: mergedPoint.name,
            steps: totalSteps,
            coordinates: [IdentifiableCoordinates(coordinates: [coordinate])],
            points: [mergedPoint]
        )
    }

    /// Collect all waypoints and tracks from selected timeline objects for deletion.
    static func collectItemsForDeletion(from items: [TimelineObject]) -> (waypoints: [GPXWaypoint], tracks: [GPXTrack]) {
        var waypoints: [GPXWaypoint] = []
        var tracks: [GPXTrack] = []

        for item in items {
            if item.type == .waypoint {
                waypoints.append(contentsOf: item.points)
            } else if item.type == .track, let track = item.track {
                tracks.append(track)
            }
        }

        return (waypoints, tracks)
    }
}
