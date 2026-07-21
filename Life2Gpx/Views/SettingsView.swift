import SwiftUI
import Photos

private struct DiagnosticReportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    @AppStorage("disableTracking") private var disableTracking: Bool = SettingsManager.shared.disableTracking

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Disable tracking", isOn: $disableTracking)
                        .fixedSize(horizontal: false, vertical: true)
                        .tint(.red)
                    
                    Text("Disable all realtime tracking from the app")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.gray)
                }
            }
            .listRowBackground(disableTracking ? Color.red.opacity(0.1) : nil)
            
            Section {
                NavigationLink("App behaviour and defaults", destination: SettingsAppBehaviourView())
                NavigationLink("Timeline", destination: SettingsLayoutAppearanceView())
                NavigationLink("Notifications", destination: SettingsNotificationsView())
                NavigationLink("Backups", destination: SettingsBackupsView())
                NavigationLink("Location and steps tracking", destination: SettingsLocationTrackingView())
                NavigationLink("Place search and edit", destination: SettingsPlaceSearchView())
                NavigationLink("Automatic cleanups", destination: SettingsAutomaticCleanupsView())
                NavigationLink("Logging", destination: SettingsLoggingView())
            }
        }
        .navigationTitle("Settings")
    }
}

private let timeUnits = ["seconds", "minutes", "hours", "days"]
private let daysSteps = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 60, 180, 365, -1]
private let versionsSteps = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 50, -1]
private let sizeStepsMB = [1, 2, 5, 10, 20, 50, 100, -1]

private func indexForDays(_ value: Int) -> Double {
    return Double(daysSteps.firstIndex(of: value) ?? (daysSteps.count - 1))
}
private func indexForVersions(_ value: Int) -> Double {
    return Double(versionsSteps.firstIndex(of: value) ?? (versionsSteps.count - 1))
}
private func indexForSizeMB(_ value: Int) -> Double {
    return Double(sizeStepsMB.firstIndex(of: value) ?? (sizeStepsMB.count - 1))
}

private let stationaryTimeSteps = [0, 1, 2, 5, 10, 20, 30, 60, 120]
private let stationaryDistanceSteps = [0, 10, 20, 50, 100, 200, 400, 1000, 10000, 20000, 100000]

private func indexForStationaryTime(_ value: Int) -> Double {
    return Double(stationaryTimeSteps.firstIndex(of: value) ?? 0)
}

private func indexForStationaryDistance(_ value: Int) -> Double {
    return Double(stationaryDistanceSteps.firstIndex(of: value) ?? 0)
}

private func formattedStationaryDistance(_ meters: Int) -> String {
    if meters == 0 { return "Always" }
    if meters < 1000 { return "\(meters)mt" }
    return "\(meters / 1000)km"
}

private func formattedStationaryTime(_ minutes: Int) -> String {
    if minutes == 0 { return "Always" }
    return "\(minutes) min"
}

struct SettingsAppBehaviourView: View {
    @AppStorage("loadCurrentDayOnRestoreAfterValue") private var loadCurrentDayOnRestoreAfterValue: Int = SettingsManager.shared.loadCurrentDayOnRestoreAfterValue
    @AppStorage("loadCurrentDayOnRestoreAfterUnit") private var loadCurrentDayOnRestoreAfterUnit: String = SettingsManager.shared.loadCurrentDayOnRestoreAfterUnit
    @AppStorage("defaultNewPlaceRadius") private var defaultNewPlaceRadius: Int = SettingsManager.shared.defaultNewPlaceRadius
    @AppStorage("suggestIncreasePlaceRadius") private var suggestIncreasePlaceRadius: Bool = SettingsManager.shared.suggestIncreasePlaceRadius
    @AppStorage("mergeVisitAddSteps") private var mergeVisitAddSteps: Bool = SettingsManager.shared.mergeVisitAddSteps
    @AppStorage("autoReverseLookupUnknownVisits") private var autoReverseLookupUnknownVisits: Bool = SettingsManager.shared.autoReverseLookupUnknownVisits
    @AppStorage("mapCoordinateSystemMode") private var mapCoordinateSystemMode: String = SettingsManager.shared.mapCoordinateSystemMode.rawValue
    @AppStorage("showCurrentPositionMode") private var showCurrentPositionMode: String = SettingsManager.shared.showCurrentPositionMode.rawValue
    @FocusState private var valueFieldIsFocused: Bool

