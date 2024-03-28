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
    
    init(type: TimelineObjectType, startDate: Date?, endDate: Date?, trackType: String? = nil, name: String? = nil, duration: String = "", steps: Int = 0, meters: Int = 0, numberOfPoints : Int = 0, averageSpeed : Double = 0, coordinates: [IdentifiableCoordinates] = []) {
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
    }
}

struct IdentifiableCoordinates: Identifiable {
    let id = UUID()
    var coordinates: [CLLocationCoordinate2D]
}
