import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var locationUpdateTimer: Timer?
    private var ignoreNextLocationUpdate = false // Step 1: Add flag to track if next update should be ignored

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 20
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !ignoreNextLocationUpdate else { // Step 3: Check the flag
            ignoreNextLocationUpdate = false // Reset the flag
            return // Skip this update
        }
        
        currentLocation = locations.last
        adjustSettingsForMovement()
        appendLocationToFile(type: "WP")
    }
    
    private func adjustSettingsForMovement() {
        print("moving")
        ignoreNextLocationUpdate = true // Step 2: Set the flag to ignore next update
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 20
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
        ignoreNextLocationUpdate = true // Step 2: Set the flag to ignore next update
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        appendLocationToFile(type: "P")
    }
    
    private func appendLocationToFile(type: String) { // Added `type` parameter
        guard let location = currentLocation else {
            print("error with location")
            return
        }
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        // Include `type` at the beginning of the log
        let log = "\(type) - \(dateString): \(location.coordinate.latitude), \(location.coordinate.longitude), \(location.altitude)\n"
        
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        
        // Correcting the date format for filename to avoid using '/'
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