    var body: some View {
        Form {
            Section(header: Text("App Behaviour")) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Auto-load current day after")
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            TextField("Value", value: $loadCurrentDayOnRestoreAfterValue, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .frame(maxWidth: 80)
                                .focused($valueFieldIsFocused)
                            
                            Picker("", selection: $loadCurrentDayOnRestoreAfterUnit) {
                                ForEach(timeUnits, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .fixedSize(horizontal: true, vertical: false)
                            .labelsHidden()
                            
                            Spacer()
                        }
                        
                        Text("The app will load today's data if it has been in the background for longer than this interval.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Default new place radius (meters)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(defaultNewPlaceRadius)")
                        }
                        Slider(value: Binding(
                            get: { Double(defaultNewPlaceRadius) },
                            set: { defaultNewPlaceRadius = Int($0) }
                        ), in: 10...1000, step: 10)
                        Text("Default size of the circular region for a newly created place.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Suggest to increase radius of places", isOn: $suggestIncreasePlaceRadius)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("When editing a visit, if the place is selected but its radius is smaller than the distance to the visit, the app will propose to increase it.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Add up steps when merging to visit", isOn: $mergeVisitAddSteps)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("When merging items into a visit, add up all the steps from the merged items and assign them to the resulting visit.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Automatically reverse lookup address for unknown visits", isOn: $autoReverseLookupUnknownVisits)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("When an unknown place is saved, if enabled, the app will automatically perform a reverse address lookup using Maps APIs.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical)
            }
            
            Section(header: Text("Map")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Show current position on map")
                        .foregroundColor(.primary)

                    Picker("Show current position on map", selection: $showCurrentPositionMode) {
                        ForEach(ShowCurrentPositionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.bottom, 8)
                
                Picker("Map coordinate system", selection: $mapCoordinateSystemMode) {
                    ForEach(MapCoordinateSystemMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }

                Text(mapCoordinateSystemHelpText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle("App Behaviour")
        .toolbar { 
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    valueFieldIsFocused = false
                }
            }
        }
    }

    private var mapCoordinateSystemHelpText: String {
        switch MapCoordinateSystemMode(rawValue: mapCoordinateSystemMode) ?? .auto {
        case .auto:
            return "Automatic: shift tracks and places on the map when your device is in mainland China (Gaode tiles). GPS data is always stored as WGS-84."
        case .forceGCJ02:
            return "Always shift map overlays for China-style (GCJ-02) tiles. Useful for testing outside China."
        case .forceWGS84:
            return "Never shift map overlays. Use when viewing China data on standard WGS-84 maps abroad."
        }
    }
}

struct SettingsLayoutAppearanceView: View {
    @AppStorage("timelinePictureDisplayMode") private var timelinePictureDisplayMode: String = SettingsManager.shared.timelinePictureDisplayMode.rawValue
    @AppStorage("timelineLocalTimeMode") private var timelineLocalTimeMode: String = SettingsManager.shared.timelineLocalTimeMode.rawValue
    @AppStorage("activitySummaryVisibility") private var activitySummaryVisibility: String = SettingsManager.shared.activitySummaryVisibility.rawValue
    @AppStorage("activitySummaryDistanceThreshold") private var activitySummaryDistanceThreshold: Int = SettingsManager.shared.activitySummaryDistanceThreshold
    @AppStorage("photoCacheMemoryMB") private var photoCacheMemoryMB: Int = SettingsManager.shared.photoCacheMemoryMB
    @AppStorage("photoCacheCountLimit") private var photoCacheCountLimit: Int = SettingsManager.shared.photoCacheCountLimit

    @State private var showAdvancedAppearance = false

    var body: some View {
        Form {
            Section(header: Text("Layout and appearance")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Show pictures in timeline")
                        .foregroundColor(.primary)

                    Picker("Show pictures in timeline", selection: $timelinePictureDisplayMode) {
                        ForEach(TimelinePictureDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Button("Advanced...") {
                        withAnimation {
                            showAdvancedAppearance.toggle()
                        }
                    }
                    .padding(.top, 4)
                    
                    if showAdvancedAppearance {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Photo Cache Memory Limit (MB)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(photoCacheMemoryMB)")
                            }
                            Slider(value: Binding(
                                get: { Double(photoCacheMemoryMB) },
                                set: { photoCacheMemoryMB = Int($0) }
                            ), in: 16...1024, step: 16)
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Full Photo Cache Count")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(photoCacheCountLimit)")
                            }
                            Slider(value: Binding(
                                get: { Double(photoCacheCountLimit) },
                                set: { photoCacheCountLimit = Int($0) }
                            ), in: 1...20, step: 1)
                        }
                    }
                }
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Show times in local time zone")
                        .foregroundColor(.primary)

                    Picker("Show times in local time zone", selection: $timelineLocalTimeMode) {
                        ForEach(TimelineLocalTimeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity Summary")
                        .foregroundColor(.primary)

                    Picker("Activity Summary", selection: $activitySummaryVisibility) {
                        ForEach(ActivitySummaryVisibility.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if activitySummaryVisibility != ActivitySummaryVisibility.dontShow.rawValue {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Distance Threshold (meters)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(activitySummaryDistanceThreshold)")
                            }
                            Slider(value: Binding(
                                get: { Double(activitySummaryDistanceThreshold) },
                                set: { activitySummaryDistanceThreshold = Int($0) }
                            ), in: 0...5000, step: 50)
                            
                            Text("Activities below this distance will not be included in the summary.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 8)
            }

        }
        .navigationTitle("Timeline")
        .onChange(of: timelineLocalTimeMode) { _, newValue in
            SettingsManager.shared.timelineLocalTimeMode = TimelineLocalTimeMode(rawValue: newValue) ?? .never
        }
        .onChange(of: timelinePictureDisplayMode) { _, newValue in
            LogManager.shared.logData(
                context: TimelinePhotoLog.context,
                content: "Settings changed timeline picture display mode to \(newValue)",
                verbosity: 4
            )
            if newValue != TimelinePictureDisplayMode.none.rawValue {
                requestPhotoLibraryAccessIfNeeded()
            }
        }
    }

    private func requestPhotoLibraryAccessIfNeeded() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        LogManager.shared.logData(
            context: TimelinePhotoLog.context,
            content: "Settings photo permission check. Current status: \(status.timelineLogDescription)",
            verbosity: 4
        )

        guard status == .notDetermined else {
            return
        }

        LogManager.shared.logData(
            context: TimelinePhotoLog.context,
            content: "Settings requesting photo library authorization.",
            verbosity: 4
        )
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            LogManager.shared.logData(
                context: TimelinePhotoLog.context,
                content: "Settings photo library authorization response: \(status.timelineLogDescription)",
                verbosity: 4
            )
        }
    }
}

struct SettingsNotificationsView: View {
    @AppStorage("sendNotificationOnUnknownPlace") private var sendNotificationOnUnknownPlace: Bool = true
    @AppStorage("unknownPlaceNotificationValue") private var unknownPlaceNotificationValue: Int = SettingsManager.shared.unknownPlaceNotificationValue
    @AppStorage("unknownPlaceNotificationUnit") private var unknownPlaceNotificationUnit: String = SettingsManager.shared.unknownPlaceNotificationUnit
    @AppStorage("enableDeadMansSwitch") private var enableDeadMansSwitch: Bool = SettingsManager.shared.enableDeadMansSwitch
    @FocusState private var valueFieldIsFocused: Bool

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Send notification to check in unknown places", isOn: $sendNotificationOnUnknownPlace)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if sendNotificationOnUnknownPlace {
                            HStack(spacing: 4) {
                                Text("After")
                                TextField("Value", value: $unknownPlaceNotificationValue, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .frame(maxWidth: 80)
                                    .focused($valueFieldIsFocused)
                                
                                Picker("", selection: $unknownPlaceNotificationUnit) {
                                    ForEach(timeUnits, id: \.self) { unit in
                                        Text(unit).tag(unit)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .fixedSize(horizontal: true, vertical: false)
                                .labelsHidden()
                                
                                Spacer()
                            }
                        }
                        
                        Text("A notification will be sent when you are in an unknown place for longer than this duration.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Notify if the app seems to have stopped", isOn: $enableDeadMansSwitch)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Sends a local notification if background execution stops unexpectedly.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Notifications")
        .toolbar { 
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    valueFieldIsFocused = false
                }
            }
        }
    }

}

struct SettingsBackupsView: View {
    @AppStorage("iCloudBackupEnabled") private var iCloudBackupEnabled: Bool = SettingsManager.shared.iCloudBackupEnabled
    @AppStorage("iCloudBackupMode") private var iCloudBackupMode: String = SettingsManager.shared.iCloudBackupMode
    @AppStorage("iCloudBackupIntervalValue") private var iCloudBackupIntervalValue: Int = SettingsManager.shared.iCloudBackupIntervalValue
    @AppStorage("iCloudBackupIntervalUnit") private var iCloudBackupIntervalUnit: String = SettingsManager.shared.iCloudBackupIntervalUnit
    @AppStorage("localBackupSaveCopyOnEdits") private var localBackupSaveCopyOnEdits: Bool = SettingsManager.shared.localBackupSaveCopyOnEdits
    @AppStorage("localBackupRetentionDays") private var localBackupRetentionDays: Int = SettingsManager.shared.localBackupRetentionDays
    @AppStorage("localBackupRetentionVersions") private var localBackupRetentionVersions: Int = SettingsManager.shared.localBackupRetentionVersions
    @AppStorage("localBackupAlwaysRetainOriginal") private var localBackupAlwaysRetainOriginal: Bool = SettingsManager.shared.localBackupAlwaysRetainOriginal
    
    @ObservedObject private var backupManager = iCloudBackupManager.shared
    @FocusState private var valueFieldIsFocused: Bool

    private var formattedLastBackupDate: String {
        if let date = SettingsManager.shared.lastICloudBackupDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        } else {
            return "never"
        }
    }

    var body: some View {
        Form {
            Section(header: Text("iCloud Backup")) {
                Toggle("Enable iCloud Backup", isOn: $iCloudBackupEnabled)
                    .fixedSize(horizontal: false, vertical: true)
                
                if iCloudBackupEnabled {
                    Picker("Backup Frequency", selection: $iCloudBackupMode) {
                        Text("Daily").tag("daily")
                        Text("Interval").tag("interval")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if iCloudBackupMode == "daily" {
                        DatePicker("Backup Time", selection: Binding(
                            get: { SettingsManager.shared.iCloudBackupDailyTime },
                            set: { SettingsManager.shared.iCloudBackupDailyTime = $0 }
                        ), displayedComponents: .hourAndMinute)
                    } else {
                        VStack(alignment: .leading) {
                            Text("Backup Interval")
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 4) {
                                TextField("Value", value: $iCloudBackupIntervalValue, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .frame(maxWidth: 80)
                                    .focused($valueFieldIsFocused)
                                
                                Picker("", selection: $iCloudBackupIntervalUnit) {
                                    ForEach(timeUnits, id: \.self) { unit in
                                        Text(unit).tag(unit)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .fixedSize(horizontal: true, vertical: false)
                                .labelsHidden()
                                
                                Spacer()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Run Backup Now") {
                            Task {
                                await backupManager.runBackup()
                            }
                        }
                        .disabled(backupManager.isBackupRunning)
                        
                        Text("Last backup: \(formattedLastBackupDate)")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                    
                    if backupManager.isBackupRunning || !backupManager.backupStatusMessage.isEmpty {
                        Text(backupManager.backupStatusMessage)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(backupManager.isBackupRunning ? .blue : .gray)
                    }
                }
                
                let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "UnknownDevice"
                Text("Backups are saved to iCloud Drive/Life2Gpx/\(deviceID)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.gray)
            }
            
            Section(header: Text("Local Backup")) {
                Toggle("Save copy on edits", isOn: $localBackupSaveCopyOnEdits)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Automatically create a copy of gpx and places files in the backups folder before any edit is applied")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.gray)

                if localBackupSaveCopyOnEdits {

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Retention Days")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(localBackupRetentionDays == -1 ? "Infinite" : "\(localBackupRetentionDays)")
                    }
                    Slider(value: Binding(
                        get: { indexForDays(localBackupRetentionDays) },
                        set: { localBackupRetentionDays = daysSteps[Int($0)] }
                    ), in: 0...Double(daysSteps.count - 1), step: 1)
                    
                    Text("Max days backup files are retained.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Retention Versions")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(localBackupRetentionVersions == -1 ? "Infinite" : "\(localBackupRetentionVersions)")
                    }
                    Slider(value: Binding(
                        get: { indexForVersions(localBackupRetentionVersions) },
                        set: { localBackupRetentionVersions = versionsSteps[Int($0)] }
                    ), in: 0...Double(versionsSteps.count - 1), step: 1)
                    
                    Text("How many versions of the same file are kept.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 4)

                Toggle("Always retain original file", isOn: $localBackupAlwaysRetainOriginal)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The first version of a file is always kept no matter the retention options.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.gray)
            
                }
            }
        }
        .navigationTitle("Backups")
        .toolbar { 
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    valueFieldIsFocused = false
                }
            }
        }
    }

}

struct SettingsLocationTrackingView: View {
    @AppStorage("minimumUpdateInterval") private var minimumUpdateInterval: Int = SettingsManager.shared.minimumUpdateInterval
    @AppStorage("stationaryDetectionTimer") private var stationaryDetectionTimer: Int = SettingsManager.shared.stationaryDetectionTimer
    @AppStorage("stationaryStepsUpdateInterval") private var stationaryStepsUpdateInterval: Int = SettingsManager.shared.stationaryStepsUpdateInterval
    @AppStorage("stationaryLocationAccuracy") private var stationaryLocationAccuracy: Int = SettingsManager.shared.stationaryLocationAccuracy
    @AppStorage("movingLocationAccuracy") private var movingLocationAccuracy: Int = SettingsManager.shared.movingLocationAccuracy
    @AppStorage("useLastStationaryAsFirstTrackPoint") private var useLastStationaryAsFirstTrackPoint: Bool = SettingsManager.shared.useLastStationaryAsFirstTrackPoint
    @AppStorage("lastStationaryTimeThreshold") private var lastStationaryTimeThreshold: Int = SettingsManager.shared.lastStationaryTimeThreshold
    @AppStorage("lastStationaryDistanceThreshold") private var lastStationaryDistanceThreshold: Int = SettingsManager.shared.lastStationaryDistanceThreshold

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Minimum Update Interval (seconds)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(minimumUpdateInterval)")
                        }
                        Slider(value: Binding(
                            get: { Double(minimumUpdateInterval) },
                            set: { minimumUpdateInterval = Int($0) }
                        ), in: 10...120, step: 5)
                        
                        if minimumUpdateInterval < 30 {
                            Text("Low values will create big GPX files on long tracks at high battery cost")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.red)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Stationary Detection Timer (seconds)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(stationaryDetectionTimer)")
                        }
                        Slider(value: Binding(
                            get: { Double(stationaryDetectionTimer) },
                            set: { stationaryDetectionTimer = Int($0) }
                        ), in: 30...300, step: 10)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Stationary Steps Update (minutes)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(stationaryStepsUpdateInterval == 0 ? "Disabled" : "\(stationaryStepsUpdateInterval)")
                        }
                        Slider(value: Binding(
                            get: { Double(stationaryStepsUpdateInterval) },
                            set: { stationaryStepsUpdateInterval = Int($0) }
                        ), in: 0...60, step: 1)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Stationary Location Accuracy")
                                .foregroundColor(.primary)
                            Spacer()
                            let level = LocationAccuracyLevel(rawValue: stationaryLocationAccuracy) ?? .medium
                            Text(level.displayName)
                                .foregroundColor(stationaryLocationAccuracy == LocationAccuracyLevel.medium.rawValue ? Color.green.opacity(0.8) : .primary)
                        }
                        Slider(value: Binding(
                            get: { Double(stationaryLocationAccuracy) },
                            set: { stationaryLocationAccuracy = Int($0) }
                        ), in: 0...5, step: 1)
                        if stationaryLocationAccuracy > LocationAccuracyLevel.medium.rawValue {
                            Text("Higher than default settings will significantly increase battery consumption.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.red)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Moving Location Accuracy")
                                .foregroundColor(.primary)
                            Spacer()
                            let level = LocationAccuracyLevel(rawValue: movingLocationAccuracy) ?? .best
                            Text(level.displayName)
                                .foregroundColor(movingLocationAccuracy == LocationAccuracyLevel.best.rawValue ? Color.green.opacity(0.8) : .primary)
                        }
                        Slider(value: Binding(
                            get: { Double(movingLocationAccuracy) },
                            set: { movingLocationAccuracy = Int($0) }
                        ), in: 0...5, step: 1)
                        if movingLocationAccuracy > LocationAccuracyLevel.best.rawValue {
                            Text("Higher than default settings will significantly increase battery consumption.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use last stationary position as the first point of the next track", isOn: $useLastStationaryAsFirstTrackPoint)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("To help properly recording the duration of movement with bad GPS like subways or planes")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                        
                        if useLastStationaryAsFirstTrackPoint {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Minimum time difference from last known position")
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(formattedStationaryTime(lastStationaryTimeThreshold))
                                }
                                Slider(value: Binding(
                                    get: { indexForStationaryTime(lastStationaryTimeThreshold) },
                                    set: { lastStationaryTimeThreshold = stationaryTimeSteps[Int($0)] }
                                ), in: 0...Double(stationaryTimeSteps.count - 1), step: 1)
                            }
                            .padding(.top, 8)
                            
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Minimum distance from last known position")
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(formattedStationaryDistance(lastStationaryDistanceThreshold))
                                }
                                Slider(value: Binding(
                                    get: { indexForStationaryDistance(lastStationaryDistanceThreshold) },
                                    set: { lastStationaryDistanceThreshold = stationaryDistanceSteps[Int($0)] }
                                ), in: 0...Double(stationaryDistanceSteps.count - 1), step: 1)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Location Tracking")
    }
}

