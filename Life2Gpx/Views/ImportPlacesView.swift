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
    @State private var timingReport: [TimerEntry] = []
    @State private var importStartTime: Date?
    @State private var importEndTime: Date?
    
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
                TimingReportView(timingReport: timingReport, startTime: importStartTime, endTime: importEndTime)
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
            
            await MainActor.run {
                progress = "Loading places..."
                progressValue = 0.05
            }
            PlaceManager.shared.reloadPlaces()
            
            // First, backup the existing places file
            let backupStart = Date()
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
            timer.addTime("Backup", Date().timeIntervalSince(backupStart))
            
            switch importType {
            case .arcBackup:
                try await importArcPlaces(timer: timer)
                // Clean up only if not canceled
                if !shouldCancel {
                    let cleanupStart = Date()
                    await MainActor.run {
                        progress = "Cleaning up..."
                    }
                    try FileManagerUtil.shared.cleanupEmptyFolders(in: "Import/Arc/Place")
                    timer.addTime("Cleanup", Date().timeIntervalSince(cleanupStart))
                }
            case .life2Gpx:
                try await importLife2GpxPlaces(timer: timer)
            }
            
            await MainActor.run {
                progressValue = 1.0
                isComplete = true
                timingReport = timer.entries
                importEndTime = Date()
            }
            
        } catch {
            await MainActor.run {
                progress = "Import failed: \(error.localizedDescription)"
                importEndTime = Date()
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
    
    private func handleDuplicate(place: Place, duplicate: Place, timer: PerformanceTimer) async throws -> Bool {
        let startHandleDuplicate = Date()
        var updatedPlace = duplicate
        var needsUpdate = false
        
        // Handle ID
        if importOptions.addIdToExisting && !place.placeId.isEmpty && 
           duplicate.placeId != place.placeId && 
           !(duplicate.previousIds?.contains(where: { $0 == place.placeId }) ?? false) {
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
            try await PlaceManager.shared.editPlace(original: duplicate, edited: updatedPlace, batch: true)
            mergedCount += 1
        }
        timer.addTime("Handle Duplicate", Date().timeIntervalSince(startHandleDuplicate), parent: "Process Place")
        
        return needsUpdate
    }
    
    private func importArcPlaces(timer: PerformanceTimer) async throws {
        let startImport = Date()  
        
        // Add this line to create the main processing timer
        timer.addTime("Main Processing", 0) // Initial duration will be updated later
        
        let startCountFiles = Date()
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let arcFolderUrl = documentsUrl.appendingPathComponent("Import/Arc/Place")
        
        let enumerator = fileManager.enumerator(at: arcFolderUrl,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles])
        var totalFiles = 0
        while let fileUrl = enumerator?.nextObject() as? URL {
            if fileUrl.pathExtension == "json" {
                totalFiles += 1
            }
        }
        timer.addTime("Count Files", Date().timeIntervalSince(startCountFiles))
        
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
        
        let startProcessing = Date()  // Add timer for main processing loop
        let batchSize = 50 // Update UI every 50 files
        var batchCounter = 0
        
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
                let startFileProcess = Date()  // Add timer for entire file processing
                
                let startReadFile = Date()
                let data = try Data(contentsOf: fileUrl)
                timer.addTime("Read File", Date().timeIntervalSince(startReadFile), parent: "Process File")
                
                let startParseJson = Date()
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
                timer.addTime("Parse JSON", Date().timeIntervalSince(startParseJson), parent: "Process File")
                
                for place in places {
                    let startProcessPlace = Date()
                    
                    let startCheckDuplicates = Date()
                    let duplicate = try await checkForDuplicates(place)
                    timer.addTime("Check Duplicates", Date().timeIntervalSince(startCheckDuplicates), parent: "Process Place")
                    
                    if let duplicate = duplicate {
                        duplicateCount += 1
                        
                        if importOptions.ignoreDuplicates {
                            print("Skipping duplicate: \(place.name) (ID: \(place.placeId))")
                            continue
                        } else {
                            _ = try await handleDuplicate(place: place, duplicate: duplicate, timer: timer)
                        }
                    } else {
                        let startAddPlace = Date()
                        try await PlaceManager.shared.addPlace(place, batch: true)
                        timer.addTime("Add New Place", Date().timeIntervalSince(startAddPlace), parent: "Process Place")
                        addedCount += 1
                    }
                    
                    timer.addTime("Process Place", Date().timeIntervalSince(startProcessPlace), parent: "Process File")
                }

                let startMoveFile = Date()
                try FileManagerUtil.shared.moveFileToImportDone(fileUrl, sessionTimestamp: timestamp)
                timer.addTime("Move File", Date().timeIntervalSince(startMoveFile), parent: "Process File")
                
                // Update UI less frequently
                batchCounter += 1
                if batchCounter >= batchSize {
                    let startUpdateUI = Date()
                    await MainActor.run {
                        processedFiles += batchCounter
                        progress = "Processing file \(processedFiles) of \(totalFiles)"
                        progressValue = 0.1 + (Double(processedFiles) / Double(totalFiles)) * 0.8
                    }
                    timer.addTime("Update UI", Date().timeIntervalSince(startUpdateUI), parent: "Process File")
                    batchCounter = 0
                }

                timer.addTime("Process File", Date().timeIntervalSince(startFileProcess), parent: "Main Processing")
                
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
        
        // Final UI update for any remaining files
        if batchCounter > 0 {
            let startUpdateUI = Date()
            await MainActor.run {
                processedFiles += batchCounter
                progressValue = 0.9
                progress = "Completed: Imported \(addedCount) places, found \(duplicateCount) duplicates"
            }
            timer.addTime("Update UI", Date().timeIntervalSince(startUpdateUI), parent: "Process File")
        }
        
        // Set to 90% when file processing is done (leaving 10% for cleanup)
        progressValue = 0.9
        progress = "Completed: Imported \(addedCount) places, found \(duplicateCount) duplicates"
        
        let startFinalize = Date()
        try await PlaceManager.shared.finalizeBatchOperations()
        timer.addTime("Finalize Batch", Date().timeIntervalSince(startFinalize))
        
        // At the end of the function, update the main processing time
        timer.addTime("Main Processing", Date().timeIntervalSince(startImport))
    }
    
    private func importLife2GpxPlaces(timer: PerformanceTimer) async throws {
        let startImport = Date()
        timer.addTime("Main Processing", 0) // Initial duration will be updated later
        
        let startCountFiles = Date()
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importFolderUrl = documentsUrl.appendingPathComponent("Import")
        
        let fileUrls = try fileManager.contentsOfDirectory(at: importFolderUrl,
                                                         includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles])
        let jsonFiles = fileUrls.filter { $0.pathExtension == "json" }
        let totalFiles = jsonFiles.count
        timer.addTime("Count Files", Date().timeIntervalSince(startCountFiles))
        
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
        
        let batchSize = 50 // Update UI every 50 files
        var batchCounter = 0
        
        for fileUrl in jsonFiles {
            // Check for cancellation
            guard !shouldCancel else {
                return
            }
            
            await MainActor.run {
                progress = "Processing file \(processedFiles + 1) of \(totalFiles)"
            }
            
            do {
                let startFileProcess = Date()
                
                let startReadFile = Date()
                let data = try Data(contentsOf: fileUrl)
                timer.addTime("Read File", Date().timeIntervalSince(startReadFile), parent: "Process File")
                
                let startParseJson = Date()
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let places = try decoder.decode([Place].self, from: data)
                timer.addTime("Parse JSON", Date().timeIntervalSince(startParseJson), parent: "Process File")
                
                for place in places {
                    let startProcessPlace = Date()
                    
                    let startCheckDuplicates = Date()
                    let duplicate = try await checkForDuplicates(place)
                    timer.addTime("Check Duplicates", Date().timeIntervalSince(startCheckDuplicates), parent: "Process Place")
                    
                    if let duplicate = duplicate {
                        duplicateCount += 1
                        
                        if importOptions.ignoreDuplicates {
                            print("Skipping duplicate: \(place.name) (ID: \(place.placeId))")
                            continue
                        } else {
                            _ = try await handleDuplicate(place: place, duplicate: duplicate, timer: timer)
                        }
                    } else {
                        let startAddPlace = Date()
                        try await PlaceManager.shared.addPlace(place, batch: true)
                        timer.addTime("Add New Place", Date().timeIntervalSince(startAddPlace), parent: "Process Place")
                        addedCount += 1
                    }
                    
                    timer.addTime("Process Place", Date().timeIntervalSince(startProcessPlace), parent: "Process File")
                }
                
                let startMoveFile = Date()
                try FileManagerUtil.shared.moveFileToImportDone(fileUrl, sessionTimestamp: timestamp)
                timer.addTime("Move File", Date().timeIntervalSince(startMoveFile), parent: "Process File")
                
                // Update UI less frequently
                batchCounter += 1
                if batchCounter >= batchSize {
                    let startUpdateUI = Date()
                    await MainActor.run {
                        processedFiles += batchCounter
                        progress = "Processing file \(processedFiles) of \(totalFiles)"
                        progressValue = 0.1 + (Double(processedFiles) / Double(totalFiles)) * 0.8
                    }
                    timer.addTime("Update UI", Date().timeIntervalSince(startUpdateUI), parent: "Process File")
                    batchCounter = 0
                }
                
                timer.addTime("Process File", Date().timeIntervalSince(startFileProcess), parent: "Main Processing")
                
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
        
        // Final UI update for any remaining files
        if batchCounter > 0 {
            let startUpdateUI = Date()
            await MainActor.run {
                processedFiles += batchCounter
                progressValue = 0.9
                progress = "Completed: Imported \(addedCount) places, found \(duplicateCount) duplicates"
            }
            timer.addTime("Update UI", Date().timeIntervalSince(startUpdateUI), parent: "Process File")
        }
        
        // Set to 90% when file processing is done (leaving 10% for cleanup)
        progressValue = 0.9
        progress = "Completed: Imported \(addedCount) places, found \(duplicateCount) duplicates"
        
        let startFinalize = Date()
        try await PlaceManager.shared.finalizeBatchOperations()
        timer.addTime("Finalize Batch", Date().timeIntervalSince(startFinalize))
        
        // At the end of the function, update the main processing time
        timer.addTime("Main Processing", Date().timeIntervalSince(startImport))
    }
}
