import SwiftUI
import CoreLocation
import CoreGPX
import CoreMotion
import UserNotifications

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentFilteredLocation: CLLocation?
    @Published var dataHasBeenUpdated: Bool = false

    private var previousSavedLocation: CLLocation?
    private var locationUpdateTimer: Timer?
    private var customDistanceFilter: CLLocationDistance = 20
    private var currentDate: Date?
    private let minimumUpdateInterval: TimeInterval = 30
    private var lastUpdateTimestamp: Date?
    private let motionActivityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()
    private var latestActivity: CMMotionActivity?
    private let pedometer = CMPedometer()
    private var lastPedometerCheckDate: Date?
    private var latestPedometerSteps: Int = 0
    private var midnightTimer: Timer?
    private let userDefaults = UserDefaults(suiteName: "group.DeltaCygniLabs.Life2Gpx")
    private var lastAppendCall: Date?
    private var notificationResetTimer: Timer?
    private var locationManagerCallCount = 0
    private var lastLocationManagerCallTimestamp: Date?
    private var locationHistory: [(location: CLLocation, receivedAt: Date)] = []
    private let locationHistoryLock = NSLock()
    private var filteredByPositionQueue: [CLLocation] = []

    override init() {
        super.init()
        FileManagerUtil.logData(context: "LocationManagerInit", content: "Initializing LocationManager.", verbosity: 3)
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
        
        setupLocationManager()
        setupMotionActivityManager()
        setupPedometer()
        scheduleMidnightUpdate()
        currentDate = Date()
        
        //these are for notifying the
        scheduleDeadMansSwitchNotification()
        startNotificationResetTimer()

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
            //extra 10 seconds of grace in case clock ran a little bit too fast. It happened.
            let adjustedInterval = (timeIntervalUntilMidnight > 0 ? timeIntervalUntilMidnight : timeIntervalUntilMidnight + 86400) + 10
            FileManagerUtil.logData(context: "LocationManager", content: "Scheduling midnight update in \(adjustedInterval) seconds.", verbosity: 4)
            midnightTimer = Timer.scheduledTimer(timeInterval: adjustedInterval, target: self, selector: #selector(forceMidnightUpdate), userInfo: nil, repeats: false)
        }
        
    @objc private func forceMidnightUpdate() {
        if currentFilteredLocation == nil {
            if let location = locationManager.location {
                currentFilteredLocation = location
                FileManagerUtil.logData(context: "LocationManager", content: "ForceMidnightUpdate: Using last known locationmanager location.", verbosity: 4)
            } else {
                FileManagerUtil.logData(context: "LocationManager", content: "ForceMidnightUpdate: No current location available to force update.", verbosity: 2)
                scheduleMidnightUpdate() // Reschedule if we couldn't update
                return
            }
        }
        let updateType = UserDefaults.standard.string(forKey: "lastUpdateType") ?? "Stationary"
        FileManagerUtil.logData(context: "LocationManager", content: "ForceMidnightUpdate: Forcing update with type: \(updateType).", verbosity: 3)
        appendLocationToFile(type: updateType, debug: "Midnight Update")
        scheduleMidnightUpdate()
    }
    
    private func scheduleDeadMansSwitchNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests() // Clear any existing notifications

        let content = UNMutableNotificationContent()
        content.title = "Recording Stopped"
        content.body = "Life2Gpx probably crashed and stopped recording. Tap here to restart it. Sorry!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false) // 5 minutes

        let request = UNNotificationRequest(identifier: "DeadMansSwitch", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }

    private func startNotificationResetTimer() {
        notificationResetTimer?.invalidate() // Invalidate any existing timer
        notificationResetTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            self?.scheduleDeadMansSwitchNotification()
        }
    }

    private func stopNotificationResetTimer() {
        notificationResetTimer?.invalidate()
        notificationResetTimer = nil
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
        FileManagerUtil.logData(context: "LocationManager", content: "Setting up location manager.", verbosity: 5)
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        //if the filter is set, the background location updates will be absolutely unreliable. 
        //https://developer.apple.com/forums/thread/776698?answerId=829420022#829420022
        //maybe it could be set to other values when the app is in the foreground. 
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let functionStartTime = Date()
        let currentTime = Date()

        locationManagerCallCount += 1
        FileManagerUtil.logData(context: "LocationManager", content: "Function called. Call count: \(locationManagerCallCount).", verbosity: 5)

        guard let newLocation = locations.last else { return }
           
        var shouldProcessThisLocation: Bool
        locationHistoryLock.lock()
        if let lastEntryInHistory = locationHistory.last {
            if currentTime.timeIntervalSince(lastEntryInHistory.receivedAt) > 1.0 {
                shouldProcessThisLocation = true
                FileManagerUtil.logData(context: "LocationManager", content: "Proceeding: currentTime \(currentTime) > 1s after last history item receivedAt \(lastEntryInHistory.receivedAt). Interval: \(String(format: "%.3f", currentTime.timeIntervalSince(lastEntryInHistory.receivedAt)))s.", verbosity: 5)
            } else {
                shouldProcessThisLocation = false
                FileManagerUtil.logData(context: "LocationManager", content: "Debouncing: currentTime \(currentTime) NOT > 1s after last history item receivedAt \(lastEntryInHistory.receivedAt). Interval: \(String(format: "%.3f", currentTime.timeIntervalSince(lastEntryInHistory.receivedAt)))s.", verbosity: 5)
            }
        } else {
            shouldProcessThisLocation = true
            FileManagerUtil.logData(context: "LocationManager", content: "Proceeding: History empty, allowing first entry at \(currentTime).", verbosity: 5)
        }
           
        if shouldProcessThisLocation {
            locationHistory.append((location: newLocation, receivedAt: currentTime))
            if locationHistory.count > 20 {
                locationHistory.removeFirst()
            }
            locationHistoryLock.unlock()
            FileManagerUtil.logData(context: "LocationManager", content: "Location added to history. LocTS: \(newLocation.timestamp), RecTS: \(currentTime). History size: \(locationHistory.count).", verbosity: 5)
        } else {
            FileManagerUtil.logData(context: "LocationManager", content: "Debouncing location update.", verbosity: 5)
            locationHistoryLock.unlock()
            return
        }

           
        let newUpdateDate = Date()
        FileManagerUtil.logData(context: "LocationManager", content: "Received location: (\(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)), HAcc: \(newLocation.horizontalAccuracy), VAcc: \(newLocation.verticalAccuracy), Alt: \(newLocation.altitude), Speed: \(newLocation.speed), Time: \(newLocation.timestamp)", verbosity: 5)

        //forcing update if it's the new day and somehow midnight scheduler has screwed. TODO: add a grace period as this thing is making double updates now
        if let previousUpdateDate = currentDate, Calendar.current.isDate(previousUpdateDate, inSameDayAs: newUpdateDate) == false {
            let calendar = Calendar.current
            let startOfNewDay = calendar.startOfDay(for: newUpdateDate)
            if newUpdateDate.timeIntervalSince(startOfNewDay) >= 10 {
                FileManagerUtil.logData(context: "LocationManager", content: "New day detected (after 10s grace period), forcing midnight update.", verbosity: 2)
                forceMidnightUpdate()
            } else {
                FileManagerUtil.logData(context: "LocationManager", content: "New day detected, but within 10s grace period. Not forcing midnight update yet. newUpdateDate: \(newUpdateDate), startOfNewDay: \(startOfNewDay)", verbosity: 4)
            }
        }
        // Default to allow update if no previous timestamp; abs to prevent manual change of dates to distant future completely screwing up the eval.
        let timeSinceLastUpdate = abs(lastUpdateTimestamp.map { newUpdateDate.timeIntervalSince($0) } ?? minimumUpdateInterval + 1)
        FileManagerUtil.logData(context: "LocationManager", content: "Time since last update: \(timeSinceLastUpdate) seconds.", verbosity: 5)
        FileManagerUtil.logData(context: "LocationManager", content: "Using lastUpdateTimestamp: \(String(describing: lastUpdateTimestamp)) for calculation.", verbosity: 5)

        
        if previousSavedLocation == nil {
            FileManagerUtil.logData(context: "LocationManager", content: "No previous location saved, loading file.", verbosity: 4)
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
            FileManagerUtil.logData(context: "LocationManager", content: "Distance from previous saved location (adjusted): \(distanceFromPrevious) meters.", verbosity: 5)

            if distanceFromPrevious >= customDistanceFilter && timeSinceLastUpdate >= minimumUpdateInterval
            {
                FileManagerUtil.logData(context: "LocationManager", content: "Decision: Adding Moving point. Reason: Distance (\(String(format: "%.1f",distanceFromPrevious))m >= \(customDistanceFilter)m) and Time (\(String(format: "%.1f",timeSinceLastUpdate))s >= \(minimumUpdateInterval)s) thresholds met.", verbosity: 4)
                adjustSettingsForMovement()
                currentFilteredLocation = newLocation
                self.previousSavedLocation = newLocation
                appendLocationToFile(type: "Moving")
                lastUpdateTimestamp = newUpdateDate
                UserDefaults.standard.set(lastUpdateTimestamp, forKey: "lastUpdateTimestamp")
                UserDefaults.standard.set("Moving", forKey: "lastUpdateType")

                if !self.filteredByPositionQueue.isEmpty {
                    self.filteredByPositionQueue.removeAll()
                    FileManagerUtil.logData(context: "LocationManager", content: "Resetting filteredByPositionQueue because a new moving point was added.", verbosity: 4)
                }
            } else {
                if distanceFromPrevious < customDistanceFilter {
                    self.filteredByPositionQueue.append(newLocation)
                    if self.filteredByPositionQueue.count > 10 {
                        self.filteredByPositionQueue.removeFirst()
                    }
                    FileManagerUtil.logData(context: "LocationManager", content: "Added location to filteredByPositionQueue. Queue size: \(self.filteredByPositionQueue.count).", verbosity: 4)
                }
                 FileManagerUtil.logData(context: "LocationManager", content: "Decision: Skipping point. Reason: Distance (\(String(format: "%.1f",distanceFromPrevious))m < \(customDistanceFilter)m) or Time (\(String(format: "%.1f",timeSinceLastUpdate))s < \(minimumUpdateInterval)s) threshold not met.", verbosity: 5)
            }
        }
        else
        {
            // No previous location means this is the first update ever
            if timeSinceLastUpdate >= minimumUpdateInterval
            {
                FileManagerUtil.logData(context: "LocationManager", content: "Decision: Adding Moving point. Reason: No previous location saved and Time (\(String(format: "%.1f",timeSinceLastUpdate))s >= \(minimumUpdateInterval)s) threshold met.", verbosity: 4)
                adjustSettingsForMovement()
                currentFilteredLocation = newLocation
                appendLocationToFile(type: "Moving", debug: "No PreviousLocation")
                lastUpdateTimestamp = newUpdateDate
                UserDefaults.standard.set(lastUpdateTimestamp, forKey: "lastUpdateTimestamp")
                UserDefaults.standard.set("Moving", forKey: "lastUpdateType")

                if !self.filteredByPositionQueue.isEmpty {
                    self.filteredByPositionQueue.removeAll()
                    FileManagerUtil.logData(context: "LocationManager", content: "Resetting filteredByPositionQueue because a new moving point was added (no previous location).", verbosity: 4)
                }
            } else {
                FileManagerUtil.logData(context: "LocationManager", content: "Decision: Skipping point. Reason: No previous location saved and Time (\(String(format: "%.1f",timeSinceLastUpdate))s < \(minimumUpdateInterval)s) threshold not met.", verbosity: 5)
            }
            self.previousSavedLocation = newLocation
        }
        currentDate = newUpdateDate

        let endTime = Date()
        let executionTime = endTime.timeIntervalSince(functionStartTime)
        let executionTimeString = String(format: "%.10f", executionTime)
        let logContent = "Execution time: \(executionTimeString) seconds - Call count: \(locationManagerCallCount)"
        FileManagerUtil.logData(context: "LocationUpdate", content: logContent, verbosity: 5)
    }
    private func adjustSettingsForMovement() {
        FileManagerUtil.logData(context: "LocationManager", content: "Adjusting settings for movement. Accuracy: Best, DistanceFilter: 20m.", verbosity: 4)
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        customDistanceFilter = 20
        resetLocationUpdateTimer()
    }
    
    private func resetLocationUpdateTimer() {
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            self?.adjustSettingsForStationary()
        }
    }
    
    private func adjustSettingsForStationary() {

        customDistanceFilter = 60 // Reset custom distance filter for movement
        FileManagerUtil.logData(context: "LocationManager", content: "Decision: Adding Stationary point. Reason: Timer expired. Adjusting distance filter to \(customDistanceFilter)m.", verbosity: 4)
        appendLocationToFile(type: "Stationary")
        UserDefaults.standard.set("Stationary", forKey: "lastUpdateType")

    }
    
    private func appendLocationToFile(type: String, debug: String = "") {
        guard var location = currentFilteredLocation else {
            print("No location to save")
            FileManagerUtil.logData(context: "GPXAppend", content: "Attempting to append point failed: currentFilteredLocation is nil. Type: \(type), Debug: '\(debug)'.", verbosity: 2)
            return
        }

        if type == "Stationary", !filteredByPositionQueue.isEmpty {
            let queueSize = filteredByPositionQueue.count
            FileManagerUtil.logData(context: "GPXAppend", content: "Averaging location for stationary point from a queue of \(queueSize) points.", verbosity: 4)
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
        FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Attempting to append point at \(appendAttemptTime). Type: \(type), Location: (\(location.coordinate.latitude), \(location.coordinate.longitude)), Debug: '\(debug)'.", verbosity: 3)

        if lastAppendCall != nil {
            let timeSinceLastAppend = appendAttemptTime.timeIntervalSince(lastAppendCall!)
            FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Debounce check: Current time \(appendAttemptTime), lastAppendCall \(String(describing: lastAppendCall)), difference: \(timeSinceLastAppend) seconds.", verbosity: 5)
            if timeSinceLastAppend < 1 {
                print ("Cowardly refusing to double append – debouncing.")
                FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Debounced append call. Type: \(type).", verbosity: 4)
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
                
                FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Querying pedometer data from \(startDate) to \(Date()).", verbosity: 4)
                if let pedometerData = data, error == nil {
                    self.latestPedometerSteps = pedometerData.numberOfSteps.intValue
                } else {
                    print("Pedometer data error: \(error?.localizedDescription ?? "unknown error")")
                    self.latestPedometerSteps = -1
                    FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Pedometer data error: \(error?.localizedDescription ?? "unknown error")", verbosity: 2)
                }
            }
        } else {
            FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] No start date for pedometer query.", verbosity: 3)
        }
        dispatchGroup.notify(queue: .main)
        {
            FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Pedometer query finished. Proceeding with GPX file operations.", verbosity: 4)
            GPXManager.shared.loadFile(forDate: Date()) 
            {   loadedGpxWaypoints, loadedGpxTracks in
               
                var gpxTracks = loadedGpxTracks
                var gpxWaypoints = loadedGpxWaypoints
                
                var stepsExtensionData: [String: String] = [:]
                if self.latestPedometerSteps > 0
                {
                    stepsExtensionData["Steps"] = String(self.latestPedometerSteps)
                    if let lastElement = self.getMostRecentGPXElement(waypoints: gpxWaypoints, tracks: gpxTracks){
                        lastElement.extensions?.append(at: nil, contents: stepsExtensionData)
                        FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Added 'Steps' extension to last element: \(String(describing: lastElement.time)).", verbosity: 4)
                    }
                    self.lastPedometerCheckDate = Date()
                }
                else if self.latestPedometerSteps == -1{
                    stepsExtensionData["Debug"] = "Steps error"
                    if let lastElement = self.getMostRecentGPXElement(waypoints: gpxWaypoints, tracks: gpxTracks){
                        lastElement.extensions?.append(at: nil, contents: stepsExtensionData)
                        FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Added 'Steps error' debug extension to last element: \(String(describing: lastElement.time)).", verbosity: 3)
                    } else {
                        FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Could not add 'Steps error' debug extension: No last element found.", verbosity: 2)
                    }
                }

                if type == "Moving"
                {
                    let newTrackPoint = GPXTrackPoint(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    newTrackPoint.time = Date()
                    newTrackPoint.elevation = location.altitude
                    
                    var customExtensionData: [String: String] = [
                        "HorizontalPrecision": String(location.horizontalAccuracy),
                        "VerticalPrecision": String(location.verticalAccuracy),
                        "Speed": String(location.speed),
                        "SpeedAccuracy": String(location.speedAccuracy),
                    ]
                    
                    if debug != "" {
                        customExtensionData["Debug"] = debug
                    }
                    if let activity = self.latestActivity {
                        let activityConfidence: String = {
                            switch activity.confidence {
                            case .low: return "Low"
                            case .medium: return "Medium"
                            case .high: return "High"
                            @unknown default: return "Unknown"
                            }
                        }()
                        customExtensionData["ActivityConfidence"] = activityConfidence
                        
                        if activity.walking { customExtensionData["Walking"] = "True" }
                        if activity.running { customExtensionData["Running"] = "True" }
                        if activity.cycling { customExtensionData["Cycling"] = "True" }
                        if activity.automotive { customExtensionData["Automotive"] = "True" }
                        if activity.stationary { customExtensionData["Stationary"] = "True" }
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
                }
                else if type == "Stationary" {
                    let newWaypoint = GPXWaypoint(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    newWaypoint.time = Date()
                    newWaypoint.elevation = location.altitude
                    
                    if let matchingPlace = PlaceManager.shared.findPlaceAtCoordinates(for: location.coordinate) {
                        newWaypoint.name = matchingPlace.name
                        
                        var customExtensionData: [String: String] = [
                            "HorizontalPrecision": String(location.horizontalAccuracy),
                            "VerticalPrecision": String(location.verticalAccuracy),
                            "PlaceId": matchingPlace.placeId,
                        ]
                        
                        if let address = matchingPlace.streetAddress {
                            customExtensionData["Address"] = address
                        }
                        if let fbId = matchingPlace.facebookPlaceId {
                            customExtensionData["FacebookPlaceId"] = fbId
                        }
                        if let mapboxId = matchingPlace.mapboxPlaceId {
                            customExtensionData["MapboxPlaceId"] = mapboxId
                        }
                        if let foursquareId = matchingPlace.foursquareVenueId {
                            customExtensionData["FoursquareVenueId"] = foursquareId
                        }
                        
                        if debug != "" {
                            customExtensionData["Debug"] = debug
                        }
                        
                        let extensions = GPXExtensions()
                        extensions.append(at: nil, contents: customExtensionData)
                        newWaypoint.extensions = extensions
                    } else {
                        var customExtensionData: [String: String] = [
                            "HorizontalPrecision": String(location.horizontalAccuracy),
                            "VerticalPrecision": String(location.verticalAccuracy)
                        ]
                        if debug != "" {
                            customExtensionData["Debug"] = debug
                        }
                        let extensions = GPXExtensions()
                        extensions.append(at: nil, contents: customExtensionData)
                        newWaypoint.extensions = extensions
                    }
                    
                    gpxWaypoints.append(newWaypoint)
                }

                GPXManager.shared.saveLocationData(gpxWaypoints, tracks: gpxTracks, forDate: Date())
                if let userDefaults = UserDefaults(suiteName: "group.DeltaCygniLabs.Life2Gpx") {
                    userDefaults.set(Date.now, forKey: "lastUpdateTimestamp")
                    userDefaults.set(type, forKey: "lastUpdateType")
                    userDefaults.synchronize()
                    self.dataHasBeenUpdated = true
                    self.lastUpdateTimestamp = Date.now
                    FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Successfully appended point. Type: \(type). Updated self.lastUpdateTimestamp to \(String(describing: self.lastUpdateTimestamp)).", verbosity: 3)
                } else {
                    FileManagerUtil.logData(context: "GPXAppend", content: "[\(appendId)] Failed to get UserDefaults.", verbosity: 2)
                }
            }
        }
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
        FileManagerUtil.logData(context: "GPXUtil", content: "getMostRecentGPXElement found: Type: \(elementType), Time: \(String(describing: mostRecentTime)).", verbosity: 5)
        return mostRecentElement
    }
}
