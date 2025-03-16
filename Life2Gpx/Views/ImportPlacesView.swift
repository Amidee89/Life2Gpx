import SwiftUI

struct ImportPlacesView: View {
    @State private var arcBackupCount: Int = 0
    @State private var life2GpxFileCount: (files: Int, places: Int) = (0, 0)
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var ignoreDuplicates = false
    @State private var addIdToExisting = true
    @State private var radiusHandling = RadiusHandlingOption.smaller
    @State private var overwriteExistingMetadata = false
    @State private var isImporting = false
    @State private var duplicateDistanceThreshold: Double = 20
    
    enum RadiusHandlingOption: String, CaseIterable {
        case smaller = "Keep Smaller"
        case bigger = "Keep Bigger"
        case original = "Keep Original"
        case imported = "Keep Imported"
    }
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Scanning for import files...")
                        Spacer()
                    }
                }
            } else {
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                if arcBackupCount == 0 && life2GpxFileCount.files == 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No import files found")
                                .foregroundStyle(.secondary)
                            Text("To start importing places, place Life2Gpx places.json files in the Import folder or the Place folder of an Arc backup in Import/Arc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                if arcBackupCount > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(arcBackupCount) place files found")
                                .foregroundStyle(.secondary)
                        }
                        
                        NavigationLink {
                            ImportProgressView(importType: .arcBackup,
                                            importOptions: createImportOptions())
                        } label: {
                            Text("Import Arc Backups")
                        }
                    } header: {
                        Text("Arc Backups")
                    }
                }
                
                if life2GpxFileCount.files > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(life2GpxFileCount.files) files found")
                                .foregroundStyle(.secondary)
                            Text("\(life2GpxFileCount.places) places total")
                                .foregroundStyle(.secondary)
                        }
                        
                        NavigationLink {
                            ImportProgressView(importType: .life2Gpx,
                                            importOptions: createImportOptions())
                        } label: {
                            Text("Import Life2Gpx Files")
                        }
                    } header: {
                        Text("Life2Gpx Files")
                    }
                }
                
                Section {
                    Toggle("Ignore Duplicates", isOn: $ignoreDuplicates)
                    
                    if !ignoreDuplicates {
                        Toggle("Add ID to Existing Places", isOn: $addIdToExisting)
                        
                        Picker("Radius Handling", selection: $radiusHandling) {
                            ForEach(RadiusHandlingOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        
                        Toggle("Overwrite Existing Metadata", isOn: $overwriteExistingMetadata)
                        
                        HStack {
                            Text("Duplicate Distance")
                            Spacer()
                            TextField("meters", value: $duplicateDistanceThreshold, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("meters")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Import Options")
                } footer: {
                    Text("Duplicates are places that either have the same ID or the same name within \(Int(duplicateDistanceThreshold)) meters")
                }
            }
        }
        .navigationTitle("Import Places")
        .task {
            await scanForImportFiles()
        }
    }
    
    private func scanForImportFiles() async {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                // Mock data for previews
                arcBackupCount = 3
                life2GpxFileCount = (files: 2, places: 156)
                isLoading = false
                return
            }
            #endif
            
            arcBackupCount = try await checkForArcPlaceBackups()
            life2GpxFileCount = try await checkForLife2GpxJson()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func checkForArcPlaceBackups() async throws -> Int {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let arcFolderUrl = documentsUrl.appendingPathComponent("Import/Arc/Place")
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: arcFolderUrl.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return 0
        }
        
        let enumerator = fileManager.enumerator(at: arcFolderUrl,
                                               includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles])
        
        var count = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if fileAttributes.isRegularFile == true && fileURL.pathExtension == "json" {
                count += 1
            }
        }
        
        return count
    }
    
    private func checkForLife2GpxJson() async throws -> (files: Int, places: Int) {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importFolderUrl = documentsUrl.appendingPathComponent("Import")
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: importFolderUrl.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (0, 0)
        }
        
        let fileUrls = try fileManager.contentsOfDirectory(at: importFolderUrl,
                                                         includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles])
        
        let jsonFiles = fileUrls.filter { $0.pathExtension == "json" }
        var totalPlaces = 0
        
        for fileUrl in jsonFiles {
            if let data = try? Data(contentsOf: fileUrl) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let places = try? decoder.decode([Place].self, from: data) {
                    totalPlaces += places.count
                }
            }
        }
        
        return (jsonFiles.count, totalPlaces)
    }
    
    private func createImportOptions() -> ImportOptions {
        ImportOptions(
            ignoreDuplicates: ignoreDuplicates,
            addIdToExisting: addIdToExisting,
            radiusHandling: radiusHandling,
            overwriteExistingMetadata: overwriteExistingMetadata,
            duplicateDistanceThreshold: duplicateDistanceThreshold
        )
    }
}