struct SettingsPlaceSearchView: View {
    @AppStorage("findClosePlacesLimit") private var findClosePlacesLimit: Int = SettingsManager.shared.findClosePlacesLimit
    @AppStorage("placeSearchDefaultRadius") private var placeSearchDefaultRadius: Int = SettingsManager.shared.placeSearchDefaultRadius
    @AppStorage("placeSearchKeywordRadius") private var placeSearchKeywordRadius: Int = SettingsManager.shared.placeSearchKeywordRadius
    @AppStorage("placeSearchPageLimit") private var placeSearchPageLimit: Int = SettingsManager.shared.placeSearchPageLimit
    @AppStorage("suggestApplyToOtherPlaces") private var suggestApplyToOtherPlaces: Bool = SettingsManager.shared.suggestApplyToOtherPlaces
    @AppStorage("overwriteExistingAddressOnNewPlaceCreation") private var overwriteExistingAddressOnNewPlaceCreation: Bool = SettingsManager.shared.overwriteExistingAddressOnNewPlaceCreation

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Find close places limit")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(findClosePlacesLimit)")
                        }
                        Slider(value: Binding(
                            get: { Double(findClosePlacesLimit) },
                            set: { findClosePlacesLimit = Int($0) }
                        ), in: 1...50, step: 1)
                        Text("Maximum number of nearby places to show when matching an unknown location.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Suggest apply to other places", isOn: $suggestApplyToOtherPlaces)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("When assigning a place, suggest to apply the same place to other matching unknown places in the current file.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Overwrite existing address on new place creation", isOn: $overwriteExistingAddressOnNewPlaceCreation)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("If an unknown place visit has an address, adding a place id from a provider will also override the existing address if the provider gives one.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Default Search Radius (meters)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(placeSearchDefaultRadius)")
                        }
                        Slider(value: Binding(
                            get: { Double(placeSearchDefaultRadius) },
                            set: { placeSearchDefaultRadius = Int($0) }
                        ), in: 10...5000, step: 10)
                        
                        Text("Radius used when searching for nearby places without a keyword.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Keyword Search Radius (meters)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(placeSearchKeywordRadius)")
                        }
                        Slider(value: Binding(
                            get: { Double(placeSearchKeywordRadius) },
                            set: { placeSearchKeywordRadius = Int($0) }
                        ), in: 100...20000, step: 100)
                        
                        Text("Radius used when searching for places with a specific keyword.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Search Page Limit")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(placeSearchPageLimit)")
                        }
                        Slider(value: Binding(
                            get: { Double(placeSearchPageLimit) },
                            set: { placeSearchPageLimit = Int($0) }
                        ), in: 5...100, step: 5)
                        
                        Text("Number of results to load per page.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Place Search and Edit")
    }
}

