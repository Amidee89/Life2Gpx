import XCTest
@testable import Life2Gpx
import CoreGPX

final class MergeReplaceTests: XCTestCase {
    func testReplaceItemsAbortsOnMismatch() throws {
        let expectation = self.expectation(description: "Replace Completes")
        
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destURL = documentsDirectory.appendingPathComponent("Life2Gpx").appendingPathComponent("Logs").appendingPathComponent("2026-06-10.gpx")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Copy before.gpx to the mock destination
        let sourceURL = URL(fileURLWithPath: "/Users/marcocarandente/Documents/Personal/Life2Gpx/Life2Gpx/Life2Gpx/Logs/2026-06-10-before.gpx")
        if fileManager.fileExists(atPath: destURL.path) {
            try? fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)
        
        let date = ISO8601DateFormatter().date(from: "2026-06-10T12:00:00Z")!
        
        GPXManager.shared.loadFile(forDate: date) { waypoints, tracks in
            var deleteTracks = Array(tracks[0..<19])
            
            // INTENTIONAL MISMATCH: Modify the time of the first track so areTracksTheSame fails
            if let firstTrack = deleteTracks.first {
                let firstPoint = firstTrack.segments.first?.points.first
                firstPoint?.time = Date()
            }
            
            // Build merged track (won't actually be added because it should abort)
            let mergedTrack = GPXTrack()
            let segment = GPXTrackSegment()
            var allPoints = deleteTracks.flatMap { $0.segments.flatMap { $0.points } }
            for point in allPoints {
                let trackPoint = GPXTrackPoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
                segment.add(trackpoint: trackPoint)
            }
            mergedTrack.add(trackSegment: segment)
            
            GPXManager.shared.replaceItems(
                deleteWaypoints: [],
                deleteTracks: deleteTracks,
                addWaypoint: nil,
                addTrack: mergedTrack,
                forDate: date
            ) { success in
                XCTAssertFalse(success, "Merge should have failed due to mismatch!")
                
                // Read the file and verify it was NOT modified
                guard let gpx = GPXParser(withURL: destURL)?.parsedData() else {
                    XCTFail("Failed to parse saved file")
                    expectation.fulfill()
                    return
                }
                
                XCTAssertEqual(gpx.tracks.count, 38, "File should still have 38 tracks")
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
}
