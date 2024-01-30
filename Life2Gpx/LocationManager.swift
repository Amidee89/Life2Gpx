//
//  LocationManager.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 29.1.2024.
//
import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        setupLocationManager()
        appendLocationToFile() // Start writing immediately
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        locationManager.distanceFilter = 50
        appendLocationToFile()
    }

    private func appendLocationToFile() {
        print("starting append location")
        guard let location = currentLocation else { 
            print("error with location")
            return }
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let log = "\(dateString): \(location.coordinate.latitude), \(location.coordinate.longitude), \(location.altitude)\n"
        
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        
        // Correcting the date format for filename to avoid using '/'
        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(fileNameFormatter.string(from: Date())).txt"
        let fileURL = documentsURL?.appendingPathComponent(fileName)
        print("getting file url")

        if let fileURL = fileURL {
            if fileManager.fileExists(atPath: fileURL.path) {
                if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(log.data(using: .utf8)!)
                    fileHandle.closeFile()
                    print("write success")

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