struct SettingsAutomaticCleanupsView: View {
    @AppStorage("automaticallyMergeUnknownToKnownTypeTracks") private var automaticallyMergeUnknownToKnownTypeTracks: Bool = SettingsManager.shared.automaticallyMergeUnknownToKnownTypeTracks
    @AppStorage("automaticMergeUnknownTrackMaxPoints") private var automaticMergeUnknownTrackMaxPoints: Int = SettingsManager.shared.automaticMergeUnknownTrackMaxPoints
    @AppStorage("automaticMergeKnownTrackMinimumPoints") private var automaticMergeKnownTrackMinimumPoints: Int = SettingsManager.shared.automaticMergeKnownTrackMinimumPoints
    @AppStorage("filterSmallRoundTrips") private var filterSmallRoundTrips: Bool = SettingsManager.shared.filterSmallRoundTrips
    @AppStorage("roundTripMaxPoints") private var roundTripMaxPoints: Int = SettingsManager.shared.roundTripMaxPoints
    @AppStorage("roundTripUnknownRadius") private var roundTripUnknownRadius: Int = SettingsManager.shared.roundTripUnknownRadius

    var body: some View {
        Form {
            Section(header: Text("Automatic Track Merging")) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Automatically merge unknown to known type tracks", isOn: $automaticallyMergeUnknownToKnownTypeTracks)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("When a known track becomes reliable, merge a small adjacent unknown track into it.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.gray)

                    if automaticallyMergeUnknownToKnownTypeTracks {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Maximum unknown track points")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(automaticMergeUnknownTrackMaxPoints)")
                            }
                            Slider(value: Binding(
                                get: { Double(automaticMergeUnknownTrackMaxPoints) },
                                set: { automaticMergeUnknownTrackMaxPoints = Int($0) }
                            ), in: 1...10, step: 1)

