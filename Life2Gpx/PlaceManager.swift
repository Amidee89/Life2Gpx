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
        places = []
        loadPlaces()
        buildGridIndex()
    }
    
    func getAllPlaces() -> [Place] {
        return places
    }

    private func getPlacesFilePath() -> URL {
        return getDocumentsDirectory().appendingPathComponent("Places/places.json")
    }

    private func loadPlaces() {
        let fileURL = getPlacesFilePath()
        
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
    func getPreviewPlaces() -> [Place] {
        return Place.previewPlaces
    }
    
    private func buildGridIndex() {
        // Clear the existing index first
        gridIndex = [:]
        
        print("\nBuilding grid index for \(places.count) places")
        var cellCounts: [GridCell: Int] = [:]
        
        for place in places {
            let gridCells = gridCellsFor(boundingRect: place.boundingRect)
            for cell in gridCells {
                gridIndex[cell, default: []].append(place)
                cellCounts[cell, default: 0] += 1
            }
        }
        
        // Debug: Print cells with multiple places
        for (cell, count) in cellCounts where count > 1 {
            print("Cell \(cell) contains \(count) places")
            if let placesInCell = gridIndex[cell] {
                for place in placesInCell {
                }
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
    
    func findPlaceAtCoordinates(for coordinate: CLLocationCoordinate2D) -> Place? {
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
    
    func findDuplicatePlaces() -> [(Place, Place)] {
        var duplicates: [(Place, Place)] = []
        var seenPlaces: [String: [Place]] = [:]
        
        // Group places by name
        for place in places {
            seenPlaces[place.name, default: []].append(place)
        }
        
        // Find duplicates with additional heuristic
        for (_, placesWithSameName) in seenPlaces where placesWithSameName.count > 1 {
            for i in 0..<placesWithSameName.count {
                for j in (i + 1)..<placesWithSameName.count {
                    let place1 = placesWithSameName[i]
                    let place2 = placesWithSameName[j]
                    
                    // Check if IDs are different
                    guard place1.placeId != place2.placeId else { continue }
                    
                    // Check if the distance between the two is less than or equal to the larger radius
                    let distance = place1.centerCoordinate.distance(to: place2.centerCoordinate)
                    let maxRadius = max(place1.radius, place2.radius)
                    
                    if distance <= maxRadius {
                        duplicates.append((place1, place2))
                    }
                }
            }
        }
        
        return duplicates
    }

    
    private func gridCellFor(coordinate: CLLocationCoordinate2D) -> GridCell {
        let row = Int(floor(coordinate.latitude / gridCellSize))
        let col = Int(floor(coordinate.longitude / gridCellSize))
        return GridCell(row: row, col: col)
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func checkPlaceValidity(_ place: Place) throws {
        if place.placeId.isEmpty {
            throw PlaceError.invalidPlaceId("Place ID cannot be empty")
        }
        
        if place.name.trim().isEmpty {
            throw PlaceError.invalidName("Place name cannot be empty")
        }
        
        if place.center.latitude < -90 || place.center.latitude > 90 {
            throw PlaceError.invalidLatitude("Latitude must be between -90 and 90")
        }
        
        if place.center.longitude < -180 || place.center.longitude > 180 {
            throw PlaceError.invalidLongitude("Longitude must be between -180 and 180")
        }
    }
    
    func editPlace(original: Place, edited: Place, batch: Bool = false) throws {
        try checkPlaceValidity(edited)
        
        guard let index = places.firstIndex(where: { $0.placeId == original.placeId }) else {
            throw PlaceError.placeNotFound
        }
        
        places[index] = edited
        if !batch {
            try savePlaces()
            buildGridIndex()
        }
    }
    
    private func savePlaces() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let data = try encoder.encode(places)
        let fileURL = getPlacesFilePath()
        
        try data.write(to: fileURL)
    }
    
    func deletePlace(_ place: Place) throws {
        places.removeAll { $0.placeId == place.placeId }
        try savePlaces()
        buildGridIndex()
    }
    
    func addPlace(_ place: Place, batch: Bool = false) throws {
        try checkPlaceValidity(place)
        
        // Check for duplicate ID
        if places.contains(where: { $0.placeId == place.placeId }) {
            throw PlaceError.invalidPlaceId("Place ID already exists")
        }
        
        places.append(place)
        if !batch {
            try savePlaces()
            buildGridIndex()
        }
    }
    
    func saveAllPlaces(_ newPlaces: [Place]) throws {
        places = newPlaces
        try savePlaces()
        buildGridIndex()
    }

    // Add a new method to rebuild indexes after batch operations
    func finalizeBatchOperations() throws {
        try savePlaces()
        buildGridIndex()
    }

    func findClosePlaces(to coordinate: CLLocationCoordinate2D, limit: Int = 10) -> [Place] {
        // First, get the maximum radius among all places to determine search bounds
        let maxRadius = places.map { $0.radius }.max() ?? 1000
        
        // Convert radius from meters to degrees (approximate)
        let radiusDegrees = maxRadius / 111320.0
        
        // Create bounding box
        let searchBounds = BoundingRect(
            minLat: coordinate.latitude - radiusDegrees,
            maxLat: coordinate.latitude + radiusDegrees,
            minLon: coordinate.longitude - radiusDegrees / cos(coordinate.latitude * .pi / 180),
            maxLon: coordinate.longitude + radiusDegrees / cos(coordinate.latitude * .pi / 180)
        )
        
        // Get grid cells that intersect with our search bounds
        let gridCells = gridCellsFor(boundingRect: searchBounds)
        
        // Add debug logging
        print("Total places in manager: \(places.count)")
        print("Grid cells searched: \(gridCells.count)")
        
        // Collect unique places from all relevant grid cells
        var candidatePlaces = Set<Place>()
        for cell in gridCells {
            if let placesInCell = gridIndex[cell] {
                let beforeCount = candidatePlaces.count
                candidatePlaces.formUnion(placesInCell)
                let afterCount = candidatePlaces.count
                if afterCount - beforeCount != placesInCell.count {
                    print("Potential duplicate detected in cell \(cell)")
                }
            }
        }
        
        print("Unique candidates found: \(candidatePlaces.count)")
        
        // Calculate distances and sort
        let placesWithDistances = candidatePlaces.map { place -> (Place, Double) in
            let distance = coordinate.distance(to: place.centerCoordinate)
            return (place, distance)
        }
        print("Found \(placesWithDistances.count) places within \(maxRadius) meters")
        
        // Sort by distance and return the closest ones
        return placesWithDistances
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
}

enum PlaceError: Error {
    case placeNotFound
    case invalidPlaceId(String)
    case invalidName(String)
    case invalidLatitude(String)
    case invalidLongitude(String)
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
