//
//  PlaceManager.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 18.10.2024.
//

import Foundation
import CoreLocation

class PlaceManager {
    static let shared = PlaceManager()
    
    private var places: [Place] = []
    private var gridIndex: [GridCell: [Place]] = [:]
    private let gridCellSize = 0.1 // Adjust grid cell size as needed
    
    private init() {
        loadPlaces()
        buildGridIndex()
    }
    func reloadPlaces() {
        loadPlaces()
        buildGridIndex()
    }
    
    func getAllPlaces() -> [Place] {
        return places
    }

    private func loadPlaces() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("places.json")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            print("Failed to load places.json")
            return
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase // Adjust if your JSON uses snake_case
        do {
            places = try decoder.decode([Place].self, from: data)
        } catch {
            print("Failed to decode places.json: \(error)")
        }
    }
    
    private func buildGridIndex() {
        for place in places {
            let gridCells = gridCellsFor(boundingRect: place.boundingRect)
            for cell in gridCells {
                gridIndex[cell, default: []].append(place)
            }
        }
    }
    
    private func gridCellsFor(boundingRect: BoundingRect) -> [GridCell] {
        let minRow = Int(floor(boundingRect.minLat / gridCellSize))
        let maxRow = Int(floor(boundingRect.maxLat / gridCellSize))
        let minCol = Int(floor(boundingRect.minLon / gridCellSize))
        let maxCol = Int(floor(boundingRect.maxLon / gridCellSize))
        
        var cells: [GridCell] = []
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                cells.append(GridCell(row: row, col: col))
            }
        }
        return cells
    }
    
    func findPlace(for coordinate: CLLocationCoordinate2D) -> Place? {
        let cell = gridCellFor(coordinate: coordinate)
        guard let candidates = gridIndex[cell] else {
            return nil
        }
        for place in candidates {
            let distance = coordinate.distance(to: place.centerCoordinate)
            if distance <= place.radius {
                return place
            }
        }
        return nil
    }
    
    
    private func gridCellFor(coordinate: CLLocationCoordinate2D) -> GridCell {
        let row = Int(floor(coordinate.latitude / gridCellSize))
        let col = Int(floor(coordinate.longitude / gridCellSize))
        return GridCell(row: row, col: col)
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct GridCell: Hashable {
    let row: Int
    let col: Int
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }
}
