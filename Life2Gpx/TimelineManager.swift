//
//  TimelineManager.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 28.3.2024.
//

import Foundation
import CoreGPX
import CoreLocation

func loadTimelineForDate (_ selectedDate: Date, completion: @escaping ([TimelineObject]) -> Void){
    GPXManager.shared.loadFile(forDate: selectedDate) { gpxWaypoints, gpxTracks in
        var timelineObjects = [TimelineObject]()
        if gpxWaypoints.isEmpty && gpxTracks.isEmpty {
            completion([])
            return
        }
        let waypointObjects = gpxWaypoints.map { waypoint -> TimelineObject in
            let coordinate = CLLocationCoordinate2D(latitude: waypoint.latitude ?? 0, longitude: waypoint.longitude ?? 0)
            return TimelineObject(
                type: .waypoint,
                startDate: waypoint.time,
                endDate: waypoint.time,
                name: waypoint.name,
                steps: Int(waypoint.extensions?["Steps"].text ?? "0") ?? 0,
                coordinates: [IdentifiableCoordinates(coordinates: [coordinate])]
            )
        }
        timelineObjects.append(contentsOf: waypointObjects)
        
        for (index, track) in gpxTracks.enumerated() {
            var steps = 0
            var totalDistanceMeters: Double = 0
            var trackCoordinates = track.segments.flatMap { $0.points }.map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) }
            let numberOfPoints = trackCoordinates.count
            
            // Check if this is not the last track and append the first point of the next track if necessary; TODO: also include stops
            if index < gpxTracks.count - 1 {
                let nextTrackFirstPoint = gpxTracks[index + 1].segments.first?.points.first
                if let nextTrackFirstCoordinate = nextTrackFirstPoint {
                    trackCoordinates.append(CLLocationCoordinate2D(latitude: nextTrackFirstCoordinate.latitude!, longitude: nextTrackFirstCoordinate.longitude!))
                }
            }
            let trackStartDate = track.segments.first?.points.first?.time ?? Date()
            let trackEndDate = track.segments.last?.points.last?.time ?? trackStartDate
            for trackSegment in track.segments {
                for (index, trackPoint) in trackSegment.points.enumerated()
                {
                    if index < trackSegment.points.count - 1 {
                        totalDistanceMeters += calculateDistance(from: trackPoint, to: trackSegment.points[index+1])
                    }
                    steps += Int(trackPoint.extensions?["Steps"].text ?? "0") ?? 0
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
                coordinates: [IdentifiableCoordinates(coordinates: trackCoordinates)]
            )
            timelineObjects.append(trackObject)
        }
        timelineObjects = timelineObjects.sorted(by: { $0.startDate ?? Date.distantPast < $1.startDate ?? Date.distantPast })
        for (index, item) in timelineObjects.enumerated() {
            if item.type == .waypoint{
                if index + 1 < timelineObjects.count {
                    item.endDate = timelineObjects[index + 1].startDate
                } else
                {
                    item.endDate = adjustDateToEndOfDayIfNeeded(date: Date(), comparedToDate: selectedDate)
                }
            }
            if item.startDate != nil && item.endDate != nil
            {
                
                item.duration = calculateDuration (from: item.startDate!, to: item.endDate!)
            }
        }
        completion(timelineObjects)
        return
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
    if (hours > 0){
        return String(format: "%01dh %01dm", hours, minutes)
    }else{
        return String(format: "%01dm",  minutes)

    }
}

func calculateDistance(from startCoordinate: GPXTrackPoint, to endCoordinate: GPXTrackPoint) -> Double {
    let startLocation = CLLocation(latitude: startCoordinate.latitude ?? 0, longitude: startCoordinate.longitude ?? 0)
    let endLocation = CLLocation(latitude: endCoordinate.latitude ?? 0, longitude: endCoordinate.longitude ?? 0)
    return startLocation.distance(from: endLocation) // Returns distance in meters
}
