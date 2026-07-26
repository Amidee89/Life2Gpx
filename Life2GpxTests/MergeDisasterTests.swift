import XCTest
@testable import Life2Gpx
import CoreGPX

final class MergeDisasterTests: XCTestCase {
    func testMergeDuplicates() throws {
        let expectation = self.expectation(description: "Merge Completes")
        
        let url = URL(fileURLWithPath: "/Users/marcocarandente/Documents/Personal/Life2Gpx/Life2Gpx/Life2Gpx/Logs/2026-06-10-before.gpx")
        guard let gpx = GPXParser(withURL: url)?.parsedData() else {
            XCTFail("Failed to parse")
            return
        }
        
        // 1. Simulate TimelineManager loading objects
        var timelineObjects = [TimelineObject]()
        for track in gpx.tracks {
            let pts = track.segments.flatMap { $0.points }.map { GPXUtils.deepCopyPoint($0) }
            let trackObject = TimelineObject(
                type: .track,
                startDate: pts.first?.time,
                endDate: pts.last?.time,
                points: pts,
                track: track
            )
            timelineObjects.append(trackObject)
        }
        
        // 2. Select items (e.g. tracks from index 0 to 19)
        let selectedItems = Array(timelineObjects[0..<19])
        
        // 3. Build merged track
        let mergedTrack = MergeItemsView.buildMergedTrack(from: selectedItems)
        
        // 4. Verify duplicates in merged track
        let mergedPts = mergedTrack.segments.flatMap { $0.points }
        let uniqueTimes = Set(mergedPts.compactMap { $0.time })
        print("MERGED TRACK: \(mergedPts.count) points, \(uniqueTimes.count) unique")
        
        XCTAssertEqual(mergedPts.count, uniqueTimes.count, "Duplicates found in a single pass!")
        
        expectation.fulfill()
        waitForExpectations(timeout: 5, handler: nil)
    }
}
