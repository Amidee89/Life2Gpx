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

    // Saves locations directly using CoreGPX models
    func saveLocationData(_ waypoints: [GPXWaypoint], tracks: [GPXTrack], forDate date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forName: fileName)

        let gpx = GPXRoot(creator: "Life2Gpx App")
        waypoints.forEach { gpx.add(waypoint: $0) }
        tracks.forEach { gpx.add(track: $0) }

        do {
            let gpxString = gpx.gpx() // Serialize the GPXRoot object to a GPX format string
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("GPX data saved successfully.")
        } catch {
            print("Error writing GPX file: \(error)")
        }
    }

    // Loads GPX file and returns CoreGPX objects
    func loadFile(forDate date: Date, completion: @escaping ([GPXWaypoint], [GPXTrack]) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forName: fileName)
        print(fileURL.path) //when we need to find current data folder for simulator
        guard let gpx = GPXParser(withURL: fileURL)?.parsedData() else {
            completion([], []) // File does not exist or can't be parsed
            return
        }
        completion(gpx.waypoints, gpx.tracks)
    }

    private func fileURL(forName fileName: String) -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(fileName)
    }
    
    func fileExists(forDate date: Date) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forName: fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    func getDateRange(completion: @escaping (Date?, Date?) -> Void) {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)

        let dates = files?.compactMap { fileURL -> Date? in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = fileURL.deletingPathExtension().lastPathComponent
            return dateFormatter.date(from: dateString)
        }

        let sortedDates = dates?.sorted()
        let earliestDate = sortedDates?.first
        let latestDate = sortedDates?.last

        DispatchQueue.main.async {
            completion(earliestDate, latestDate)
        }
    }

    func updateWaypoint(forDate date: Date, timelineObject: TimelineObject, with place: Place?) {
        // Load existing GPX file
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            
            // Find the waypoint that matches our timelineObject
            var updatedWaypoints = waypoints
            if let originalWaypoint = timelineObject.points.first,
               let index = updatedWaypoints.firstIndex(where: { waypoint in
                   // Match by multiple criteria to ensure we find the correct waypoint
                   let timeMatch = waypoint.time == originalWaypoint.time
                   let latMatch = abs((waypoint.latitude ?? 0) - (originalWaypoint.latitude ?? 0)) < 0.0000001
                   let lonMatch = abs((waypoint.longitude ?? 0) - (originalWaypoint.longitude ?? 0)) < 0.0000001
                   let nameMatch = waypoint.name == originalWaypoint.name
                   let elevationMatch = abs((waypoint.elevation ?? 0) - (originalWaypoint.elevation ?? 0)) < 0.0000001
                   
                   // Consider it a match if most criteria match (at least 3 out of 5)
                   let matchCount = [timeMatch, latMatch, lonMatch, nameMatch, elevationMatch]
                       .filter { $0 }
                       .count
                   return matchCount >= 3
               }) {
                let waypoint = updatedWaypoints[index]
                
                // Update waypoint time if it changed
                waypoint.time = timelineObject.startDate
                
                if let place = place {
                    // Update waypoint with place data
                    waypoint.name = place.name
                    
                    // Create extensions dictionary with place metadata
                    var extensionData: [String: String] = [
                        "PlaceId": place.placeId
                    ]
                    
                    // Add optional metadata if available
                    if let address = place.streetAddress {
                        extensionData["Address"] = address
                    }
                    if let fbId = place.facebookPlaceId {
                        extensionData["FacebookPlaceId"] = fbId
                    }
                    if let mapboxId = place.mapboxPlaceId {
                        extensionData["MapboxPlaceId"] = mapboxId
                    }
                    if let foursquareId = place.foursquareVenueId {
                        extensionData["FoursquareVenueId"] = foursquareId
                    }
                    if let categoryId = place.foursquareCategoryId {
                        extensionData["FoursquareCategoryId"] = categoryId
                    }
                    
                    let extensions = GPXExtensions()
                    extensions.append(at: nil, contents: extensionData)
                    waypoint.extensions = extensions
                } 
                self.saveLocationData(updatedWaypoints, tracks: tracks, forDate: date)
            }
        }
    }
}
