import Foundation
import HealthKit
import CoreGPX

struct WorkoutInfo {
    let activityType: String
    let startDate: Date
    let endDate: Date
}

class WorkoutManager: ObservableObject {
    static let shared = WorkoutManager()
    
    private let healthStore = HKHealthStore()
    @Published var isAuthorized: Bool = false
    @Published var activeWorkoutType: String?
    @Published var activeWorkoutStartDate: Date?
    
    private init() {
        if HKHealthStore.isHealthDataAvailable() {
            requestAuthorization { _ in }
        }
    }
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        let workoutType = HKObjectType.workoutType()
        let typesToRead: Set<HKObjectType> = [workoutType]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if success {
                    LogManager.shared.logData(context: "WorkoutManager", content: "HealthKit workout authorization granted.", verbosity: 3)
                    self.checkActiveOrRecentWorkouts()
                } else if let error = error {
                    LogManager.shared.logData(context: "WorkoutManager", content: "HealthKit authorization error: \(error.localizedDescription)", verbosity: 2)
                }
                completion(success)
            }
        }
    }
    
    func checkActiveOrRecentWorkouts(for date: Date = Date(), completion: (([WorkoutInfo]) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?([])
            return
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion?([])
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: [.strictStartDate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let self = self else { return }
            if let error = error {
                LogManager.shared.logData(context: "WorkoutManager", content: "Workout query error: \(error.localizedDescription)", verbosity: 2)
                completion?([])
                return
            }
            
            guard let workouts = samples as? [HKWorkout] else {
                completion?([])
                return
            }
            
            var workoutInfos: [WorkoutInfo] = []
            let now = Date()
            var currentActive: String? = nil
            var currentActiveStart: Date? = nil
            
            for workout in workouts {
                let typeString = self.formatWorkoutActivityType(workout.workoutActivityType)
                let info = WorkoutInfo(activityType: typeString, startDate: workout.startDate, endDate: workout.endDate)
                workoutInfos.append(info)
                
                // If workout ends very recently (or end date is close to now), consider it active
                if workout.endDate >= now.addingTimeInterval(-60) {
                    currentActive = typeString
                    currentActiveStart = workout.startDate
                }
            }
            
            DispatchQueue.main.async {
                self.activeWorkoutType = currentActive
                self.activeWorkoutStartDate = currentActiveStart
            }
            
            completion?(workoutInfos)
        }
        
        healthStore.execute(query)
    }
    
    func syncWorkoutsToGPX(for date: Date = Date(), completion: (() -> Void)? = nil) {
        checkActiveOrRecentWorkouts(for: date) { workoutInfos in
            guard !workoutInfos.isEmpty else {
                completion?()
                return
            }
            
            GPXManager.shared.loadFile(forDate: date) { waypoints, tracks in
                var fileModified = false
                var updatedTracks = tracks
                
                for trackIndex in 0..<updatedTracks.count {
                    let track = updatedTracks[trackIndex]
                    for segmentIndex in 0..<track.segments.count {
                        let segment = track.segments[segmentIndex]
                        for pointIndex in 0..<segment.points.count {
                            let point = segment.points[pointIndex]
                            guard let pointTime = point.time else { continue }
                            
                            for workout in workoutInfos {
                                if pointTime >= workout.startDate && pointTime <= workout.endDate {
                                    let currentWorkoutType = point.extensions?[GPXExtensionKey.workoutType.rawValue].text
                                    if currentWorkoutType != workout.activityType {
                                        let ext = point.extensions ?? GPXExtensions()
                                        var dict: [String: String] = [:]
                                        for child in ext.children {
                                            if let text = child.text {
                                                dict[child.name] = text
                                            }
                                        }
                                        dict[GPXExtensionKey.workoutType.rawValue] = workout.activityType
                                        let newExt = GPXExtensions()
                                        newExt.append(at: nil, contents: dict)
                                        point.extensions = newExt
                                        fileModified = true
                                    }
                                }
                            }
                        }
                    }
                }
                
                if fileModified {
                    LogManager.shared.logData(context: "WorkoutManager", content: "Retroactively synced \(workoutInfos.count) workout(s) to GPX trackpoints for date: \(date).", verbosity: 3)
                    GPXManager.shared.saveLocationData(waypoints, tracks: updatedTracks, forDate: date)
                    
                    // Re-run track splitting and rules after retroactively adding workout types
                    for track in updatedTracks {
                        ActivityRulesManager.shared.evaluateAndUpdate(track: track, previousWaypoint: waypoints.last, nextWaypoint: nil, date: date)
                    }
                }
                
                completion?()
            }
        }
    }
    
    func formatWorkoutActivityType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "walking"
        case .running: return "running"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        case .swimming: return "swimming"
        case .downhillSkiing, .crossCountrySkiing: return "skiing"
        case .snowboarding: return "snowboarding"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stair_climbing"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "functional_strength_training"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .dance, .cardioDance, .socialDance: return "dance"
        case .coreTraining: return "core_training"
        case .badminton: return "badminton"
        case .tennis: return "tennis"
        case .tableTennis: return "table_tennis"
        case .basketball: return "basketball"
        case .soccer: return "soccer"
        case .golf: return "golf"
        case .pickleball: return "pickleball"
        case .paddleSports: return "paddlesports"
        case .wheelchairWalkPace, .wheelchairRunPace: return "wheelchair"
        default:
            let rawString = String(describing: type)
                .replacingOccurrences(of: "HKWorkoutActivityType", with: "")
                .lowercased()
            return rawString.isEmpty ? "workout" : rawString
        }
    }
}
