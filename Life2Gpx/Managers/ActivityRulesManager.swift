import Foundation
import SwiftUI
import CoreGPX
import CoreLocation

class ActivityRulesManager: ObservableObject {
    static let shared = ActivityRulesManager()
    
    @Published var rules: [ActivityRule] {
        didSet { saveRules() }
    }
    
    private let rulesURL: URL
    private let geocoder = CLGeocoder()
    
    private init() {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let preferencesDir = documentsUrl.appendingPathComponent("Preferences")
        self.rulesURL = preferencesDir.appendingPathComponent("activityrules.json")
        
        self.rules = []
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: preferencesDir.path) {
            do {
                try fileManager.createDirectory(at: preferencesDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating preferences directory: \(error)")
            }
        }
        
        loadRules()
    }
    
    private func defaultRules() -> [ActivityRule] {
        let walkingRule = ActivityRule(
            name: "Walking",
            resultingActivityType: "walking",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "walking", value2: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "10")
            ]
        )
        
        let runningRule = ActivityRule(
            name: "Running",
            resultingActivityType: "running",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "running", value2: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "30")
            ]
        )

        let cyclingRule = ActivityRule(
            name: "Cycling",
            resultingActivityType: "cycling",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "cycling", value2: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "80")
            ]
        )
        
        let trainRule = ActivityRule(
            name: "Train",
            resultingActivityType: "train",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "automotive", value2: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .between, value1: "150", value2: "500")
            ]
        )
        
        let planeRule = ActivityRule(
            name: "Plane",
            resultingActivityType: "plane",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .totalDistance, comparisonOperator: .moreThan, value1: "200000"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .moreThan, value1: "550")
            ]
        )

        let automotiveRule = ActivityRule(
            name: "Automotive",
            resultingActivityType: "automotive",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "automotive", value2: "50")
            ]
        )
        
        let boatRule = ActivityRule(
            name: "Boat",
            resultingActivityType: "boat",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .pointsCount, comparisonOperator: .moreThan, value1: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .overWaterPercent, comparisonOperator: .moreThan, value1: "99"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "80")
            ]
        )
        
        return [walkingRule, runningRule, cyclingRule, trainRule, planeRule, automotiveRule, boatRule]
    }
    
    private func loadRules() {
        if let data = try? Data(contentsOf: rulesURL) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([ActivityRule].self, from: data) {
                self.rules = decoded
                return
            }
        }
        self.rules = defaultRules()
        saveRules()
    }
    
    private func saveRules() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(rules) {
            do {
                try data.write(to: rulesURL, options: .atomic)
            } catch {
                print("Failed to save activityrules: \(error)")
            }
        }
    }
    
    func evaluate(track: GPXTrack, previousWaypoint: GPXWaypoint?, nextWaypoint: GPXWaypoint?) async -> String? {
        let activeRules = self.rules.filter { $0.isActive }
        
        for rule in activeRules {
            if await evaluateRule(rule, track: track, previousWaypoint: previousWaypoint, nextWaypoint: nextWaypoint) {
                return rule.resultingActivityType
            }
        }
        
        return nil
    }
    
    func evaluateAndUpdate(track: GPXTrack, previousWaypoint: GPXWaypoint?, nextWaypoint: GPXWaypoint?, date: Date) {
        // Run asynchronously
        Task {
            if let newType = await evaluate(track: track, previousWaypoint: previousWaypoint, nextWaypoint: nextWaypoint) {
                if track.type != newType {
                    track.type = newType
                    GPXManager.shared.updateTrack(originalTrack: track, updatedTrack: track, forDate: date)
                }
            }
        }
    }
    
    private func evaluateRule(_ rule: ActivityRule, track: GPXTrack, previousWaypoint: GPXWaypoint?, nextWaypoint: GPXWaypoint?) async -> Bool {
        guard !rule.conditions.isEmpty else { return false }
        
        var currentResult = false
        
        for (index, condition) in rule.conditions.enumerated() {
            let conditionResult = await evaluateCondition(condition, track: track, previousWaypoint: previousWaypoint, nextWaypoint: nextWaypoint)
            
            if index == 0 {
                currentResult = conditionResult
            } else {
                if condition.logicalOperator == .and {
                    currentResult = currentResult && conditionResult
                } else if condition.logicalOperator == .or {
                    currentResult = currentResult || conditionResult
                }
            }
        }
        
        return currentResult
    }
    
    private func evaluateCondition(_ condition: RuleCondition, track: GPXTrack, previousWaypoint: GPXWaypoint?, nextWaypoint: GPXWaypoint?) async -> Bool {
        let allPoints = track.segments.flatMap { $0.points }
        guard !allPoints.isEmpty else { return false }
        
        switch condition.conditionType {
        case .startingPlace:
            let placeId = previousWaypoint?.extensions?["PlaceId"].text
            return placeId == condition.value1
            
        case .endingPlace:
            let placeId = nextWaypoint?.extensions?["PlaceId"].text
            return placeId == condition.value1
            
        case .speed:
            let speed = calculateSpeed(track: track, type: condition.speedCalculationType ?? .average)
            return compare(value: speed, condition: condition)
            
        case .pointsCount:
            return compare(value: Double(allPoints.count), condition: condition)
            
        case .elevation:
            let ele = calculateElevation(points: allPoints, type: condition.speedCalculationType ?? .average)
            return compare(value: ele, condition: condition)
            
        case .overWaterPercent:
            let waterPercent = await calculateOverWaterPercent(points: allPoints)
            return compare(value: waterPercent, condition: condition)
            
        case .iosActivityType:
            let targetType = condition.value1.lowercased()
            let requiredPercent = Double(condition.value2 ?? "0") ?? 0
            
            var matchingPoints = 0
            for point in allPoints {
                if let ext = point.extensions, let isType = ext[targetType].text, isType.lowercased() == "true" {
                    matchingPoints += 1
                }
            }
            let percent = (Double(matchingPoints) / Double(allPoints.count)) * 100.0
            return percent >= requiredPercent
            
        case .totalDistance:
            let distance = calculateTotalDistance(points: allPoints)
            return compare(value: distance, condition: condition)
            
        case .totalSteps:
            let steps = calculateTotalSteps(track: track)
            return compare(value: Double(steps), condition: condition)
            
        case .totalElevation:
            let elevation = calculateTotalElevation(points: allPoints)
            return compare(value: elevation, condition: condition)
            
        case .distanceFromPlace:
            // condition.value1: Place ID
            // condition.value2: Percentage X
            // condition.comparisonOperator: Operator applied to Distance
            // condition.value3: Distance Y1
            // condition.value4: Distance Y2 (if between)
            let requiredPercent = Double(condition.value2 ?? "0") ?? 0
            let actualPercent = await calculatePercentPointsNearPlace(points: allPoints, condition: condition)
            return actualPercent >= requiredPercent
        }
    }
    
    private func compare(value: Double, condition: RuleCondition) -> Bool {
        let target1 = Double(condition.value1) ?? 0
        switch condition.comparisonOperator {
        case .lessThan:
            return value < target1
        case .moreThan:
            return value > target1
        case .between:
            let target2 = Double(condition.value2 ?? "0") ?? 0
            return value >= target1 && value <= target2
        case .none:
            return false
        }
    }
    
    private func calculatePercentPointsNearPlace(points: [GPXTrackPoint], condition: RuleCondition) async -> Double {
        let placeId = condition.value1
        guard let place = PlaceManager.shared.getAllPlaces().first(where: { $0.placeId == placeId }) else { return 0 }
        let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        
        let targetDistance1 = Double(condition.value3 ?? "0") ?? 0
        let targetDistance2 = Double(condition.value4 ?? "0") ?? 0
        
        var matchingPoints = 0
        for point in points {
            if let lat = point.latitude, let lon = point.longitude {
                let loc = CLLocation(latitude: lat, longitude: lon)
                let distance = loc.distance(from: placeLocation)
                
                var matches = false
                switch condition.comparisonOperator {
                case .lessThan:
                    matches = distance < targetDistance1
                case .moreThan:
                    matches = distance > targetDistance1
                case .between:
                    matches = distance >= targetDistance1 && distance <= targetDistance2
                case .none:
                    matches = false
                }
                
                if matches {
                    matchingPoints += 1
                }
            }
        }
        
        guard points.count > 0 else { return 0 }
        return (Double(matchingPoints) / Double(points.count)) * 100.0
    }
    
    private func calculateSpeed(track: GPXTrack, type: SpeedCalculationType) -> Double {
        var speeds: [Double] = []
        for segment in track.segments {
            for point in segment.points {
                if let ext = point.extensions, let speedStr = ext["Speed"].text, let speed = Double(speedStr) {
                    // Assuming speed is in m/s, convert to km/h
                    speeds.append(speed * 3.6)
                }
            }
        }
        
        if speeds.isEmpty {
            // Fallback to calculating from distance and time
            let allPoints = track.segments.flatMap { $0.points }
            guard allPoints.count > 1,
                  let startTime = allPoints.first?.time,
                  let endTime = allPoints.last?.time else { return 0 }
            
            let duration = endTime.timeIntervalSince(startTime)
            guard duration > 0 else { return 0 }
            
            let distance = calculateTotalDistance(points: allPoints)
            return (distance / duration) * 3.6 // km/h
        }
        
        if type == .average {
            let sum = speeds.reduce(0, +)
            return sum / Double(speeds.count)
        } else {
            let sorted = speeds.sorted()
            if sorted.count % 2 == 0 {
                return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
            } else {
                return sorted[sorted.count / 2]
            }
        }
    }
    
    private func calculateTotalDistance(points: [GPXTrackPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var distance: Double = 0
        for i in 1..<points.count {
            let p1 = points[i-1]
            let p2 = points[i]
            if let lat1 = p1.latitude, let lon1 = p1.longitude,
               let lat2 = p2.latitude, let lon2 = p2.longitude {
                let loc1 = CLLocation(latitude: lat1, longitude: lon1)
                let loc2 = CLLocation(latitude: lat2, longitude: lon2)
                distance += loc2.distance(from: loc1)
            }
        }
        return distance
    }
    
    private func calculateElevation(points: [GPXTrackPoint], type: SpeedCalculationType) -> Double {
        let validElevations = points.compactMap { $0.elevation }
        guard !validElevations.isEmpty else { return 0 }
        
        if type == .average {
            let sum = validElevations.reduce(0, +)
            return sum / Double(validElevations.count)
        } else {
            let sorted = validElevations.sorted()
            if sorted.count % 2 == 0 {
                return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
            } else {
                return sorted[sorted.count / 2]
            }
        }
    }
    
    private func calculateTotalSteps(track: GPXTrack) -> Int {
        var steps = 0
        // TimelineManager aggregates steps from extensions usually. Let's do the same.
        if let lastPoint = track.segments.last?.points.last {
            if let ext = lastPoint.extensions, let stepStr = ext["Steps"].text, let stepVal = Int(stepStr) {
                steps += stepVal
            }
        }
        return steps
    }
    
    private func calculateTotalElevation(points: [GPXTrackPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        var currentEle = points[0].elevation
        
        for i in 1..<points.count {
            if let ele = points[i].elevation, let cur = currentEle {
                if ele > cur {
                    gain += (ele - cur)
                }
                currentEle = ele
            } else if let ele = points[i].elevation {
                currentEle = ele
            }
        }
        return gain
    }
    
    private func calculateOverWaterPercent(points: [GPXTrackPoint]) async -> Double {
        let maxSamples = 10
        guard points.count > 0 else { return 0 }
        
        var sampleIndices: [Int] = []
        if points.count <= maxSamples {
            sampleIndices = Array(0..<points.count)
        } else {
            // evenly spaced indices
            let step = Double(points.count - 1) / Double(maxSamples - 1)
            for i in 0..<maxSamples {
                sampleIndices.append(Int(round(Double(i) * step)))
            }
        }
        
        var waterCount = 0
        var evaluatedCount = 0
        
        for index in sampleIndices {
            let point = points[index]
            guard let lat = point.latitude, let lon = point.longitude else { continue }
            let location = CLLocation(latitude: lat, longitude: lon)
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    if placemark.ocean != nil || placemark.inlandWater != nil {
                        waterCount += 1
                    }
                }
            } catch {
                if let clErr = error as? CLError, clErr.code == .network {
                    // Try to continue, maybe rate limit
                }
            }
            evaluatedCount += 1
        }
        
        guard evaluatedCount > 0 else { return 0 }
        return (Double(waterCount) / Double(evaluatedCount)) * 100.0
    }
}
