import Foundation
import CoreLocation

/// How the app decides whether MapKit is using GCJ-02 (Gaode) or WGS-84 tiles.
enum MapCoordinateSystemMode: String, CaseIterable, Identifiable {
    case auto
    case forceGCJ02
    case forceWGS84

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .forceGCJ02: return "China maps (GCJ-02)"
        case .forceWGS84: return "Standard maps (WGS-84)"
        }
    }
}

enum TimelineLocalTimeMode: String, CaseIterable, Identifiable {
    case never
    case ask
    case always

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .ask: return "Ask"
        case .always: return "Always"
        }
    }
}

enum ActivitySummaryVisibility: String, CaseIterable, Identifiable {
    case always
    case onPullDown
    case dontShow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .onPullDown: return "On pull down"
        case .dontShow: return "Don't show"
        }
    }
}

enum TimelinePictureDisplayMode: String, CaseIterable, Identifiable {
    case none
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        }
    }
}

enum ShowCurrentPositionMode: String, CaseIterable, Identifiable {
    case always
    case onlyToday
    case never

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .onlyToday: return "Only Today"
        case .never: return "Never"
        }
    }
}


class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private let debugLogVerbosityKey = "debugLogVerbosity"
    private let loadCurrentDayOnRestoreAfterSecondsKey = "loadCurrentDayOnRestoreAfterSeconds" // Keep for backward compatibility
    private let loadCurrentDayOnRestoreAfterValueKey = "loadCurrentDayOnRestoreAfterValue"
    private let loadCurrentDayOnRestoreAfterUnitKey = "loadCurrentDayOnRestoreAfterUnit"
    private let defaultNewPlaceRadiusKey = "defaultNewPlaceRadius"
    private let placeProviderOrderKey = "placeProviderOrder"
    private let filterSmallRoundTripsKey = "filterSmallRoundTrips"
    private let roundTripMaxPointsKey = "roundTripMaxPoints"
    private let roundTripUnknownRadiusKey = "roundTripUnknownRadius"
    private let automaticallyMergeUnknownToKnownTypeTracksKey = "automaticallyMergeUnknownToKnownTypeTracks"
    private let automaticMergeUnknownTrackMaxPointsKey = "automaticMergeUnknownTrackMaxPoints"
    private let automaticMergeKnownTrackMinimumPointsKey = "automaticMergeKnownTrackMinimumPoints"
    private let askToOrganizeGpxFilesKey = "askToOrganizeGpxFiles"
    private let gpxOverwriteExistingKey = "gpxOverwriteExisting"
    private let gpxConflictResolutionKey = "gpxConflictResolution"
    private let timelinePictureDisplayModeKey = "timelinePictureDisplayMode"
    private let mapCoordinateSystemModeKey = "mapCoordinateSystemMode"
    private let suggestApplyToOtherPlacesKey = "suggestApplyToOtherPlaces"
    private let mergeVisitAddStepsKey = "mergeVisitAddSteps"
    private let sendNotificationOnUnknownPlaceKey = "sendNotificationOnUnknownPlace"
    private let unknownPlaceNotificationMinutesKey = "unknownPlaceNotificationMinutes"
    private let trackResourceUsageKey = "trackResourceUsage"
    private let minimumUpdateIntervalKey = "minimumUpdateInterval"
    private let stationaryDetectionTimerKey = "stationaryDetectionTimer"
    private let stationaryStepsUpdateIntervalKey = "stationaryStepsUpdateInterval"
    private let findClosePlacesLimitKey = "findClosePlacesLimit"
    private let placeSearchDefaultRadiusKey = "placeSearchDefaultRadius"
    private let placeSearchKeywordRadiusKey = "placeSearchKeywordRadius"
    private let placeSearchPageLimitKey = "placeSearchPageLimit"
    private let photoCacheMemoryMBKey = "photoCacheMemoryMB"
    private let photoCacheCountLimitKey = "photoCacheCountLimit"
    private let showCurrentPositionModeKey = "showCurrentPositionMode"
    private let disableTrackingKey = "disableTracking"
    private let iCloudBackupEnabledKey = "iCloudBackupEnabled"
    private let iCloudBackupModeKey = "iCloudBackupMode"
    private let iCloudBackupDailyTimeKey = "iCloudBackupDailyTime"
    private let iCloudBackupIntervalValueKey = "iCloudBackupIntervalValue"
    private let iCloudBackupIntervalUnitKey = "iCloudBackupIntervalUnit"
    private let lastICloudBackupDateKey = "lastICloudBackupDate"
    private let activitySummaryVisibilityKey = "activitySummaryVisibility"
    private let activitySummaryDistanceThresholdKey = "activitySummaryDistanceThreshold"
    private let timelineLocalTimeModeKey = "timelineLocalTimeMode"
    private let enableDeadMansSwitchKey = "enableDeadMansSwitch"
    private let stationaryLocationAccuracyKey = "stationaryLocationAccuracy"
    private let movingLocationAccuracyKey = "movingLocationAccuracy"
    
    private init() {
        registerDefaults()
        migrateOldSettings()
    }
    
    private func registerDefaults() {
        let defaultOrder = PlaceProvider.allCases.map { $0.rawValue }
        defaults.register(defaults: [
            debugLogVerbosityKey: 1,
            loadCurrentDayOnRestoreAfterSecondsKey: 600,
            loadCurrentDayOnRestoreAfterValueKey: 10,
            loadCurrentDayOnRestoreAfterUnitKey: "minutes",
            defaultNewPlaceRadiusKey: 100,
            placeProviderOrderKey: defaultOrder,
            filterSmallRoundTripsKey: true,
            roundTripMaxPointsKey: 3,
            roundTripUnknownRadiusKey: 100,
            automaticallyMergeUnknownToKnownTypeTracksKey: true,
            automaticMergeUnknownTrackMaxPointsKey: 2,
            automaticMergeKnownTrackMinimumPointsKey: 3,
            askToOrganizeGpxFilesKey: true,
            gpxOverwriteExistingKey: false,
            gpxConflictResolutionKey: "keepExisting",
            timelinePictureDisplayModeKey: TimelinePictureDisplayMode.small.rawValue,
            mapCoordinateSystemModeKey: MapCoordinateSystemMode.auto.rawValue,
            suggestApplyToOtherPlacesKey: true,
            mergeVisitAddStepsKey: true,
            sendNotificationOnUnknownPlaceKey: true,
            unknownPlaceNotificationMinutesKey: 10,
            trackResourceUsageKey: false,
            minimumUpdateIntervalKey: 30,
            stationaryDetectionTimerKey: 120,
            stationaryStepsUpdateIntervalKey: 5,
            findClosePlacesLimitKey: 10,
            placeSearchDefaultRadiusKey: 500,
            placeSearchKeywordRadiusKey: 5000,
            placeSearchPageLimitKey: 10,
            photoCacheMemoryMBKey: 96,
            photoCacheCountLimitKey: 4,
            showCurrentPositionModeKey: ShowCurrentPositionMode.onlyToday.rawValue,
            disableTrackingKey: false,
            iCloudBackupEnabledKey: false,
            iCloudBackupModeKey: "daily",
            iCloudBackupIntervalValueKey: 1,
            iCloudBackupIntervalUnitKey: "days",
            activitySummaryVisibilityKey: ActivitySummaryVisibility.onPullDown.rawValue,
            activitySummaryDistanceThresholdKey: 100,
            timelineLocalTimeModeKey: TimelineLocalTimeMode.never.rawValue,
            enableDeadMansSwitchKey: true,
            stationaryLocationAccuracyKey: LocationAccuracyLevel.medium.rawValue,
            movingLocationAccuracyKey: LocationAccuracyLevel.best.rawValue
        ])
        
        if defaults.object(forKey: iCloudBackupDailyTimeKey) == nil {
            var components = DateComponents()
            components.hour = 2
            components.minute = 0
            let defaultTime = Calendar.current.date(from: components) ?? Date()
            defaults.set(defaultTime, forKey: iCloudBackupDailyTimeKey)
        }
        
        print("UserDefaults registered with default verbosity: \(defaults.integer(forKey: debugLogVerbosityKey))")
        print("UserDefaults registered with default auto refresh interval: \(loadCurrentDayOnRestoreAfterValue) \(loadCurrentDayOnRestoreAfterUnit)")
        print("UserDefaults registered with default new place radius: \(defaults.integer(forKey: defaultNewPlaceRadiusKey))")
    }
    
    private func migrateOldSettings() {
        // Migrate old setting if it exists and new settings don't
        if defaults.object(forKey: loadCurrentDayOnRestoreAfterSecondsKey) != nil && 
           defaults.object(forKey: loadCurrentDayOnRestoreAfterValueKey) == nil {
            let oldSeconds = defaults.integer(forKey: loadCurrentDayOnRestoreAfterSecondsKey)
            if oldSeconds >= 3600 {
                loadCurrentDayOnRestoreAfterValue = oldSeconds / 3600
                loadCurrentDayOnRestoreAfterUnit = "hours"
            } else if oldSeconds >= 60 {
                loadCurrentDayOnRestoreAfterValue = oldSeconds / 60
                loadCurrentDayOnRestoreAfterUnit = "minutes"
            } else {
                loadCurrentDayOnRestoreAfterValue = oldSeconds
                loadCurrentDayOnRestoreAfterUnit = "seconds"
            }
        }
    }
    

    var debugLogVerbosity: Int {
        get {
            return defaults.integer(forKey: debugLogVerbosityKey)
        }
        set {
            let clampedValue = max(0, min(newValue, 5))
            defaults.set(clampedValue, forKey: debugLogVerbosityKey)
            print("UserDefaults: debugLogVerbosity set to \(clampedValue)")
        }
    }

    var loadCurrentDayOnRestoreAfterValue: Int {
        get {
            return max(1, defaults.integer(forKey: loadCurrentDayOnRestoreAfterValueKey))
        }
        set {
            let clampedValue = max(1, newValue)
            defaults.set(clampedValue, forKey: loadCurrentDayOnRestoreAfterValueKey)
            print("UserDefaults: loadCurrentDayOnRestoreAfterValue set to \(clampedValue)")
        }
    }
    
    var loadCurrentDayOnRestoreAfterUnit: String {
        get {
            let unit = defaults.string(forKey: loadCurrentDayOnRestoreAfterUnitKey) ?? "minutes"
            return ["seconds", "minutes", "hours", "days"].contains(unit) ? unit : "minutes"
        }
        set {
            let validUnits = ["seconds", "minutes", "hours", "days"]
            let unit = validUnits.contains(newValue) ? newValue : "minutes"
            defaults.set(unit, forKey: loadCurrentDayOnRestoreAfterUnitKey)
            print("UserDefaults: loadCurrentDayOnRestoreAfterUnit set to \(unit)")
        }
    }

    // Computed property for backward compatibility and actual logic
    var loadCurrentDayOnRestoreAfterSeconds: Int {
        let value = loadCurrentDayOnRestoreAfterValue
        switch loadCurrentDayOnRestoreAfterUnit {
        case "seconds":
            return value
        case "minutes":
            return value * 60
        case "hours":
            return value * 3600
        case "days":
            return value * 86400
        default:
            return value * 60 // Default to minutes
        }
    }

    var defaultNewPlaceRadius: Int {
        get {
            return defaults.integer(forKey: defaultNewPlaceRadiusKey)
        }
        set {
            let clampedValue = max(10, min(newValue, 1000)) // 10m to 1000m range
            defaults.set(clampedValue, forKey: defaultNewPlaceRadiusKey)
            print("UserDefaults: defaultNewPlaceRadius set to \(clampedValue)")
        }
    }

    var filterSmallRoundTrips: Bool {
        get {
            return defaults.bool(forKey: filterSmallRoundTripsKey)
        }
        set {
            defaults.set(newValue, forKey: filterSmallRoundTripsKey)
        }
    }

    var roundTripMaxPoints: Int {
        get {
            return defaults.integer(forKey: roundTripMaxPointsKey)
        }
        set {
            let clampedValue = max(1, min(newValue, 10))
            defaults.set(clampedValue, forKey: roundTripMaxPointsKey)
        }
    }

    var roundTripUnknownRadius: Int {
        get {
            return defaults.integer(forKey: roundTripUnknownRadiusKey)
        }
        set {
            let clampedValue = max(10, min(newValue, 1000))
            defaults.set(clampedValue, forKey: roundTripUnknownRadiusKey)
        }
    }

    var automaticallyMergeUnknownToKnownTypeTracks: Bool {
        get { defaults.bool(forKey: automaticallyMergeUnknownToKnownTypeTracksKey) }
        set { defaults.set(newValue, forKey: automaticallyMergeUnknownToKnownTypeTracksKey) }
    }

    var automaticMergeUnknownTrackMaxPoints: Int {
        get { max(1, min(defaults.integer(forKey: automaticMergeUnknownTrackMaxPointsKey), 10)) }
        set { defaults.set(max(1, min(newValue, 10)), forKey: automaticMergeUnknownTrackMaxPointsKey) }
    }

    var automaticMergeKnownTrackMinimumPoints: Int {
        get { max(1, min(defaults.integer(forKey: automaticMergeKnownTrackMinimumPointsKey), 10)) }
        set { defaults.set(max(1, min(newValue, 10)), forKey: automaticMergeKnownTrackMinimumPointsKey) }
    }

    var placeProviderOrder: [PlaceProvider] {
        get {
            let rawValues = defaults.stringArray(forKey: placeProviderOrderKey) ?? PlaceProvider.allCases.map { $0.rawValue }
            var providers = rawValues.compactMap { PlaceProvider(rawValue: $0) }
            for provider in PlaceProvider.allCases where !providers.contains(provider) {
                providers.append(provider)
            }
            return providers
        }
        set {
            defaults.set(newValue.map { $0.rawValue }, forKey: placeProviderOrderKey)
        }
    }

    var askToOrganizeGpxFiles: Bool {
        get {
            return defaults.bool(forKey: askToOrganizeGpxFilesKey)
        }
        set {
            defaults.set(newValue, forKey: askToOrganizeGpxFilesKey)
        }
    }

    var gpxOverwriteExisting: Bool {
        get {
            return defaults.bool(forKey: gpxOverwriteExistingKey)
        }
        set {
            defaults.set(newValue, forKey: gpxOverwriteExistingKey)
        }
    }

    var gpxConflictResolution: FileManagerUtil.ConflictResolution {
        get {
            let raw = defaults.string(forKey: gpxConflictResolutionKey) ?? "keepExisting"
            return raw == "replaceExisting" ? .replaceExisting : .keepExisting
        }
        set {
            let raw: String
            switch newValue {
            case .replaceExisting: raw = "replaceExisting"
            default: raw = "keepExisting"
            }
            defaults.set(raw, forKey: gpxConflictResolutionKey)
        }
    }

    /// Returns the effective conflict resolution based on the overwrite toggle and the choice picker
    var effectiveGpxConflictResolution: FileManagerUtil.ConflictResolution {
        return gpxOverwriteExisting ? .overwrite : gpxConflictResolution
    }

    var timelinePictureDisplayMode: TimelinePictureDisplayMode {
        get {
            let raw = defaults.string(forKey: timelinePictureDisplayModeKey) ?? TimelinePictureDisplayMode.small.rawValue
            return TimelinePictureDisplayMode(rawValue: raw) ?? .small
        }
        set {
            defaults.set(newValue.rawValue, forKey: timelinePictureDisplayModeKey)
        }
    }

    var mapCoordinateSystemMode: MapCoordinateSystemMode {
        get {
            let raw = defaults.string(forKey: mapCoordinateSystemModeKey) ?? MapCoordinateSystemMode.auto.rawValue
            return MapCoordinateSystemMode(rawValue: raw) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: mapCoordinateSystemModeKey)
        }
    }

    var showCurrentPositionMode: ShowCurrentPositionMode {
        get {
            let raw = defaults.string(forKey: showCurrentPositionModeKey) ?? ShowCurrentPositionMode.onlyToday.rawValue
            return ShowCurrentPositionMode(rawValue: raw) ?? .onlyToday
        }
        set {
            defaults.set(newValue.rawValue, forKey: showCurrentPositionModeKey)
        }
    }

    var activitySummaryVisibility: ActivitySummaryVisibility {
        get {
            let raw = defaults.string(forKey: activitySummaryVisibilityKey) ?? ActivitySummaryVisibility.onPullDown.rawValue
            return ActivitySummaryVisibility(rawValue: raw) ?? .onPullDown
        }
        set {
            defaults.set(newValue.rawValue, forKey: activitySummaryVisibilityKey)
        }
    }

    var activitySummaryDistanceThreshold: Int {
        get { return defaults.integer(forKey: activitySummaryDistanceThresholdKey) }
        set { defaults.set(max(0, newValue), forKey: activitySummaryDistanceThresholdKey) }
    }

    var timelineLocalTimeMode: TimelineLocalTimeMode {
        get {
            let raw = defaults.string(forKey: timelineLocalTimeModeKey) ?? TimelineLocalTimeMode.never.rawValue
            return TimelineLocalTimeMode(rawValue: raw) ?? .never
        }
        set {
            defaults.set(newValue.rawValue, forKey: timelineLocalTimeModeKey)
        }
    }

    var suggestApplyToOtherPlaces: Bool {
        get {
            return defaults.bool(forKey: suggestApplyToOtherPlacesKey)
        }
        set {
            defaults.set(newValue, forKey: suggestApplyToOtherPlacesKey)
        }
    }
    
    var mergeVisitAddSteps: Bool {
        get { return defaults.bool(forKey: mergeVisitAddStepsKey) }
        set { defaults.set(newValue, forKey: mergeVisitAddStepsKey) }
    }

    var sendNotificationOnUnknownPlace: Bool {
        get { return defaults.bool(forKey: sendNotificationOnUnknownPlaceKey) }
        set { defaults.set(newValue, forKey: sendNotificationOnUnknownPlaceKey) }
    }

    var unknownPlaceNotificationMinutes: Int {
        get { return max(1, defaults.integer(forKey: unknownPlaceNotificationMinutesKey)) }
        set { defaults.set(max(1, newValue), forKey: unknownPlaceNotificationMinutesKey) }
    }

    var trackResourceUsage: Bool {
        get { return defaults.bool(forKey: trackResourceUsageKey) }
        set { defaults.set(newValue, forKey: trackResourceUsageKey) }
    }

    var minimumUpdateInterval: Int {
        get { return defaults.integer(forKey: minimumUpdateIntervalKey) }
        set { defaults.set(newValue, forKey: minimumUpdateIntervalKey) }
    }

    var stationaryDetectionTimer: Int {
        get { return defaults.integer(forKey: stationaryDetectionTimerKey) }
        set { defaults.set(newValue, forKey: stationaryDetectionTimerKey) }
    }

    var stationaryStepsUpdateInterval: Int {
        get { return defaults.integer(forKey: stationaryStepsUpdateIntervalKey) }
        set { defaults.set(newValue, forKey: stationaryStepsUpdateIntervalKey) }
    }

    var findClosePlacesLimit: Int {
        get { return defaults.integer(forKey: findClosePlacesLimitKey) }
        set { defaults.set(newValue, forKey: findClosePlacesLimitKey) }
    }

    var placeSearchDefaultRadius: Int {
        get { return defaults.integer(forKey: placeSearchDefaultRadiusKey) }
        set { defaults.set(max(10, min(newValue, 50000)), forKey: placeSearchDefaultRadiusKey) }
    }

    var placeSearchKeywordRadius: Int {
        get { return defaults.integer(forKey: placeSearchKeywordRadiusKey) }
        set { defaults.set(max(10, min(newValue, 50000)), forKey: placeSearchKeywordRadiusKey) }
    }



    var placeSearchPageLimit: Int {
        get { return defaults.integer(forKey: placeSearchPageLimitKey) }
        set { defaults.set(max(5, min(newValue, 100)), forKey: placeSearchPageLimitKey) }
    }

    var photoCacheMemoryMB: Int {
        get { return defaults.integer(forKey: photoCacheMemoryMBKey) }
        set { defaults.set(max(16, min(newValue, 1024)), forKey: photoCacheMemoryMBKey) }
    }

    var photoCacheCountLimit: Int {
        get { return defaults.integer(forKey: photoCacheCountLimitKey) }
        set { defaults.set(max(1, min(newValue, 20)), forKey: photoCacheCountLimitKey) }
    }

    var disableTracking: Bool {
        get { return defaults.bool(forKey: disableTrackingKey) }
        set { defaults.set(newValue, forKey: disableTrackingKey) }
    }

    var iCloudBackupEnabled: Bool {
        get { return defaults.bool(forKey: iCloudBackupEnabledKey) }
        set { defaults.set(newValue, forKey: iCloudBackupEnabledKey) }
    }

    var iCloudBackupMode: String {
        get { return defaults.string(forKey: iCloudBackupModeKey) ?? "daily" }
        set { defaults.set(newValue, forKey: iCloudBackupModeKey) }
    }

    var iCloudBackupDailyTime: Date {
        get { return defaults.object(forKey: iCloudBackupDailyTimeKey) as? Date ?? Date() }
        set { defaults.set(newValue, forKey: iCloudBackupDailyTimeKey) }
    }

    var iCloudBackupIntervalValue: Int {
        get { return max(1, defaults.integer(forKey: iCloudBackupIntervalValueKey)) }
        set { defaults.set(max(1, newValue), forKey: iCloudBackupIntervalValueKey) }
    }

    var iCloudBackupIntervalUnit: String {
        get {
            let unit = defaults.string(forKey: iCloudBackupIntervalUnitKey) ?? "days"
            return ["seconds", "minutes", "hours", "days"].contains(unit) ? unit : "days"
        }
        set {
            let validUnits = ["seconds", "minutes", "hours", "days"]
            let unit = validUnits.contains(newValue) ? newValue : "days"
            defaults.set(unit, forKey: iCloudBackupIntervalUnitKey)
        }
    }

    var lastICloudBackupDate: Date? {
        get { return defaults.object(forKey: lastICloudBackupDateKey) as? Date }
        set { defaults.set(newValue, forKey: lastICloudBackupDateKey) }
    }

    var enableDeadMansSwitch: Bool {
        get { return defaults.bool(forKey: enableDeadMansSwitchKey) }
        set { defaults.set(newValue, forKey: enableDeadMansSwitchKey) }
    }

    var stationaryLocationAccuracy: Int {
        get { return defaults.integer(forKey: stationaryLocationAccuracyKey) }
        set { defaults.set(max(0, min(newValue, 5)), forKey: stationaryLocationAccuracyKey) }
    }

    var movingLocationAccuracy: Int {
        get { return defaults.integer(forKey: movingLocationAccuracyKey) }
        set { defaults.set(max(0, min(newValue, 5)), forKey: movingLocationAccuracyKey) }
    }

    var stationaryLocationAccuracyLevel: LocationAccuracyLevel {
        return LocationAccuracyLevel(rawValue: stationaryLocationAccuracy) ?? .medium
    }

    var movingLocationAccuracyLevel: LocationAccuracyLevel {
        return LocationAccuracyLevel(rawValue: movingLocationAccuracy) ?? .best
    }

    func apiKey(for provider: PlaceProvider) -> String {
        return defaults.string(forKey: provider.settingsKey) ?? ""
    }

    func setApiKey(_ key: String, for provider: PlaceProvider) {
        defaults.set(key, forKey: provider.settingsKey)
    }
} 
import Foundation
import SwiftUI

