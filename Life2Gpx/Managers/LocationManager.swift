import SwiftUI
import CoreLocation
import CoreGPX
import CoreMotion
import UserNotifications

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentFilteredLocation: CLLocation?
    @Published var currentRawLocation: CLLocation?
    @Published var dataHasBeenUpdated: Bool = false
    @Published var heading: Double = 0.0
    private var lastRawHeading: Double?

    private var previousSavedLocation: CLLocation?
    private var locationUpdateTimer: Timer?
    private var customDistanceFilter: CLLocationDistance = 20
    private var currentDate: Date?
    private var minimumUpdateInterval: TimeInterval { TimeInterval(SettingsManager.shared.minimumUpdateInterval) }
    
    // Constants for timers and thresholds
    private let movingDistanceFilterConstant: CLLocationDistance = 20
    private let stationaryDistanceFilterConstant: CLLocationDistance = 60
    private let midnightUpdateGracePeriod: TimeInterval = 10
    private let deadMansSwitchTriggerTime: TimeInterval = 300
    private let notificationResetTimerInterval: TimeInterval = 180
    private let locationUpdateDebounceInterval: TimeInterval = 1.0
    private let locationHistoryMaxSize = 20
    private let filteredPositionQueueMaxSize = 10
    private let gpxAppendDebounceInterval: TimeInterval = 1.0
    private var lastUpdateTimestamp: Date?
    private let motionActivityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private var latestActivity: CMMotionActivity?
    private let pedometer = CMPedometer()
    private var lastPedometerCheckDate: Date?
    private var latestPedometerSteps: Int = 0
    private var midnightTimer: Timer?
    private var stationaryStepsUpdateTimer: Timer?
    private let userDefaults = UserDefaults(suiteName: "group.DeltaCygniLabs.Life2Gpx")
    private var lastAppendCall: Date?
    private var notificationResetTimer: Timer?
    private var lastBackgroundTaskCheck: Date = Date.distantPast
    private var locationManagerCallCount = 0
    private var lastLocationManagerCallTimestamp: Date?
    private var locationHistory: [(location: CLLocation, receivedAt: Date)] = []
    private let locationHistoryLock = NSLock()
    private var filteredByPositionQueue: [CLLocation] = []

    override init() {
        super.init()
        LogManager.shared.logData(context: "LocationManagerInit", content: "Initializing LocationManager.", verbosity: 3)
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["DeadMansSwitch"])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission request error: \(error)")
            }
        }
        
        if let savedTimestamp = UserDefaults.standard.object(forKey: "lastUpdateTimestamp") as? Date {
             lastUpdateTimestamp = savedTimestamp
        }
        
        if !SettingsManager.shared.disableTracking {
            setupLocationManager()
            setupMotionActivityManager()
            scheduleMidnightUpdate()
            scheduleDeadMansSwitchNotification()
            startNotificationResetTimer()
        }
        
        setupPedometer()
        currentDate = Date()
    }

    func stopAllTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionActivityManager.stopActivityUpdates()
        midnightTimer?.invalidate()
        stopNotificationResetTimer()
        
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["DeadMansSwitch", "UnknownPlaceCheckIn"])
        
        LogManager.shared.logData(context: "LocationManager", content: "All tracking stopped.", verbosity: 2)
    }

    func startAllTracking() {
        setupLocationManager()
        setupMotionActivityManager()
        scheduleMidnightUpdate()
        scheduleDeadMansSwitchNotification()
        startNotificationResetTimer()
        LogManager.shared.logData(context: "LocationManager", content: "All tracking started.", verbosity: 2)
    }
    private func scheduleMidnightUpdate() {
            let calendar = Calendar.current
            let now = Date()
            
            var midnightComponents = calendar.dateComponents([.year, .month, .day], from: now)
            midnightComponents.hour = 0
            midnightComponents.minute = 0
            midnightComponents.second = 0
            
            guard let midnight = calendar.date(from: midnightComponents) else { return }
            let timeIntervalUntilMidnight = midnight.timeIntervalSince(now)
            //extra grace period in case clock ran a little bit too fast. It happened.
            let adjustedInterval = (timeIntervalUntilMidnight > 0 ? timeIntervalUntilMidnight : timeIntervalUntilMidnight + 86400) + midnightUpdateGracePeriod
            LogManager.shared.logData(context: "LocationManager", content: "Scheduling midnight update in \(adjustedInterval) seconds.", verbosity: 4)
            midnightTimer = Timer.scheduledTimer(withTimeInterval: adjustedInterval, repeats: false) { [weak self] _ in
                self?.forceMidnightUpdate()
            }
        }
        
    private func forceMidnightUpdate() {
        if currentFilteredLocation == nil {
            if let location = locationManager.location {
                currentFilteredLocation = location
                LogManager.shared.logData(context: "LocationManager", content: "ForceMidnightUpdate: Using last known locationmanager location.", verbosity: 4)
            } else {
                LogManager.shared.logData(context: "LocationManager", content: "ForceMidnightUpdate: No current location available to force update.", verbosity: 2)
                scheduleMidnightUpdate() // Reschedule if we couldn't update
                return
            }
        }
        currentDate = Date()
        let rawType = UserDefaults.standard.string(forKey: "lastUpdateType") ?? ""
        let updateType = LocationUpdateType(rawValue: rawType) ?? .stationary
        LogManager.shared.logData(context: "LocationManager", content: "ForceMidnightUpdate: Forcing update with type: \(updateType.rawValue).", verbosity: 3)
        appendLocationToFile(type: updateType, debug: "Midnight Update")
        scheduleMidnightUpdate()
    }
    
    private func scheduleDeadMansSwitchNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["DeadMansSwitch"]) 
        
        guard SettingsManager.shared.enableDeadMansSwitch else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Recording Stopped"
        content.body = "Life2Gpx probably crashed and stopped recording. Tap here to restart it. Sorry!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: deadMansSwitchTriggerTime, repeats: false) // configured switch time

        let request = UNNotificationRequest(identifier: "DeadMansSwitch", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }

    private func startNotificationResetTimer() {
        notificationResetTimer?.invalidate() // Invalidate any existing timer
        notificationResetTimer = Timer.scheduledTimer(withTimeInterval: notificationResetTimerInterval, repeats: true) { [weak self] _ in
            self?.scheduleDeadMansSwitchNotification()
        }
    }

    private func stopNotificationResetTimer() {
        notificationResetTimer?.invalidate()
        notificationResetTimer = nil
    }

    private func cancelUnknownPlaceCheckInNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["UnknownPlaceCheckIn"])
        LogManager.shared.logData(context: "LocationManager", content: "Cancelled pending UnknownPlaceCheckIn notification.", verbosity: 4)
    }

    private func scheduleUnknownPlaceCheckInNotification(for waypoint: GPXWaypoint) {
        guard SettingsManager.shared.sendNotificationOnUnknownPlace else {
            LogManager.shared.logData(context: "LocationManager", content: "Skip scheduling UnknownPlaceCheckIn: setting is disabled.", verbosity: 4)
            return
        }
        
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["UnknownPlaceCheckIn"])
        
        let content = UNMutableNotificationContent()
        content.title = "Unknown Place Detected"
        content.body = "Tap here to add a name to this unknown place"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        
        let waypointTime = waypoint.time ?? Date()
        let userInfo: [AnyHashable: Any] = [
            "waypointTimestamp": waypointTime.timeIntervalSince1970,
            "latitude": waypoint.latitude ?? 0.0,
            "longitude": waypoint.longitude ?? 0.0
        ]
        content.userInfo = userInfo
        
        let triggerSeconds = SettingsManager.shared.unknownPlaceNotificationSeconds
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerSeconds, repeats: false)
        let request = UNNotificationRequest(identifier: "UnknownPlaceCheckIn", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                LogManager.shared.logData(context: "LocationManager", content: "Error scheduling UnknownPlaceCheckIn: \(error.localizedDescription)", verbosity: 2)
            } else {
                LogManager.shared.logData(context: "LocationManager", content: "Scheduled UnknownPlaceCheckIn in \(SettingsManager.shared.unknownPlaceNotificationValue) \(SettingsManager.shared.unknownPlaceNotificationUnit) (\(triggerSeconds)s) for waypoint at \(waypointTime).", verbosity: 3)
            }
        }
    }

    private func setupMotionActivityManager() {
        if CMMotionActivityManager.isActivityAvailable() {
            motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
                self?.processActivity(activity)
            }
        }
    }
    
    private func setupPedometer() {
        if CMPedometer.isStepCountingAvailable() {
            lastPedometerCheckDate = Date()
        } else {
            print("Step counting not available")
            latestPedometerSteps = -1
        }
    }
    private func processActivity(_ activity: CMMotionActivity?) {
        if let activity = activity {
            latestActivity = activity
        }
    }
    
    private func setupLocationManager() {
        LogManager.shared.logData(context: "LocationManager", content: "Setting up location manager.", verbosity: 5)
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = SettingsManager.shared.movingLocationAccuracyLevel.clLocationAccuracy
        //if the filter is set, the background location updates will be absolutely unreliable. 
        //https://developer.apple.com/forums/thread/776698?answerId=829420022#829420022
        //maybe it could be set to other values when the app is in the foreground. 
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        if let location = locationManager.location {
            CoordinateConverter.updateDeviceLocation(location.coordinate)
        } else {
            CoordinateConverter.restoreLastKnownDeviceLocation(from: nil)
        }
    }
    
    func startHeadingUpdates() {
        locationManager.startUpdatingHeading()
        LogManager.shared.logData(context: "LocationManager", content: "Started updating heading.", verbosity: 4)
    }

    func stopHeadingUpdates() {
        locationManager.stopUpdatingHeading()
        LogManager.shared.logData(context: "LocationManager", content: "Stopped updating heading.", verbosity: 4)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let functionStartTime = Date()
        let currentTime = Date()

        locationManagerCallCount += 1
        LogManager.shared.logData(context: "LocationManager", content: "Function called. Call count: \(locationManagerCallCount).", verbosity: 5)

        guard let newLocation = locations.last else { return }
        DispatchQueue.main.async {
            self.currentRawLocation = newLocation
        }
        CoordinateConverter.updateDeviceLocation(newLocation.coordinate)
        checkBackgroundTasks()
           
        var shouldProcessThisLocation: Bool
        locationHistoryLock.lock()
        if let lastEntryInHistory = locationHistory.last {
            if currentTime.timeIntervalSince(lastEntryInHistory.receivedAt) > locationUpdateDebounceInterval {
                shouldProcessThisLocation = true
                LogManager.shared.logData(context: "LocationManager", content: "Proceeding: currentTime \(currentTime) > \(locationUpdateDebounceInterval)s after last history item receivedAt \(lastEntryInHistory.receivedAt). Interval: \(String(format: "%.3f", currentTime.timeIntervalSince(lastEntryInHistory.receivedAt)))s.", verbosity: 5)
            } else {
                shouldProcessThisLocation = false
                LogManager.shared.logData(context: "LocationManager", content: "Debouncing: currentTime \(currentTime) NOT > \(locationUpdateDebounceInterval)s after last history item receivedAt \(lastEntryInHistory.receivedAt). Interval: \(String(format: "%.3f", currentTime.timeIntervalSince(lastEntryInHistory.receivedAt)))s.", verbosity: 5)
            }
        } else {
            shouldProcessThisLocation = true
            LogManager.shared.logData(context: "LocationManager", content: "Proceeding: History empty, allowing first entry at \(currentTime).", verbosity: 5)
        }
           
        if shouldProcessThisLocation {
            locationHistory.append((location: newLocation, receivedAt: currentTime))
            if locationHistory.count > locationHistoryMaxSize {
                locationHistory.removeFirst()
            }
            locationHistoryLock.unlock()
            LogManager.shared.logData(context: "LocationManager", content: "Location added to history. LocTS: \(newLocation.timestamp), RecTS: \(currentTime). History size: \(locationHistory.count).", verbosity: 5)
        } else {
            LogManager.shared.logData(context: "LocationManager", content: "Debouncing location update.", verbosity: 5)
            locationHistoryLock.unlock()
            return
        }

           
        let newUpdateDate = Date()
        LogManager.shared.logData(context: "LocationManager", content: "Received location: (\(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)), HAcc: \(newLocation.horizontalAccuracy), VAcc: \(newLocation.verticalAccuracy), Alt: \(newLocation.altitude), Speed: \(newLocation.speed), Time: \(newLocation.timestamp)", verbosity: 5)

        //forcing update if it's the new day and somehow midnight scheduler has screwed.
        if let previousUpdateDate = currentDate, Calendar.current.isDate(previousUpdateDate, inSameDayAs: newUpdateDate) == false {
            let calendar = Calendar.current
            let startOfNewDay = calendar.startOfDay(for: newUpdateDate)
            if newUpdateDate.timeIntervalSince(startOfNewDay) >= midnightUpdateGracePeriod {
                LogManager.shared.logData(context: "LocationManager", content: "New day detected (after grace period), forcing midnight update.", verbosity: 2)
                forceMidnightUpdate()
            } else {
                LogManager.shared.logData(context: "LocationManager", content: "New day detected, but within grace period. Not forcing midnight update yet. newUpdateDate: \(newUpdateDate), startOfNewDay: \(startOfNewDay)", verbosity: 4)
            }
        }
        // Default to allow update if no previous timestamp; abs to prevent manual change of dates to distant future completely screwing up the eval.
        let timeSinceLastUpdate = abs(lastUpdateTimestamp.map { newUpdateDate.timeIntervalSince($0) } ?? minimumUpdateInterval + 1)
        LogManager.shared.logData(context: "LocationManager", content: "Time since last update: \(timeSinceLastUpdate) seconds.", verbosity: 5)
        LogManager.shared.logData(context: "LocationManager", content: "Using lastUpdateTimestamp: \(String(describing: lastUpdateTimestamp)) for calculation.", verbosity: 5)

        
        if previousSavedLocation == nil {
            LogManager.shared.logData(context: "LocationManager", content: "No previous location saved, loading file.", verbosity: 4)
            GPXManager.shared.loadFile(forDate: Date()) { [weak self] loadedGpxWaypoints, loadedGpxTracks in
                var allLocations: [(location: CLLocation, date: Date)] = []

                for waypoint in loadedGpxWaypoints {
                    if let date = waypoint.time {
                        allLocations.append((CLLocation(latitude: waypoint.latitude ?? 0, longitude: waypoint.longitude ?? 0), date))
                    }
                }

                for track in loadedGpxTracks {
                    for segment in track.segments {
                        for trackpoint in segment.points {
                            if let date = trackpoint.time {
                                allLocations.append((CLLocation(latitude: trackpoint.latitude ?? 0, longitude: trackpoint.longitude ?? 0), date))
                            }
                        }
                    }
                }

                allLocations.sort { $0.date < $1.date }

                self?.previousSavedLocation = allLocations.last?.location
            }
        }
        if let previousSavedLocation = previousSavedLocation
        {
            let distanceFromPrevious = previousSavedLocation.distance(from: newLocation) - ((newLocation.horizontalAccuracy + newLocation.verticalAccuracy)/2)
            LogManager.shared.logData(context: "LocationManager", content: "Distance from previous saved location (adjusted): \(distanceFromPrevious) meters.", verbosity: 5)

            if distanceFromPrevious >= customDistanceFilter && timeSinceLastUpdate >= minimumUpdateInterval
            {
                LogManager.shared.logData(context: "LocationManager", content: "Decision: Adding Moving point. Reason: Distance (\(String(format: "%.1f",distanceFromPrevious))m >= \(customDistanceFilter)m) and Time (\(String(format: "%.1f",timeSinceLastUpdate))s >= \(minimumUpdateInterval)s) thresholds met.", verbosity: 4)
                adjustSettingsForMovement()
                currentFilteredLocation = newLocation
                self.previousSavedLocation = newLocation
                appendLocationToFile(type: .moving)
                lastUpdateTimestamp = newUpdateDate
                UserDefaults.standard.set(lastUpdateTimestamp, forKey: "lastUpdateTimestamp")
                UserDefaults.standard.set(LocationUpdateType.moving.rawValue, forKey: "lastUpdateType")

                if !self.filteredByPositionQueue.isEmpty {
                    self.filteredByPositionQueue.removeAll()
                    LogManager.shared.logData(context: "LocationManager", content: "Resetting filteredByPositionQueue because a new moving point was added.", verbosity: 4)
                }
            } else {
                if distanceFromPrevious < customDistanceFilter {
                    self.filteredByPositionQueue.append(newLocation)
                    if self.filteredByPositionQueue.count > filteredPositionQueueMaxSize {
                        self.filteredByPositionQueue.removeFirst()
                    }
                    LogManager.shared.logData(context: "LocationManager", content: "Added location to filteredByPositionQueue. Queue size: \(self.filteredByPositionQueue.count).", verbosity: 4)
                }
                 LogManager.shared.logData(context: "LocationManager", content: "Decision: Skipping point. Reason: Distance (\(String(format: "%.1f",distanceFromPrevious))m < \(customDistanceFilter)m) or Time (\(String(format: "%.1f",timeSinceLastUpdate))s < \(minimumUpdateInterval)s) threshold not met.", verbosity: 5)
                 
                let intervalMinutes = SettingsManager.shared.stationaryStepsUpdateInterval
                if intervalMinutes > 0, let lastCheck = self.lastPedometerCheckDate, Date().timeIntervalSince(lastCheck) >= Double(intervalMinutes * 60) {
                    LogManager.shared.logData(context: "LocationManager", content: "Triggering steps update from background location update since we are skipping points.", verbosity: 4)
                    self.updateStationarySteps()
                }
            }
        }
        else
        {
            // No previous location means this is the first update ever
            if timeSinceLastUpdate >= minimumUpdateInterval
            {
                LogManager.shared.logData(context: "LocationManager", content: "Decision: Adding Moving point. Reason: No previous location saved and Time (\(String(format: "%.1f",timeSinceLastUpdate))s >= \(minimumUpdateInterval)s) threshold met.", verbosity: 4)
                adjustSettingsForMovement()
                currentFilteredLocation = newLocation
                appendLocationToFile(type: .moving, debug: "No PreviousLocation")
                lastUpdateTimestamp = newUpdateDate
                UserDefaults.standard.set(lastUpdateTimestamp, forKey: "lastUpdateTimestamp")
                UserDefaults.standard.set(LocationUpdateType.moving.rawValue, forKey: "lastUpdateType")

                if !self.filteredByPositionQueue.isEmpty {
                    self.filteredByPositionQueue.removeAll()
                    LogManager.shared.logData(context: "LocationManager", content: "Resetting filteredByPositionQueue because a new moving point was added (no previous location).", verbosity: 4)
                }
            } else {
                LogManager.shared.logData(context: "LocationManager", content: "Decision: Skipping point. Reason: No previous location saved and Time (\(String(format: "%.1f",timeSinceLastUpdate))s < \(minimumUpdateInterval)s) threshold not met.", verbosity: 5)
            }
            self.previousSavedLocation = newLocation
        }
        currentDate = newUpdateDate

        let endTime = Date()
        let executionTime = endTime.timeIntervalSince(functionStartTime)
        let executionTimeString = String(format: "%.10f", executionTime)
        let logContent = "Execution time: \(executionTimeString) seconds - Call count: \(locationManagerCallCount)"
        LogManager.shared.logData(context: "LocationUpdate", content: logContent, verbosity: 5)
        
        ResourceTracker.shared.logResourceEvent(
            context: "LocationUpdate", 
            executionTime: executionTime, 
            extraInfo: ["Locations Received": String(locations.count)]
        )
    }
    private func adjustSettingsForMovement() {
        stopStationaryStepsUpdateTimer()
        self.cancelUnknownPlaceCheckInNotification()
        locationManager.stopUpdatingLocation()
        LogManager.shared.logData(context: "LocationManager", content: "Adjusting settings for movement. DistanceFilter: 20m.", verbosity: 4)
        locationManager.desiredAccuracy = SettingsManager.shared.movingLocationAccuracyLevel.clLocationAccuracy
        locationManager.startUpdatingLocation()
        customDistanceFilter = movingDistanceFilterConstant
        resetLocationUpdateTimer()
    }
    
    private func resetLocationUpdateTimer() {
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(SettingsManager.shared.stationaryDetectionTimer), repeats: false) { [weak self] _ in
            self?.adjustSettingsForStationary()
        }
    }
    
    private func startStationaryStepsUpdateTimer() {
        stopStationaryStepsUpdateTimer()
        let intervalMinutes = SettingsManager.shared.stationaryStepsUpdateInterval
        if intervalMinutes > 0 {
            stationaryStepsUpdateTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalMinutes * 60), repeats: true) { [weak self] _ in
                self?.updateStationarySteps()
            }
        }
    }

    private func stopStationaryStepsUpdateTimer() {
        stationaryStepsUpdateTimer?.invalidate()
        stationaryStepsUpdateTimer = nil
    }

    private func updateStationarySteps() {
        guard let startDate = self.lastPedometerCheckDate else { return }
        
        self.pedometer.queryPedometerData(from: startDate, to: Date()) { [weak self] data, error in
            guard let self = self else { return }
            
            if let pedometerData = data, error == nil {
                let steps = pedometerData.numberOfSteps.intValue
                DispatchQueue.main.async {
                    if steps > 0 {
                        LogManager.shared.logData(context: "LocationManager", content: "Stationary steps update: fetched \(steps) steps.", verbosity: 4)
                        GPXManager.shared.loadFile(forDate: Date()) { loadedGpxWaypoints, loadedGpxTracks in
                            if let lastElement = self.getMostRecentGPXElement(waypoints: loadedGpxWaypoints, tracks: loadedGpxTracks) {
                                let existingSteps = Int(lastElement.extensions?["Steps"].text ?? "0") ?? 0
                                let combinedSteps = existingSteps + steps
                                GPXUtils.updateExtension(for: lastElement, with: ["Steps": String(combinedSteps)])
                                GPXManager.shared.saveLocationData(loadedGpxWaypoints, tracks: loadedGpxTracks, forDate: Date())
                            }
                        }
                    }
                    self.lastPedometerCheckDate = Date()
                }
            } else {
                LogManager.shared.logData(context: "LocationManager", content: "Stationary steps update error: \(error?.localizedDescription ?? "unknown error")", verbosity: 2)
            }
        }
    }
    
    private func adjustSettingsForStationary() {
        startStationaryStepsUpdateTimer()
        customDistanceFilter = stationaryDistanceFilterConstant // Reset custom distance filter for stationary
        LogManager.shared.logData(context: "LocationManager", content: "Decision: Adding Stationary point. Reason: Timer expired. Adjusting distance filter to \(customDistanceFilter)m.", verbosity: 4)
        appendLocationToFile(type: .stationary)
        UserDefaults.standard.set(LocationUpdateType.stationary.rawValue, forKey: "lastUpdateType")
        locationManager.stopUpdatingLocation()
        locationManager.desiredAccuracy = SettingsManager.shared.stationaryLocationAccuracyLevel.clLocationAccuracy
        locationManager.startUpdatingLocation()

    }
    
    private func appendLocationToFile(type: LocationUpdateType, debug: String = "") {
        guard var location = currentFilteredLocation else {
            print("No location to save")
            LogManager.shared.logData(context: "GPXAppend", content: "Attempting to append point failed: currentFilteredLocation is nil. Type: \(type.rawValue), Debug: '\(debug)'.", verbosity: 2)
            return
        }

        if type == .stationary, !filteredByPositionQueue.isEmpty {
            let queueSize = filteredByPositionQueue.count
            LogManager.shared.logData(context: "GPXAppend", content: "Averaging location for stationary point from a queue of \(queueSize) points.", verbosity: 4)
            let count = Double(queueSize)
            let avgLatitude = filteredByPositionQueue.reduce(0.0) { $0 + $1.coordinate.latitude } / count
            let avgLongitude = filteredByPositionQueue.reduce(0.0) { $0 + $1.coordinate.longitude } / count
            let avgAltitude = filteredByPositionQueue.reduce(0.0) { $0 + $1.altitude } / count
            let avgHorizontalAccuracy = filteredByPositionQueue.reduce(0.0) { $0 + $1.horizontalAccuracy } / count
            let avgVerticalAccuracy = filteredByPositionQueue.reduce(0.0) { $0 + $1.verticalAccuracy } / count

            let avgCoordinate = CLLocationCoordinate2D(latitude: avgLatitude, longitude: avgLongitude)

            location = CLLocation(coordinate: avgCoordinate,
                                  altitude: avgAltitude,
                                  horizontalAccuracy: avgHorizontalAccuracy,
                                  verticalAccuracy: avgVerticalAccuracy,
                                  timestamp: Date())
        }
        
        let appendAttemptTime = Date()
        let appendId = UUID().uuidString.prefix(8)
        LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Attempting to append point at \(appendAttemptTime). Type: \(type.rawValue), Location: (\(location.coordinate.latitude), \(location.coordinate.longitude)), Debug: '\(debug)'.", verbosity: 3)

        if lastAppendCall != nil {
            let timeSinceLastAppend = appendAttemptTime.timeIntervalSince(lastAppendCall!)
            LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Debounce check: Current time \(appendAttemptTime), lastAppendCall \(String(describing: lastAppendCall)), difference: \(timeSinceLastAppend) seconds.", verbosity: 5)
            if timeSinceLastAppend < gpxAppendDebounceInterval {
                print ("Cowardly refusing to double append – debouncing.")
                LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Debounced append call. Type: \(type.rawValue).", verbosity: 4)
                return
            }
        }
        lastAppendCall = appendAttemptTime
        
        let dispatchGroup = DispatchGroup()

        if let startDate = self.lastPedometerCheckDate {
            dispatchGroup.enter()
            
            self.pedometer.queryPedometerData(from: startDate, to: Date()) { data, error in
                defer {
                    dispatchGroup.leave()
                }
                
                LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Querying pedometer data from \(startDate) to \(Date()).", verbosity: 4)
                if let pedometerData = data, error == nil {
                    self.latestPedometerSteps = pedometerData.numberOfSteps.intValue
                } else {
                    print("Pedometer data error: \(error?.localizedDescription ?? "unknown error")")
                    self.latestPedometerSteps = -1
                    LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Pedometer data error: \(error?.localizedDescription ?? "unknown error")", verbosity: 2)
                }
            }
        } else {
            LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] No start date for pedometer query.", verbosity: 3)
        }
        dispatchGroup.notify(queue: .main)
        {
            LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Pedometer query finished. Proceeding with GPX file operations.", verbosity: 4)
            GPXManager.shared.loadFile(forDate: Date()) 
            {   loadedGpxWaypoints, loadedGpxTracks in
               
                var gpxTracks = loadedGpxTracks
                var gpxWaypoints = loadedGpxWaypoints
                
                var stepsExtensionData: [String: String] = [:]
                if self.latestPedometerSteps > 0
                {
                    stepsExtensionData["Steps"] = String(self.latestPedometerSteps)
                    if let lastElement = self.getMostRecentGPXElement(waypoints: gpxWaypoints, tracks: gpxTracks){
                        GPXUtils.updateExtension(for: lastElement, with: stepsExtensionData)
                        LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Added 'Steps' extension to last element: \(String(describing: lastElement.time)).", verbosity: 4)
                    }
                    self.lastPedometerCheckDate = Date()
                }
                else if self.latestPedometerSteps == -1{
                    stepsExtensionData["Debug"] = "Steps error"
                    if let lastElement = self.getMostRecentGPXElement(waypoints: gpxWaypoints, tracks: gpxTracks){
                        GPXUtils.updateExtension(for: lastElement, with: stepsExtensionData)
                        LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Added 'Steps error' debug extension to last element: \(String(describing: lastElement.time)).", verbosity: 3)
                    } else {
                        LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Could not add 'Steps error' debug extension: No last element found.", verbosity: 2)
                    }
                }

                if type == .moving
                {
                    self.cancelUnknownPlaceCheckInNotification()
                    let newTrackPoint = GPXTrackPoint(
                        latitude: location.coordinate.latitude.roundedTo5DecimalPlaces(),
                        longitude: location.coordinate.longitude.roundedTo5DecimalPlaces()
                    )
                    newTrackPoint.time = Date()
                    newTrackPoint.elevation = location.altitude.roundedTo5DecimalPlaces()
                    
                    var customExtensionData: [String: String] = [
                        GPXExtensionKey.horizontalPrecision.rawValue: String(location.horizontalAccuracy.roundedTo5DecimalPlaces()),
                        GPXExtensionKey.verticalPrecision.rawValue: String(location.verticalAccuracy.roundedTo5DecimalPlaces()),
                        GPXExtensionKey.speed.rawValue: String(location.speed.roundedTo5DecimalPlaces()),
                        GPXExtensionKey.speedAccuracy.rawValue: String(location.speedAccuracy.roundedTo5DecimalPlaces()),
                        GPXExtensionKey.course.rawValue: String(location.course.roundedTo5DecimalPlaces()),
                        GPXExtensionKey.courseAccuracy.rawValue: String(location.courseAccuracy.roundedTo5DecimalPlaces()),
                        GPXExtensionKey.timezoneOffset.rawValue: String(TimeZone.current.secondsFromGMT())
                    ]
                    
                    if debug != "" {
                        customExtensionData[GPXExtensionKey.debug.rawValue] = debug
                    }
                    if let activity = self.latestActivity {
                        let activityConfidence: String = {
                            switch activity.confidence {
                            case .low: return ActivityConfidenceValue.low.rawValue
                            case .medium: return ActivityConfidenceValue.medium.rawValue
                            case .high: return ActivityConfidenceValue.high.rawValue
                            @unknown default: return ActivityConfidenceValue.unknown.rawValue
                            }
                        }()
                        customExtensionData[GPXExtensionKey.activityConfidence.rawValue] = activityConfidence
                        
                        if activity.walking { customExtensionData[GPXExtensionKey.walking.rawValue] = "True" }
                        if activity.running { customExtensionData[GPXExtensionKey.running.rawValue] = "True" }
                        if activity.cycling { customExtensionData[GPXExtensionKey.cycling.rawValue] = "True" }
                        if activity.automotive { customExtensionData[GPXExtensionKey.automotive.rawValue] = "True" }
                        if activity.stationary { customExtensionData[GPXExtensionKey.stationary.rawValue] = "True" }
                    }
                    
                    let extensions = GPXExtensions()
                    extensions.append(at: nil, contents: customExtensionData)
                    newTrackPoint.extensions = extensions
                    
                    var lastMajorActivityType = ""
                    if let activity = self.latestActivity {
                        if activity.automotive {
                            lastMajorActivityType = "automotive"
                        }
                        else if activity.running{
                            lastMajorActivityType = "running"
                        }
                        else if activity.walking{
                            lastMajorActivityType = "walking"
                        }
                        else if activity.cycling{
                            lastMajorActivityType = "cycling"
                        }
                    }
                    
                    if let lastTrack = gpxTracks.last, 
                        let lastSegment = lastTrack.segments.last,
                        lastSegment.points.last?.time ?? Date.distantFuture > gpxWaypoints.last?.time ?? Date.distantPast
                    {
                        
                        if lastMajorActivityType != "" && lastMajorActivityType != lastTrack.type
                            && (self.latestActivity?.confidence == CMMotionActivityConfidence.high || self.latestActivity?.confidence == CMMotionActivityConfidence.medium)
                        {
                            let newSegment = GPXTrackSegment()
                            newSegment.add(trackpoint: newTrackPoint)
                            let newTrack = GPXTrack()
                            newTrack.add(trackSegment: newSegment)
                            newTrack.type = lastMajorActivityType
                            gpxTracks.append(newTrack)
                        }
                        else
                        {
                            let modifiedLastTrack = lastTrack
                            let modifiedLastSegment = lastSegment
                            modifiedLastSegment.add(trackpoint: newTrackPoint)
                            modifiedLastTrack.segments[modifiedLastTrack.segments.count - 1] = modifiedLastSegment
                            gpxTracks[gpxTracks.count - 1] = modifiedLastTrack
                        }
                        
                    } else {
                        // No tracks or segments found, or the last track was earlier than the last point so create and add a new track and segment
                        let newSegment = GPXTrackSegment()
                        newSegment.add(trackpoint: newTrackPoint)
                        let newTrack = GPXTrack()
                        newTrack.add(trackSegment: newSegment)
                        if (lastMajorActivityType != "" )
                        {
                            newTrack.type = lastMajorActivityType
                        }
                        gpxTracks.append(newTrack)
                    }

                    let settings = SettingsManager.shared
                    if settings.automaticallyMergeUnknownToKnownTypeTracks,
                       let mergeResult = AutomaticTrackMerger.mergePreviousUnknownTrackIfEligible(
                            tracks: &gpxTracks,
                            waypoints: gpxWaypoints,
                            maximumUnknownPoints: settings.automaticMergeUnknownTrackMaxPoints,
                            minimumKnownPoints: settings.automaticMergeKnownTrackMinimumPoints
                       ) {
                        LogManager.shared.logData(
                            context: "AutomaticTrackMerge",
                            content: "[\(appendId)] Merged \(mergeResult.unknownPointCount)-point unknown track into \(mergeResult.knownType) track after it reached \(mergeResult.knownPointCount) known points.",
                            verbosity: 3
                        )
                    }
                }
                else if type == .stationary {
                    if self.shouldFilterAsRoundTrip(
                        newLocation: location,
                        gpxWaypoints: &gpxWaypoints,
                        gpxTracks: &gpxTracks,
                        appendId: String(appendId)
                    ) {
                        GPXManager.shared.saveLocationData(gpxWaypoints, tracks: gpxTracks, forDate: Date())
                        if let userDefaults = UserDefaults(suiteName: "group.DeltaCygniLabs.Life2Gpx") {
                            userDefaults.set(Date.now, forKey: "lastUpdateTimestamp")
                            userDefaults.set(type.rawValue, forKey: "lastUpdateType")
                            userDefaults.synchronize()
                            self.dataHasBeenUpdated = true
                            self.lastUpdateTimestamp = Date.now
                        }
                        return
                    }

                    let newWaypoint = GPXWaypoint(
                        latitude: location.coordinate.latitude.roundedTo5DecimalPlaces(),
                        longitude: location.coordinate.longitude.roundedTo5DecimalPlaces()
                    )
                    newWaypoint.time = Date()
                    newWaypoint.elevation = location.altitude.roundedTo5DecimalPlaces()
                    
                    if let matchingPlace = PlaceManager.shared.findPlaceAtCoordinates(for: location.coordinate) {
                        self.cancelUnknownPlaceCheckInNotification()
                        newWaypoint.name = matchingPlace.name
                        
                        var customExtensionData: [String: String] = [
                            GPXExtensionKey.horizontalPrecision.rawValue: String(location.horizontalAccuracy.roundedTo5DecimalPlaces()),
                            GPXExtensionKey.verticalPrecision.rawValue: String(location.verticalAccuracy.roundedTo5DecimalPlaces()),
                            GPXExtensionKey.placeId.rawValue: matchingPlace.placeId,
                            GPXExtensionKey.timezoneOffset.rawValue: String(TimeZone.current.secondsFromGMT())
                        ]
                        
                        if let address = matchingPlace.streetAddress {
                            customExtensionData[GPXExtensionKey.address.rawValue] = address
                        }
                        if let fbId = matchingPlace.facebookPlaceId {
                            customExtensionData[GPXExtensionKey.facebookPlaceId.rawValue] = fbId
                        }
                        if let mapboxId = matchingPlace.mapboxPlaceId {
                            customExtensionData[GPXExtensionKey.mapboxPlaceId.rawValue] = mapboxId
                        }
                        if let foursquareId = matchingPlace.foursquareVenueId {
                            customExtensionData[GPXExtensionKey.foursquareVenueId.rawValue] = foursquareId
                        }
                        
                        if debug != "" {
                            customExtensionData[GPXExtensionKey.debug.rawValue] = debug
                        }
                        
                        let extensions = GPXExtensions()
                        extensions.append(at: nil, contents: customExtensionData)
                        newWaypoint.extensions = extensions
                    } else {
                        var customExtensionData: [String: String] = [
                            GPXExtensionKey.horizontalPrecision.rawValue: String(location.horizontalAccuracy.roundedTo5DecimalPlaces()),
                            GPXExtensionKey.verticalPrecision.rawValue: String(location.verticalAccuracy.roundedTo5DecimalPlaces()),
                            GPXExtensionKey.timezoneOffset.rawValue: String(TimeZone.current.secondsFromGMT())
                        ]
                        if debug != "" {
                            customExtensionData[GPXExtensionKey.debug.rawValue] = debug
                        }
                        let extensions = GPXExtensions()
                        extensions.append(at: nil, contents: customExtensionData)
                        newWaypoint.extensions = extensions
                        self.scheduleUnknownPlaceCheckInNotification(for: newWaypoint)
                    }
                    
                    gpxWaypoints.append(newWaypoint)
                }

                GPXManager.shared.saveLocationData(gpxWaypoints, tracks: gpxTracks, forDate: Date())
                if let userDefaults = UserDefaults(suiteName: "group.DeltaCygniLabs.Life2Gpx") {
                    userDefaults.set(Date.now, forKey: "lastUpdateTimestamp")
                    userDefaults.set(type.rawValue, forKey: "lastUpdateType")
                    userDefaults.synchronize()
                    self.dataHasBeenUpdated = true
                    self.lastUpdateTimestamp = Date.now
                    LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Successfully appended point. Type: \(type.rawValue). Updated self.lastUpdateTimestamp to \(String(describing: self.lastUpdateTimestamp)).", verbosity: 3)
                } else {
                    LogManager.shared.logData(context: "GPXAppend", content: "[\(appendId)] Failed to get UserDefaults.", verbosity: 2)
                }
            }
        }
    }

    private func checkBackgroundTasks() {
        let now = Date()
        if now.timeIntervalSince(lastBackgroundTaskCheck) > 60 {
            lastBackgroundTaskCheck = now
            DispatchQueue.main.async {
                iCloudBackupManager.shared.checkAndRunBackupIfNeeded()
            }
        }
    }

    private func shouldFilterAsRoundTrip(
        newLocation: CLLocation,
        gpxWaypoints: inout [GPXWaypoint],
        gpxTracks: inout [GPXTrack],
        appendId: String
    ) -> Bool {
        let settings = SettingsManager.shared
        guard settings.filterSmallRoundTrips else { return false }

        guard let lastTrack = gpxTracks.last,
              let firstSegment = lastTrack.segments.first,
              let firstPointTime = firstSegment.points.first?.time,
              lastTrack.segments.last?.points.last?.time ?? Date.distantPast > gpxWaypoints.last?.time ?? Date.distantFuture
        else {
            return false
        }

        let totalTrackPoints = lastTrack.segments.reduce(0) { $0 + $1.points.count }
        guard totalTrackPoints <= settings.roundTripMaxPoints else {
            LogManager.shared.logData(context: "RoundTripFilter", content: "[\(appendId)] Track has \(totalTrackPoints) points, exceeds max \(settings.roundTripMaxPoints). Not filtering.", verbosity: 4)
            return false
        }

        guard let previousWaypoint = gpxWaypoints.last,
              let previousWaypointTime = previousWaypoint.time,
              previousWaypointTime < firstPointTime
        else {
            LogManager.shared.logData(context: "RoundTripFilter", content: "[\(appendId)] No preceding waypoint found before the track. Not filtering.", verbosity: 4)
            return false
        }

        let previousPlaceId = previousWaypoint.extensions?["PlaceId"].text
        let radius: Double
        if let placeId = previousPlaceId,
           let place = PlaceManager.shared.getAllPlaces().first(where: { $0.placeId == placeId }) {
            radius = place.radius
        } else {
            radius = Double(settings.roundTripUnknownRadius)
        }

        guard let prevLat = previousWaypoint.latitude, let prevLon = previousWaypoint.longitude else {
            return false
        }
        let previousLocation = CLLocation(latitude: prevLat, longitude: prevLon)
        let distance = newLocation.distance(from: previousLocation)

        guard distance <= radius else {
            LogManager.shared.logData(context: "RoundTripFilter", content: "[\(appendId)] New point is \(String(format: "%.1f", distance))m from previous waypoint, exceeds radius \(String(format: "%.1f", radius))m. Not filtering.", verbosity: 4)
            return false
        }

        var trackSteps = 0
        for segment in lastTrack.segments {
            for point in segment.points {
                trackSteps += Int(point.extensions?["Steps"].text ?? "0") ?? 0
            }
        }

        let existingSteps = Int(previousWaypoint.extensions?["Steps"].text ?? "0") ?? 0
        let combinedSteps = existingSteps + trackSteps
        if combinedSteps > 0 {
            GPXUtils.updateExtension(for: previousWaypoint, with: ["Steps": String(combinedSteps)])
        }

        gpxTracks.removeLast()

        LogManager.shared.logData(context: "RoundTripFilter", content: "[\(appendId)] Round trip track filtered: \(totalTrackPoints) points, \(String(format: "%.1f", distance))m from previous waypoint (radius: \(String(format: "%.1f", radius))m). Transferred \(trackSteps) steps to previous waypoint (total: \(combinedSteps)). Track removed, new point not saved.", verbosity: 3)

        return true
    }

    func getMostRecentGPXElement(waypoints: [GPXWaypoint], tracks: [GPXTrack]) -> (GPXWaypoint?) {
        let lastWaypoint = waypoints.last
        let lastTrackPoint = tracks.last?.segments.last?.points.last

        var mostRecentElement: GPXWaypoint? = nil
        var mostRecentTime: Date? = nil
        var elementType: String = "None"

        if let waypointTime = lastWaypoint?.time, let trackpointTime = lastTrackPoint?.time {
            if waypointTime > trackpointTime {
                mostRecentElement = lastWaypoint
                mostRecentTime = waypointTime
                elementType = "Waypoint"
            } else {
                mostRecentElement = lastTrackPoint
                mostRecentTime = trackpointTime
                elementType = "TrackPoint"
            }
        } else if let waypointTime = lastWaypoint?.time {
            mostRecentElement = lastWaypoint
            mostRecentTime = waypointTime
            elementType = "Waypoint"
        } else if let trackpointTime = lastTrackPoint?.time {
            mostRecentElement = lastTrackPoint
            mostRecentTime = trackpointTime
            elementType = "TrackPoint"
        }
        LogManager.shared.logData(context: "GPXUtil", content: "getMostRecentGPXElement found: Type: \(elementType), Time: \(String(describing: mostRecentTime)).", verbosity: 5)
        return mostRecentElement
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let functionStartTime = Date()
        
        DispatchQueue.main.async {
            let rawHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            if let lastRaw = self.lastRawHeading {
                var diff = rawHeading - lastRaw
                if diff > 180 {
                    diff -= 360
                } else if diff < -180 {
                    diff += 360
                }
                self.heading += diff
            } else {
                self.heading = rawHeading
            }
            self.lastRawHeading = rawHeading
        }
        
        let endTime = Date()
        let executionTime = endTime.timeIntervalSince(functionStartTime)
        let executionTimeString = String(format: "%.10f", executionTime)
        let logContent = "Execution time: \(executionTimeString) seconds"
        LogManager.shared.logData(context: "HeadingUpdate", content: logContent, verbosity: 5)
        
        ResourceTracker.shared.logResourceEvent(
            context: "HeadingUpdate", 
            executionTime: executionTime, 
            extraInfo: ["TrueHeading": String(newHeading.trueHeading), "MagneticHeading": String(newHeading.magneticHeading)]
        )
    }
}

