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

enum UpdatePlaceInformationMode: String, CaseIterable, Identifiable {
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

enum MatchUnknownPlacesMode: String, CaseIterable, Identifiable {
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

enum VisuallyConnectTracksMode: String, CaseIterable, Identifiable {
    case never
    case transparent
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .transparent: return "Transparent"
        case .solid: return "Solid"
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

struct GPXExportSettings: Equatable, RawRepresentable {
    var waypoints: GPXExportFields
    var tracks: GPXExportFields
    var trackpoints: GPXExportFields

    init() {
        self.waypoints = GPXExportFields(isWaypoint: true)
        self.tracks = GPXExportFields(isTrack: true)
        self.trackpoints = GPXExportFields(isWaypoint: false)
    }
    
    private struct CodableWrapper: Codable {
        var waypoints: GPXExportFields
        var tracks: GPXExportFields
        var trackpoints: GPXExportFields
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(CodableWrapper.self, from: data)
        else {
            return nil
        }
        self.waypoints = result.waypoints
        self.tracks = result.tracks
        self.trackpoints = result.trackpoints
    }

    var rawValue: String {
        let wrapper = CodableWrapper(waypoints: waypoints, tracks: tracks, trackpoints: trackpoints)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(wrapper),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }
}

struct GPXFieldState: Codable, Equatable {
    var export: Bool
    var visible: Bool

    init(export: Bool = true, visible: Bool = false) {
        self.export = export
        self.visible = visible
    }
}

struct GPXExportFields: Codable, Equatable {
    var magneticVariation: GPXFieldState = GPXFieldState(export: false)
    var geoidHeight: GPXFieldState = GPXFieldState(export: false)
    var name: GPXFieldState = GPXFieldState(export: true)
    var comment: GPXFieldState = GPXFieldState(export: true)
    var desc: GPXFieldState = GPXFieldState(export: true)
    var source: GPXFieldState = GPXFieldState(export: true)
    var symbol: GPXFieldState = GPXFieldState(export: true)
    var type: GPXFieldState = GPXFieldState(export: true)
    var fix: GPXFieldState = GPXFieldState(export: false)
    var satellites: GPXFieldState = GPXFieldState(export: false)
    var horizontalDilution: GPXFieldState = GPXFieldState(export: false)
    var verticalDilution: GPXFieldState = GPXFieldState(export: false)
    var positionDilution: GPXFieldState = GPXFieldState(export: false)
    var ageofDGPSData: GPXFieldState = GPXFieldState(export: false)
    var DGPSid: GPXFieldState = GPXFieldState(export: false)
    var links: GPXFieldState = GPXFieldState(export: true)
    var number: GPXFieldState = GPXFieldState(export: true)
    
    var extensions: [String: GPXFieldState] = [:]
    