                            Text("Unknown tracks with up to this many points can be merged.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Known track minimum points")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(automaticMergeKnownTrackMinimumPoints)")
                            }
                            Slider(value: Binding(
                                get: { Double(automaticMergeKnownTrackMinimumPoints) },
                                set: { automaticMergeKnownTrackMinimumPoints = Int($0) }
                            ), in: 1...10, step: 1)

                            Text("Wait until the recognized track reaches this many points before merging.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical)
            }
            
            Section(header: Text("Filter Small Round Trip Tracks")) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Filter small round trip tracks", isOn: $filterSmallRoundTrips)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Do not save small tracks that end up in the same place as the starting point (often caused by GPS location errors).")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.gray)
                    
                    if filterSmallRoundTrips {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Max points in filtered track")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(roundTripMaxPoints)")
                            }
                            Slider(value: Binding(
                                get: { Double(roundTripMaxPoints) },
                                set: { roundTripMaxPoints = Int($0) }
                            ), in: 1...10, step: 1)
                            
                            Text("Round trip tracks above this number of points will be saved.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Unknown location round trip radius (meters)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(roundTripUnknownRadius)")
                            }
                            Slider(value: Binding(
                                get: { Double(roundTripUnknownRadius) },
                                set: { roundTripUnknownRadius = Int($0) }
                            ), in: 10...1000, step: 10)
                            
                            Text("Radius from a starting unknown location to consider track as a round trip.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Automatic Cleanups")
    }
}

