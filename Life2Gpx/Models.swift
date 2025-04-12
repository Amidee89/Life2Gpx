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
    var numberOfPoints: Int
    var averageSpeed: Double //kmh
    var identifiableCoordinates: [IdentifiableCoordinates]
    var points: [GPXWaypoint]
    var selected: Bool
    var customIcon: String?
    var track: GPXTrack?
    
    init(type: TimelineObjectType, 
         startDate: Date?, 
         endDate: Date?, 
         trackType: String? = nil, 
         name: String? = nil, 
         duration: String = "", 
         steps: Int = 0, 
         meters: Int = 0, 
         numberOfPoints: Int = 0, 
         averageSpeed: Double = 0, 
         coordinates: [IdentifiableCoordinates] = [], 
         points: [GPXWaypoint] = [], 
         customIcon: String? = nil,
         track: GPXTrack? = nil) { 
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
        self.customIcon = customIcon
        self.track = track
    }

    private static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    static let previewTrack: TimelineObject = {
        // Create multiple sets of coordinates for different segments
        let segment1Coordinates = [
            CLLocationCoordinate2D(latitude: 40.785091, longitude: -73.968285),
            CLLocationCoordinate2D(latitude: 40.786091, longitude: -73.969285),
            CLLocationCoordinate2D(latitude: 40.787091, longitude: -73.970285),
            CLLocationCoordinate2D(latitude: 40.788091, longitude: -73.971285),
            CLLocationCoordinate2D(latitude: 40.789091, longitude: -73.972285)
        ]
        
        let segment2Coordinates = [
            CLLocationCoordinate2D(latitude: 40.789091, longitude: -73.972285),
            CLLocationCoordinate2D(latitude: 40.789591, longitude: -73.973785),
            CLLocationCoordinate2D(latitude: 40.790091, longitude: -73.975285),
            CLLocationCoordinate2D(latitude: 40.790591, longitude: -73.976785)
        ]
        
        let segment3Coordinates = [
            CLLocationCoordinate2D(latitude: 40.790591, longitude: -73.976785),
            CLLocationCoordinate2D(latitude: 40.791091, longitude: -73.976285),
            CLLocationCoordinate2D(latitude: 40.791591, longitude: -73.975785),
            CLLocationCoordinate2D(latitude: 40.792091, longitude: -73.975285),
            CLLocationCoordinate2D(latitude: 40.792591, longitude: -73.974785),
            CLLocationCoordinate2D(latitude: 40.793091, longitude: -73.974285)
        ]
        
        let allCoordinates = [segment1Coordinates, segment2Coordinates, segment3Coordinates]
        let identifiableCoordinates = allCoordinates.map { IdentifiableCoordinates(coordinates: $0) }
        
        let startTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        // Create GPX track with multiple segments
        let track = GPXTrack()
        track.name = "Preview Track"
        
        // Create all waypoints for the flat list
        var allPoints: [GPXWaypoint] = []
        
        // Create segments with points at 15-second intervals
        var currentTime = startTime
        for (segmentIndex, segmentCoords) in allCoordinates.enumerated() {
            let segment = GPXTrackSegment()
            
            for (pointIndex, coord) in segmentCoords.enumerated() {
                // Add some variation to elevation
                let elevation = 100.0 + Double(segmentIndex * 10) + sin(Double(pointIndex) * 0.5) * 5.0
                
                // Create track point for the segment
                let trackPoint = GPXTrackPoint(latitude: coord.latitude, longitude: coord.longitude)
                trackPoint.time = currentTime
                trackPoint.elevation = elevation
                segment.add(trackpoint: trackPoint)
                
                // Create corresponding waypoint for the flat list
                let waypoint = GPXWaypoint(latitude: coord.latitude, longitude: coord.longitude)
                waypoint.time = currentTime
                waypoint.elevation = elevation
                allPoints.append(waypoint)
                
                // Advance time by 15 seconds for each point
                currentTime = currentTime.addingTimeInterval(15)
            }
            
            track.add(trackSegment: segment)
            
            // Add a small gap between segments
            currentTime = currentTime.addingTimeInterval(60)
        }
        
        let totalPoints = allPoints.count
        let totalDuration = currentTime.timeIntervalSince(startTime)
        let formattedDuration = formatDuration(seconds: Int(totalDuration))
        
        return TimelineObject(
            type: .track,
            startDate: startTime,
            endDate: currentTime,
            trackType: "walking",
            name: "Preview Track",
            duration: formattedDuration,
            steps: 1200,
            meters: 3500,
            numberOfPoints: totalPoints,
            averageSpeed: 3.5,
            coordinates: identifiableCoordinates,
            points: allPoints,
            track: track
        )
    }()
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
    let elevation: Double?
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
        var elevation: Double?

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
            self.elevation = place.elevation
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
                customIcon: customIcon,
                elevation: elevation
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
            self.places = Place.previewPlaces
            return
        }
        #endif
        loadPlaces()
    }
    
    init(places: [Place]) {
        self.places = places
    }
    
    func loadPlaces() {
        // Only load from PlaceManager if not in preview mode
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            places = PlaceManager.shared.getAllPlaces()
        }
        #else
        places = PlaceManager.shared.getAllPlaces()
        #endif
    }

    // Single source of truth for preview data
    static var preview: ManagePlacesViewModel {
        let viewModel = ManagePlacesViewModel()
        viewModel.places = Place.previewPlaces
        return viewModel
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

extension Place {
    static let previewPlaces: [Place] = [
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
             customIcon: nil,
             elevation: 45.0),
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
             customIcon: nil,
             elevation: nil),
        Place(placeId: "3", 
             name: "Golden Gate Park", 
             center: Center(latitude: 37.769421, longitude: -122.486314), 
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
             customIcon: nil,
             elevation: 30.5)
    ]
    
    static let previewPlace: Place = previewPlaces[0]
}