enum AutomaticTrackMerger {
    struct MergeResult {
        let unknownPointCount: Int
        let knownPointCount: Int
        let knownType: String
    }

    static func mergePreviousUnknownTrackIfEligible(
        tracks: inout [GPXTrack],
        waypoints: [GPXWaypoint],
        maximumUnknownPoints: Int,
        minimumKnownPoints: Int
    ) -> MergeResult? {
        guard tracks.count >= 2 else { return nil }

        let knownTrackIndex = tracks.count - 1
        let unknownTrackIndex = knownTrackIndex - 1
        let knownTrack = tracks[knownTrackIndex]
        let unknownTrack = tracks[unknownTrackIndex]

        guard let knownType = normalizedKnownType(knownTrack.type),
              isUnknownType(unknownTrack.type)
        else {
            return nil
        }

        let knownPointCount = pointCount(in: knownTrack)
        let unknownPointCount = pointCount(in: unknownTrack)
        guard knownPointCount >= minimumKnownPoints,
              unknownPointCount > 0,
              unknownPointCount <= maximumUnknownPoints,
              let unknownEndTime = unknownTrack.segments.last?.points.last?.time,
              let knownStartTime = knownTrack.segments.first?.points.first?.time,
              unknownEndTime <= knownStartTime
        else {
            return nil
        }

        if let mostRecentWaypointTime = waypoints.compactMap(\.time).max(),
           mostRecentWaypointTime > unknownEndTime {
            return nil
        }

        knownTrack.segments.insert(contentsOf: unknownTrack.segments, at: 0)
        tracks.remove(at: unknownTrackIndex)

        return MergeResult(
            unknownPointCount: unknownPointCount,
            knownPointCount: knownPointCount,
            knownType: knownType
        )
    }

    private static func pointCount(in track: GPXTrack) -> Int {
        track.segments.reduce(0) { $0 + $1.points.count }
    }

    private static func normalizedKnownType(_ type: String?) -> String? {
        let normalized = type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty, normalized.caseInsensitiveCompare("unknown") != .orderedSame else {
            return nil
        }
        return normalized
    }

    private static func isUnknownType(_ type: String?) -> Bool {
        normalizedKnownType(type) == nil
    }
}
