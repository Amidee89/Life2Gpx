import Foundation

class FileManagerUtil {
    static let shared = FileManagerUtil()
    
    private init() {
        setupFolderStructure()
    }
    
    private func setupFolderStructure() {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let folders = [
            "Gpx",
            "Import",
            "Import/Arc",
            "Import/Done",
            "Places",
            "Preferences",
            "Backups",
            "Backups/GPX",
            "Backups/Places",
            "Logs/App",
            "Logs/Dumps",
            "Logs/Resources"
        ]
        
        for folder in folders {
            let folderUrl = documentsUrl.appendingPathComponent(folder)
            if !fileManager.fileExists(atPath: folderUrl.path) {
                do {
                    try fileManager.createDirectory(at: folderUrl, 
                                                  withIntermediateDirectories: true)
                    FileManagerUtil.logData(context: "Setup", content: "Created directory: \(folder)", verbosity: 4)
                } catch {
                    FileManagerUtil.logData(context: "Setup", content: "Error creating directory \(folder): \(error)", verbosity: 1)
                }
            }
        }
    }
    
    func moveFileToImportDone(_ fileUrl: URL, sessionTimestamp: String) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let doneFolder = documentsUrl.appendingPathComponent("Import/Done/\(sessionTimestamp)")
        
        let components = fileUrl.pathComponents
        if let importIndex = components.firstIndex(of: "Import") {
            if let arcIndex = components.firstIndex(of: "Arc"), arcIndex > importIndex {
                let subPath = components[(arcIndex + 1)...].joined(separator: "/")
                let destinationUrl = doneFolder.appendingPathComponent(subPath)
                try fileManager.createDirectory(at: destinationUrl.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
                
                if fileManager.fileExists(atPath: destinationUrl.path) {
                    FileManagerUtil.logData(context: "MoveFile", content: "Removing existing file at destination: \(destinationUrl.path)", verbosity: 4)
                    try fileManager.removeItem(at: destinationUrl)
                }
                
                try fileManager.moveItem(at: fileUrl, to: destinationUrl)
                FileManagerUtil.logData(context: "MoveFile", content: "Moved \(fileUrl.lastPathComponent) to \(destinationUrl.path)", verbosity: 3)
            } else {
                let filename = fileUrl.lastPathComponent
                let destinationUrl = doneFolder.appendingPathComponent(filename)

                try fileManager.createDirectory(at: doneFolder,
                                             withIntermediateDirectories: true)
                
                if fileManager.fileExists(atPath: destinationUrl.path) {
                    FileManagerUtil.logData(context: "MoveFile", content: "Removing existing file at destination: \(destinationUrl.path)", verbosity: 4)
                    try fileManager.removeItem(at: destinationUrl)
                }
                
                try fileManager.moveItem(at: fileUrl, to: destinationUrl)
                FileManagerUtil.logData(context: "MoveFile", content: "Moved \(fileUrl.lastPathComponent) to \(destinationUrl.path)", verbosity: 3)
            }
        } else {
            FileManagerUtil.logData(context: "MoveFile", content: "Could not find 'Import' in path: \(fileUrl.path)", verbosity: 1)
            throw NSError(domain: "FileManagerError", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not find 'Import' in path"])
        }
    }
    
    func backupFile(_ fileUrl: URL) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupType = fileUrl.pathExtension == "gpx" ? "GPX" : "Places"
        let backupFolder = documentsUrl.appendingPathComponent("Backups/\(backupType)/\(timestamp)")
        try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let backupUrl = backupFolder.appendingPathComponent(fileUrl.lastPathComponent)
        try fileManager.copyItem(at: fileUrl, to: backupUrl)
        FileManagerUtil.logData(context: "Backup", content: "Backed up \(fileUrl.lastPathComponent) to \(backupUrl.path)", verbosity: 3)
    }
    
    func backupFile(forDate date: Date) throws {
        let fileUrl = GPXManager.shared.resolvedFileURL(forDate: date)
        try backupFile(fileUrl)
    }
    
    func cleanupEmptyFolders(in baseFolder: String) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseFolderUrl = documentsUrl.appendingPathComponent(baseFolder)
        
        FileManagerUtil.logData(context: "Cleanup", content: "Starting cleanup of: \(baseFolderUrl.path)", verbosity: 4)
        
