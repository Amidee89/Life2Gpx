//
//  GPXManager.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 18.2.2024.
//

import Foundation
import CoreLocation

class GPXManager {
    static let shared = GPXManager()

    private init() {}

    func saveLocationData(_ dataContainer: DataContainer, forDate date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).json"
        let fileURL = self.fileURL(forName: fileName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(dataContainer)
            try data.write(to: fileURL, options: [.atomicWrite])
            print("Location data saved successfully.")
        } catch {
            print("Error writing to JSON file: \(error)")
        }
    }

    func loadFile(forDate date: Date, completion: @escaping (DataContainer?) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).json"
        let fileURL = self.fileURL(forName: fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(nil) // File does not exist for the given date
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let dataContainer = try decoder.decode(DataContainer.self, from: data)
            completion(dataContainer)
        } catch {
            print("Error reading JSON file: \(error)")
            completion(nil)
        }
    }

    private func fileURL(forName fileName: String) -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(fileName)
    }
}
