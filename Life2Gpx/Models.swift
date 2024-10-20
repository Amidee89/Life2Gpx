//
//  Models.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 17.2.2024.
//
import SwiftUI
import CoreLocation
import CoreGPX

let trackTypeColorMapping: [String: Color] = [
    "walking": .green,
    "running": .orange,
    "cycling": .red,
    "automotive": .blue,
    "unknown": .purple
]

enum TimelineObjectType {
    case waypoint, track
}

class TimelineObject: Identifiable {
    let id = UUID()
    var type: TimelineObjectType
    var startDate: Date?
    var endDate: Date?
    var trackType: String?
    var name: String?
    var duration: String
    var steps: Int
    var meters: Int
    var numberOfPoints : Int
    var averageSpeed: Double //kmh
    var identifiableCoordinates: [IdentifiableCoordinates]
    var points: [GPXWaypoint]
    var selected: Bool
    
    
    init(type: TimelineObjectType, startDate: Date?, endDate: Date?, trackType: String? = nil, name: String? = nil, duration: String = "", steps: Int = 0, meters: Int = 0, numberOfPoints : Int = 0, averageSpeed : Double = 0, coordinates: [IdentifiableCoordinates] = [], points:[GPXWaypoint]=[]) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.trackType = trackType
        self.name = name
        self.duration = duration
        self.steps = steps
        self.meters = meters
        self.numberOfPoints = numberOfPoints
        self.averageSpeed = averageSpeed
        self.identifiableCoordinates = coordinates
        self.points = points
        self.selected = false
    }
}

struct IdentifiableCoordinates: Identifiable {
    let id = UUID()
    var coordinates: [CLLocationCoordinate2D]
}


struct Place: Identifiable, Codable, Equatable {
    let placeId: String
    let name: String
    let center: Center
    let radius: Double
    let streetAddress: String?
    let secondsFromGMT: Int?
    let lastSaved: String?
    var id: String { placeId }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
    }
}


extension Place {
    var centerCoordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
    }

    // Helper to compute the bounding rectangle of the place
    var boundingRect: BoundingRect {
        let radiusDegrees = radius / 111320.0 // Approximate conversion from meters to degrees latitude
        let minLat = center.latitude - radiusDegrees
        let maxLat = center.latitude + radiusDegrees
        let minLon = center.longitude - radiusDegrees / cos(center.latitude * .pi / 180)
        let maxLon = center.longitude + radiusDegrees / cos(center.latitude * .pi / 180)
        return BoundingRect(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
}

struct Center: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct BoundingRect {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

protocol GPXPointProtocol {
    var latitude: Double? { get }
    var longitude: Double? { get }
    var time: Date? { get }
}

extension GPXWaypoint: GPXPointProtocol {}
extension GPXTrackPoint: GPXPointProtocol {}

class ManagePlacesViewModel: ObservableObject {
    @Published var places: [Place] = []
    
    init() {
        loadPlaces()
    }
    
    private func loadPlaces() {
        places = PlaceManager.shared.getAllPlaces()
    }
}
