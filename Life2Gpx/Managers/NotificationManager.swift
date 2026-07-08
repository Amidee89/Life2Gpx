//
//  NotificationManager.swift
//  Life2Gpx
//
//  Created by Antigravity on 5.7.2026.
//

import Foundation
import Combine

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
}

extension Notification.Name {
    static let openEditVisitForUnknownPlace = Notification.Name("openEditVisitForUnknownPlace")
}