#Preview("Empty") {
    NavigationView {
        ImportPlacesView()
    }
}

#Preview("With Files") {
    NavigationView {
        ImportPlacesView(arcBackupCount: 3,
                        life2GpxFileCount: (files: 2, places: 15),
                        isLoading: false)
    }
}

#Preview("Loading") {
    NavigationView {
        ImportPlacesView(arcBackupCount: 0,
                        life2GpxFileCount: (0, 0),
                        isLoading: true)
    }
}

#Preview("Error") {
    NavigationView {
        ImportPlacesView(arcBackupCount: 0,
                        life2GpxFileCount: (0, 0),
                        isLoading: false,
                        errorMessage: "Failed to scan import directory")
    }
}

extension ImportPlacesView {
    init(arcBackupCount: Int = 0,
         life2GpxFileCount: (files: Int, places: Int) = (0, 0),
         isLoading: Bool = true,
         errorMessage: String? = nil) {
        _arcBackupCount = State(initialValue: arcBackupCount)
        _life2GpxFileCount = State(initialValue: life2GpxFileCount)
        _isLoading = State(initialValue: isLoading)
        _errorMessage = State(initialValue: errorMessage)
    }
}

enum ImportType {
    case arcBackup
    case life2Gpx
}

struct ImportOptions {
    let ignoreDuplicates: Bool
    let addIdToExisting: Bool
    let radiusHandling: ImportPlacesView.RadiusHandlingOption
    let overwriteExistingMetadata: Bool
    let duplicateDistanceThreshold: Double
}

struct ImportProgressView: View {
    let importType: ImportType
    let importOptions: ImportOptions
    @State private var progress: String = "Starting import..."
    @State private var progressValue: Double = 0.0
    @State private var duplicateCount: Int = 0
    @State private var addedCount: Int = 0
    @State private var sameNameDifferentLocationCount: Int = 0
    @State private var mergedCount: Int = 0
    @State private var isComplete: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var duplicateIdCount: Int = 0
    @State private var duplicateNameLocationCount: Int = 0
    @State private var shouldCancel = false
    @State private var importErrors: [(filename: String, error: String)] = []
    @State private var timingReport: [(operation: String, duration: TimeInterval)] = []
    @State private var importStartTime: Date?
    
