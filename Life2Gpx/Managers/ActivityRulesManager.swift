import Foundation
import SwiftUI
import CoreGPX
import CoreLocation

class ActivityRulesManager: ObservableObject {
    static let shared = ActivityRulesManager()
    
    @Published var rules: [ActivityRule] {
        didSet { saveRules() }
    }
    
    @Published var splitRules: [SplitRule] {
        didSet { saveSplitRules() }
    }
    
    @Published var workoutSplitRule: SplitRule {
        didSet { saveWorkoutSplitRule() }
    }
    
    private let rulesURL: URL
    private let splitRulesURL: URL
    private let workoutSplitRuleURL: URL
    private let geocoder = CLGeocoder()
    
    private init() {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let preferencesDir = documentsUrl.appendingPathComponent("Preferences")
        self.rulesURL = preferencesDir.appendingPathComponent("activityrules.json")
        self.splitRulesURL = preferencesDir.appendingPathComponent("splitrules.json")
        self.workoutSplitRuleURL = preferencesDir.appendingPathComponent("workoutsplitrule.json")
        
        self.rules = []
        self.splitRules = []
        self.workoutSplitRule = SplitRule(activityType: "workout", minimumPoints: 3, minimumConfidence: "Low", isActive: true)
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: preferencesDir.path) {
            do {
                try fileManager.createDirectory(at: preferencesDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating preferences directory: \(error)")
            }
        }
        
        loadRules()
        loadSplitRules()
        loadWorkoutSplitRule()
    }
    
    private func loadWorkoutSplitRule() {
        if let data = try? Data(contentsOf: workoutSplitRuleURL),
           let decoded = try? JSONDecoder().decode(SplitRule.self, from: data) {
            self.workoutSplitRule = decoded
        } else {
            self.workoutSplitRule = SplitRule(activityType: "workout", minimumPoints: 3, minimumConfidence: "Low", isActive: true)
            saveWorkoutSplitRule()
        }
    }
    
    private func saveWorkoutSplitRule() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(workoutSplitRule) {
            do {
                try data.write(to: workoutSplitRuleURL, options: .atomic)
            } catch {
                print("Failed to save workoutsplitrule: \(error)")
            }
        }
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
        
        let runningFromWalkingRule = ActivityRule(
            name: "Running from Walking",
            resultingActivityType: "running",
            conditions: [
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "walking", value2: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .moreThan, value1: "10")
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
                RuleCondition(logicalOperator: .and, conditionType: .iosActivityType, value1: "automotive", value2: "50"),
                RuleCondition(logicalOperator: .and, conditionType: .speed, comparisonOperator: .lessThan, value1: "150")
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
        
        return [walkingRule, runningFromWalkingRule, runningRule, cyclingRule, automotiveRule, trainRule, planeRule, boatRule]
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
    
    private func defaultSplitRules() -> [SplitRule] {
        return [
            SplitRule(activityType: "automotive", minimumPoints: 5, minimumPointsToStop: 2, minimumConfidence: "High"),
            SplitRule(activityType: "cycling", minimumPoints: 2, minimumPointsToStop: 8, minimumConfidence: "High"),
            SplitRule(activityType: "running", minimumPoints: 2, minimumPointsToStop: 4, minimumConfidence: "High"),
            SplitRule(activityType: "walking", minimumPoints: 5, minimumPointsToStop: 2, minimumConfidence: "High"),
            SplitRule(activityType: "unknown", minimumPoints: 5, minimumPointsToStop: 0, minimumConfidence: "High")
        ]
    }
    
    private func loadSplitRules() {
        if let data = try? Data(contentsOf: splitRulesURL) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([SplitRule].self, from: data) {
                self.splitRules = decoded
                return
            }
        }
        self.splitRules = defaultSplitRules()
        saveSplitRules()
    }
    