        func removeEmptySubfolders(at url: URL) throws -> Bool {
            FileManagerUtil.logData(context: "Cleanup", content: "Checking folder: \(url.lastPathComponent)", verbosity: 5)
            let contents = try fileManager.contentsOfDirectory(at: url, 
                                                             includingPropertiesForKeys: nil)
                .filter { !$0.lastPathComponent.hasPrefix(".") } // Ignore hidden files
            
            FileManagerUtil.logData(context: "Cleanup", content: "Contents of \(url.lastPathComponent): \(contents.map { $0.lastPathComponent })", verbosity: 5)
            
            var isEmpty = true
            
            for contentUrl in contents {
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: contentUrl.path, isDirectory: &isDirectory)
                
                if isDirectory.boolValue {
                    FileManagerUtil.logData(context: "Cleanup", content: "Processing subfolder: \(contentUrl.lastPathComponent)", verbosity: 5)
                    if try removeEmptySubfolders(at: contentUrl) {
                        FileManagerUtil.logData(context: "Cleanup", content: "Removing empty folder: \(contentUrl.lastPathComponent)", verbosity: 4)
                        try fileManager.removeItem(at: contentUrl)
                    } else {
                        FileManagerUtil.logData(context: "Cleanup", content: "Folder not empty: \(contentUrl.lastPathComponent)", verbosity: 5)
                        isEmpty = false
                    }
                } else {
                    FileManagerUtil.logData(context: "Cleanup", content: "Found file: \(contentUrl.lastPathComponent)", verbosity: 5)
                    isEmpty = false
                }
            }
            
            // Remove .DS_Store file if present
            let dsStoreUrl = url.appendingPathComponent(".DS_Store")
            if fileManager.fileExists(atPath: dsStoreUrl.path) {
                FileManagerUtil.logData(context: "Cleanup", content: "Removing .DS_Store from \(url.lastPathComponent)", verbosity: 4)
                try fileManager.removeItem(at: dsStoreUrl)
            }
            
