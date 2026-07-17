//
//  Life2GpxTests.swift
//  Life2GpxTests
//
//  Created by Marco Carandente on 28.1.2024.
//

import XCTest
import CoreGPX
@testable import Life2Gpx

final class Life2GpxTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testAutomaticTrackMergerMergesUnknownTrackAtInclusivePointLimit() {
        let start = Date(timeIntervalSince1970: 1_000)
        let unknownTrack = makeTrack(type: nil, pointCount: 2, startingAt: start)
        let knownTrack = makeTrack(type: "automotive", pointCount: 3, startingAt: start.addingTimeInterval(10))
        var tracks = [unknownTrack, knownTrack]

        let result = AutomaticTrackMerger.mergePreviousUnknownTrackIfEligible(
            tracks: &tracks,
            waypoints: [makeWaypoint(at: start.addingTimeInterval(-10))],
            maximumUnknownPoints: 2,
            minimumKnownPoints: 3
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].type, "automotive")
        XCTAssertEqual(tracks[0].segments.flatMap(\.points).count, 5)
        XCTAssertEqual(tracks[0].segments.first?.points.first?.time, start)
    }

    func testAutomaticTrackMergerWaitsForKnownTrackMinimum() {
        let start = Date(timeIntervalSince1970: 1_000)
        var tracks = [
            makeTrack(type: "unknown", pointCount: 2, startingAt: start),
            makeTrack(type: "walking", pointCount: 2, startingAt: start.addingTimeInterval(10))
        ]

        let result = AutomaticTrackMerger.mergePreviousUnknownTrackIfEligible(
            tracks: &tracks,
            waypoints: [],
            maximumUnknownPoints: 2,
            minimumKnownPoints: 3
        )

        XCTAssertNil(result)
        XCTAssertEqual(tracks.count, 2)
    }

    func testAutomaticTrackMergerKeepsUnknownTrackAboveMaximum() {
        let start = Date(timeIntervalSince1970: 1_000)
        var tracks = [
            makeTrack(type: "Unknown", pointCount: 3, startingAt: start),
            makeTrack(type: "cycling", pointCount: 4, startingAt: start.addingTimeInterval(10))
        ]

        let result = AutomaticTrackMerger.mergePreviousUnknownTrackIfEligible(
            tracks: &tracks,
            waypoints: [],
            maximumUnknownPoints: 2,
            minimumKnownPoints: 4
        )

        XCTAssertNil(result)
        XCTAssertEqual(tracks.count, 2)
    }

    func testAutomaticTrackMergerDoesNotMergeAcrossWaypoint() {
        let start = Date(timeIntervalSince1970: 1_000)
        var tracks = [
            makeTrack(type: nil, pointCount: 2, startingAt: start),
            makeTrack(type: "running", pointCount: 4, startingAt: start.addingTimeInterval(10))
        ]

        let result = AutomaticTrackMerger.mergePreviousUnknownTrackIfEligible(
            tracks: &tracks,
            waypoints: [makeWaypoint(at: start.addingTimeInterval(5))],
            maximumUnknownPoints: 2,
            minimumKnownPoints: 4
        )

        XCTAssertNil(result)
        XCTAssertEqual(tracks.count, 2)
    }

    private func makeTrack(type: String?, pointCount: Int, startingAt start: Date) -> GPXTrack {
        let track = GPXTrack()
        track.type = type
        let segment = GPXTrackSegment()
        for index in 0..<pointCount {
            let point = GPXTrackPoint(latitude: Double(index), longitude: Double(index))
            point.time = start.addingTimeInterval(Double(index))
            segment.add(trackpoint: point)
        }
        track.add(trackSegment: segment)
        return track
    }

    private func makeWaypoint(at time: Date) -> GPXWaypoint {
        let waypoint = GPXWaypoint(latitude: 0, longitude: 0)
        waypoint.time = time
        return waypoint
    }

}
