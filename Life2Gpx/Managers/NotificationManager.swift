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

    static func isUnknownPlace(_ waypoint: GPXWaypoint) -> Bool {
        guard let placeId = waypoint.extensions?["PlaceId"].text?.trimmingCharacters(in: .whitespacesAndNewlines), !placeId.isEmpty else {
            return true
        }
        return placeId == "-1"
    }

    struct DailyRecapData {
        let placesCount: Int
        let unknownPlacesCount: Int
        let unknownTracksCount: Int
        let activities: [(type: String, meters: Double)]
        let totalSteps: Int
    }

    static func extractDailyRecapData(waypoints: [GPXWaypoint], tracks: [GPXTrack]) -> DailyRecapData {
        let placesCount = waypoints.count
        let unknownPlacesCount = waypoints.filter { isUnknownPlace($0) }.count

        var totalSteps = 0
        for wp in waypoints {
            totalSteps += Int(wp.extensions?["Steps"].text ?? "0") ?? 0
        }

        var unknownTracksCount = 0
        var activityMap: [String: Double] = [:]

        for track in tracks {
            if isUnknownTrack(track) {
                unknownTracksCount += 1
            }

            var trackDistance: Double = 0
            for segment in track.segments {
                for i in 0..<segment.points.count {
                    if i < segment.points.count - 1 {
                        trackDistance += calculateDistance(from: segment.points[i], to: segment.points[i + 1])
                    }
                    totalSteps += Int(segment.points[i].extensions?["Steps"].text ?? "0") ?? 0
                }
            }

            let rawType = track.type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !isUnknownTrack(track) && !rawType.isEmpty {
                let key = rawType.lowercased()
                activityMap[key, default: 0] += trackDistance
            }
        }

        let activities = activityMap.map { (type: $0.key, meters: $0.value) }

        return DailyRecapData(
            placesCount: placesCount,
            unknownPlacesCount: unknownPlacesCount,
            unknownTracksCount: unknownTracksCount,
            activities: activities,
            totalSteps: totalSteps
        )
    }

    static func formatActivityRecapMessage(placesCount: Int, activities: [(type: String, meters: Double)], totalSteps: Int) -> String {
        let placesText: String
        if placesCount == 1 {
            placesText = "You visited 1 place"
        } else {
            placesText = "You visited \(placesCount) places"
        }

        let stepsText: String
        if totalSteps == 1 {
            stepsText = "1 step"
        } else {
            stepsText = "\(totalSteps) steps"
        }

        let sortedActivities = activities
            .filter { $0.meters >= 100 }
            .sorted { $0.meters > $1.meters }

        let topActivities = Array(sortedActivities.prefix(3))

        if topActivities.isEmpty {
            return "\(placesText), and walked \(stepsText)."
        }

        let formattedActivities = topActivities.map { item -> String in
            let typeName = PreferencesManager.shared.trackType(for: item.type)?.name.lowercased() ?? item.type.lowercased()
            let km = item.meters / 1000.0
            let rounded = (km * 10).rounded() / 10
            let kmText: String
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                kmText = "\(Int(rounded)) km"
            } else {
                kmText = String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), rounded)
            }
            return "\(typeName) \(kmText)"
        }

        let activitiesText = formattedActivities.joined(separator: ", ")
        return "\(placesText), \(activitiesText), and walked \(stepsText)."
    }

    static func formatUnknownItemsRecapMessage(unknownPlacesCount: Int, unknownTracksCount: Int) -> String {
        let placesText: String
        if unknownPlacesCount == 1 {
            placesText = "You've been to 1 unknown place"
        } else {
            placesText = "You've been to \(unknownPlacesCount) unknown places"
        }

        let tracksText: String
        if unknownTracksCount == 1 {
            tracksText = "there is 1 unknown type track today."
        } else {
            tracksText = "there are \(unknownTracksCount) unknown type tracks today."
        }

        return "\(placesText) and \(tracksText)"
    }

    func scheduleOrUpdateDailyRecapNotifications() {
        let settings = SettingsManager.shared
        guard settings.dailyActivityRecapEnabled || settings.dailyUnknownItemsRecapEnabled else {
            cancelDailyActivityRecapNotification()
            cancelDailyUnknownItemsRecapNotification()
            return
        }

        GPXManager.shared.loadFile(forDate: Date()) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let recapData = Self.extractDailyRecapData(waypoints: waypoints, tracks: tracks)
            self.scheduleRecapNotifications(with: recapData)
        }
    }

    private func scheduleRecapNotifications(with recapData: DailyRecapData) {
        let settings = SettingsManager.shared
        let center = UNUserNotificationCenter.current()
        let now = Date()

        if settings.dailyActivityRecapEnabled {
            let body = Self.formatActivityRecapMessage(
                placesCount: recapData.placesCount,
                activities: recapData.activities,
                totalSteps: recapData.totalSteps
            )
            scheduleDailyNotification(
                identifier: "DailyActivityRecap",
                title: "Daily Activity Recap",
                body: body,
                time: settings.dailyActivityRecapTime,
                lastSentDate: settings.lastDailyActivityRecapDate,
                now: now,
                center: center
            )
        } else {
            cancelDailyActivityRecapNotification()
        }

        if settings.dailyUnknownItemsRecapEnabled {
            let body = Self.formatUnknownItemsRecapMessage(
                unknownPlacesCount: recapData.unknownPlacesCount,
                unknownTracksCount: recapData.unknownTracksCount
            )
            scheduleDailyNotification(
                identifier: "DailyUnknownItemsRecap",
                title: "Daily Unknown Items Recap",
                body: body,
                time: settings.dailyUnknownItemsRecapTime,
                lastSentDate: settings.lastDailyUnknownItemsRecapDate,
                now: now,
                center: center
            )
        } else {
            cancelDailyUnknownItemsRecapNotification()
        }
    }

    private func scheduleDailyNotification(
        identifier: String,
        title: String,
        body: String,
        time: Date,
        lastSentDate: Date?,
        now: Date,
        center: UNUserNotificationCenter
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = timeComponents.hour
        todayComponents.minute = timeComponents.minute
        todayComponents.second = 0

        guard let targetDateToday = calendar.date(from: todayComponents) else { return }

        let alreadySentToday = lastSentDate != nil && calendar.isDate(lastSentDate!, inSameDayAs: now)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        if !alreadySentToday && now < targetDateToday {
            var matchingComponents = DateComponents()
            matchingComponents.hour = timeComponents.hour
            matchingComponents.minute = timeComponents.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: matchingComponents, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request) { error in
                if let error = error {
                    LogManager.shared.logData(context: "NotificationManager", content: "Error scheduling \(identifier): \(error.localizedDescription)", verbosity: 2)
                } else {
                    LogManager.shared.logData(context: "NotificationManager", content: "Scheduled \(identifier) for today at \(timeComponents.hour ?? 0):\(timeComponents.minute ?? 0).", verbosity: 3)
                }
            }
        } else if alreadySentToday {
            // Already sent today; schedule for tomorrow's recurring trigger
            var matchingComponents = DateComponents()
            matchingComponents.hour = timeComponents.hour
            matchingComponents.minute = timeComponents.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: matchingComponents, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request) { _ in }
        }
    }

    func checkDailyRecapNotifications() {
        let settings = SettingsManager.shared
        guard settings.dailyActivityRecapEnabled || settings.dailyUnknownItemsRecapEnabled else { return }

        GPXManager.shared.loadFile(forDate: Date()) { [weak self] waypoints, tracks in
            guard let self = self else { return }
            let recapData = Self.extractDailyRecapData(waypoints: waypoints, tracks: tracks)
            self.evaluateAndSendDueRecapNotifications(recapData: recapData)
        }
    }

    private func evaluateAndSendDueRecapNotifications(recapData: DailyRecapData) {
        let settings = SettingsManager.shared
        let calendar = Calendar.current
        let now = Date()

        if settings.dailyActivityRecapEnabled {
            let alreadySentToday = settings.lastDailyActivityRecapDate != nil && calendar.isDate(settings.lastDailyActivityRecapDate!, inSameDayAs: now)
            if !alreadySentToday, let targetDate = Self.targetDateForToday(time: settings.dailyActivityRecapTime), now >= targetDate {
                let body = Self.formatActivityRecapMessage(
                    placesCount: recapData.placesCount,
                    activities: recapData.activities,
                    totalSteps: recapData.totalSteps
                )
                sendImmediateRecapNotification(
                    identifier: "DailyActivityRecap",
                    title: "Daily Activity Recap",
                    body: body
                ) {
                    SettingsManager.shared.lastDailyActivityRecapDate = Date()
                }
            }
        }

        if settings.dailyUnknownItemsRecapEnabled {
            let alreadySentToday = settings.lastDailyUnknownItemsRecapDate != nil && calendar.isDate(settings.lastDailyUnknownItemsRecapDate!, inSameDayAs: now)
            if !alreadySentToday, let targetDate = Self.targetDateForToday(time: settings.dailyUnknownItemsRecapTime), now >= targetDate {
                let body = Self.formatUnknownItemsRecapMessage(
                    unknownPlacesCount: recapData.unknownPlacesCount,
                    unknownTracksCount: recapData.unknownTracksCount
                )
                sendImmediateRecapNotification(
                    identifier: "DailyUnknownItemsRecap",
                    title: "Daily Unknown Items Recap",
                    body: body
                ) {
                    SettingsManager.shared.lastDailyUnknownItemsRecapDate = Date()
                }
            }
        }
    }

    private func sendImmediateRecapNotification(identifier: String, title: String, body: String, completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                LogManager.shared.logData(context: "NotificationManager", content: "Error sending immediate \(identifier): \(error.localizedDescription)", verbosity: 2)
            } else {
                LogManager.shared.logData(context: "NotificationManager", content: "Delivered immediate \(identifier).", verbosity: 3)
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    private static func targetDateForToday(time: Date) -> Date? {
        let calendar = Calendar.current
        var targetComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        targetComponents.hour = timeComponents.hour
        targetComponents.minute = timeComponents.minute
        targetComponents.second = 0
        return calendar.date(from: targetComponents)
    }

    func cancelDailyActivityRecapNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["DailyActivityRecap"])
        center.removeDeliveredNotifications(withIdentifiers: ["DailyActivityRecap"])
        LogManager.shared.logData(context: "NotificationManager", content: "Cancelled DailyActivityRecap notification.", verbosity: 4)
    }

    func cancelDailyUnknownItemsRecapNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["DailyUnknownItemsRecap"])
        center.removeDeliveredNotifications(withIdentifiers: ["DailyUnknownItemsRecap"])
        LogManager.shared.logData(context: "NotificationManager", content: "Cancelled DailyUnknownItemsRecap notification.", verbosity: 4)
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