    init(isWaypoint: Bool = false, isTrack: Bool = false) {
        if isWaypoint {
            for ext in GPXExtensionKey.waypointCases {
                let defaultExport = ext.rawValue.hasSuffix("CategoryId") ? false : true
                extensions[ext.rawValue] = GPXFieldState(export: defaultExport)
            }
        } else if !isTrack {
            for ext in GPXExtensionKey.trackpointCases {
                extensions[ext.rawValue] = GPXFieldState(export: true)
            }
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
    private let filterBeforeFirstWaypointKey = "filterBeforeFirstWaypoint"
    private let roundTripMaxPointsKey = "roundTripMaxPoints"
    private let roundTripUnknownRadiusKey = "roundTripUnknownRadius"
    private let automaticallyMergeUnknownToKnownTypeTracksKey = "automaticallyMergeUnknownToKnownTypeTracks"
    private let automaticMergeUnknownTrackMaxPointsKey = "automaticMergeUnknownTrackMaxPoints"
    private let automaticMergeKnownTrackMinimumPointsKey = "automaticMergeKnownTrackMinimumPoints"
    private let askToOrganizeGpxFilesKey = "askToOrganizeGpxFiles"
    private let gpxOverwriteExistingKey = "gpxOverwriteExisting"
    private let gpxConflictResolutionKey = "gpxConflictResolution"
    private let timelinePictureDisplayModeKey = "timelinePictureDisplayMode"
    private let timelineShowNumberOfPointsKey = "timelineShowNumberOfPoints"
    private let mapCoordinateSystemModeKey = "mapCoordinateSystemMode"
    private let suggestApplyToOtherPlacesKey = "suggestApplyToOtherPlaces"
    private let mergeVisitAddStepsKey = "mergeVisitAddSteps"
    private let autoReverseLookupUnknownVisitsKey = "autoReverseLookupUnknownVisits"
    private let sendNotificationOnUnknownPlaceKey = "sendNotificationOnUnknownPlace"
    private let notifyOfSavedUnknownTrackTypesKey = "notifyOfSavedUnknownTrackTypes"
    private let unknownPlaceNotificationValueKey = "unknownPlaceNotificationValue"
    private let unknownPlaceNotificationUnitKey = "unknownPlaceNotificationUnit"
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
    private let localBackupSaveCopyOnEditsKey = "localBackupSaveCopyOnEdits"
    private let localBackupRetentionDaysKey = "localBackupRetentionDays"
    private let localBackupRetentionVersionsKey = "localBackupRetentionVersions"
    private let localBackupAlwaysRetainOriginalKey = "localBackupAlwaysRetainOriginal"
    private let logRetentionDaysKey = "logRetentionDays"
    private let logSizeLimitMBKey = "logSizeLimitMB"
    private let gpxExportSettingsKey = "gpxExportSettings"
    private let useLastStationaryAsFirstTrackPointKey = "useLastStationaryAsFirstTrackPoint"
    private let lastStationaryTimeThresholdKey = "lastStationaryTimeThreshold"
    private let lastStationaryDistanceThresholdKey = "lastStationaryDistanceThreshold"
    private let logAllReceivedPositionsKey = "logAllReceivedPositions"
    private let logMotionDataKey = "logMotionData"
    private let logFitnessDataKey = "logFitnessData"
    private let suggestIncreasePlaceRadiusKey = "suggestIncreasePlaceRadius"
    private let overwriteExistingAddressOnNewPlaceCreationKey = "overwriteExistingAddressOnNewPlaceCreation"
    private let updatePlaceInformationModeKey = "updatePlaceInformationMode"
    private let matchUnknownPlacesModeKey = "matchUnknownPlacesMode"
    private let visuallyConnectTracksModeKey = "visuallyConnectTracksMode"
    
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
            defaultNewPlaceRadiusKey: 20,
            placeProviderOrderKey: defaultOrder,
            filterSmallRoundTripsKey: true,
            filterBeforeFirstWaypointKey: true,
            roundTripMaxPointsKey: 3,
            roundTripUnknownRadiusKey: 100,
            automaticallyMergeUnknownToKnownTypeTracksKey: true,
            automaticMergeUnknownTrackMaxPointsKey: 2,
            automaticMergeKnownTrackMinimumPointsKey: 3,
            askToOrganizeGpxFilesKey: true,
            gpxOverwriteExistingKey: false,
            gpxConflictResolutionKey: "keepExisting",
            timelinePictureDisplayModeKey: TimelinePictureDisplayMode.large.rawValue,
            timelineShowNumberOfPointsKey: false,
            mapCoordinateSystemModeKey: MapCoordinateSystemMode.auto.rawValue,
            suggestApplyToOtherPlacesKey: true,
            mergeVisitAddStepsKey: true,
            autoReverseLookupUnknownVisitsKey: true,
            sendNotificationOnUnknownPlaceKey: true,
            notifyOfSavedUnknownTrackTypesKey: true,
            unknownPlaceNotificationValueKey: 10,
            unknownPlaceNotificationUnitKey: "minutes",
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
            timelineLocalTimeModeKey: TimelineLocalTimeMode.always.rawValue,
            enableDeadMansSwitchKey: true,
            stationaryLocationAccuracyKey: LocationAccuracyLevel.medium.rawValue,
            movingLocationAccuracyKey: LocationAccuracyLevel.best.rawValue,
            localBackupSaveCopyOnEditsKey: true,
            localBackupRetentionDaysKey: -1,
            localBackupRetentionVersionsKey: -1,
            localBackupAlwaysRetainOriginalKey: true,
            logRetentionDaysKey: -1,
            logSizeLimitMBKey: 10,
            gpxExportSettingsKey: GPXExportSettings().rawValue,
            useLastStationaryAsFirstTrackPointKey: true,
            lastStationaryTimeThresholdKey: 1,
            lastStationaryDistanceThresholdKey: 20,
            logAllReceivedPositionsKey: false,
            logMotionDataKey: false,
            logFitnessDataKey: false,
            suggestIncreasePlaceRadiusKey: true,
            overwriteExistingAddressOnNewPlaceCreationKey: true,
            updatePlaceInformationModeKey: UpdatePlaceInformationMode.always.rawValue,
            matchUnknownPlacesModeKey: MatchUnknownPlacesMode.ask.rawValue,
            visuallyConnectTracksModeKey: VisuallyConnectTracksMode.transparent.rawValue
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
        
        if defaults.object(forKey: "unknownPlaceNotificationMinutes") != nil &&
           defaults.object(forKey: unknownPlaceNotificationValueKey) == nil {
            let oldMinutes = defaults.integer(forKey: "unknownPlaceNotificationMinutes")
            if oldMinutes > 0 {
                defaults.set(oldMinutes, forKey: unknownPlaceNotificationValueKey)
                defaults.set("minutes", forKey: unknownPlaceNotificationUnitKey)
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

    var gpxExportSettings: GPXExportSettings {
        get {
            let raw = defaults.string(forKey: gpxExportSettingsKey) ?? GPXExportSettings().rawValue
            return GPXExportSettings(rawValue: raw) ?? GPXExportSettings()
        }
        set {
            defaults.set(newValue.rawValue, forKey: gpxExportSettingsKey)
            defaults.set(newValue.rawValue, forKey: "gpxExportSettings") // for @AppStorage syncing
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

    var filterBeforeFirstWaypoint: Bool {
        get {
            return defaults.bool(forKey: filterBeforeFirstWaypointKey)
        }
        set {
            defaults.set(newValue, forKey: filterBeforeFirstWaypointKey)
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
            let raw = defaults.string(forKey: timelinePictureDisplayModeKey) ?? TimelinePictureDisplayMode.large.rawValue
            return TimelinePictureDisplayMode(rawValue: raw) ?? .large
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
            let raw = defaults.string(forKey: timelineLocalTimeModeKey) ?? TimelineLocalTimeMode.always.rawValue
            return TimelineLocalTimeMode(rawValue: raw) ?? .always
        }
        set {
            defaults.set(newValue.rawValue, forKey: timelineLocalTimeModeKey)
        }
    }

    var timelineShowNumberOfPoints: Bool {
        get { defaults.bool(forKey: timelineShowNumberOfPointsKey) }
        set { defaults.set(newValue, forKey: timelineShowNumberOfPointsKey) }
    }

    var updatePlaceInformationMode: UpdatePlaceInformationMode {
        get {
            let raw = defaults.string(forKey: updatePlaceInformationModeKey) ?? UpdatePlaceInformationMode.always.rawValue
            return UpdatePlaceInformationMode(rawValue: raw) ?? .always
        }
        set {
            defaults.set(newValue.rawValue, forKey: updatePlaceInformationModeKey)
        }
    }

    var matchUnknownPlacesMode: MatchUnknownPlacesMode {
        get {
            let raw = defaults.string(forKey: matchUnknownPlacesModeKey) ?? MatchUnknownPlacesMode.ask.rawValue
            return MatchUnknownPlacesMode(rawValue: raw) ?? .ask
        }
        set {
            defaults.set(newValue.rawValue, forKey: matchUnknownPlacesModeKey)
        }
    }

    var visuallyConnectTracksMode: VisuallyConnectTracksMode {
        get {
            let raw = defaults.string(forKey: visuallyConnectTracksModeKey) ?? VisuallyConnectTracksMode.transparent.rawValue
            return VisuallyConnectTracksMode(rawValue: raw) ?? .transparent
        }
        set {
            defaults.set(newValue.rawValue, forKey: visuallyConnectTracksModeKey)
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

    var autoReverseLookupUnknownVisits: Bool {
        get { return defaults.bool(forKey: autoReverseLookupUnknownVisitsKey) }
        set { defaults.set(newValue, forKey: autoReverseLookupUnknownVisitsKey) }
    }

    var suggestIncreasePlaceRadius: Bool {
        get { return defaults.bool(forKey: suggestIncreasePlaceRadiusKey) }
        set { defaults.set(newValue, forKey: suggestIncreasePlaceRadiusKey) }
    }

    var overwriteExistingAddressOnNewPlaceCreation: Bool {
        get { return defaults.object(forKey: overwriteExistingAddressOnNewPlaceCreationKey) != nil ? defaults.bool(forKey: overwriteExistingAddressOnNewPlaceCreationKey) : true }
        set { defaults.set(newValue, forKey: overwriteExistingAddressOnNewPlaceCreationKey) }
    }

    var sendNotificationOnUnknownPlace: Bool {
        get { return defaults.bool(forKey: sendNotificationOnUnknownPlaceKey) }
        set { defaults.set(newValue, forKey: sendNotificationOnUnknownPlaceKey) }
    }

    var notifyOfSavedUnknownTrackTypes: Bool {
        get { return defaults.bool(forKey: notifyOfSavedUnknownTrackTypesKey) }
        set { defaults.set(newValue, forKey: notifyOfSavedUnknownTrackTypesKey) }
    }

    var unknownPlaceNotificationValue: Int {
        get { return max(1, defaults.integer(forKey: unknownPlaceNotificationValueKey)) }
        set { defaults.set(max(1, newValue), forKey: unknownPlaceNotificationValueKey) }
    }

    var unknownPlaceNotificationUnit: String {
        get { return defaults.string(forKey: unknownPlaceNotificationUnitKey) ?? "minutes" }
        set { defaults.set(newValue, forKey: unknownPlaceNotificationUnitKey) }
    }
    
    var unknownPlaceNotificationSeconds: Double {
        let value = Double(unknownPlaceNotificationValue)
        switch unknownPlaceNotificationUnit {
        case "seconds": return value
        case "minutes": return value * 60
        case "hours": return value * 3600
        case "days": return value * 86400
        default: return value * 60
        }
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

    var localBackupSaveCopyOnEdits: Bool {
        get { return defaults.bool(forKey: localBackupSaveCopyOnEditsKey) }
        set { defaults.set(newValue, forKey: localBackupSaveCopyOnEditsKey) }
    }

    var localBackupRetentionDays: Int {
        get { return defaults.integer(forKey: localBackupRetentionDaysKey) }
        set { defaults.set(newValue, forKey: localBackupRetentionDaysKey) }
    }

    var localBackupRetentionVersions: Int {
        get { return defaults.integer(forKey: localBackupRetentionVersionsKey) }
        set { defaults.set(newValue, forKey: localBackupRetentionVersionsKey) }
    }

    var localBackupAlwaysRetainOriginal: Bool {
        get { return defaults.bool(forKey: localBackupAlwaysRetainOriginalKey) }
        set { defaults.set(newValue, forKey: localBackupAlwaysRetainOriginalKey) }
    }

    var logRetentionDays: Int {
        get {
            // Provide a default of -1 if it was registered but let's just return what defaults gives.
            // Wait, registerDefaults already provides -1.
            return defaults.integer(forKey: logRetentionDaysKey)
        }
        set { defaults.set(newValue, forKey: logRetentionDaysKey) }
    }

    var logSizeLimitMB: Int {
        get {
            return defaults.integer(forKey: logSizeLimitMBKey)
        }
        set { defaults.set(newValue, forKey: logSizeLimitMBKey) }
    }

    var useLastStationaryAsFirstTrackPoint: Bool {
        get { return defaults.bool(forKey: useLastStationaryAsFirstTrackPointKey) }
        set { defaults.set(newValue, forKey: useLastStationaryAsFirstTrackPointKey) }
    }

    var lastStationaryTimeThreshold: Int {
        get { return defaults.integer(forKey: lastStationaryTimeThresholdKey) }
        set { defaults.set(newValue, forKey: lastStationaryTimeThresholdKey) }
    }

    var lastStationaryDistanceThreshold: Int {
        get { return defaults.integer(forKey: lastStationaryDistanceThresholdKey) }
        set { defaults.set(newValue, forKey: lastStationaryDistanceThresholdKey) }
    }

    var logAllReceivedPositions: Bool {
        get { return defaults.bool(forKey: logAllReceivedPositionsKey) }
        set { defaults.set(newValue, forKey: logAllReceivedPositionsKey) }
    }

    var logMotionData: Bool {
        get { return defaults.bool(forKey: logMotionDataKey) }
        set { defaults.set(newValue, forKey: logMotionDataKey) }
    }

    var logFitnessData: Bool {
        get { return defaults.bool(forKey: logFitnessDataKey) }
        set { defaults.set(newValue, forKey: logFitnessDataKey) }
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

enum TrackTypeCategory: String, CaseIterable, Identifiable, Codable {
    case basic = "Basic"
    case custom = "Custom"
    case workouts = "Workouts"
    case otherWorkouts = "Other Workouts"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .custom: return "Custom"
        case .workouts: return "Workouts"
        case .otherWorkouts: return "Other Activities"
        }
    }
}

struct TrackType: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var icon: String
    var isDefault: Bool
    
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
    
    var category: TrackTypeCategory {
        if !isDefault {
            return .custom
        }
        switch id.lowercased() {
        case "walking", "running", "cycling", "scooter", "automotive", "motorcycle", "train", "plane", "boat", "unknown":
            return .basic
        case "outdoor_cycling", "hiking", "swimming", "skiing", "snowboarding", "rowing", "stair_climbing", "golf", "wheelchair", "equestrian_sports", "skating_sports", "surfing_sports", "paddlesports", "sailing", "climbing", "track_and_field", "swim_bike_run", "underwater_diving", "hand_cycling", "hunting", "water_sports":
            return .workouts
        default:
            return .otherWorkouts
        }
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
            // Basic
            TrackType(id: "walking", name: "Walking", colorHex: "#34C759", icon: "figure.walk", isDefault: true),
            TrackType(id: "running", name: "Running", colorHex: "#FF9500", icon: "figure.run", isDefault: true),
            TrackType(id: "cycling", name: "Cycling", colorHex: "#FF3B30", icon: "figure.outdoor.cycle", isDefault: true),
            TrackType(id: "scooter", name: "Scooter", colorHex: "#FF9F0A", icon: "scooter", isDefault: true),
            TrackType(id: "automotive", name: "Automotive", colorHex: "#007AFF", icon: "car.fill", isDefault: true),
            TrackType(id: "motorcycle", name: "Motorcycle", colorHex: "#5856D6", icon: "motorcycle", isDefault: true),
            TrackType(id: "train", name: "Train", colorHex: "#5AC8FA", icon: "train.side.front.car", isDefault: true),
            TrackType(id: "plane", name: "Plane", colorHex: "#5856D6", icon: "airplane", isDefault: true),
            TrackType(id: "boat", name: "Boat", colorHex: "#00C7BE", icon: "sailboat.fill", isDefault: true),
            TrackType(id: "unknown", name: "Unknown", colorHex: "#AF52DE", icon: "arrow.down", isDefault: true),
            
            // Workouts
            TrackType(id: "outdoor_cycling", name: "Outdoor Cycling", colorHex: "#FF3B30", icon: "figure.outdoor.cycle", isDefault: true),
            TrackType(id: "hiking", name: "Hiking", colorHex: "#A2845E", icon: "figure.hiking", isDefault: true),
            TrackType(id: "swimming", name: "Swimming", colorHex: "#1D70B8", icon: "figure.pool.swim", isDefault: true),
            TrackType(id: "skiing", name: "Skiing", colorHex: "#64D2FF", icon: "figure.skiing.downhill", isDefault: true),
            TrackType(id: "snowboarding", name: "Snowboarding", colorHex: "#30B0C7", icon: "figure.snowboarding", isDefault: true),
            TrackType(id: "rowing", name: "Rowing", colorHex: "#32ADE6", icon: "figure.rower", isDefault: true),
            TrackType(id: "stair_climbing", name: "Stair Climbing", colorHex: "#FFD60A", icon: "figure.stair.stepper", isDefault: true),
            TrackType(id: "golf", name: "Golf", colorHex: "#30B0C7", icon: "figure.golf", isDefault: true),
            TrackType(id: "wheelchair", name: "Wheelchair", colorHex: "#5856D6", icon: "figure.roll", isDefault: true),
            TrackType(id: "equestrian_sports", name: "Equestrian Sports", colorHex: "#A2845E", icon: "figure.equestrian.sports", isDefault: true),
            TrackType(id: "swim_bike_run", name: "Triathlon", colorHex: "#FF9500", icon: "figure.open.water.swim", isDefault: true),
            
            // Other Workouts (Confined to a place)
            TrackType(id: "functional_strength_training", name: "Strength Training", colorHex: "#FF453A", icon: "figure.strengthtraining.functional", isDefault: true),
            TrackType(id: "yoga", name: "Yoga", colorHex: "#BF5AF2", icon: "figure.yoga", isDefault: true),
            TrackType(id: "pilates", name: "Pilates", colorHex: "#DA8FFF", icon: "figure.pilates", isDefault: true),
            TrackType(id: "dance", name: "Dance", colorHex: "#FF375F", icon: "figure.dance", isDefault: true),
            TrackType(id: "core_training", name: "Core Training", colorHex: "#FF9F0A", icon: "figure.core.training", isDefault: true),
            TrackType(id: "basketball", name: "Basketball", colorHex: "#FF9500", icon: "figure.basketball", isDefault: true),
            TrackType(id: "table_tennis", name: "Table Tennis", colorHex: "#40C8E0", icon: "figure.table.tennis", isDefault: true),
            TrackType(id: "tennis", name: "Tennis", colorHex: "#66D4CF", icon: "figure.tennis", isDefault: true),
            TrackType(id: "badminton", name: "Badminton", colorHex: "#30D158", icon: "figure.badminton", isDefault: true),
            TrackType(id: "elliptical", name: "Elliptical", colorHex: "#FF6482", icon: "figure.elliptical", isDefault: true),
            TrackType(id: "soccer", name: "Soccer", colorHex: "#34C759", icon: "figure.soccer", isDefault: true),
            TrackType(id: "pickleball", name: "Pickleball", colorHex: "#63E6E2", icon: "figure.pickleball", isDefault: true),
            TrackType(id: "paddlesports", name: "Paddlesports", colorHex: "#00C7BE", icon: "figure.open.water.swim", isDefault: true),
            TrackType(id: "american_football", name: "American Football", colorHex: "#A2845E", icon: "figure.american.football", isDefault: true),
            TrackType(id: "archery", name: "Archery", colorHex: "#8E8E93", icon: "figure.archery", isDefault: true),
            TrackType(id: "australian_football", name: "Australian Football", colorHex: "#FF9500", icon: "figure.australian.football", isDefault: true),
            TrackType(id: "baseball", name: "Baseball", colorHex: "#FFCC00", icon: "figure.baseball", isDefault: true),
            TrackType(id: "bowling", name: "Bowling", colorHex: "#5AC8FA", icon: "figure.bowling", isDefault: true),
            TrackType(id: "boxing", name: "Boxing", colorHex: "#FF3B30", icon: "figure.boxing", isDefault: true),
            TrackType(id: "cricket", name: "Cricket", colorHex: "#4CD964", icon: "figure.cricket", isDefault: true),
            TrackType(id: "cross_training", name: "Cross Training", colorHex: "#FF9500", icon: "figure.cross.training", isDefault: true),
            TrackType(id: "curling", name: "Curling", colorHex: "#5AC8FA", icon: "figure.curling", isDefault: true),
            TrackType(id: "fencing", name: "Fencing", colorHex: "#8E8E93", icon: "figure.fencing", isDefault: true),
            TrackType(id: "fitness_gaming", name: "Fitness Gaming", colorHex: "#AF52DE", icon: "gamecontroller", isDefault: true),
            TrackType(id: "flexibility", name: "Flexibility", colorHex: "#DA8FFF", icon: "figure.flexibility", isDefault: true),
            TrackType(id: "gymnastics", name: "Gymnastics", colorHex: "#FF2D55", icon: "figure.gymnastics", isDefault: true),
            TrackType(id: "handball", name: "Handball", colorHex: "#FF9500", icon: "figure.handball", isDefault: true),
            TrackType(id: "hiit", name: "HIIT", colorHex: "#FF3B30", icon: "figure.highintensity.intervaltraining", isDefault: true),
            TrackType(id: "hockey", name: "Hockey", colorHex: "#007AFF", icon: "figure.hockey", isDefault: true),
            TrackType(id: "jump_rope", name: "Jump Rope", colorHex: "#FFCC00", icon: "figure.jumprope", isDefault: true),
            TrackType(id: "kickboxing", name: "Kickboxing", colorHex: "#FF3B30", icon: "figure.kickboxing", isDefault: true),
            TrackType(id: "martial_arts", name: "Martial Arts", colorHex: "#FF453A", icon: "figure.martial.arts", isDefault: true),
            TrackType(id: "mind_and_body", name: "Mind & Body", colorHex: "#BF5AF2", icon: "figure.mind.and.body", isDefault: true),
            TrackType(id: "mixed_cardio", name: "Mixed Cardio", colorHex: "#FF9500", icon: "figure.mixed.cardio", isDefault: true),
            TrackType(id: "cooldown", name: "Cooldown", colorHex: "#5AC8FA", icon: "figure.cooldown", isDefault: true),
            TrackType(id: "racquetball", name: "Racquetball", colorHex: "#66D4CF", icon: "figure.racquetball", isDefault: true),
            TrackType(id: "rugby", name: "Rugby", colorHex: "#A2845E", icon: "figure.rugby", isDefault: true),
            TrackType(id: "softball", name: "Softball", colorHex: "#FFCC00", icon: "figure.softball", isDefault: true),
            TrackType(id: "squash", name: "Squash", colorHex: "#66D4CF", icon: "figure.squash", isDefault: true),
            TrackType(id: "stairs", name: "Stairs / Stepper", colorHex: "#FFD60A", icon: "figure.stair.stepper", isDefault: true),
            TrackType(id: "step_training", name: "Step Training", colorHex: "#FFD60A", icon: "figure.step.training", isDefault: true),
            TrackType(id: "tai_chi", name: "Tai Chi", colorHex: "#BF5AF2", icon: "figure.taichi", isDefault: true),
            TrackType(id: "volleyball", name: "Volleyball", colorHex: "#FF9500", icon: "figure.volleyball", isDefault: true),
            TrackType(id: "water_fitness", name: "Water Fitness", colorHex: "#1D70B8", icon: "figure.water.fitness", isDefault: true),
            TrackType(id: "water_polo", name: "Water Polo", colorHex: "#1D70B8", icon: "figure.waterpolo", isDefault: true),
            TrackType(id: "wrestling", name: "Wrestling", colorHex: "#FF3B30", icon: "figure.wrestling", isDefault: true),
            TrackType(id: "barre", name: "Barre", colorHex: "#DA8FFF", icon: "figure.barre", isDefault: true),
            TrackType(id: "disc_sports", name: "Disc Sports", colorHex: "#30B0C7", icon: "figure.disc.sports", isDefault: true),
            TrackType(id: "lacrosse", name: "Lacrosse", colorHex: "#FF9500", icon: "figure.lacrosse", isDefault: true),
            TrackType(id: "play", name: "Play", colorHex: "#FFCC00", icon: "figure.play", isDefault: true),
            TrackType(id: "transition", name: "Transition", colorHex: "#8E8E93", icon: "arrow.triangle.2.circlepath", isDefault: true)
        ]
    }
    
    private func loadTrackTypes() {
        if let data = try? Data(contentsOf: trackTypesURL) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([TrackType].self, from: data) {
                var mergedTypes = decoded
                let defaults = defaultTrackTypes()
                for defaultType in defaults {
                    if !mergedTypes.contains(where: { $0.id == defaultType.id }) {
                        if let defaultIndex = defaults.firstIndex(where: { $0.id == defaultType.id }),
                           defaultIndex > 0 {
                            let prevDefaultId = defaults[defaultIndex - 1].id
                            if let prevIndex = mergedTypes.firstIndex(where: { $0.id == prevDefaultId }) {
                                mergedTypes.insert(defaultType, at: prevIndex + 1)
                                continue
                            }
                        }
                        mergedTypes.append(defaultType)
                    }
                }
                for i in 0..<mergedTypes.count {
                    if mergedTypes[i].id == "tai_chi" && mergedTypes[i].icon == "figure.tai.chi" {
                        mergedTypes[i].icon = "figure.taichi"
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
