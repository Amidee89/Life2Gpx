//
//  GPXManager.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 18.2.2024.
//

import Foundation
import CoreGPX

class GPXManager {
    static let shared = GPXManager()

    private init() {}

    func saveLocationData(_ dataContainer: DataContainer, forDate date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forName: fileName)

        let gpx = GPXRoot(creator: "Life2Gpx App")
        dataContainer.waypoints.forEach { waypoint in
            let gpxWaypoint = GPXWaypoint(latitude: waypoint.latitude, longitude: waypoint.longitude)
            gpxWaypoint.elevation = waypoint.elevation
            gpxWaypoint.time = waypoint.time
            // Add additional waypoint details here
            gpx.add(waypoint: gpxWaypoint)
        }

        dataContainer.tracks.forEach { track in
            let gpxTrack = GPXTrack()
            track.segments.forEach { segment in
                let gpxSegment = GPXTrackSegment()
                segment.trackPoints.forEach { trackPoint in
                    let gpxTrackPoint = GPXTrackPoint(latitude: trackPoint.latitude, longitude: trackPoint.longitude)
                    gpxTrackPoint.elevation = trackPoint.elevation
                    gpxTrackPoint.time = trackPoint.time
                    // Add additional track point details here
                    gpxSegment.add(trackpoint: gpxTrackPoint)
                }
                gpxTrack.add(trackSegment: gpxSegment)
            }
            gpx.add(track: gpxTrack)
        }

        do {
            let gpxString = gpx.gpx() // Serialize the GPXRoot object to a GPX format string
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("GPX data saved successfully.")
        } catch {
            print("Error writing GPX file: \(error)")
        }
        print("GPX data saved successfully.")
        
    }

    func loadFile(forDate date: Date, completion: @escaping (DataContainer?) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forName: fileName)

        guard let gpx = GPXParser(withPath: fileURL.path)?.parsedData() else {
            completion(nil) // File does not exist or can't be parsed
            return
        }

        var dataContainer = DataContainer()

        gpx.waypoints.forEach { gpxWaypoint in
            let waypoint = Waypoint(
                latitude: gpxWaypoint.latitude ?? 0,
                longitude: gpxWaypoint.longitude ?? 0,
                elevation: gpxWaypoint.elevation,
                time: gpxWaypoint.time ?? Date()
                // Map other details as necessary
            )
            dataContainer.waypoints.append(waypoint)
        }

        gpx.tracks.forEach { gpxTrack in
            var track = Track(segments: [])
            gpxTrack.segments.forEach { gpxSegment in
                var segment = TrackSegment(trackPoints: [])
                gpxSegment.points.forEach { gpxTrackPoint in
                    let trackPoint = Waypoint(
                        latitude: gpxTrackPoint.latitude ?? 0,
                        longitude: gpxTrackPoint.longitude ?? 0,
                        elevation: gpxTrackPoint.elevation,
                        time: gpxTrackPoint.time ?? Date()
                        // Map other details as necessary
                    )
                    segment.trackPoints.append(trackPoint)
                }
                track.segments.append(segment)
            }
            dataContainer.tracks.append(track)
        }

        completion(dataContainer)
    }

    private func fileURL(forName fileName: String) -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(fileName)
    }
}

