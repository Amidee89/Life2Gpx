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


struct Place: Identifiable, Codable, Equatable, Hashable {
    let placeId: String
    let name: String
    let center: Center
    let radius: Double
    let streetAddress: String?
    let secondsFromGMT: Int?
    let lastSaved: String?
    let facebookPlaceId: String?
    let mapboxPlaceId: String?
    let foursquareVenueId: String?
    let foursquareCategoryId: String?
    let previousIds: [String?]?
    let lastVisited: Date?
    let isFavorite: Bool?
    let customIcon: String?
    var id: String { placeId }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
    }

    // Create a mutable copy for editing
    struct EditableCopy {
        var placeId: String
        var name: String
        var center: Center
        var radius: Double
        var streetAddress: String?
        var secondsFromGMT: Int?
        var lastSaved: String?
        var facebookPlaceId: String?
        var mapboxPlaceId: String?
        var foursquareVenueId: String?
        var foursquareCategoryId: String?
        var previousIds: [String?]?
        var lastVisited: Date?
        var isFavorite: Bool?
        var customIcon: String?
        
        init(from place: Place) {
            self.placeId = place.placeId
            self.name = place.name
            self.center = place.center
            self.radius = place.radius
            self.streetAddress = place.streetAddress
            self.secondsFromGMT = place.secondsFromGMT
            self.lastSaved = place.lastSaved
            self.facebookPlaceId = place.facebookPlaceId
            self.mapboxPlaceId = place.mapboxPlaceId
            self.foursquareVenueId = place.foursquareVenueId
            self.foursquareCategoryId = place.foursquareCategoryId
            self.previousIds = place.previousIds
            self.lastVisited = place.lastVisited
            self.isFavorite = place.isFavorite
            self.customIcon = place.customIcon
        }
        
        func toPlace() -> Place {
            Place(
                placeId: placeId,
                name: name,
                center: center,
                radius: radius,
                streetAddress: streetAddress,
                secondsFromGMT: secondsFromGMT,
                lastSaved: lastSaved,
                facebookPlaceId: facebookPlaceId,
                mapboxPlaceId: mapboxPlaceId,
                foursquareVenueId: foursquareVenueId,
                foursquareCategoryId: foursquareCategoryId,
                previousIds: previousIds,
                lastVisited: lastVisited,
                isFavorite: isFavorite,
                customIcon: customIcon
            )
        }
    }

    // Add hash function
    func hash(into hasher: inout Hasher) {
        hasher.combine(placeId)  // Since placeId is unique, we can just hash that
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
           #if DEBUG
           if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
               // Load preview data
               places = PlaceManager.shared.getPreviewPlaces()
               return
           }
           #endif
           loadPlaces()
       }
       

    init(places: [Place]) {
        self.places = places
    }
    
    func loadPlaces() {
        places = PlaceManager.shared.getAllPlaces()
    }
    // Static mock data for previews
    static var preview: ManagePlacesViewModel {
        
        let mockPlaces = [
            Place(placeId: "1", 
                 name: "Central Park", 
                 center: Center(latitude: 40.785091, longitude: -73.968285), 
                 radius: 200, 
                 streetAddress: "New York, NY", 
                 secondsFromGMT: -18000, 
                 lastSaved: "2024-10-18", 
                 facebookPlaceId: nil, 
                 mapboxPlaceId: nil, 
                 foursquareVenueId: nil, 
                 foursquareCategoryId: nil, 
                 previousIds: [nil],
                 lastVisited: nil,
                 isFavorite: nil,
                 customIcon: nil),
            Place(placeId: "2", 
                 name: "Golden Gate Park", 
                 center: Center(latitude: 37.769421, longitude: -122.486214), 
                 radius: 300, 
                 streetAddress: "San Francisco, CA", 
                 secondsFromGMT: -28800, 
                 lastSaved: "2024-10-19", 
                 facebookPlaceId: "goldengatepark.sanfrancisco", 
                 mapboxPlaceId: nil, 
                 foursquareVenueId: "445e36bff964a520fb321fe3", 
                 foursquareCategoryId: "16032", 
                 previousIds: [nil],
                 lastVisited: nil,
                 isFavorite: nil,
                 customIcon: nil),
            Place(placeId: "3", 
                 name: "Golden Gate Park", 
                 center: Center(latitude: 37.769521, longitude: -122.486214), 
                 radius: 200, 
                 streetAddress: "San Francisco, CA", 
                 secondsFromGMT: -28800, 
                 lastSaved: "2024-10-19", 
                 facebookPlaceId: "goldengatepark.sanfrancisco", 
                 mapboxPlaceId: nil, 
                 foursquareVenueId: "445e36bff964a520fb321fe3", 
                 foursquareCategoryId: "16032", 
                 previousIds: [nil],
                 lastVisited: nil,
                 isFavorite: nil,
                 customIcon: nil)
        ]
        return ManagePlacesViewModel(places: mockPlaces)
    }
}

extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TimerEntry: Identifiable {
    let id: String
    let duration: TimeInterval
    let parent: String?
    
    init(operation: String, duration: TimeInterval, parent: String? = nil) {
        self.id = operation
        self.duration = duration
        self.parent = parent
    }
}

class PerformanceTimer {
    private struct Measurement {
        let duration: TimeInterval
        let parent: String?
    }
    
    private var measurements: [String: Measurement] = [:]
    
    func addTime(_ operation: String, _ duration: TimeInterval, parent: String? = nil) {
        measurements[operation] = Measurement(duration: duration + (measurements[operation]?.duration ?? 0), parent: parent)
    }
    
    var entries: [TimerEntry] {
        measurements.map { TimerEntry(operation: $0.key, duration: $0.value.duration, parent: $0.value.parent) }
            .sorted { $0.duration > $1.duration }
    }
}
