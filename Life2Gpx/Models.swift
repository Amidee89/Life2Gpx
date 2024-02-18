//
//  Models.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 17.2.2024.
//

import Foundation

struct Waypoint : Codable {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date
    var magneticVariation: Double?
    var geoidHeight: Double?
    var name: String?
    var comment: String?
    var description: String?
    var source: String?
    var links: [Link]?
    var symbol: String?
    var type: String?
    var fix: String?
    var satellites: Int?
    var horizontalDilutionOfPrecision: Double?
    var verticalDilutionOfPrecision: Double?
    var positionDilutionOfPrecision: Double?
    var ageOfDGPSData: Double?
    var dgpsID: Int?
    var extensions: Extensions?
}
struct Track : Codable {
    var name: String?
    var comment: String?
    var description: String?
    var source: String?
    var links: [Link]?
    var number: Int?
    var type: String?
    var extensions: Extensions?
    var segments: [TrackSegment]
}
struct TrackSegment : Codable {
    var trackPoints: [Waypoint]
    var extensions: Extensions?
}

struct Link : Codable {
    var href: String
    var text: String?
    var type: String?
}

struct Extensions : Codable {
    // Define as needed based on your GPX extensions requirements
}

protocol GPXElement: Codable {}
// Extend Waypoint and Track to conform to GPXElement
extension Waypoint: GPXElement {}
extension Track: GPXElement {}

struct DataContainer: Codable {
    var tracks: [Track] = []
    var waypoints: [Waypoint] = [] // To handle stationary waypoints separately
}