    private func saveSplitRules() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(splitRules) {
            do {
                try data.write(to: splitRulesURL, options: .atomic)
            } catch {
                print("Failed to save splitrules: \(error)")
            }
        }
    }
    
    func evaluate(track: GPXTrack, previousWaypoint: GPXWaypoint?, nextWaypoint: GPXWaypoint?) async -> String? {
        let activeRules = self.rules.filter { $0.isActive }
        
        for rule in activeRules {
            if await evaluateRule(rule, track: track, previousWaypoint: previousWaypoint, nextWaypoint: nextWaypoint) {
                let type = rule.resultingActivityType
                return type == "unknown" ? nil : type
            }
        }
        
        return nil
    }
    
    func evaluateAndUpdate(track: GPXTrack, previousWaypoint: GPXWaypoint?, nextWaypoint: GPXWaypoint?, date: Date) {
        // Run asynchronously
        Task {
            let splitTracks = split(track: track)
            var categorizedTracks: [GPXTrack] = []
            
            for splitTrack in splitTracks {
                let hasWorkoutType = splitTrack.segments.flatMap({ $0.points }).contains(where: {
                    $0.extensions?[GPXExtensionKey.workoutType.rawValue].text != nil
                })
                
                if !hasWorkoutType {
                    if let newType = await evaluate(track: splitTrack, previousWaypoint: previousWaypoint, nextWaypoint: nextWaypoint) {
                        splitTrack.type = newType == "unknown" ? nil : newType
                    }
                } else if splitTrack.type == nil || splitTrack.type == "unknown" {
                    let workoutType = splitTrack.segments.flatMap({ $0.points }).compactMap({ $0.extensions?[GPXExtensionKey.workoutType.rawValue].text }).first
                    splitTrack.type = workoutType
                }
                categorizedTracks.append(splitTrack)
            }
            
            var mergedTracks: [GPXTrack] = []
            for categorizedTrack in categorizedTracks {
                if let lastTrack = mergedTracks.last, lastTrack.type == categorizedTrack.type {
                    let targetSegment = lastTrack.segments.last ?? {
                        let newSegment = GPXTrackSegment()
                        lastTrack.add(trackSegment: newSegment)
                        return newSegment
                    }()
                    
                    for segment in categorizedTrack.segments {
                        for point in segment.points {
                            targetSegment.add(trackpoint: point)
                        }
                    }
                } else {
                    mergedTracks.append(categorizedTrack)
                }
            }
            
            if mergedTracks.count == 1 && track.type == mergedTracks[0].type {
                // No split/merge resulting in a difference, but refresh unknown track notification
                NotificationManager.shared.checkAndNotifyUnknownTracks(forDate: date)
                return
            }
            
            GPXManager.shared.replaceItemWithMultiple(
                deleteWaypoints: [],
                deleteTracks: [track],
                addWaypoints: [],
                addTracks: mergedTracks,
                forDate: date
            ) { success in
                if success {
                    NotificationManager.shared.checkAndNotifyUnknownTracks(forDate: date)
                }
            }
        }
    }
    
    func split(track: GPXTrack) -> [GPXTrack] {
        guard let firstSegment = track.segments.first, !firstSegment.points.isEmpty else {
            return [track]
        }
        
        let allPoints = track.segments.flatMap { $0.points }
        
        if workoutSplitRule.isActive {
            let workoutSubtracks = splitByWorkout(points: allPoints)
            if !workoutSubtracks.isEmpty {
                var finalTracks: [GPXTrack] = []
                for subtrack in workoutSubtracks {
                    let points = subtrack.segments.flatMap { $0.points }
                    let isWorkoutTrack = points.contains(where: { $0.extensions?[GPXExtensionKey.workoutType.rawValue].text != nil })
                    if isWorkoutTrack {
                        finalTracks.append(subtrack)
                    } else {
                        finalTracks.append(contentsOf: splitByMotionRules(track: subtrack))
                    }
                }
                return finalTracks
            }
        }
        
        return splitByMotionRules(track: track)
    }

    private func splitByWorkout(points: [GPXTrackPoint]) -> [GPXTrack] {
        var resultingTracks: [GPXTrack] = []
        var currentTrackPoints: [GPXTrackPoint] = []
        var currentWorkoutType: String? = nil
        var pendingType: String? = nil
        var matchCount = 0
        
        for point in points {
            let pointWorkoutType = point.extensions?[GPXExtensionKey.workoutType.rawValue].text
            
            if pointWorkoutType == pendingType {
                matchCount += 1
            } else {
                pendingType = pointWorkoutType
                matchCount = 1
            }
            
            if matchCount >= workoutSplitRule.minimumPoints && pendingType != currentWorkoutType {
                let splitIndex = currentTrackPoints.count + 1 - matchCount
                if splitIndex > 0 {
                    let previousPoints = Array(currentTrackPoints[0..<splitIndex])
                    if !previousPoints.isEmpty {
                        let newTrack = GPXTrack()
                        let newSegment = GPXTrackSegment()
                        previousPoints.forEach { newSegment.add(trackpoint: $0) }
                        newTrack.add(trackSegment: newSegment)
                        newTrack.type = currentWorkoutType
                        resultingTracks.append(newTrack)
                    }
                    currentTrackPoints = Array(currentTrackPoints[splitIndex...])
                }
                currentWorkoutType = pendingType
            }
            
            currentTrackPoints.append(point)
        }
        
        if !currentTrackPoints.isEmpty {
            let newTrack = GPXTrack()
            let newSegment = GPXTrackSegment()
            currentTrackPoints.forEach { newSegment.add(trackpoint: $0) }
            newTrack.add(trackSegment: newSegment)
            if currentWorkoutType == nil {
                let fallbackWorkoutType = currentTrackPoints.compactMap({ $0.extensions?[GPXExtensionKey.workoutType.rawValue].text }).first
                newTrack.type = fallbackWorkoutType
            } else {
                newTrack.type = currentWorkoutType
            }
            resultingTracks.append(newTrack)
        }
        
        return resultingTracks
    }

    private func splitByMotionRules(track: GPXTrack) -> [GPXTrack] {
        guard let firstSegment = track.segments.first, !firstSegment.points.isEmpty else {
            return [track]
        }
        
        let allPoints = track.segments.flatMap { $0.points }
        let activeSplitRules = splitRules.filter { $0.isActive }
        
        guard !activeSplitRules.isEmpty else { return [track] }
        
        var resultingTracks: [GPXTrack] = []
        var currentTrackPoints: [GPXTrackPoint] = []
        var currentRule: SplitRule? = nil
        
        var matchingRule: SplitRule? = nil
        var matchingCount = 0
        
        for point in allPoints {
            var pointMatchedRule: SplitRule? = nil
            for rule in activeSplitRules {
                let activityConfidence = point.extensions?["ActivityConfidence"].text ?? "Unknown"
                let confidenceLevel: Int
                switch activityConfidence {
                case "High": confidenceLevel = 3
                case "Medium": confidenceLevel = 2
                case "Low": confidenceLevel = 1
                default: confidenceLevel = 0
                }
                
                let ruleConfidenceLevel: Int
                switch rule.minimumConfidence {
                case "High": ruleConfidenceLevel = 3
                case "Medium": ruleConfidenceLevel = 2
                case "Low": ruleConfidenceLevel = 1
                default: ruleConfidenceLevel = 0
                }
                
                let hasActivity = (point.extensions?[rule.activityType.capitalized].text?.lowercased() == "true")
                
                var matches = false
                if rule.activityType == "unknown" {
                    matches = true
                } else {
                    matches = hasActivity && (confidenceLevel >= ruleConfidenceLevel)
                }
                
                if matches {
                    pointMatchedRule = rule
                    break
                }
            }
            
            currentTrackPoints.append(point)
            
            if let matched = pointMatchedRule {
                if matched == matchingRule {
                    matchingCount += 1
                } else {
                    matchingRule = matched
                    matchingCount = 1
                }
                
                let currentMinToStop = currentRule?.minimumPointsToStop ?? 0
                let accumulatedPreviousPoints = currentTrackPoints.count - matchingCount
                let canStopCurrentTrack = (currentRule == nil) || (accumulatedPreviousPoints >= currentMinToStop)
                
                if matchingCount >= matched.minimumPoints && canStopCurrentTrack && currentRule != matched {
                    if currentRule == nil {
                        currentRule = matched
                    } else {
                        let splitIndex = currentTrackPoints.count - matchingCount
                        if splitIndex > 0 {
                            let previousPoints = Array(currentTrackPoints[0..<splitIndex])
                            
                            if !previousPoints.isEmpty {
                                let newTrack = GPXTrack()
                                let newSegment = GPXTrackSegment()
                                previousPoints.forEach { newSegment.add(trackpoint: $0) }
                                newTrack.add(trackSegment: newSegment)
                                if let type = currentRule?.activityType {
                                    newTrack.type = type == "unknown" ? nil : type
                                } else {
                                    newTrack.type = track.type == "unknown" ? nil : track.type
                                }
                                resultingTracks.append(newTrack)
                            }
                            
                            currentTrackPoints = Array(currentTrackPoints[splitIndex...])
                        }
                        
                        currentRule = matched
                    }
                }
            } else {
                matchingRule = nil
                matchingCount = 0
            }
        }
        
        if !currentTrackPoints.isEmpty {
            let newTrack = GPXTrack()
            let newSegment = GPXTrackSegment()
            currentTrackPoints.forEach { newSegment.add(trackpoint: $0) }
            newTrack.add(trackSegment: newSegment)
            if let type = currentRule?.activityType {
                newTrack.type = type == "unknown" ? nil : type
            } else {
                newTrack.type = track.type == "unknown" ? nil : track.type
            }
            resultingTracks.append(newTrack)
        }
        
        return resultingTracks
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
