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
    private var observerQuery: HKObserverQuery?
    
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
            LogManager.shared.logFitnessData(message: "HealthKit is not available on this device.")
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
                    LogManager.shared.logFitnessData(message: "HealthKit workout authorization granted.")
                    self.setupObserverQuery()
                    self.checkActiveOrRecentWorkouts()
                } else if let error = error {
                    LogManager.shared.logData(context: "WorkoutManager", content: "HealthKit authorization error: \(error.localizedDescription)", verbosity: 2)
                    LogManager.shared.logFitnessData(message: "HealthKit authorization error: \(error.localizedDescription)")
                }
                completion(success)
            }
        }
    }
    
    func setupObserverQuery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        
        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error = error {
                    LogManager.shared.logData(context: "WorkoutManager", content: "Observer query error: \(error.localizedDescription)", verbosity: 2)
                    LogManager.shared.logFitnessData(message: "Observer query error: \(error.localizedDescription)")
                    completionHandler()
                    return
                }
                LogManager.shared.logData(context: "WorkoutManager", content: "Observer query triggered for HealthKit workouts.", verbosity: 3)
                LogManager.shared.logFitnessData(message: "Observer query triggered: new or updated workout detected in HealthKit.")
                
                self?.syncWorkoutsToGPX(for: Date()) {
                    completionHandler()
                }
            }
            observerQuery = query
            healthStore.execute(query)
        }
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if let error = error {
                LogManager.shared.logData(context: "WorkoutManager", content: "Enable background delivery error: \(error.localizedDescription)", verbosity: 2)
                LogManager.shared.logFitnessData(message: "Background delivery registration error: \(error.localizedDescription)")
            } else {
                LogManager.shared.logData(context: "WorkoutManager", content: "Background delivery enabled for workouts.", verbosity: 3)
                LogManager.shared.logFitnessData(message: "Background delivery enabled for workouts.")
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
        
        // Use a 24-hour buffer before startOfDay so workouts crossing midnight are included
        let queryStart = startOfDay.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: endOfDay, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let self = self else { return }
            if let error = error {
                LogManager.shared.logData(context: "WorkoutManager", content: "Workout query error: \(error.localizedDescription)", verbosity: 2)
                LogManager.shared.logFitnessData(message: "Workout query error: \(error.localizedDescription)")
                completion?([])
                return
            }
            
            guard let workouts = samples as? [HKWorkout] else {
                LogManager.shared.logFitnessData(message: "Workout query returned non-HKWorkout samples.")
                completion?([])
                return
            }
            
            var workoutInfos: [WorkoutInfo] = []
            let now = Date()
            var currentActive: String? = nil
            var currentActiveStart: Date? = nil
            
            for workout in workouts {
                // Keep workouts that fall within or overlap [startOfDay, endOfDay]
                guard workout.endDate >= startOfDay && workout.startDate <= endOfDay else { continue }
                
                let typeString = self.formatWorkoutActivityType(workout.workoutActivityType)
                let info = WorkoutInfo(activityType: typeString, startDate: workout.startDate, endDate: workout.endDate)
                workoutInfos.append(info)
                
                // A workout is active if it is running or ended within the last 5 minutes (300s)
                if workout.startDate <= now && workout.endDate >= now.addingTimeInterval(-300) {
                    currentActive = typeString
                    currentActiveStart = workout.startDate
                }
            }
            
            let workoutSummary = workoutInfos.map { "\($0.activityType) (\($0.startDate) - \($0.endDate))" }.joined(separator: ", ")
            LogManager.shared.logFitnessData(message: "Queried workouts for date \(date): found \(workoutInfos.count) workout(s) [\(workoutSummary)]. Active: \(currentActive ?? "none")")
            
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
                let updatedTracks = tracks
                var totalModifiedPoints = 0
                
                for trackIndex in 0..<updatedTracks.count {
                    let track = updatedTracks[trackIndex]
                    var trackMatchedWorkout = false
                    var trackWorkoutType: String? = nil
                    
                    for segmentIndex in 0..<track.segments.count {
                        let segment = track.segments[segmentIndex]
                        for pointIndex in 0..<segment.points.count {
                            let point = segment.points[pointIndex]
                            guard let pointTime = point.time else { continue }
                            
                            for workout in workoutInfos {
                                if pointTime >= workout.startDate && pointTime <= workout.endDate {
                                    trackMatchedWorkout = true
                                    trackWorkoutType = workout.activityType
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
                                        totalModifiedPoints += 1
                                    }
                                }
                            }
                        }
                    }
                    
                    if trackMatchedWorkout, let workoutType = trackWorkoutType {
                        if track.type == nil || track.type == "unknown" || track.type != workoutType {
                            track.type = workoutType
                            fileModified = true
                        }
                    }
                }
                
                if fileModified {
                    LogManager.shared.logData(context: "WorkoutManager", content: "Retroactively synced \(workoutInfos.count) workout(s) (updated \(totalModifiedPoints) points) to GPX tracks for date: \(date).", verbosity: 3)
                    LogManager.shared.logFitnessData(message: "Retroactively synced \(workoutInfos.count) workout(s) to GPX tracks for date \(date): updated \(totalModifiedPoints) trackpoint(s).")
                    GPXManager.shared.saveLocationData(waypoints, tracks: updatedTracks, forDate: date)
                    
                    // Re-evaluate tracks after retroactively adding workout types
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
        case .stairClimbing, .stairs: return "stair_climbing"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "functional_strength_training"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .dance, .cardioDance, .socialDance, .danceInspiredTraining: return "dance"
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
        case .americanFootball: return "american_football"
        case .archery: return "archery"
        case .australianFootball: return "australian_football"
        case .baseball: return "baseball"
        case .bowling: return "bowling"
        case .boxing: return "boxing"
        case .climbing: return "climbing"
        case .cricket: return "cricket"
        case .crossTraining: return "cross_training"
        case .curling: return "curling"
        case .equestrianSports: return "equestrian_sports"
        case .fencing: return "fencing"
        case .fishing: return "fishing"
        case .gymnastics: return "gymnastics"
        case .handball: return "handball"
        case .hockey: return "hockey"
        case .hunting: return "hunting"
        case .lacrosse: return "lacrosse"
        case .martialArts: return "martial_arts"
        case .mindAndBody: return "mind_and_body"
        case .mixedMetabolicCardioTraining, .mixedCardio: return "mixed_cardio"
        case .play: return "play"
        case .preparationAndRecovery, .cooldown: return "cooldown"
        case .racquetball: return "racquetball"
        case .rugby: return "rugby"
        case .sailing: return "sailing"
        case .skatingSports: return "skating_sports"
        case .snowSports: return "snow_sports"
        case .softball: return "softball"
        case .squash: return "squash"
        case .surfingSports: return "surfing_sports"
        case .trackAndField: return "track_and_field"
        case .volleyball: return "volleyball"
        case .waterFitness: return "water_fitness"
        case .waterPolo: return "water_polo"
        case .waterSports: return "water_sports"
        case .wrestling: return "wrestling"
        case .barre: return "barre"
        case .flexibility: return "flexibility"
        case .highIntensityIntervalTraining: return "hiit"
        case .jumpRope: return "jump_rope"
        case .kickboxing: return "kickboxing"
        case .stepTraining: return "step_training"
        case .taiChi: return "tai_chi"
        case .handCycling: return "hand_cycling"
        case .discSports: return "disc_sports"
        case .fitnessGaming: return "fitness_gaming"
        case .swimBikeRun: return "swim_bike_run"
        case .transition: return "transition"
        case .underwaterDiving: return "underwater_diving"
        default:
            let name = String(describing: type)
            var snakeCase = ""
            for (i, char) in name.enumerated() {
                if char.isUppercase && i > 0 {
                    snakeCase.append("_")
                }
                snakeCase.append(char.lowercased())
            }
            let cleaned = snakeCase.replacingOccurrences(of: "hk_workout_activity_type_", with: "")
            return cleaned.isEmpty ? "workout" : cleaned
        }
    }
}
