import Foundation
import CoreLocation

class SignificantLocationChangeManager: NSObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()

    override init() {
        super.init()
        LogManager.shared.logData(context: "SigLocChangeMgr", content: "Initializing.", verbosity: 3)
        
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization() 
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        if !SettingsManager.shared.disableTracking {
            start()
        }
    }

    func start() {
        locationManager.startMonitoringSignificantLocationChanges()
        LogManager.shared.logData(context: "SigLocChangeMgr", content: "Started monitoring significant location changes.", verbosity: 3)
    }

    func stop() {
        locationManager.stopMonitoringSignificantLocationChanges()
        LogManager.shared.logData(context: "SigLocChangeMgr", content: "Stopped monitoring significant location changes.", verbosity: 3)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let timestamp = Date()
        LogManager.shared.logData(context: "SigLocChangeMgr", content: "Received significant location update at \(timestamp): \(location.coordinate). Triggering app launch/resume.", verbosity: 4)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        LogManager.shared.logData(context: "SigLocChangeMgr", content: "Failed with error: \(error.localizedDescription)", verbosity: 1)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
         LogManager.shared.logData(context: "SigLocChangeMgr", content: "Authorization status changed: \(manager.authorizationStatus.rawValue)", verbosity: 2)
    }
} 
