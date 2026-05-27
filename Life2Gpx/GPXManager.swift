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

    func saveLocationData(_ waypoints: [GPXWaypoint], tracks: [GPXTrack], forDate date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.fileURL(forDate: date)

        FileManagerUtil.logData(context: "GPXManager", content: "Saving GPX data to \(fileName). Waypoints: \(waypoints.count), Tracks: \(tracks.count)", verbosity: 4)

        let gpx = GPXRoot(creator: "Life2Gpx App")
        waypoints.forEach { gpx.add(waypoint: $0) }
        tracks.forEach { gpx.add(track: $0) }

        do {
            let fileManager = FileManager.default
            let parentDir = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            let gpxString = gpx.gpx()
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            FileManagerUtil.logData(context: "GPXManager", content: "GPX data saved successfully to \(fileName).", verbosity: 3)
        } catch {
            print("Error writing GPX file: \(error)")
            FileManagerUtil.logData(context: "GPXManager", content: "Error writing GPX file \(fileName): \(error.localizedDescription)", verbosity: 1)
        }
    }
    
    func loadFile(forDate date: Date, completion: @escaping ([GPXWaypoint], [GPXTrack]) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileURL = self.resolvedFileURL(forDate: date)
        print(fileURL.path)
        FileManagerUtil.logData(context: "GPXManager", content: "Loading GPX file: \(fileName)", verbosity: 4)

        guard let gpx = GPXParser(withURL: fileURL)?.parsedData() else {
            FileManagerUtil.logData(context: "GPXManager", content: "Failed to load or parse GPX file: \(fileName). Returning empty data.", verbosity: 2)
            completion([], [])
            return
        }
        FileManagerUtil.logData(context: "GPXManager", content: "Successfully loaded and parsed GPX file: \(fileName). Waypoints: \(gpx.waypoints.count), Tracks: \(gpx.tracks.count)", verbosity: 3)
        completion(gpx.waypoints, gpx.tracks)
    }

    /// Canonical path for new writes: Gpx/year/yyyy-MM-dd.gpx
    private func fileURL(forDate date: Date) -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let year = String(Calendar.current.component(.year, from: date))
        return documentsURL.appendingPathComponent("Gpx/\(year)/\(fileName)")
    }
    
    /// Resolves actual file location: checks new path first, falls back to root for unmigrated files
    func resolvedFileURL(forDate date: Date) -> URL {
        let newPath = fileURL(forDate: date)
        if FileManager.default.fileExists(atPath: newPath.path) {
            return newPath
        }
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let legacyPath = documentsURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: legacyPath.path) {
            return legacyPath
        }
        return newPath
    }
    
    func fileExists(forDate date: Date) -> Bool {
        let resolved = self.resolvedFileURL(forDate: date)
        let exists = FileManager.default.fileExists(atPath: resolved.path)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        FileManagerUtil.logData(context: "GPXManager", content: "Checking existence for file: \(dateFormatter.string(from: date)).gpx. Exists: \(exists)", verbosity: 5)
        return exists
    }
    func getDateRange(completion: @escaping (Date?, Date?) -> Void) {
        FileManagerUtil.logData(context: "GPXManager", content: "Getting date range from Gpx directory.", verbosity: 4)
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let gpxBaseURL = documentsURL.appendingPathComponent("Gpx")
        
        var allDates: [Date] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        if let yearFolders = try? fileManager.contentsOfDirectory(at: gpxBaseURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for yearFolder in yearFolders {
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: yearFolder.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }
                
                if let files = try? fileManager.contentsOfDirectory(at: yearFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                    for file in files where file.pathExtension.lowercased() == "gpx" {
                        let dateString = file.deletingPathExtension().lastPathComponent
                        if let date = dateFormatter.date(from: dateString) {
                            allDates.append(date)
                        }
                    }
                }
            }
        }
        
        // Also check root for legacy files that haven't been organized yet
        if let rootFiles = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for file in rootFiles where file.pathExtension.lowercased() == "gpx" {
                let dateString = file.deletingPathExtension().lastPathComponent
                if let date = dateFormatter.date(from: dateString) {
                    allDates.append(date)
                }
            }
        }

        FileManagerUtil.logData(context: "GPXManager", content: "Found \(allDates.count) potential date files.", verbosity: 4)
        let sortedDates = allDates.sorted()
        let earliestDate = sortedDates.first
        let latestDate = sortedDates.last

        DispatchQueue.main.async {
            completion(earliestDate, latestDate)
        }
    }

    func updateWaypoint(originalWaypoint: GPXWaypoint, updatedWaypoint: GPXWaypoint, forDate date: Date) {
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to update waypoint for date: \(dateFormatter.string(from: date))", verbosity: 4)

            var fileWaypoints = waypoints
            if let index = fileWaypoints.firstIndex(where: { currentFileWaypoint in
                return GPXUtils.arePointsTheSame(currentFileWaypoint, originalWaypoint, confidenceLevel: 5)
            }) {
                fileWaypoints[index] = updatedWaypoint
                FileManagerUtil.logData(context: "GPXManager", content: "Found waypoint at index \(index). Updating.", verbosity: 3)
                self.saveLocationData(fileWaypoints, tracks: tracks, forDate: date)
            } else {
                print("Waypoint not found")
                FileManagerUtil.logData(context: "GPXManager", content: "Waypoint not found for update.", verbosity: 2)
            }
        }
    }

    func deleteWaypoint(originalWaypoint: GPXWaypoint, forDate date: Date) {
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to delete waypoint for date: \(dateFormatter.string(from: date))", verbosity: 4)

            var fileWaypoints = waypoints
            if let index = fileWaypoints.firstIndex(where: { currentFileWaypoint in
                return GPXUtils.arePointsTheSame(currentFileWaypoint, originalWaypoint, confidenceLevel: 5)
            }) {
                fileWaypoints.remove(at: index)
                FileManagerUtil.logData(context: "GPXManager", content: "Found waypoint at index \(index). Deleting.", verbosity: 3)
                self.saveLocationData(fileWaypoints, tracks: tracks, forDate: date)
            } else {
                print("Waypoint not found for deletion")
                FileManagerUtil.logData(context: "GPXManager", content: "Waypoint not found for deletion.", verbosity: 2)
            }
        }
    }

    func deleteTrack(originalTrack: GPXTrack, forDate date: Date) {
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to delete track for date: \(dateFormatter.string(from: date))", verbosity: 4)

            var fileTracks = tracks
            if let index = fileTracks.firstIndex(where: { currentFileTrack in
                return GPXUtils.areTracksTheSame(currentFileTrack, originalTrack, confidenceLevel: 5)
            }) {
                fileTracks.remove(at: index)
                FileManagerUtil.logData(context: "GPXManager", content: "Found track at index \(index). Deleting.", verbosity: 3)
                self.saveLocationData(waypoints, tracks: fileTracks, forDate: date)
            } else {
                print("Track not found for deletion")
                FileManagerUtil.logData(context: "GPXManager", content: "Track not found for deletion.", verbosity: 2)
            }
        }
    }

    func updateTrack(originalTrack: GPXTrack, updatedTrack: GPXTrack, forDate date: Date) {
        loadFile(forDate: date) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            FileManagerUtil.logData(context: "GPXManager", content: "Attempting to update track for date: \(dateFormatter.string(from: date))", verbosity: 4)

            var fileTracks = tracks
            if let index = fileTracks.firstIndex(where: { currentFileTrack in
                return GPXUtils.areTracksTheSame(currentFileTrack, originalTrack, confidenceLevel: 5)
            }) {
                fileTracks[index] = updatedTrack
                FileManagerUtil.logData(context: "GPXManager", content: "Found track at index \(index). Updating.", verbosity: 3)
                self.saveLocationData(waypoints, tracks: fileTracks, forDate: date)
            } else {
                print("Track not found for update")
                FileManagerUtil.logData(context: "GPXManager", content: "Track not found for update.", verbosity: 2)
            }
        }
    }
}
