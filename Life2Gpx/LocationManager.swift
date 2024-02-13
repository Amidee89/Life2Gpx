import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
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
            print("error with location")
            return
        }
        let distanceFromPrevious = previousLocation?.distance(from: location) ?? 0 // Calculate distance
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let log = "\(type) - \(dateString): \(location.coordinate.latitude), \(location.coordinate.longitude), \(location.altitude), Distance from previous: \(distanceFromPrevious) meters\n"
        
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(fileNameFormatter.string(from: Date())).txt"
        let fileURL = documentsURL?.appendingPathComponent(fileName)

        if let fileURL = fileURL {
            if fileManager.fileExists(atPath: fileURL.path) {
                if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(log.data(using: .utf8)!)
                    fileHandle.closeFile()
                    print("written \(type)")

                }
            } else {
                do {
                    try log.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("write success to new file")

                } catch {
                    print("Error writing to file: \(error)")
                }
            }
        }
    }
}
