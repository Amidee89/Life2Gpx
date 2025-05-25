import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private let debugLogVerbosityKey = "debugLogVerbosity"

    
    private init() {
        registerDefaults()
    }
    
    private func registerDefaults() {
        defaults.register(defaults: [
            debugLogVerbosityKey: 1
        ])
        print("UserDefaults registered with default verbosity: \(defaults.integer(forKey: debugLogVerbosityKey))")
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
} 
