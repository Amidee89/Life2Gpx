import Foundation

class FileManagerUtil {
    static let shared = FileManagerUtil()
    
    private init() {
        setupFolderStructure()
    }
    
    private func setupFolderStructure() {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Define required folders
        let folders = [
            "Import",
            "Import/Arc",
            "Import/Done",
            "Places",
            "Backups",
            "Backups/GPX",
            "Backups/Places",
            "Logs"
        ]
        
        // Create each folder if it doesn't exist
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
        
        // Get the relative path after "Import"
        let components = fileUrl.pathComponents
        if let importIndex = components.firstIndex(of: "Import") {
            // For Arc files, preserve the folder structure after "Arc"
            if let arcIndex = components.firstIndex(of: "Arc"), arcIndex > importIndex {
                let subPath = components[(arcIndex + 1)...].joined(separator: "/")
                let destinationUrl = doneFolder.appendingPathComponent(subPath)
                
                // Create intermediate directories if needed
                try fileManager.createDirectory(at: destinationUrl.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
                
                if fileManager.fileExists(atPath: destinationUrl.path) {
                    FileManagerUtil.logData(context: "MoveFile", content: "Removing existing file at destination: \(destinationUrl.path)", verbosity: 4)
                    try fileManager.removeItem(at: destinationUrl)
                }
                
                try fileManager.moveItem(at: fileUrl, to: destinationUrl)
                FileManagerUtil.logData(context: "MoveFile", content: "Moved \(fileUrl.lastPathComponent) to \(destinationUrl.path)", verbosity: 3)
            } else {
                // For Life2Gpx files, just move them directly to the Done folder
                let filename = fileUrl.lastPathComponent
                let destinationUrl = doneFolder.appendingPathComponent(filename)
                
                // Create the Done folder if needed
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
        
        // Create timestamp for backup folder
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Determine backup folder based on file type
        let backupType = fileUrl.pathExtension == "gpx" ? "GPX" : "Places"
        let backupFolder = documentsUrl.appendingPathComponent("Backups/\(backupType)/\(timestamp)")
        
        // Create the backup folder
        try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        
        // Create backup URL with original filename
        let backupUrl = backupFolder.appendingPathComponent(fileUrl.lastPathComponent)
        
        // Copy file to backup location
        try fileManager.copyItem(at: fileUrl, to: backupUrl)
        FileManagerUtil.logData(context: "Backup", content: "Backed up \(fileUrl.lastPathComponent) to \(backupUrl.path)", verbosity: 3)
    }
    
    func backupFile(forDate date: Date) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create the file URL for the given date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(dateFormatter.string(from: date)).gpx"
        let fileUrl = documentsUrl.appendingPathComponent(fileName)
        
        // Use existing backup method
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
                    // If subfolder is empty after processing, remove it
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
        
        // Process subfolders and check if base folder should be removed
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
        let logsDirectory = documentDirectory.appendingPathComponent("Logs")
        if !FileManager.default.fileExists(atPath: logsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
                FileManagerUtil.logData(context: "LogSetup", content: "Created Logs directory via getLogFileURL (should not happen)", verbosity: 2)
            } catch {
                FileManagerUtil.logData(context: "LogSetup", content: "Failed to create Logs directory: \(error)", verbosity: 1)
            }
        }

        // Return the full path to the log file in the "Logs" directory
        return logsDirectory.appendingPathComponent(fileName)
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
