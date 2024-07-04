import Foundation
import CoreGPX
import CoreLocation



func loadTimelineForDate(_ selectedDate: Date, completion: @escaping ([TimelineObject]) -> Void) {
    GPXManager.shared.loadFile(forDate: selectedDate) { gpxWaypoints, gpxTracks in
        var timelineObjects = [TimelineObject]()
        if gpxWaypoints.isEmpty && gpxTracks.isEmpty {
            completion([])
            return
        }

        // Flatten and sort all waypoints and track points
        var allCoordinates = [GPXPointProtocol]()
        allCoordinates.append(contentsOf: gpxWaypoints)
        for track in gpxTracks {
            for segment in track.segments {
                allCoordinates.append(contentsOf: segment.points)
            }
        }

        allCoordinates.sort { $0.time ?? Date.distantPast < $1.time ?? Date.distantPast }

        let waypointObjects = gpxWaypoints.map { waypoint -> TimelineObject in
            let coordinate = CLLocationCoordinate2D(latitude: waypoint.latitude ?? 0, longitude: waypoint.longitude ?? 0)
            return TimelineObject(
                type: .waypoint,
                startDate: waypoint.time,
                endDate: waypoint.time,
                name: waypoint.name,
                steps: Int(waypoint.extensions?["Steps"].text ?? "0") ?? 0,
                coordinates: [IdentifiableCoordinates(coordinates: [coordinate])],
                points: [waypoint as GPXWaypoint]
            )
        }
        timelineObjects.append(contentsOf: waypointObjects)

        for track in gpxTracks {
            var steps = 0
            var totalDistanceMeters: Double = 0
            var trackCoordinates = track.segments.flatMap { $0.points }.map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) }
            let numberOfPoints = trackCoordinates.count

            // Add the closest point to the beginning of the track
            if let firstTrackPoint = track.segments.first?.points.first {
                if let closestPreviousPoint = findClosestPoint(to: firstTrackPoint, in: allCoordinates, before: true) {
                    trackCoordinates.insert(CLLocationCoordinate2D(latitude: closestPreviousPoint.latitude!, longitude: closestPreviousPoint.longitude!), at: 0)
                }
            }

            // Add the closest point to the end of the track
            if let lastTrackPoint = track.segments.last?.points.last {
                if let closestNextPoint = findClosestPoint(to: lastTrackPoint, in: allCoordinates, before: false) {
                    trackCoordinates.append(CLLocationCoordinate2D(latitude: closestNextPoint.latitude!, longitude: closestNextPoint.longitude!))
                }
            }

            let trackStartDate = track.segments.first?.points.first?.time ?? Date()
            let trackEndDate = track.segments.last?.points.last?.time ?? trackStartDate
            var waypoints: [GPXWaypoint] = []
            for trackSegment in track.segments {
                for (index, trackPoint) in trackSegment.points.enumerated() {
                    if index < trackSegment.points.count - 1 {
                        totalDistanceMeters += calculateDistance(from: trackPoint, to: trackSegment.points[index + 1])
                    }
                    steps += Int(trackPoint.extensions?["Steps"].text ?? "0") ?? 0
                    waypoints.append(trackPoint)
                }
            }
            let averageSpeed = (totalDistanceMeters / 1000) / (trackEndDate.timeIntervalSince(trackStartDate) / 3600)
            let trackObject = TimelineObject(
                type: .track,
                startDate: trackStartDate,
                endDate: trackEndDate,
                trackType: track.type,
                steps: steps,
                meters: Int(totalDistanceMeters),
                numberOfPoints: numberOfPoints,
                averageSpeed: averageSpeed,
                coordinates: [IdentifiableCoordinates(coordinates: trackCoordinates)],
                points: waypoints
            )
            timelineObjects.append(trackObject)
        }

        timelineObjects = timelineObjects.sorted(by: { $0.startDate ?? Date.distantPast < $1.startDate ?? Date.distantPast })

        for (index, item) in timelineObjects.enumerated() {
            if item.type == .waypoint {
                if index + 1 < timelineObjects.count {
                    item.endDate = timelineObjects[index + 1].startDate
                } else {
                    item.endDate = adjustDateToEndOfDayIfNeeded(date: Date(), comparedToDate: selectedDate)
                }
            }
            if item.startDate != nil && index + 1 < timelineObjects.count {
                item.duration = calculateDuration(from: item.startDate!, to: timelineObjects[index + 1].startDate!)
            } else if (item.startDate != nil && item.endDate != nil) {
                item.duration = calculateDuration(from: item.startDate!, to: item.endDate!)
            }
        }
        completion(timelineObjects)
        return
    }
}

func findClosestPoint(to point: GPXPointProtocol, in points: [GPXPointProtocol], before: Bool) -> GPXPointProtocol? {
    let sortedPoints = points.sorted { $0.time ?? Date.distantPast < $1.time ?? Date.distantPast }
    if before {
        return sortedPoints.last { $0.time ?? Date.distantFuture < point.time ?? Date.distantPast }
    } else {
        return sortedPoints.first { $0.time ?? Date.distantPast > point.time ?? Date.distantFuture }
    }
}

func adjustDateToEndOfDayIfNeeded(date: Date, comparedToDate selectedDate: Date) -> Date {
    let calendar = Calendar.current
    if !calendar.isDate(date, inSameDayAs: selectedDate) {
        // If the date is not in the same day as selectedDate, adjust to end of selectedDate
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        dateComponents.hour = 23
        dateComponents.minute = 59
        dateComponents.second = 59
        return calendar.date(from: dateComponents) ?? date
    }
    return date
}

func calculateDuration(from startDate: Date, to endDate: Date) -> String {
    let interval = endDate.timeIntervalSince(startDate)
    let hours = Int(interval) / 3600 // Total seconds divided by number of seconds in an hour
    let minutes = Int(interval) % 3600 / 60 // Remainder of the above division, divided by number of seconds in a minute
    if (hours > 0) {
        return String(format: "%01dh %01dm", hours, minutes)
    } else {
        return String(format: "%01dm", minutes)
    }
}

func calculateDistance(from startCoordinate: GPXPointProtocol, to endCoordinate: GPXPointProtocol) -> Double {
    let startLocation = CLLocation(latitude: startCoordinate.latitude ?? 0, longitude: startCoordinate.longitude ?? 0)
    let endLocation = CLLocation(latitude: endCoordinate.latitude ?? 0, longitude: endCoordinate.longitude ?? 0)
    return startLocation.distance(from: endLocation) // Returns distance in meters
}
