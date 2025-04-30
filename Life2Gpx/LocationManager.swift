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

    override init() {
        super.init()
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
            midnightTimer = Timer.scheduledTimer(timeInterval: adjustedInterval, target: self, selector: #selector(forceMidnightUpdate), userInfo: nil, repeats: false)
        }
        
    @objc private func forceMidnightUpdate() {
        if currentFilteredLocation == nil {
            if let location = locationManager.location {
                currentFilteredLocation = location
            }
        }
        if let lastUpdateType = UserDefaults.standard.string(forKey: "lastUpdateType") {
            appendLocationToFile(type: lastUpdateType)
        } else {
            appendLocationToFile(type: "Stationary")
        }
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
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 20
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let functionStartTime = Date()
        locationManagerCallCount += 1

        guard let newLocation = locations.last else { return }
           
        let newUpdateDate = Date()
        //forcing update if it's the new day and somehow midnight scheduler has screwed.
        if let previousUpdateDate = currentDate, Calendar.current.isDate(previousUpdateDate, inSameDayAs: newUpdateDate) == false {
            forceMidnightUpdate()
        }
        // Default to allow update if no previous timestamp; abs to prevent manual change of dates to distant future completely screwing up the eval.
        let timeSinceLastUpdate = abs(lastUpdateTimestamp.map { newUpdateDate.timeIntervalSince($0) } ?? minimumUpdateInterval + 1)

        
        if previousSavedLocation == nil {
            GPXManager.shared.loadFile(forDate: Date()) { [weak self] loadedGpxWaypoints, loadedGpxTracks in
                var allLocations: [(location: CLLocation, date: Date)] = []

                // Add waypoints to the collection
                for waypoint in loadedGpxWaypoints {
                    if let date = waypoint.time {
                        allLocations.append((CLLocation(latitude: waypoint.latitude ?? 0, longitude: waypoint.longitude ?? 0), date))
                    }
                }

                // Add trackpoints to the collection
                for track in loadedGpxTracks {
                    for segment in track.segments {
                        for trackpoint in segment.points {
                            if let date = trackpoint.time {
                                allLocations.append((CLLocation(latitude: trackpoint.latitude ?? 0, longitude: trackpoint.longitude ?? 0), date))
                            }
                        }
                    }
                }

                // Sort all locations by date
                allLocations.sort { $0.date < $1.date }

                // Update previousSavedLocation with the most recent location, if available
                self?.previousSavedLocation = allLocations.last?.location
            }
        }
        if let previousSavedLocation = previousSavedLocation
        {
            let distanceFromPrevious = previousSavedLocation.distance(from: newLocation) - ((newLocation.horizontalAccuracy + newLocation.verticalAccuracy)/2)
            if distanceFromPrevious >= customDistanceFilter && timeSinceLastUpdate >= minimumUpdateInterval
            {
                // Movement significant enough to trigger updates and reset timer
                adjustSettingsForMovement()
                currentFilteredLocation = newLocation
                self.previousSavedLocation = newLocation
                appendLocationToFile(type: "Moving")
                lastUpdateTimestamp = newUpdateDate
                UserDefaults.standard.set(lastUpdateTimestamp, forKey: "lastUpdateTimestamp")
                UserDefaults.standard.set("Moving", forKey: "lastUpdateType")

            }
        }
        else
        {
            // No previous location means this is the first update ever
            if timeSinceLastUpdate >= minimumUpdateInterval
            {
                adjustSettingsForMovement()
                currentFilteredLocation = newLocation
                appendLocationToFile(type: "Moving", debug: "No PreviousLocation")
                lastUpdateTimestamp = newUpdateDate
                UserDefaults.standard.set(lastUpdateTimestamp, forKey: "lastUpdateTimestamp")
                UserDefaults.standard.set("Moving", forKey: "lastUpdateType")

            }
            self.previousSavedLocation = newLocation
        }
        currentDate = newUpdateDate
        
        // End time measurement
        let endTime = Date()
        let executionTime = endTime.timeIntervalSince(functionStartTime)

        // Log execution time to file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let executionTimeString = String(format: "%.10f", executionTime)
        let logMessage = "\(dateFormatter.string(from: functionStartTime)) - Execution time: \(executionTimeString) seconds - Call count: \(locationManagerCallCount)\n"

        let logFileURL = getLogFileURL()

        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                print("Could not open file handle for \(logFileURL.path)")
            }
        } else {
            do {
                try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write to \(logFileURL.path): \(error)")
            }
        }
        
    }
    private func adjustSettingsForMovement() {
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
        appendLocationToFile(type: "Stationary")
        UserDefaults.standard.set("Stationary", forKey: "lastUpdateType")

    }
    
    private func appendLocationToFile(type: String, debug: String = "") {
        if lastAppendCall != nil && Date().timeIntervalSince(lastAppendCall!) < 1 {
            print ("Cowardly refusing to double append – debouncing.")
            return
        }
        lastAppendCall = Date()
        guard let location = currentFilteredLocation else {
            print("No location to save")
            return
        }
        let dispatchGroup = DispatchGroup()

        if let startDate = self.lastPedometerCheckDate {
            dispatchGroup.enter()
            
            self.pedometer.queryPedometerData(from: startDate, to: Date()) { data, error in
                defer {
                    dispatchGroup.leave()
                }
                
                if let pedometerData = data, error == nil {
                    self.latestPedometerSteps = pedometerData.numberOfSteps.intValue
                } else {
                    print("Pedometer data error: \(error?.localizedDescription ?? "unknown error")")
                    self.latestPedometerSteps = -1
                }
            }
        }
        dispatchGroup.notify(queue: .main)
        {
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
                    }
                    self.lastPedometerCheckDate = Date()
                }
                else if self.latestPedometerSteps == -1{
                    stepsExtensionData["Debug"] = "Steps error"
                    if let lastElement = self.getMostRecentGPXElement(waypoints: gpxWaypoints, tracks: gpxTracks){
                        lastElement.extensions?.append(at: nil, contents: stepsExtensionData)
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
                    
                    // Check for matching place
                    if let matchingPlace = PlaceManager.shared.findPlace(for: location.coordinate) {
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
                }
            }
        }
    }
    func getMostRecentGPXElement(waypoints: [GPXWaypoint], tracks: [GPXTrack]) -> (GPXWaypoint?) {
        let lastWaypoint = waypoints.last
        let lastTrackPoint = tracks.last?.segments.last?.points.last

        if let waypointTime = lastWaypoint?.time, let trackpointTime = lastTrackPoint?.time {
            if waypointTime > trackpointTime {
                return (lastWaypoint)
            } else {
                return (lastTrackPoint)
            }
        } else if lastWaypoint != nil {
            return (lastWaypoint )
        } else if lastTrackPoint != nil {
            return (lastTrackPoint as GPXWaypoint?)
        }
        return (nil)
    }
}

private func getLogFileURL() -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let fileName = formatter.string(from: Date()) + ".log"
    
    var documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let logsDirectory = documentDirectory.appendingPathComponent("Logs")
    if !FileManager.default.fileExists(atPath: logsDirectory.path) {
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create Logs directory: \(error)")
        }
    }
    
    // Return the full path to the log file in the "Logs" directory
    return logsDirectory.appendingPathComponent(fileName)
}