struct SettingsLoggingView: View {
    @AppStorage("debugLogVerbosity") private var debugLogVerbosity: Int = SettingsManager.shared.debugLogVerbosity
    @AppStorage("logRetentionDays") private var logRetentionDays: Int = SettingsManager.shared.logRetentionDays
    @AppStorage("logSizeLimitMB") private var logSizeLimitMB: Int = SettingsManager.shared.logSizeLimitMB
    @AppStorage("trackResourceUsage") private var trackResourceUsage: Bool = SettingsManager.shared.trackResourceUsage
    @AppStorage("logAllReceivedPositions") private var logAllReceivedPositions: Bool = SettingsManager.shared.logAllReceivedPositions

    @State private var diagnosticReportShareItem: DiagnosticReportShareItem?
    @State private var diagnosticReportError: String?
    @State private var showDiagnosticReportError = false

    var body: some View {
        Form {
            Section(header: Text("Logging")) {
                Text("Adjust the level of detail for application logs.")
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verbosity Level:")
                        Spacer()
                        Text("\(debugLogVerbosity)")
                    }
                    Slider(value: Binding(
                        get: { Double(debugLogVerbosity) },
                        set: { debugLogVerbosity = Int($0) }
                    ), in: 0...5, step: 1)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("0: None - No logs").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("1: Errors - Only critical errors").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("2: Warnings - Errors and warnings").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("3: Info - Basic operational information").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("4: Debug - Detailed debugging information").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("5: Trace - Highly detailed tracing").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Retention Days")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(logRetentionDays == -1 ? "Infinite" : "\(logRetentionDays)")
                        }
                        Slider(value: Binding(
                            get: { indexForDays(logRetentionDays) },
                            set: { logRetentionDays = daysSteps[Int($0)] }
                        ), in: 0...Double(daysSteps.count - 1), step: 1)
                        
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Size (MB)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(logSizeLimitMB == -1 ? "Infinite" : "\(logSizeLimitMB)")
                        }
                        Slider(value: Binding(
                            get: { indexForSizeMB(logSizeLimitMB) },
                            set: { logSizeLimitMB = sizeStepsMB[Int($0)] }
                        ), in: 0...Double(sizeStepsMB.count - 1), step: 1)
                        
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Track resource usage", isOn: $trackResourceUsage)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Record detailed battery, memory, and CPU usage during background activities over time.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                        
                        
                        NavigationLink(destination: ResourceUsageView()) {
                            Text("View Resource Usage")
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Log all received positions to file", isOn: $logAllReceivedPositions)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Appends all raw data from location manager to files in Logs/Location folder.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 10)
                }
                .padding(.vertical)

                Button(action: resourceLogDump) {
                    Label("Resource log dump", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("Logging")
        .sheet(item: $diagnosticReportShareItem) { item in
            TimelinePhotoActivityView(items: [item.url])
        }
        .alert("Could not create resource log dump", isPresented: $showDiagnosticReportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(diagnosticReportError ?? "Unknown error")
        }
    }

    private func resourceLogDump() {
        ResourceDiagnostics.logRuntime(
            context: "Diagnostics",
            detail: "Manual resource log dump started from Settings."
        )

        do {
            let reportURL = try ResourceLogDumpBuilder.writeReport()
            diagnosticReportShareItem = DiagnosticReportShareItem(url: reportURL)
        } catch {
            diagnosticReportError = error.localizedDescription
            showDiagnosticReportError = true
            LogManager.shared.logData(
                context: "Diagnostics",
                content: "Failed to write resource log report: \(error.localizedDescription)",
                verbosity: 1
            )
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
