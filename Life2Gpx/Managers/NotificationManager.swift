//
//  NotificationManager.swift
//  Life2Gpx
//
//  Created by Antigravity on 5.7.2026.
//

import Foundation
import Combine
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var pendingUnknownPlaceUserInfo: [AnyHashable: Any]? = nil
    
    private init() {}
    
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            self.pendingUnknownPlaceUserInfo = userInfo
            NotificationCenter.default.post(name: .openEditVisitForUnknownPlace, object: nil, userInfo: userInfo)
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
}

extension Notification.Name {
    static let openEditVisitForUnknownPlace = Notification.Name("openEditVisitForUnknownPlace")
    static let gpxSaveFailed = Notification.Name("gpxSaveFailed")
}
