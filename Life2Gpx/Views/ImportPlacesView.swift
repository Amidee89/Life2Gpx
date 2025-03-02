import SwiftUI

struct ImportPlacesView: View {
    @State private var arcBackupCount: Int = 0
    @State private var life2GpxFileCount: (files: Int, places: Int) = (0, 0)
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var ignoreDuplicates = true
    @State private var addIdToExisting = true
    @State private var radiusHandling = RadiusHandlingOption.smaller
    @State private var overwriteExistingMetadata = false
    
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
                            // TODO: Implement import view
                            Text("Import View")
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
                            // TODO: Implement import view
                            Text("Import View")
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