struct TrackType: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var icon: String
    var isDefault: Bool
    
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
}

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    @Published var trackTypes: [TrackType] {
        didSet { saveTrackTypes() }
    }
    
    private let trackTypesURL: URL
    
    private init() {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let preferencesDir = documentsUrl.appendingPathComponent("Preferences")
        self.trackTypesURL = preferencesDir.appendingPathComponent("tracktypes.json")
        
        self.trackTypes = []
        loadTrackTypes()
    }
    
    private func defaultTrackTypes() -> [TrackType] {
        return [
            TrackType(id: "walking", name: "Walking", colorHex: "#34C759", icon: "figure.walk", isDefault: true),
            TrackType(id: "running", name: "Running", colorHex: "#FF9500", icon: "figure.run", isDefault: true),
            TrackType(id: "cycling", name: "Cycling", colorHex: "#FF3B30", icon: "figure.outdoor.cycle", isDefault: true),
            TrackType(id: "automotive", name: "Automotive", colorHex: "#007AFF", icon: "car.fill", isDefault: true),
            TrackType(id: "train", name: "Train", colorHex: "#5AC8FA", icon: "train.side.front.car", isDefault: true),
            TrackType(id: "plane", name: "Plane", colorHex: "#5856D6", icon: "airplane", isDefault: true),
            TrackType(id: "boat", name: "Boat", colorHex: "#00C7BE", icon: "sailboat.fill", isDefault: true),
            TrackType(id: "unknown", name: "Unknown", colorHex: "#AF52DE", icon: "arrow.down", isDefault: true)
        ]
    }
    
    private func loadTrackTypes() {
        if let data = try? Data(contentsOf: trackTypesURL) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([TrackType].self, from: data) {
                var mergedTypes = decoded
                for defaultType in defaultTrackTypes() {
                    if !mergedTypes.contains(where: { $0.id == defaultType.id }) {
                        mergedTypes.append(defaultType)
                    }
                }
                self.trackTypes = mergedTypes
                return
            }
        }
        self.trackTypes = defaultTrackTypes()
        saveTrackTypes()
    }
    
    private func saveTrackTypes() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(trackTypes) {
            do {
                try data.write(to: trackTypesURL, options: .atomic)
            } catch {
                print("Failed to save tracktypes: \(error)")
            }
        }
    }
    
    func trackType(for id: String?) -> TrackType? {
        guard let id = id else { return nil }
        return trackTypes.first(where: { $0.id.lowercased() == id.lowercased() })
    }
    
    func color(for id: String?) -> Color {
        if let type = trackType(for: id) { return type.color }
        return trackTypes.first(where: { $0.id == "unknown" })?.color ?? .purple
    }
    
    func icon(for id: String?) -> String {
        if let type = trackType(for: id) { return type.icon }
        return trackTypes.first(where: { $0.id == "unknown" })?.icon ?? "arrow.down"
    }
}

// MARK: - Color Hex Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }

    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != Float(1.0) {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}
