import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private let debugLogVerbosityKey = "debugLogVerbosity"
    private let loadCurrentDayOnRestoreAfterSecondsKey = "loadCurrentDayOnRestoreAfterSeconds" // Keep for backward compatibility
    private let loadCurrentDayOnRestoreAfterValueKey = "loadCurrentDayOnRestoreAfterValue"
    private let loadCurrentDayOnRestoreAfterUnitKey = "loadCurrentDayOnRestoreAfterUnit"
    private let defaultNewPlaceRadiusKey = "defaultNewPlaceRadius"

    
    private init() {
        registerDefaults()
        migrateOldSettings()
    }
    
    private func registerDefaults() {
        defaults.register(defaults: [
            debugLogVerbosityKey: 1,
            loadCurrentDayOnRestoreAfterSecondsKey: 600,
            loadCurrentDayOnRestoreAfterValueKey: 10,
            loadCurrentDayOnRestoreAfterUnitKey: "minutes",
            defaultNewPlaceRadiusKey: 100
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
} 
