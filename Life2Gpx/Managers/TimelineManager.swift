import Foundation
import CoreGPX
import CoreLocation



func loadTimelineForDate(_ selectedDate: Date, completion: @escaping ([TimelineObject]) -> Void) {
    let startedAt = Date()
    LogManager.shared.logData(
        context: "TimelineManager",
        content: "loadTimelineForDate started for \(selectedDate). \(ResourceDiagnostics.memorySnapshot()), network={\(NetworkDiagnostics.shared.snapshot())}",
        verbosity: 5
    )
    GPXManager.shared.loadFile(forDate: selectedDate) { gpxWaypoints, gpxTracks in
        var timelineObjects = [TimelineObject]()
        LogManager.shared.logData(
            context: "TimelineManager",
            content: "GPX loaded for \(selectedDate). waypoints=\(gpxWaypoints.count), tracks=\(gpxTracks.count), trackSegments=\(gpxTracks.reduce(0) { $0 + $1.segments.count }), trackPoints=\(gpxTracks.flatMap(\.segments).reduce(0) { $0 + $1.points.count })",
            verbosity: 5
        )
        if gpxWaypoints.isEmpty && gpxTracks.isEmpty {
            LogManager.shared.logData(
                context: "TimelineManager",
                content: "loadTimelineForDate finished empty for \(selectedDate) in \(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s.",
                verbosity: 4
            )
            completion([])
            return
        }

        let updateMode = SettingsManager.shared.updatePlaceInformationMode
        let matchUnknownMode = SettingsManager.shared.matchUnknownPlacesMode

        if updateMode == .always || matchUnknownMode == .always {
            var updatedAny = false
            for waypoint in gpxWaypoints {
                if updateMode == .always,
                   let matchingPlace = GPXUtils.getMatchingPlace(for: waypoint),
                   GPXUtils.isWaypointPlaceInfoOutdated(waypoint, matchingPlace: matchingPlace) {
                    _ = GPXUtils.updateWaypointMetadataFromPlace(updatedWaypoint: waypoint, place: matchingPlace)
                    updatedAny = true
                }
                
                if matchUnknownMode == .always,
                   let lat = waypoint.latitude, let lon = waypoint.longitude {
                    let placeId = waypoint.extensions?["PlaceId"].text
                    if placeId == nil || placeId!.isEmpty {
                        if let matchingPlace = PlaceManager.shared.findPlacesAtCoordinates(for: CLLocationCoordinate2D(latitude: lat, longitude: lon)).first {
                            _ = GPXUtils.updateWaypointMetadataFromPlace(updatedWaypoint: waypoint, place: matchingPlace)
                            updatedAny = true
                        }
                    }
                }
            }

            if updatedAny {
                LogManager.shared.logData(context: "TimelineManager", content: "Auto-updated place info / matched unknown places on file open for \(selectedDate). Saving GPX.", verbosity: 3)
                GPXManager.shared.saveLocationData(gpxWaypoints, tracks: gpxTracks, forDate: selectedDate)
            }
        }

        var allCoordinates = [GPXPointProtocol]()
        allCoordinates.append(contentsOf: gpxWaypoints)
        for track in gpxTracks {
            for segment in track.segments {
                allCoordinates.append(contentsOf: segment.points)
            }
        }

        allCoordinates.sort { $0.time ?? Date.distantPast < $1.time ?? Date.distantPast }

        let allPlaces = PlaceManager.shared.getAllPlaces()

        let waypointObjects = gpxWaypoints.map { waypoint -> TimelineObject in
            let coordinate = CLLocationCoordinate2D(latitude: waypoint.latitude ?? 0, longitude: waypoint.longitude ?? 0)
            
            var icon: String? = nil
            if let waypointPlaceId = waypoint.extensions?["PlaceId"].text {
                if let matchingPlace = allPlaces.first(where: { $0.placeId == waypointPlaceId }) {
                    icon = matchingPlace.customIcon
                }
            }
            
            return TimelineObject(
                type: .waypoint,
                startDate: waypoint.time,
                endDate: waypoint.time,
                name: waypoint.name,
                steps: Int(waypoint.extensions?["Steps"].text ?? "0") ?? 0,
                coordinates: [IdentifiableCoordinates(coordinates: [coordinate])],
                points: [waypoint as GPXWaypoint],
                customIcon: icon
            )
        }
        timelineObjects.append(contentsOf: waypointObjects)

        for track in gpxTracks {
            var steps = 0
            var totalDistanceMeters: Double = 0
            var trackCoordinates = track.segments.flatMap { $0.points }.map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) }
            let numberOfPoints = trackCoordinates.count

            var extensionToPrevious: [CLLocationCoordinate2D]? = nil
            var extensionToNext: [CLLocationCoordinate2D]? = nil
            let connectMode = SettingsManager.shared.visuallyConnectTracksMode

            if let firstTrackPoint = track.segments.first?.points.first {
                if let closestPreviousPoint = findClosestPoint(to: firstTrackPoint, in: allCoordinates, before: true) {
                    if connectMode == .solid {
                        trackCoordinates.insert(CLLocationCoordinate2D(latitude: closestPreviousPoint.latitude!, longitude: closestPreviousPoint.longitude!), at: 0)
                    } else if connectMode == .transparent {
                        let prevCoord = CLLocationCoordinate2D(latitude: closestPreviousPoint.latitude!, longitude: closestPreviousPoint.longitude!)
                        let firstCoord = CLLocationCoordinate2D(latitude: firstTrackPoint.latitude!, longitude: firstTrackPoint.longitude!)
                        extensionToPrevious = [prevCoord, firstCoord]
                    }
                }
            }

            if let lastTrackPoint = track.segments.last?.points.last {
                if let closestNextPoint = findClosestPoint(to: lastTrackPoint, in: allCoordinates, before: false) {
                    if connectMode == .solid {
                        trackCoordinates.append(CLLocationCoordinate2D(latitude: closestNextPoint.latitude!, longitude: closestNextPoint.longitude!))
                    } else if connectMode == .transparent {
                        let lastCoord = CLLocationCoordinate2D(latitude: lastTrackPoint.latitude!, longitude: lastTrackPoint.longitude!)
                        let nextCoord = CLLocationCoordinate2D(latitude: closestNextPoint.latitude!, longitude: closestNextPoint.longitude!)
                        extensionToNext = [lastCoord, nextCoord]
                    }
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
                extensionToPrevious: extensionToPrevious,
                extensionToNext: extensionToNext,
                points: waypoints,
                track: track
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
        let totalTrackPoints = timelineObjects
            .filter { $0.type == .track }
            .flatMap(\.identifiableCoordinates)
            .reduce(0) { $0 + $1.coordinates.count }
        let executionTime = Date().timeIntervalSince(startedAt)
        LogManager.shared.logData(
            context: "TimelineManager",
            content: "loadTimelineForDate finished for \(selectedDate) in \(String(format: "%.3f", executionTime))s. objects=\(timelineObjects.count), totalTrackPoints=\(totalTrackPoints), \(ResourceDiagnostics.memorySnapshot())",
            verbosity: 4
        )
        ResourceTracker.shared.logResourceEvent(context: "TimelineLoad", executionTime: executionTime)
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
    let totalSeconds = max(0, Int(interval))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%01dh %01dm", hours, minutes)
    } else if minutes > 0 {
        return String(format: "%01dm", minutes)
    } else {
        return String(format: "0m %01ds", seconds)
    }
}

func calculateDistance(from startCoordinate: GPXPointProtocol, to endCoordinate: GPXPointProtocol) -> Double {
    let startLocation = CLLocation(latitude: startCoordinate.latitude ?? 0, longitude: startCoordinate.longitude ?? 0)
    let endLocation = CLLocation(latitude: endCoordinate.latitude ?? 0, longitude: endCoordinate.longitude ?? 0)
    return startLocation.distance(from: endLocation)
}
