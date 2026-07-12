import SwiftUI
import Photos

private struct DiagnosticReportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    @AppStorage("debugLogVerbosity") private var debugLogVerbosity: Int = SettingsManager.shared.debugLogVerbosity
    @AppStorage("loadCurrentDayOnRestoreAfterValue") private var loadCurrentDayOnRestoreAfterValue: Int = SettingsManager.shared.loadCurrentDayOnRestoreAfterValue
    @AppStorage("loadCurrentDayOnRestoreAfterUnit") private var loadCurrentDayOnRestoreAfterUnit: String = SettingsManager.shared.loadCurrentDayOnRestoreAfterUnit
    @AppStorage("defaultNewPlaceRadius") private var defaultNewPlaceRadius: Int = SettingsManager.shared.defaultNewPlaceRadius
    @AppStorage("filterSmallRoundTrips") private var filterSmallRoundTrips: Bool = SettingsManager.shared.filterSmallRoundTrips
    @AppStorage("roundTripMaxPoints") private var roundTripMaxPoints: Int = SettingsManager.shared.roundTripMaxPoints
    @AppStorage("roundTripUnknownRadius") private var roundTripUnknownRadius: Int = SettingsManager.shared.roundTripUnknownRadius
    @AppStorage("timelinePictureDisplayMode") private var timelinePictureDisplayMode: String = SettingsManager.shared.timelinePictureDisplayMode.rawValue
    @AppStorage("mapCoordinateSystemMode") private var mapCoordinateSystemMode: String = SettingsManager.shared.mapCoordinateSystemMode.rawValue
    @AppStorage("showCurrentPositionMode") private var showCurrentPositionMode: String = SettingsManager.shared.showCurrentPositionMode.rawValue
    @AppStorage("suggestApplyToOtherPlaces") private var suggestApplyToOtherPlaces: Bool = SettingsManager.shared.suggestApplyToOtherPlaces
    @AppStorage("mergeVisitAddSteps") private var mergeVisitAddSteps: Bool = SettingsManager.shared.mergeVisitAddSteps
    @AppStorage("sendNotificationOnUnknownPlace") private var sendNotificationOnUnknownPlace: Bool = true
    @AppStorage("unknownPlaceNotificationMinutes") private var unknownPlaceNotificationMinutes: Int = 10
    @AppStorage("trackResourceUsage") private var trackResourceUsage: Bool = SettingsManager.shared.trackResourceUsage
    @AppStorage("minimumUpdateInterval") private var minimumUpdateInterval: Int = SettingsManager.shared.minimumUpdateInterval
    @AppStorage("stationaryDetectionTimer") private var stationaryDetectionTimer: Int = SettingsManager.shared.stationaryDetectionTimer
    @AppStorage("findClosePlacesLimit") private var findClosePlacesLimit: Int = SettingsManager.shared.findClosePlacesLimit
    @AppStorage("placeSearchDefaultRadius") private var placeSearchDefaultRadius: Int = SettingsManager.shared.placeSearchDefaultRadius
    @AppStorage("placeSearchKeywordRadius") private var placeSearchKeywordRadius: Int = SettingsManager.shared.placeSearchKeywordRadius
    @AppStorage("placeSearchAppleDefaultRadius") private var placeSearchAppleDefaultRadius: Int = SettingsManager.shared.placeSearchAppleDefaultRadius
    @AppStorage("placeSearchAppleKeywordRadius") private var placeSearchAppleKeywordRadius: Int = SettingsManager.shared.placeSearchAppleKeywordRadius
    @AppStorage("placeSearchPageLimit") private var placeSearchPageLimit: Int = SettingsManager.shared.placeSearchPageLimit
    @AppStorage("photoCacheMemoryMB") private var photoCacheMemoryMB: Int = SettingsManager.shared.photoCacheMemoryMB
    @AppStorage("photoCacheCountLimit") private var photoCacheCountLimit: Int = SettingsManager.shared.photoCacheCountLimit
    @AppStorage("disableTracking") private var disableTracking: Bool = SettingsManager.shared.disableTracking
    @AppStorage("iCloudBackupEnabled") private var iCloudBackupEnabled: Bool = SettingsManager.shared.iCloudBackupEnabled
    @AppStorage("iCloudBackupMode") private var iCloudBackupMode: String = SettingsManager.shared.iCloudBackupMode
    @State private var iCloudBackupDailyTime: Date = SettingsManager.shared.iCloudBackupDailyTime
    @AppStorage("iCloudBackupIntervalValue") private var iCloudBackupIntervalValue: Int = SettingsManager.shared.iCloudBackupIntervalValue
    @AppStorage("iCloudBackupIntervalUnit") private var iCloudBackupIntervalUnit: String = SettingsManager.shared.iCloudBackupIntervalUnit
    
    @ObservedObject private var backupManager = iCloudBackupManager.shared

    @FocusState private var valueFieldIsFocused: Bool
    @State private var diagnosticReportShareItem: DiagnosticReportShareItem?
    @State private var diagnosticReportError: String?
    @State private var showDiagnosticReportError = false

    private let timeUnits = ["seconds", "minutes", "hours", "days"]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Disable tracking", isOn: $disableTracking)
                        .tint(.red)
                    
                    Text("Disable all realtime tracking from the app")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .listRowBackground(disableTracking ? Color.red.opacity(0.1) : nil)
            
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
                        Text("1: Errors - Only critical errors").font(.caption)
                        Text("2: Warnings - Errors and warnings").font(.caption)
                        Text("3: Info - Basic operational information").font(.caption)
                        Text("4: Debug - Detailed debugging information").font(.caption)
                        Text("5: Trace - Highly detailed tracing").font(.caption)
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 5)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Track resource usage", isOn: $trackResourceUsage)
                        
                        Text("Record detailed battery, memory, and CPU usage during background activities over time.")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        NavigationLink(destination: ResourceUsageView()) {
                            Text("View Resource Usage")
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 10)
                }
                .padding(.vertical)

                Button(action: resourceLogDump) {
                    Label("Resource log dump", systemImage: "doc.text.magnifyingglass")
                }
            }
            
            Section(header: Text("iCloud Backup")) {
                Toggle("Enable iCloud Backup", isOn: $iCloudBackupEnabled)
                
                if iCloudBackupEnabled {
                    Picker("Backup Frequency", selection: $iCloudBackupMode) {
                        Text("Daily").tag("daily")
                        Text("Interval").tag("interval")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if iCloudBackupMode == "daily" {
                        DatePicker("Backup Time", selection: $iCloudBackupDailyTime, displayedComponents: .hourAndMinute)
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
                    
                    Button("Run Backup Now") {
                        Task {
                            await backupManager.runBackup()
                        }
                    }
                    .disabled(backupManager.isBackupRunning)
                    
                    if backupManager.isBackupRunning || !backupManager.backupStatusMessage.isEmpty {
                        Text(backupManager.backupStatusMessage)
                            .font(.caption)
                            .foregroundColor(backupManager.isBackupRunning ? .blue : .gray)
                    }
                }
                
                let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "UnknownDevice"
                Text("Backups are saved to iCloud Drive/Life2Gpx/\(deviceID)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Section(header: Text("Location Tracking")) {
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
                }
                .padding(.vertical)
            }
            
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
                                .focused($valueFieldIsFocused) // Apply focus state
                            
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
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Default new place radius (meters)")
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("\(defaultNewPlaceRadius)")
                            Spacer()
                        }
                        Slider(value: Binding(
                            get: { Double(defaultNewPlaceRadius) },
                            set: { defaultNewPlaceRadius = Int($0) }
                        ), in: 10...1000, step: 10)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Find close places limit")
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("\(findClosePlacesLimit)")
                            Spacer()
                        }
                        Slider(value: Binding(
                            get: { Double(findClosePlacesLimit) },
                            set: { findClosePlacesLimit = Int($0) }
                        ), in: 1...50, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Show pictures in timeline")
                            .foregroundColor(.primary)

                        Picker("Show pictures in timeline", selection: $timelinePictureDisplayMode) {
                            ForEach(TimelinePictureDisplayMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

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

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Suggest apply to other places", isOn: $suggestApplyToOtherPlaces)
                        
                        Text("When assigning a place, suggest to apply the same place to other matching unknown places in the current file.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Add up steps when merging to visit", isOn: $mergeVisitAddSteps)
                        
                        Text("When merging items into a visit, add up all the steps from the merged items and assign them to the resulting visit.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Send notification to check in unknown places", isOn: $sendNotificationOnUnknownPlace)
                        
                        if sendNotificationOnUnknownPlace {
                            HStack(spacing: 4) {
                                Text("After")
                                TextField("Minutes", value: $unknownPlaceNotificationMinutes, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .frame(maxWidth: 80)
                                    .focused($valueFieldIsFocused)
                                Text("minutes")
                                Spacer()
                            }
                        }
                        
                        Text("A notification will be sent when you are in an unknown place for longer than this duration.")
                            .font(.caption)
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
                    .foregroundColor(.gray)
            }
            
            Section(header: Text("Place Search")) {
                VStack(alignment: .leading, spacing: 16) {
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
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Apple Maps Default Radius (meters)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(placeSearchAppleDefaultRadius)")
                        }
                        Slider(value: Binding(
                            get: { Double(placeSearchAppleDefaultRadius) },
                            set: { placeSearchAppleDefaultRadius = Int($0) }
                        ), in: 100...5000, step: 100)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Apple Maps Keyword Radius (meters)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(placeSearchAppleKeywordRadius)")
                        }
                        Slider(value: Binding(
                            get: { Double(placeSearchAppleKeywordRadius) },
                            set: { placeSearchAppleKeywordRadius = Int($0) }
                        ), in: 1000...50000, step: 1000)
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
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical)
            }
            
            Section(header: Text("Filter Small Round Trip Tracks")) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Filter small round trip tracks", isOn: $filterSmallRoundTrips)
                    
                    Text("Do not save small tracks that end up in the same place as the starting point (often caused by GPS location errors).")
                        .font(.caption)
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
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Settings")
        .toolbar { 
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    valueFieldIsFocused = false
                }
            }
        }
        .onChange(of: iCloudBackupDailyTime) { _, newValue in
            SettingsManager.shared.iCloudBackupDailyTime = newValue
        }
        .onChange(of: timelinePictureDisplayMode) { _, newValue in
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Settings changed timeline picture display mode to \(newValue)",
                verbosity: 4
            )
            if newValue != TimelinePictureDisplayMode.none.rawValue {
                requestPhotoLibraryAccessIfNeeded()
            }
        }
        .sheet(item: $diagnosticReportShareItem) { item in
            TimelinePhotoActivityView(items: [item.url])
        }
        .alert("Could not create resource log dump", isPresented: $showDiagnosticReportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(diagnosticReportError ?? "Unknown error")
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

    private func requestPhotoLibraryAccessIfNeeded() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Settings photo permission check. Current status: \(status.timelineLogDescription)",
            verbosity: 4
        )

        guard status == .notDetermined else {
            return
        }

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Settings requesting photo library authorization.",
            verbosity: 4
        )
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Settings photo library authorization response: \(status.timelineLogDescription)",
                verbosity: 4
            )
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
            FileManagerUtil.logData(
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
