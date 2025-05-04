import Foundation
import CoreLocation

class SignificantLocationChangeManager: NSObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()

    override init() {
        super.init()
        FileManagerUtil.logData(context: "SigLocChangeMgr", content: "Initializing.", verbosity: 3)
        
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization() 
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startMonitoringSignificantLocationChanges()
        FileManagerUtil.logData(context: "SigLocChangeMgr", content: "Started monitoring significant location changes.", verbosity: 3)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let timestamp = Date()
        FileManagerUtil.logData(context: "SigLocChangeMgr", content: "Received significant location update at \(timestamp): \(location.coordinate). Triggering app launch/resume.", verbosity: 4)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        FileManagerUtil.logData(context: "SigLocChangeMgr", content: "Failed with error: \(error.localizedDescription)", verbosity: 1)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
         FileManagerUtil.logData(context: "SigLocChangeMgr", content: "Authorization status changed: \(manager.authorizationStatus.rawValue)", verbosity: 2)
    }
} 