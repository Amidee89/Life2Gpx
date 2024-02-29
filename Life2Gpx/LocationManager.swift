import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    private var previousLocation: CLLocation? // Store the previous location
    private var locationUpdateTimer: Timer?
    private var customDistanceFilter: CLLocationDistance = 20 // Default to 20 meters
    private var currentDate: Date?

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
             appendLocationToFile(type: "P")
         }
        
        
           if let previousLocation = previousLocation {
               let distanceFromPrevious = previousLocation.distance(from: newLocation)

               if distanceFromPrevious >= customDistanceFilter {
                   // Movement significant enough to trigger updates and reset timer
                   currentLocation = newLocation
                   adjustSettingsForMovement()
                   appendLocationToFile(type: "WP")
                   self.previousLocation = currentLocation
               }
               // If distance is not enough, don't update settings or reset the timer
           } else {
               // No previous location means this is the first update
               currentLocation = newLocation
               adjustSettingsForMovement() // Initial setting adjustments
               appendLocationToFile(type: "WP")
               previousLocation = currentLocation // Update the previous location after appending
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
        appendLocationToFile(type: "P")
    }
    
    private func appendLocationToFile(type: String) {
        guard let location = currentLocation else {
            print("Error with location")
            return
        }

        var dataContainer: DataContainer = DataContainer()

        // Attempt to load existing data for today's date if it exists
        GPXManager.shared.loadFile(forDate: Date()) { loadedDataContainer in
            if let loadedData = loadedDataContainer {
                // If data was loaded successfully, use it
                dataContainer = loadedData
            }

            let newWaypoint = Waypoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                elevation: location.altitude,
                time: Date()
            )

            if type == "WP" {
                if var lastTrack = dataContainer.tracks.last, var lastSegment = lastTrack.segments.last {
                    lastSegment.trackPoints.append(newWaypoint)
                    lastTrack.segments[lastTrack.segments.count - 1] = lastSegment
                    dataContainer.tracks[dataContainer.tracks.count - 1] = lastTrack
                } else {
                    let newSegment = TrackSegment(trackPoints: [newWaypoint])
                    let newTrack = Track(segments: [newSegment])
                    dataContainer.tracks.append(newTrack)
                }
            } else if type == "P" {
                // Handle stationary points separately
                dataContainer.waypoints.append(newWaypoint)
            }

            // Save the updated dataContainer using GPXManager
            GPXManager.shared.saveLocationData(dataContainer, forDate: Date())
        }
    }
    
}