    var body: some View {
        List {
            if !isComplete {
                Section {
                    Text(progress)
                        .animation(.default, value: progress)
                    if duplicateCount > 0 {
                        Text("Found \(duplicateCount) duplicates")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .padding(.vertical, 8)
                        .animation(.default, value: progressValue)
                    
                    Button("Cancel", role: .destructive) {
                        shouldCancel = true
                        progress = "Canceling..."
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            } else {
                Section {
                    Text("Import Complete")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Places added: \(addedCount)")
                        
                        if duplicateCount > 0 {
                            Text(importOptions.ignoreDuplicates ? "Duplicates skipped: \(duplicateCount)" : "Duplicates managed: \(duplicateCount)")
                            Group {
                                Text("• Same ID: \(duplicateIdCount)")
                                Text("• Same name within 20m: \(duplicateNameLocationCount)")
                            }
                            .padding(.leading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        
                        if sameNameDifferentLocationCount > 0 {
                            Text("Same name, different location (>20m): \(sameNameDifferentLocationCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button("Done") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            }
            
            if !importErrors.isEmpty {
                Section("Import Errors") {
                    ForEach(importErrors, id: \.filename) { error in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error.filename)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Text(error.error)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            if !timingReport.isEmpty {
                Section("Performance Report") {
                    if let startTime = importStartTime {
                        Text("Total time: \(Date().timeIntervalSince(startTime).formatted(.number.precision(.fractionLength(1)))) seconds")
                            .font(.headline)
                    }
                    
                    ForEach(timingReport, id: \.operation) { timing in
                        HStack {
                            Text(timing.operation)
                            Spacer()
                            Text("\(timing.duration.formatted(.number.precision(.fractionLength(1))))s")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Importing Places")
        .interactiveDismissDisabled()
        .navigationBarBackButtonHidden(!isComplete)
        .task {
            await importPlaces()
        }
    }
    
    private func importPlaces() async {
        importStartTime = Date()
        let timer = PerformanceTimer()
        
        do {
            // Check for cancellation
            guard !shouldCancel else {
                await MainActor.run {
                    progress = "Import canceled"
                    isComplete = true
                }
                return
            }
            
            // First, backup the existing places file
            timer.start("Backup")
            let fileManager = FileManager.default
            let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let placesUrl = documentsUrl.appendingPathComponent("Places/places.json")
            
            if fileManager.fileExists(atPath: placesUrl.path) {
                await MainActor.run {
                    progress = "Creating backup..."
                    progressValue = 0.1
                }
                try FileManagerUtil.shared.backupFile(placesUrl)
            }
            timer.stop()
            
            if importType == .arcBackup {
                try await importArcPlaces(timer: timer)
                
                // Clean up only if not canceled
                if !shouldCancel {
                    timer.start("Cleanup")
                    await MainActor.run {
                        progress = "Cleaning up..."
                    }
                    try FileManagerUtil.shared.cleanupEmptyFolders(in: "Import/Arc/Place")
                    timer.stop()
                }
            }
            
            await MainActor.run {
                progressValue = 1.0
                isComplete = true
                timingReport = timer.report
            }
            
        } catch {
            await MainActor.run {
                progress = "Import failed: \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
    
    private func checkForDuplicates(_ place: Place) async throws -> Place? {
        let existingPlaces = PlaceManager.shared.getAllPlaces()
        
        for existingPlace in existingPlaces {
            // Check for ID match first (immediate duplicate)
            if !place.placeId.isEmpty && place.placeId == existingPlace.placeId {
                duplicateIdCount += 1
                print("Found places with same ID:")
                print("  Place 1: \(place.name) - \(place.placeId)")
                return existingPlace
            }
            
            // Check for name similarity (case-insensitive, trimmed)
            let normalizedNewName = place.name.trim().lowercased()
            let normalizedExistingName = existingPlace.name.trim().lowercased()
            
            if normalizedNewName == normalizedExistingName {
                // Check distance using the configurable threshold
                let distance = place.centerCoordinate.distance(to: existingPlace.centerCoordinate)
                if distance <= importOptions.duplicateDistanceThreshold {
                    duplicateNameLocationCount += 1
                    print("Found places with same name within \(Int(importOptions.duplicateDistanceThreshold))m:")
                    print("  Place 1: \(place.name) - \(place.placeId)")
                    print("  Place 2: \(existingPlace.name) - \(existingPlace.placeId)")
                    print("  Distance: \(Int(distance))m")
                    return existingPlace
                } else {
                    sameNameDifferentLocationCount += 1
                    print("Found places with same name '\(place.name)' but \(Int(distance))m apart:")
                    print("  Place 1: lat: \(place.center.latitude), lon: \(place.center.longitude)")
                    print("  Place 2: lat: \(existingPlace.center.latitude), lon: \(existingPlace.center.longitude)")
                }
            }
        }
        
        return nil
    }
    
    private func importArcPlaces(timer: PerformanceTimer) async throws {
        timer.start("Count Files")
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let arcFolderUrl = documentsUrl.appendingPathComponent("Import/Arc/Place")
        
        // Count total files first
        let enumerator = fileManager.enumerator(at: arcFolderUrl,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles])
        var totalFiles = 0
        while let fileUrl = enumerator?.nextObject() as? URL {
            if fileUrl.pathExtension == "json" {
                totalFiles += 1
            }
        }
        timer.stop()
        
        // Create timestamp for this import session
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var processedFiles = 0
        duplicateCount = 0
        addedCount = 0
        duplicateIdCount = 0
        duplicateNameLocationCount = 0
        sameNameDifferentLocationCount = 0
        
        // Start with 10% progress after backup
        progressValue = 0.1
        
        guard let enumerator = fileManager.enumerator(at: arcFolderUrl,
                                                    includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles]) else {
            progress = "Could not access Arc Place folder"
            throw NSError(domain: "ImportError", code: 2, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not access Arc Place folder"])
        }
        
        timer.start("Process Files")
        while let fileUrl = enumerator.nextObject() as? URL {
            // Check for cancellation at the start of each file
            guard !shouldCancel else {
                return
            }
            
            guard fileUrl.pathExtension == "json" else { continue }
            
            await MainActor.run {
                progress = "Processing file \(processedFiles + 1) of \(totalFiles)"
            }
            
            do {
                timer.start("Read File")
                let data = try Data(contentsOf: fileUrl)
                timer.stop()
                
                timer.start("Parse JSON")
                let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                
                var placeDict: [String: Any] = [:]
                placeDict["placeId"] = jsonObject["placeId"] as? String ?? fileUrl.deletingPathExtension().lastPathComponent
                placeDict["name"] = jsonObject["name"] as? String
                
                if let center = jsonObject["center"] as? [String: Any] {
                    placeDict["center"] = center
                }
                
                if let radius = jsonObject["radius"] as? [String: Any],
                   let mean = radius["mean"] as? Double {
                    placeDict["radius"] = mean
                }
                
                for field in ["streetAddress", "secondsFromGMT", "lastSaved", 
                             "facebookPlaceId", "mapboxPlaceId", 
                             "foursquareVenueId", "foursquareCategoryId"] {
                    if let value = jsonObject[field] {
                        placeDict[field] = value
                    }
                }
                
                let cleanedData = try JSONSerialization.data(withJSONObject: [placeDict])
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let places = try decoder.decode([Place].self, from: cleanedData)
                timer.stop()
                
                for place in places {
                    timer.start("Process Place")
                    let placeTimer = PerformanceTimer()
                    
                    // Check for cancellation before processing each place
                    guard !shouldCancel else {
                        return
                    }
                    
                    placeTimer.start("Check Duplicates")
                    let duplicate = try await checkForDuplicates(place)
                    placeTimer.stop()
                    
                    if let duplicate = duplicate {
                        await MainActor.run {
                            duplicateCount += 1
                            progressValue = 0.1 + (Double(processedFiles) / Double(totalFiles)) * 0.8
                        }
                        
                        if importOptions.ignoreDuplicates {
                            print("Skipping duplicate: \(place.name) (ID: \(place.placeId))")
                            timer.stop()
                            continue
                        } else {
                            placeTimer.start("Handle Duplicate")
                            // Handle duplicate according to options
                            var updatedPlace = duplicate
                            var needsUpdate = false
                            
                            // Handle ID
                            if importOptions.addIdToExisting && !place.placeId.isEmpty && duplicate.placeId != place.placeId && !(duplicate.previousIds?.contains(where: { $0 == place.placeId }) ?? false) {
                                // Create a new place with updated previousIds
                                var previousIds = duplicate.previousIds ?? []
                                previousIds.append(duplicate.placeId)
                                updatedPlace = Place(
                                    placeId: place.placeId,
                                    name: duplicate.name,
                                    center: duplicate.center,
                                    radius: duplicate.radius,
                                    streetAddress: duplicate.streetAddress,
                                    secondsFromGMT: duplicate.secondsFromGMT,
                                    lastSaved: ISO8601DateFormatter().string(from: Date()),
                                    facebookPlaceId: duplicate.facebookPlaceId,
                                    mapboxPlaceId: duplicate.mapboxPlaceId,
                                    foursquareVenueId: duplicate.foursquareVenueId,
                                    foursquareCategoryId: duplicate.foursquareCategoryId,
                                    previousIds: previousIds
                                )
                                needsUpdate = true
                            }
                            
                            // Handle radius
                            let newRadius: Double
                            switch importOptions.radiusHandling {
                            case .smaller:
                                newRadius = min(place.radius, duplicate.radius)
                            case .bigger:
                                newRadius = max(place.radius, duplicate.radius)
                            case .imported:
                                newRadius = place.radius
                            case .original:
                                newRadius = duplicate.radius
                            }
                            
                            if newRadius != updatedPlace.radius {
                                updatedPlace = Place(
                                    placeId: updatedPlace.placeId,
                                    name: updatedPlace.name,
                                    center: updatedPlace.center,
                                    radius: newRadius,
                                    streetAddress: updatedPlace.streetAddress,
                                    secondsFromGMT: updatedPlace.secondsFromGMT,
                                    lastSaved: ISO8601DateFormatter().string(from: Date()),
                                    facebookPlaceId: updatedPlace.facebookPlaceId,
                                    mapboxPlaceId: updatedPlace.mapboxPlaceId,
                                    foursquareVenueId: updatedPlace.foursquareVenueId,
                                    foursquareCategoryId: updatedPlace.foursquareCategoryId,
                                    previousIds: updatedPlace.previousIds
                                )
                                needsUpdate = true
                            }
                            
                            // Handle metadata
                            if importOptions.overwriteExistingMetadata {
                                // Overwrite all metadata from imported place
                                updatedPlace = Place(
                                    placeId: updatedPlace.placeId,
                                    name: updatedPlace.name,
                                    center: updatedPlace.center,
                                    radius: updatedPlace.radius,
                                    streetAddress: place.streetAddress,
                                    secondsFromGMT: place.secondsFromGMT,
                                    lastSaved: ISO8601DateFormatter().string(from: Date()),
                                    facebookPlaceId: place.facebookPlaceId,
                                    mapboxPlaceId: place.mapboxPlaceId,
                                    foursquareVenueId: place.foursquareVenueId,
                                    foursquareCategoryId: place.foursquareCategoryId,
                                    previousIds: updatedPlace.previousIds
                                )
                                needsUpdate = true
                            } else {
                                // Only add missing metadata
                                let updatedMetadata = Place(
                                    placeId: updatedPlace.placeId,
                                    name: updatedPlace.name,
                                    center: updatedPlace.center,
                                    radius: updatedPlace.radius,
                                    streetAddress: updatedPlace.streetAddress ?? place.streetAddress,
                                    secondsFromGMT: updatedPlace.secondsFromGMT ?? place.secondsFromGMT,
                                    lastSaved: ISO8601DateFormatter().string(from: Date()),
                                    facebookPlaceId: updatedPlace.facebookPlaceId ?? place.facebookPlaceId,
                                    mapboxPlaceId: updatedPlace.mapboxPlaceId ?? place.mapboxPlaceId,
                                    foursquareVenueId: updatedPlace.foursquareVenueId ?? place.foursquareVenueId,
                                    foursquareCategoryId: updatedPlace.foursquareCategoryId ?? place.foursquareCategoryId,
                                    previousIds: updatedPlace.previousIds
                                )
                                if updatedMetadata != updatedPlace {
                                    updatedPlace = updatedMetadata
                                    needsUpdate = true
                                }
                            }
                            
                            if needsUpdate {
                                placeTimer.start("Save Updated Place")
                                try await PlaceManager.shared.editPlace(original: duplicate, edited: updatedPlace, batch: true)
                                placeTimer.stop()
                                mergedCount += 1
                            }
                            placeTimer.stop()
                        }
                    } else {
                        placeTimer.start("Add New Place")
                        try await PlaceManager.shared.addPlace(place, batch: true)
                        placeTimer.stop()
                        
                        await MainActor.run {
                            addedCount += 1
                            progressValue = 0.1 + (Double(processedFiles) / Double(totalFiles)) * 0.8
                        }
                    }
                    
                    timer.stop()
                    // Add the sub-timings to the main timer's report with indentation
                    for (operation, duration) in placeTimer.report {
                        timer.addSubOperation("  " + operation, duration)
                    }
                }
                
                timer.start("Move File")
                try FileManagerUtil.shared.moveFileToImportDone(fileUrl, sessionTimestamp: timestamp)
                timer.stop()
                
                await MainActor.run {
                    processedFiles += 1
                    progressValue = 0.1 + (Double(processedFiles) / Double(totalFiles)) * 0.8
                }
                
            } catch {
                await MainActor.run {
                    progress = "Processing files..."
                    importErrors.append((
                        filename: fileUrl.lastPathComponent,
                        error: error.localizedDescription
                    ))
                }
                continue
            }
        }
        
        // Set to 90% when file processing is done (leaving 10% for cleanup)
        progressValue = 0.9
        progress = "Completed: Imported \(addedCount) places, found \(duplicateCount) duplicates"
        timer.stop()
        
        // Add this after processing all files, before cleanup:
        timer.start("Finalize Batch")
        try await PlaceManager.shared.finalizeBatchOperations()
        timer.stop()
    }
}

private class PerformanceTimer {
    private var measurements: [(operation: String, duration: TimeInterval)] = []
    private var currentOperation: (name: String, startTime: Date)?
    
    func start(_ operation: String) {
        if let current = currentOperation {
            print("Warning: Starting \(operation) while \(current.name) is still running")
        }
        currentOperation = (operation, Date())
    }
    
    func stop() {
        guard let current = currentOperation else {
            print("Warning: stop() called with no operation running")
            return
        }
        let duration = Date().timeIntervalSince(current.startTime)
        measurements.append((current.name, duration))
        currentOperation = nil
    }
    
    func addSubOperation(_ operation: String, _ duration: TimeInterval) {
        measurements.append((operation, duration))
    }
    
    var report: [(operation: String, duration: TimeInterval)] {
        // Group by operation name and sum durations
        var grouped: [String: TimeInterval] = [:]
        for measurement in measurements {
            grouped[measurement.operation, default: 0] += measurement.duration
        }
        
        // Convert back to array and sort by duration, keeping indented items after their parent
        return grouped.map { ($0.key, $0.value) }
            .sorted { a, b in
                // If both are main operations (not indented) or both are sub-operations,
                // sort by duration
                if a.0.hasPrefix("  ") == b.0.hasPrefix("  ") {
                    return a.1 > b.1
                }
                // If one is a main operation and one is a sub-operation,
                // keep main operations first
                if !a.0.hasPrefix("  ") && b.0.hasPrefix("  ") {
                    // If this is the parent of the sub-operation, keep them together
                    if b.0.trimmingPrefix("  ").hasPrefix(a.0) {
                        return true
                    }
                }
                // Otherwise, sort by whether they're indented
                return !a.0.hasPrefix("  ")
            }
    }
} 
