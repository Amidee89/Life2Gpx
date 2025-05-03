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

        FileManagerUtil.logData(context: "GPXManager", content: "Saving GPX data to \(fileName). Waypoints: \(waypoints.count), Tracks: \(tracks.count)")

        let gpx = GPXRoot(creator: "Life2Gpx App")
        waypoints.forEach { gpx.add(waypoint: $0) }
        tracks.forEach { gpx.add(track: $0) }

        do {
            let gpxString = gpx.gpx() // Serialize the GPXRoot object to a GPX format string
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            FileManagerUtil.logData(context: "GPXManager", content: "GPX data saved successfully to \(fileName).")
        } catch {
            print("Error writing GPX file: \(error)")
            FileManagerUtil.logData(context: "GPXManager", content: "Error writing GPX file \(fileName): \(error.localizedDescription)")
        }
    }

    // Loads GPX file and returns CoreGPX objects
    func loadFile(forDate date: Date, completion: @escaping ([GPXWaypoint], [GPXTrack]) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forName: fileName)
        print(fileURL.path) //when we need to find current data folder for simulator
        FileManagerUtil.logData(context: "GPXManager", content: "Loading GPX file: \(fileName)")

        guard let gpx = GPXParser(withURL: fileURL)?.parsedData() else {
            FileManagerUtil.logData(context: "GPXManager", content: "Failed to load or parse GPX file: \(fileName). Returning empty data.")
            completion([], []) // File does not exist or can't be parsed
            return
        }
        FileManagerUtil.logData(context: "GPXManager", content: "Successfully loaded and parsed GPX file: \(fileName). Waypoints: \(gpx.waypoints.count), Tracks: \(gpx.tracks.count)")
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
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        FileManagerUtil.logData(context: "GPXManager", content: "Checking existence for file: \(fileName). Exists: \(exists)")
        return exists
    }
    func getDateRange(completion: @escaping (Date?, Date?) -> Void) {
        FileManagerUtil.logData(context: "GPXManager", content: "Getting date range from documents directory.")
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)

        let dates = files?.compactMap { fileURL -> Date? in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = fileURL.deletingPathExtension().lastPathComponent
            return dateFormatter.date(from: dateString)
        }

        FileManagerUtil.logData(context: "GPXManager", content: "Found \(dates?.count ?? 0) potential date files.")
        let sortedDates = dates?.sorted()
        let earliestDate = sortedDates?.first
        let latestDate = sortedDates?.last

        DispatchQueue.main.async {
            completion(earliestDate, latestDate)
        }
    }

    func updateWaypoint(originalWaypoint: GPXWaypoint, updatedWaypoint: GPXWaypoint, forDate date: Date) {
        // Load existing GPX file
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to update waypoint for date: \(dateFormatter.string(from: date))")

            // Find the waypoint that matches our original waypoint
            var fileWaypoints = waypoints
            if let index = fileWaypoints.firstIndex(where: { currentFileWaypoint in
                return GPXUtils.arePointsTheSame(currentFileWaypoint, originalWaypoint, confidenceLevel: 5)
            }) {
                fileWaypoints[index] = updatedWaypoint
                FileManagerUtil.logData(context: "GPXManager", content: "Found waypoint at index \(index). Updating.")
                self.saveLocationData(fileWaypoints, tracks: tracks, forDate: date)
            } else {
                print("Waypoint not found")
                FileManagerUtil.logData(context: "GPXManager", content: "Waypoint not found for update.")
            }
        }
    }

    func deleteWaypoint(originalWaypoint: GPXWaypoint, forDate date: Date) {
        // Load existing GPX file
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to delete waypoint for date: \(dateFormatter.string(from: date))")

            // Find and remove the waypoint that matches our original waypoint
            var fileWaypoints = waypoints
            if let index = fileWaypoints.firstIndex(where: { currentFileWaypoint in
                return GPXUtils.arePointsTheSame(currentFileWaypoint, originalWaypoint, confidenceLevel: 5)
            }) {
                fileWaypoints.remove(at: index)
                FileManagerUtil.logData(context: "GPXManager", content: "Found waypoint at index \(index). Deleting.")
                self.saveLocationData(fileWaypoints, tracks: tracks, forDate: date)
            } else {
                print("Waypoint not found for deletion")
                FileManagerUtil.logData(context: "GPXManager", content: "Waypoint not found for deletion.")
            }
        }
    }

    func deleteTrack(originalTrack: GPXTrack, forDate date: Date) {
        // Load existing GPX file
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to delete track for date: \(dateFormatter.string(from: date))")

            // Find and remove the track that matches our original track
            var fileTracks = tracks
            if let index = fileTracks.firstIndex(where: { currentFileTrack in
                // Use confidence level 5 for exact match
                return GPXUtils.areTracksTheSame(currentFileTrack, originalTrack, confidenceLevel: 5)
            }) {
                fileTracks.remove(at: index)
                FileManagerUtil.logData(context: "GPXManager", content: "Found track at index \(index). Deleting.")
                self.saveLocationData(waypoints, tracks: fileTracks, forDate: date)
            } else {
                print("Track not found for deletion")
                FileManagerUtil.logData(context: "GPXManager", content: "Track not found for deletion.")
            }
        }
    }
}
