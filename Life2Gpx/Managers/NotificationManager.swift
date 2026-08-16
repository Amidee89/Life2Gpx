import Foundation
import Combine
import UserNotifications
import CoreGPX

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var pendingUnknownPlaceUserInfo: [AnyHashable: Any]? = nil
    @Published var pendingUnknownTrackUserInfo: [AnyHashable: Any]? = nil
    
    private init() {}
    
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            self.pendingUnknownPlaceUserInfo = userInfo
            NotificationCenter.default.post(name: .openEditVisitForUnknownPlace, object: nil, userInfo: userInfo)
        }
    }

    func handleUnknownTrackNotificationTap(userInfo: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            self.pendingUnknownTrackUserInfo = userInfo
            NotificationCenter.default.post(name: .openEditTrackForUnknownTrack, object: nil, userInfo: userInfo)
        }
    }

    func cancelUnknownPlaceNotification(forWaypointTime waypointTime: Date?) {
        guard let wpTime = waypointTime?.timeIntervalSince1970 else { return }
        
        let center = UNUserNotificationCenter.current()
        
        center.getPendingNotificationRequests { requests in
            if let request = requests.first(where: { $0.identifier == "UnknownPlaceCheckIn" }),
               let timestamp = request.content.userInfo["waypointTimestamp"] as? TimeInterval,
               abs(timestamp - wpTime) < 1.0 {
                center.removePendingNotificationRequests(withIdentifiers: ["UnknownPlaceCheckIn"])
            }
        }
        
        center.getDeliveredNotifications { notifications in
            if let notification = notifications.first(where: { $0.request.identifier == "UnknownPlaceCheckIn" }),
               let timestamp = notification.request.content.userInfo["waypointTimestamp"] as? TimeInterval,
               abs(timestamp - wpTime) < 1.0 {
                center.removeDeliveredNotifications(withIdentifiers: ["UnknownPlaceCheckIn"])
            }
        }
    }

    static func isUnknownTrack(_ track: GPXTrack) -> Bool {
        guard let type = track.type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty else {
            return true
        }
        return type.caseInsensitiveCompare("unknown") == .orderedSame
    }

    func checkAndNotifyUnknownTracks(tracks: [GPXTrack], forDate date: Date) {
        guard SettingsManager.shared.notifyOfSavedUnknownTrackTypes else {
            cancelUnknownTrackNotification()
            return
        }

        let unknownTracks = tracks.filter { Self.isUnknownTrack($0) }
        let count = unknownTracks.count

        guard count > 0, let firstTrack = unknownTracks.first else {
            cancelUnknownTrackNotification()
            return
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["UnknownTrackType"])

        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "Unknown Track Type Detected" : "Unknown Track Types Detected"
        content.body = count == 1
            ? "1 unknown track type has been saved. Tap to edit."
            : "\(count) unknown track types have been saved. Tap to edit."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let firstTrackStartTime = firstTrack.segments.first?.points.first?.time ?? date
        let userInfo: [AnyHashable: Any] = [
            "notificationType": "unknownTrack",
            "trackTimestamp": firstTrackStartTime.timeIntervalSince1970,
            "fileDateTimestamp": date.timeIntervalSince1970,
            "unknownTrackCount": count
        ]
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "UnknownTrackType", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                LogManager.shared.logData(context: "NotificationManager", content: "Error scheduling UnknownTrackType: \(error.localizedDescription)", verbosity: 2)
            } else {
                LogManager.shared.logData(context: "NotificationManager", content: "Scheduled UnknownTrackType notification: \(count) unknown tracks for date \(date).", verbosity: 3)
            }
        }
    }

    func checkAndNotifyUnknownTracks(forDate date: Date) {
        GPXManager.shared.loadFile(forDate: date) { [weak self] _, tracks in
            self?.checkAndNotifyUnknownTracks(tracks: tracks, forDate: date)
        }
    }

    func cancelUnknownTrackNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["UnknownTrackType"])
        center.removeDeliveredNotifications(withIdentifiers: ["UnknownTrackType"])
        LogManager.shared.logData(context: "NotificationManager", content: "Cancelled pending and delivered UnknownTrackType notification.", verbosity: 4)
    }
}

extension Notification.Name {
    static let openEditVisitForUnknownPlace = Notification.Name("openEditVisitForUnknownPlace")
    static let openEditTrackForUnknownTrack = Notification.Name("openEditTrackForUnknownTrack")
    static let gpxSaveFailed = Notification.Name("gpxSaveFailed")
}
