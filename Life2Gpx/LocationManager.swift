import SwiftUI
import CoreLocation
import CoreGPX

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    private var previousLocation: CLLocation?
    private var locationUpdateTimer: Timer?
    private var customDistanceFilter: CLLocationDistance = 20 // Default to 20 meters
    private var currentDate: Date?
    private let minimumUpdateInterval: TimeInterval = 30
    private var lastUpdateTimestamp: Date?

    override init() {
        super.init()
        setupLocationManager()
        currentDate = Date()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
           guard let newLocation = locations.last else { return }
           
         let newUpdateDate = Date()
         if let previousUpdateDate = currentDate, Calendar.current.isDate(previousUpdateDate, inSameDayAs: newUpdateDate) == false {
             appendLocationToFile(type: "Stationary")
         }
        let timeSinceLastUpdate = lastUpdateTimestamp.map { newUpdateDate.timeIntervalSince($0) } ?? minimumUpdateInterval + 1 // Default to allow update if no previous timestamp

        
           if let previousLocation = previousLocation {
               let distanceFromPrevious = previousLocation.distance(from: newLocation)

               if distanceFromPrevious >= customDistanceFilter && timeSinceLastUpdate >= minimumUpdateInterval{
                   // Movement significant enough to trigger updates and reset timer
                   currentLocation = newLocation
                   adjustSettingsForMovement()
                   appendLocationToFile(type: "Moving")
                   self.previousLocation = currentLocation
                   lastUpdateTimestamp = newUpdateDate
               }
               // If distance is not enough, don't update settings or reset the timer
           } else {
               // No previous location means this is the first update
               currentLocation = newLocation
               adjustSettingsForMovement()
               appendLocationToFile(type: "Moving")
               previousLocation = currentLocation
               lastUpdateTimestamp = newUpdateDate
           }
        currentDate = newUpdateDate

       }
    private func adjustSettingsForMovement() {
        print("moving")
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        //locationManager.distanceFilter = 20
        //locationManager.startUpdatingLocation()
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
        print("stationary")
        //locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        //locationManager.distanceFilter = 60
        //locationManager.startUpdatingLocation()
        customDistanceFilter = 60 // Reset custom distance filter for movement
        appendLocationToFile(type: "Stationary")
    }
    
    private func appendLocationToFile(type: String) {
        guard let location = currentLocation else {
            print("Error with location")
            return
        }

        GPXManager.shared.loadFile(forDate: Date()) { loadedGpxWaypoints, loadedGpxTracks in
            var gpxTracks = loadedGpxTracks // Make a mutable copy of the loaded tracks
            var gpxWaypoints = loadedGpxWaypoints
            if type == "Moving" {
                let newTrackPoint = GPXTrackPoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                newTrackPoint.time = Date()
                newTrackPoint.elevation = location.altitude
                let customExtensionData: [String: String] = [
                    "HorizontalPrecision": String(location.horizontalAccuracy),
                    "VerticalPrecision": String(location.verticalAccuracy)
                ]
                let extensions = GPXExtensions()
                extensions.append(at: nil, contents: customExtensionData)
                newTrackPoint.extensions = extensions
                
                if let lastTrack = gpxTracks.last, let lastSegment = lastTrack.segments.last {
                    var modifiedLastTrack = lastTrack
                    var modifiedLastSegment = lastSegment
                    modifiedLastSegment.add(trackpoint: newTrackPoint)
                    modifiedLastTrack.segments[modifiedLastTrack.segments.count - 1] = modifiedLastSegment
                    gpxTracks[gpxTracks.count - 1] = modifiedLastTrack
                } else {
                    // No tracks or segments found, so create and add them
                    let newSegment = GPXTrackSegment()
                    newSegment.add(trackpoint: newTrackPoint)
                    let newTrack = GPXTrack()
                    newTrack.add(trackSegment: newSegment)
                    gpxTracks.append(newTrack)
                }
            } else if type == "Stationary" {
                let newWaypoint = GPXWaypoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                newWaypoint.time = Date()
                newWaypoint.elevation = location.altitude
                let customExtensionData: [String: String] = [
                    "HorizontalPrecision": String(location.horizontalAccuracy),
                    "VerticalPrecision": String(location.verticalAccuracy)
                ]
                let extensions = GPXExtensions()
                extensions.append(at: nil, contents: customExtensionData)
                newWaypoint.extensions = extensions
                gpxWaypoints.append(newWaypoint)
            }

            // Save the updated data using GPXManager
            GPXManager.shared.saveLocationData(gpxWaypoints, tracks: gpxTracks, forDate: Date())
        }
    }

    
}
