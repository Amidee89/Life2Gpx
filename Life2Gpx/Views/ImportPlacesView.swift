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
                    }
                } header: {
                    Text("Import Options")
                } footer: {
                    Text("Duplicates are places with the same name, within 20 meters, or with the same ID")
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
            overwriteExistingMetadata: overwriteExistingMetadata
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
}

struct ImportProgressView: View {
    let importType: ImportType
    let importOptions: ImportOptions
    @State private var progress: String = "Starting import..."
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                Text(progress)
            }
        }
        .navigationTitle("Importing Places")
        .interactiveDismissDisabled()
        .task {
            do {
                // First, backup the existing places file
                let fileManager = FileManager.default
                let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let placesUrl = documentsUrl.appendingPathComponent("Places/places.json")
                
                if fileManager.fileExists(atPath: placesUrl.path) {
                    progress = "Creating backup..."
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try FileManagerUtil.shared.backupFile(placesUrl)
                }
                
                if importType == .arcBackup {
                    progress = "Processing Arc backup files..."
                    let places = try await importArcPlaces()
                    
                    progress = "Saving imported places..."
                    let exportUrl = documentsUrl.appendingPathComponent("Import/exportresult.json")
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(places)
                    try data.write(to: exportUrl)
                }
                
                progress = "Import completed!"
                try await Task.sleep(nanoseconds: 1_000_000_000)
                dismiss()
                
            } catch {
                progress = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func importArcPlaces() async throws -> [Place] {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let arcFolderUrl = documentsUrl.appendingPathComponent("Import/Arc/Place")
        
        var importedPlaces: [Place] = []
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: arcFolderUrl.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            progress = "Arc Place folder not found at: \(arcFolderUrl.path)"
            throw NSError(domain: "ImportError", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Arc Place folder not found"])
        }
        
        guard let enumerator = fileManager.enumerator(at: arcFolderUrl,
                                                    includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles]) else {
            progress = "Could not create enumerator for: \(arcFolderUrl.path)"
            throw NSError(domain: "ImportError", code: 2, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not access Arc Place folder"])
        }
        
        var filesFound = false
        
        while let fileUrl = enumerator.nextObject() as? URL {
            guard fileUrl.pathExtension == "json" else { continue }
            
            filesFound = true
            progress = "Processing file: \(fileUrl.lastPathComponent)"
            
            do {
                let data = try Data(contentsOf: fileUrl)
                let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                
                // Create a single place object with the correct structure
                var placeDict: [String: Any] = [:]
                
                // Extract the required fields
                placeDict["placeId"] = jsonObject["placeId"] as? String ?? fileUrl.deletingPathExtension().lastPathComponent
                placeDict["name"] = jsonObject["name"] as? String
                
                // Handle center
                if let center = jsonObject["center"] as? [String: Any] {
                    placeDict["center"] = center
                }
                
                // Handle radius
                if let radius = jsonObject["radius"] as? [String: Any],
                   let mean = radius["mean"] as? Double {
                    placeDict["radius"] = mean
                }
                
                // Copy over additional fields
                for field in ["streetAddress", "secondsFromGMT", "lastSaved", 
                             "facebookPlaceId", "mapboxPlaceId", 
                             "foursquareVenueId", "foursquareCategoryId"] {
                    if let value = jsonObject[field] {
                        placeDict[field] = value
                    }
                }
                
                // Convert to data and decode
                let cleanedData = try JSONSerialization.data(withJSONObject: [placeDict])
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let places = try decoder.decode([Place].self, from: cleanedData)
                importedPlaces.append(contentsOf: places)
                
                progress = "Processed \(importedPlaces.count) places..."
            } catch {
                progress = "Error processing \(fileUrl.lastPathComponent): \(error.localizedDescription)"
                continue
            }
        }
        
        if importedPlaces.isEmpty {
            progress = "No places were successfully imported"
            throw NSError(domain: "ImportError", code: 4, 
                         userInfo: [NSLocalizedDescriptionKey: "No places were successfully imported"])
        }
        
        print("Import completed successfully with \(importedPlaces.count) places")
        return importedPlaces
    }
} 