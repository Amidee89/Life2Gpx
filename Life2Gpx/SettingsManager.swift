import Foundation

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
    private let askToOrganizeGpxFilesKey = "askToOrganizeGpxFiles"
    private let gpxOverwriteExistingKey = "gpxOverwriteExisting"
    private let gpxConflictResolutionKey = "gpxConflictResolution"
    private let timelinePictureDisplayModeKey = "timelinePictureDisplayMode"

    
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
            askToOrganizeGpxFilesKey: true,
            gpxOverwriteExistingKey: false,
            gpxConflictResolutionKey: "keepExisting",
            timelinePictureDisplayModeKey: TimelinePictureDisplayMode.small.rawValue
        ])
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

    func apiKey(for provider: PlaceProvider) -> String {
        return defaults.string(forKey: provider.settingsKey) ?? ""
    }

    func setApiKey(_ key: String, for provider: PlaceProvider) {
        defaults.set(key, forKey: provider.settingsKey)
    }
} 