            FileManagerUtil.logData(context: "Cleanup", content: "Folder \(url.lastPathComponent) is \(isEmpty ? "empty" : "not empty")", verbosity: 5)
            return isEmpty
        }
        
        if try removeEmptySubfolders(at: baseFolderUrl) {
            FileManagerUtil.logData(context: "Cleanup", content: "Removing base folder: \(baseFolderUrl.lastPathComponent)", verbosity: 4)
            try fileManager.removeItem(at: baseFolderUrl)
        } else {
            FileManagerUtil.logData(context: "Cleanup", content: "Base folder not empty: \(baseFolderUrl.lastPathComponent)", verbosity: 5)
        }
    }

    static func getLogFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = formatter.string(from: Date()) + ".log"

        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsDirectory = documentDirectory.appendingPathComponent("Logs/App")
        if !FileManager.default.fileExists(atPath: logsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
                FileManagerUtil.logData(context: "LogSetup", content: "Created Logs/App directory via getLogFileURL (should not happen)", verbosity: 2)
            } catch {
                FileManagerUtil.logData(context: "LogSetup", content: "Failed to create Logs/App directory: \(error)", verbosity: 1)
            }
        }

        return logsDirectory.appendingPathComponent(fileName)
    }

    /// Returns GPX files found directly in the Documents root (not in Gpx/ subfolders).
    /// Includes both normal ".gpx" files and duplicate variants like ".gpx 2" created by Files app.
    func gpxFilesInRoot() -> [URL] {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: documentsUrl,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        
        return contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".gpx") || name.range(of: #"\.gpx \d+$"#, options: .regularExpression) != nil
        }
    }
    
    enum ConflictResolution: Hashable {
        case overwrite
        case keepExisting   // incoming file goes to Duplicates
        case replaceExisting // existing file goes to Duplicates, incoming takes its place
    }
    
    /// Moves a file into the Duplicates folder without overwriting anything already there.
    /// Appends " 2", " 3", etc. if the name already exists in Duplicates.
    private func moveToDuplicates(_ fileUrl: URL) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let duplicatesFolder = documentsUrl.appendingPathComponent("Gpx/Duplicates")
        
        if !fileManager.fileExists(atPath: duplicatesFolder.path) {
            try fileManager.createDirectory(at: duplicatesFolder, withIntermediateDirectories: true)
        }
        
        let originalName = fileUrl.lastPathComponent
        var destination = duplicatesFolder.appendingPathComponent(originalName)
        
        if fileManager.fileExists(atPath: destination.path) {
            let nameWithoutExt = fileUrl.deletingPathExtension().lastPathComponent
            let ext = fileUrl.pathExtension
            var counter = 2
            repeat {
                let numberedName = ext.isEmpty ? "\(nameWithoutExt) \(counter)" : "\(nameWithoutExt) \(counter).\(ext)"
                destination = duplicatesFolder.appendingPathComponent(numberedName)
                counter += 1
            } while fileManager.fileExists(atPath: destination.path)
        }
        
        try fileManager.moveItem(at: fileUrl, to: destination)
        FileManagerUtil.logData(context: "OrganizeGPX", content: "Moved \(originalName) to Duplicates as \(destination.lastPathComponent)", verbosity: 3)
    }
    
    /// Moves GPX files from the Documents root into Gpx/year/ subfolders based on filename date.
    /// Files with duplicate suffixes (e.g. "2024-05-27.gpx 2") are moved to Gpx/Duplicates/.
    func organizeGpxFiles(conflictResolution: ConflictResolution = .keepExisting) -> (moved: Int, duplicates: Int, failed: Int) {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let gpxBaseUrl = documentsUrl.appendingPathComponent("Gpx")
        let rootFiles = gpxFilesInRoot()
        
        var moved = 0
        var duplicates = 0
        var failed = 0
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Matches "yyyy-MM-dd.gpx N" (Files app duplicate naming, e.g. "2024-05-27.gpx 2")
        let duplicateSuffixPattern = try! NSRegularExpression(pattern: #"\.gpx \d+$"#, options: .caseInsensitive)
        
        for fileUrl in rootFiles {
            let fileName = fileUrl.lastPathComponent
            let fileNameRange = NSRange(fileName.startIndex..., in: fileName)
            let isDuplicate = duplicateSuffixPattern.firstMatch(in: fileName, range: fileNameRange) != nil
            
            if isDuplicate {
                do {
                    try moveToDuplicates(fileUrl)
                    duplicates += 1
                } catch {
                    failed += 1
                    FileManagerUtil.logData(context: "OrganizeGPX", content: "Failed to move duplicate \(fileUrl.lastPathComponent): \(error.localizedDescription)", verbosity: 1)
                }
            } else {
                let baseName = fileUrl.deletingPathExtension().lastPathComponent
                if let date = dateFormatter.date(from: baseName) {
                    let calendar = Calendar.current
                    let year = String(calendar.component(.year, from: date))
                    let yearFolder = gpxBaseUrl.appendingPathComponent(year)
                    
                    do {
                        if !fileManager.fileExists(atPath: yearFolder.path) {
                            try fileManager.createDirectory(at: yearFolder, withIntermediateDirectories: true)
                        }
                        let destination = yearFolder.appendingPathComponent(fileUrl.lastPathComponent)
                        
                        if fileManager.fileExists(atPath: destination.path) {
                            switch conflictResolution {
                            case .overwrite:
                                try fileManager.removeItem(at: destination)
                                try fileManager.moveItem(at: fileUrl, to: destination)
                            case .keepExisting:
                                try moveToDuplicates(fileUrl)
                                duplicates += 1
                                continue
                            case .replaceExisting:
                                try moveToDuplicates(destination)
                                duplicates += 1
                                try fileManager.moveItem(at: fileUrl, to: destination)
                            }
                        } else {
                            try fileManager.moveItem(at: fileUrl, to: destination)
                        }
                        moved += 1
                        FileManagerUtil.logData(context: "OrganizeGPX", content: "Moved \(fileUrl.lastPathComponent) to Gpx/\(year)/", verbosity: 3)
                    } catch {
                        failed += 1
                        FileManagerUtil.logData(context: "OrganizeGPX", content: "Failed to move \(fileUrl.lastPathComponent): \(error.localizedDescription)", verbosity: 1)
                    }
                } else {
                    failed += 1
                    FileManagerUtil.logData(context: "OrganizeGPX", content: "Could not parse date from filename: \(baseName)", verbosity: 2)
                }
            }
        }
        
        FileManagerUtil.logData(context: "OrganizeGPX", content: "Organization complete. Moved: \(moved), Duplicates: \(duplicates), Failed: \(failed)", verbosity: 2)
        return (moved, duplicates, failed)
    }
    
    static func logData(context: String, content: String, verbosity: Int) {
        guard SettingsManager.shared.debugLogVerbosity > 0, 
              verbosity <= SettingsManager.shared.debugLogVerbosity else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())

        let sanitizedContent = content.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let logMessage = "\(context) [V\(verbosity)] - \(timestamp) - \(sanitizedContent)\n"

        let logFileURL = getLogFileURL()

        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                print("[V1] Could not open file handle for \(logFileURL.path)")
            }
        } else {
            do {
                try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("[V1] Failed to write to \(logFileURL.path): \(error)")
            }
        }
    }
} 
