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

    func testAutomotiveDefaultRuleSpeedCondition() {
        let rules = ActivityRulesManager.shared.rules
        guard let automotiveRule = rules.first(where: { $0.resultingActivityType == "automotive" }) else {
            XCTFail("Automotive rule not found")
            return
        }
        
        let speedCondition = automotiveRule.conditions.first(where: { $0.conditionType == .speed })
        XCTAssertNotNil(speedCondition, "Automotive rule should have a speed condition")
        XCTAssertEqual(speedCondition?.comparisonOperator, .lessThan)
        XCTAssertEqual(speedCondition?.value1, "150")
    }

    func testNotifyOfSavedUnknownTrackTypesDefault() {
        XCTAssertTrue(SettingsManager.shared.notifyOfSavedUnknownTrackTypes)
    }

    func testNotificationManagerIsUnknownTrack() {
        let nilTrack = makeTrack(type: nil, pointCount: 1, startingAt: Date())
        XCTAssertTrue(NotificationManager.isUnknownTrack(nilTrack))

        let emptyTrack = makeTrack(type: "", pointCount: 1, startingAt: Date())
        XCTAssertTrue(NotificationManager.isUnknownTrack(emptyTrack))

        let whitespaceTrack = makeTrack(type: "   ", pointCount: 1, startingAt: Date())
        XCTAssertTrue(NotificationManager.isUnknownTrack(whitespaceTrack))

        let unknownTrack = makeTrack(type: "unknown", pointCount: 1, startingAt: Date())
        XCTAssertTrue(NotificationManager.isUnknownTrack(unknownTrack))

        let unknownUpperTrack = makeTrack(type: "UNKNOWN", pointCount: 1, startingAt: Date())
        XCTAssertTrue(NotificationManager.isUnknownTrack(unknownUpperTrack))

        let knownTrack = makeTrack(type: "walking", pointCount: 1, startingAt: Date())
        XCTAssertFalse(NotificationManager.isUnknownTrack(knownTrack))

        let cyclingTrack = makeTrack(type: "cycling", pointCount: 1, startingAt: Date())
        XCTAssertFalse(NotificationManager.isUnknownTrack(cyclingTrack))

        let scooterTrack = makeTrack(type: "scooter", pointCount: 1, startingAt: Date())
        XCTAssertFalse(NotificationManager.isUnknownTrack(scooterTrack))

        let motorcycleTrack = makeTrack(type: "motorcycle", pointCount: 1, startingAt: Date())
        XCTAssertFalse(NotificationManager.isUnknownTrack(motorcycleTrack))
    }

    func testBasicTrackTypesIncludeScooterAndMotorcycleInOrder() {
        let basicTypes = PreferencesManager.shared.trackTypes.filter { $0.category == .basic }
        let basicIds = basicTypes.map { $0.id.lowercased() }
        
        XCTAssertTrue(basicIds.contains("scooter"), "Basic track types should contain scooter")
        XCTAssertTrue(basicIds.contains("motorcycle"), "Basic track types should contain motorcycle")

        guard let cyclingIndex = basicIds.firstIndex(of: "cycling"),
              let scooterIndex = basicIds.firstIndex(of: "scooter"),
              let automotiveIndex = basicIds.firstIndex(of: "automotive"),
              let motorcycleIndex = basicIds.firstIndex(of: "motorcycle") else {
            XCTFail("Missing basic track types")
            return
        }

        XCTAssertEqual(scooterIndex, cyclingIndex + 1, "Scooter should be immediately after cycling")
        XCTAssertEqual(motorcycleIndex, automotiveIndex + 1, "Motorcycle should be immediately after automotive")
    }

    func testCalculateDuration() {
        let base = Date(timeIntervalSince1970: 1_000_000)

        // Under 1 minute
        XCTAssertEqual(calculateDuration(from: base, to: base), "0m 0s")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(1)), "0m 1s")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(45)), "0m 45s")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(59)), "0m 59s")

        // 1 minute to under 60 minutes
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(60)), "1m")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(75)), "1m")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(300)), "5m")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(3599)), "59m")

        // 60 minutes and above
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(3600)), "1h 0m")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(3660)), "1h 1m")
        XCTAssertEqual(calculateDuration(from: base, to: base.addingTimeInterval(7320)), "2h 2m")
    }

    func testNextMidnightSchedulingCalculation() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 23
        components.hour = 23
        components.minute = 57
        components.second = 0
        
        let now = calendar.date(from: components)!
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            XCTFail("Failed to get startOfTomorrow")
            return
        }
        
        let timeIntervalUntilMidnight = startOfTomorrow.timeIntervalSince(now)
        let gracePeriod: TimeInterval = 10
        let adjustedInterval = max(1.0, timeIntervalUntilMidnight + gracePeriod)
        
        // 3 minutes (180s) + 10s = 190s
        XCTAssertEqual(timeIntervalUntilMidnight, 180, accuracy: 0.001)
        XCTAssertEqual(adjustedInterval, 190, accuracy: 0.001)
        
        // Fire time should be 00:00:10 of the next day
        let fireDate = now.addingTimeInterval(adjustedInterval)
        let fireComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        XCTAssertEqual(fireComponents.year, 2026)
        XCTAssertEqual(fireComponents.month, 8)
        XCTAssertEqual(fireComponents.day, 24)
        XCTAssertEqual(fireComponents.hour, 0)
        XCTAssertEqual(fireComponents.minute, 0)
        XCTAssertEqual(fireComponents.second, 10)
    }

    func testMidnightUpdateClampingDoesNotUsePreviousDay() {
        let calendar = Calendar.current
        var todayComponents = DateComponents()
        todayComponents.year = 2026
        todayComponents.month = 8
        todayComponents.day = 24
        todayComponents.hour = 0
        todayComponents.minute = 0
        todayComponents.second = 10
        let todayDate = calendar.date(from: todayComponents)!
        let startOfToday = calendar.startOfDay(for: todayDate)

        // Previous day timestamp (e.g. 23:57 of Aug 23)
        var staleComponents = DateComponents()
        staleComponents.year = 2026
        staleComponents.month = 8
        staleComponents.day = 23
        staleComponents.hour = 23
        staleComponents.minute = 57
        staleComponents.second = 0
        let staleLocationTimestamp = calendar.date(from: staleComponents)!

        // Midnight update explicitly sets Date()
        let midnightUpdateWaypoint = GPXWaypoint(latitude: 40.0, longitude: 10.0)
        let isMidnightUpdate = true
        if isMidnightUpdate {
            midnightUpdateWaypoint.time = todayDate
        } else {
            midnightUpdateWaypoint.time = max(staleLocationTimestamp, startOfToday)
        }

        XCTAssertEqual(midnightUpdateWaypoint.time, todayDate)
        XCTAssertGreaterThanOrEqual(midnightUpdateWaypoint.time!, startOfToday)
        XCTAssertEqual(calendar.component(.day, from: midnightUpdateWaypoint.time!), 24)

        // Non-midnight update with stale timestamp is clamped to startOfToday
        let fallbackWaypoint = GPXWaypoint(latitude: 40.0, longitude: 10.0)
        fallbackWaypoint.time = max(staleLocationTimestamp, startOfToday)
        XCTAssertEqual(fallbackWaypoint.time, startOfToday)
        XCTAssertEqual(calendar.component(.day, from: fallbackWaypoint.time!), 24)
    }

    func testNotificationManagerIsUnknownPlace() {
        let nilExtWaypoint = GPXWaypoint(latitude: 40.0, longitude: 10.0)
        XCTAssertTrue(NotificationManager.isUnknownPlace(nilExtWaypoint))

        let emptyPlaceIdWaypoint = GPXWaypoint(latitude: 40.0, longitude: 10.0)
        GPXUtils.updateExtension(for: emptyPlaceIdWaypoint, with: ["PlaceId": ""])
        XCTAssertTrue(NotificationManager.isUnknownPlace(emptyPlaceIdWaypoint))

        let rejectedPlaceIdWaypoint = GPXWaypoint(latitude: 40.0, longitude: 10.0)
        GPXUtils.updateExtension(for: rejectedPlaceIdWaypoint, with: ["PlaceId": "-1"])
        XCTAssertTrue(NotificationManager.isUnknownPlace(rejectedPlaceIdWaypoint))

        let knownPlaceWaypoint = GPXWaypoint(latitude: 40.0, longitude: 10.0)
        GPXUtils.updateExtension(for: knownPlaceWaypoint, with: ["PlaceId": "place_abc123"])
        XCTAssertFalse(NotificationManager.isUnknownPlace(knownPlaceWaypoint))
    }

    func testFormatActivityRecapMessageSingularPlural() {
        let msgZero = NotificationManager.formatActivityRecapMessage(placesCount: 0, activities: [], totalSteps: 0)
        XCTAssertEqual(msgZero, "You visited 0 places, and walked 0 steps.")

        let msgOne = NotificationManager.formatActivityRecapMessage(placesCount: 1, activities: [], totalSteps: 1)
        XCTAssertEqual(msgOne, "You visited 1 place, and walked 1 step.")

        let msgPlural = NotificationManager.formatActivityRecapMessage(placesCount: 2, activities: [], totalSteps: 500)
        XCTAssertEqual(msgPlural, "You visited 2 places, and walked 500 steps.")
    }

    func testFormatActivityRecapMessageWithActivitiesAndLimiting() {
        let activities: [(type: String, meters: Double)] = [
            ("automotive", 14500),
            ("walking", 3200)
        ]
        let msg = NotificationManager.formatActivityRecapMessage(placesCount: 3, activities: activities, totalSteps: 4120)
        XCTAssertEqual(msg, "You visited 3 places, automotive 14.5 km, walking 3.2 km, and walked 4120 steps.")

        let singleActivity: [(type: String, meters: Double)] = [
            ("cycling", 8000)
        ]
        let msgSingle = NotificationManager.formatActivityRecapMessage(placesCount: 1, activities: singleActivity, totalSteps: 1200)
        XCTAssertEqual(msgSingle, "You visited 1 place, cycling 8 km, and walked 1200 steps.")

        // Test limiting to top 3 biggest activities
        let manyActivities: [(type: String, meters: Double)] = [
            ("walking", 3000),
            ("cycling", 12000),
            ("automotive", 45000),
            ("running", 5000),
            ("scooter", 1500)
        ]
        let msgMany = NotificationManager.formatActivityRecapMessage(placesCount: 5, activities: manyActivities, totalSteps: 10000)
        XCTAssertEqual(msgMany, "You visited 5 places, automotive 45 km, cycling 12 km, running 5 km, and walked 10000 steps.")

        // Test filtering out sub-100m drift
        let tinyActivities: [(type: String, meters: Double)] = [
            ("walking", 50),
            ("automotive", 30)
        ]
        let msgTiny = NotificationManager.formatActivityRecapMessage(placesCount: 1, activities: tinyActivities, totalSteps: 100)
        XCTAssertEqual(msgTiny, "You visited 1 place, and walked 100 steps.")
    }

    func testFormatUnknownItemsRecapMessageSingularPlural() {
        let msg11 = NotificationManager.formatUnknownItemsRecapMessage(unknownPlacesCount: 1, unknownTracksCount: 1)
        XCTAssertEqual(msg11, "You've been to 1 unknown place and there is 1 unknown type track today.")

        let msg12 = NotificationManager.formatUnknownItemsRecapMessage(unknownPlacesCount: 1, unknownTracksCount: 2)
        XCTAssertEqual(msg12, "You've been to 1 unknown place and there are 2 unknown type tracks today.")

        let msg21 = NotificationManager.formatUnknownItemsRecapMessage(unknownPlacesCount: 2, unknownTracksCount: 1)
        XCTAssertEqual(msg21, "You've been to 2 unknown places and there is 1 unknown type track today.")

        let msg00 = NotificationManager.formatUnknownItemsRecapMessage(unknownPlacesCount: 0, unknownTracksCount: 0)
        XCTAssertEqual(msg00, "You've been to 0 unknown places and there are 0 unknown type tracks today.")

        let msg35 = NotificationManager.formatUnknownItemsRecapMessage(unknownPlacesCount: 3, unknownTracksCount: 5)
        XCTAssertEqual(msg35, "You've been to 3 unknown places and there are 5 unknown type tracks today.")
    }

    func testDailyRecapSettingsDefaults() {
        XCTAssertFalse(SettingsManager.shared.dailyActivityRecapEnabled)
        XCTAssertFalse(SettingsManager.shared.dailyUnknownItemsRecapEnabled)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: SettingsManager.shared.dailyActivityRecapTime), 21)
        XCTAssertEqual(calendar.component(.minute, from: SettingsManager.shared.dailyActivityRecapTime), 30)

        XCTAssertEqual(calendar.component(.hour, from: SettingsManager.shared.dailyUnknownItemsRecapTime), 21)
        XCTAssertEqual(calendar.component(.minute, from: SettingsManager.shared.dailyUnknownItemsRecapTime), 30)
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
