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
            "Backups/GPX"
        ]
        
        // Create each folder if it doesn't exist
        for folder in folders {
            let folderUrl = documentsUrl.appendingPathComponent(folder)
            if !fileManager.fileExists(atPath: folderUrl.path) {
                do {
                    try fileManager.createDirectory(at: folderUrl, 
                                                  withIntermediateDirectories: true)
                    print("Created directory: \(folder)")
                } catch {
                    print("Error creating directory \(folder): \(error)")
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
                    try fileManager.removeItem(at: destinationUrl)
                }
                
                try fileManager.moveItem(at: fileUrl, to: destinationUrl)
            } else {
                // For Life2Gpx files, just move them directly to the Done folder
                let filename = fileUrl.lastPathComponent
                let destinationUrl = doneFolder.appendingPathComponent(filename)
                
                // Create the Done folder if needed
                try fileManager.createDirectory(at: doneFolder,
                                             withIntermediateDirectories: true)
                
                if fileManager.fileExists(atPath: destinationUrl.path) {
                    try fileManager.removeItem(at: destinationUrl)
                }
                
                try fileManager.moveItem(at: fileUrl, to: destinationUrl)
            }
        } else {
            throw NSError(domain: "FileManagerError", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Could not find 'Import' in path"])
        }
    }
    
    func backupFile(_ fileUrl: URL) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupsFolder = documentsUrl.appendingPathComponent("Backups")
        
        // Create timestamp for backup file name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Create backup file name with timestamp
        let backupFileName = fileUrl.deletingPathExtension().lastPathComponent + "_" + timestamp + "." + fileUrl.pathExtension
        let backupUrl = backupsFolder.appendingPathComponent(backupFileName)
        
        // Copy file to backup location
        try fileManager.copyItem(at: fileUrl, to: backupUrl)
    }
    
    func backupGpxFile(_ fileUrl: URL) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let gpxBackupsFolder = documentsUrl.appendingPathComponent("Backups/GPX")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let backupFileName = fileUrl.deletingPathExtension().lastPathComponent + "_" + timestamp + ".gpx"
        let backupUrl = gpxBackupsFolder.appendingPathComponent(backupFileName)
        
        try fileManager.copyItem(at: fileUrl, to: backupUrl)
    }
    
    func cleanupEmptyFolders(in baseFolder: String) throws {
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseFolderUrl = documentsUrl.appendingPathComponent(baseFolder)
        
        print("Starting cleanup of: \(baseFolderUrl.path)")
        
        func removeEmptySubfolders(at url: URL) throws -> Bool {
            print("Checking folder: \(url.lastPathComponent)")
            let contents = try fileManager.contentsOfDirectory(at: url, 
                                                             includingPropertiesForKeys: nil)
                .filter { !$0.lastPathComponent.hasPrefix(".") } // Ignore hidden files
            
            print("Contents of \(url.lastPathComponent): \(contents.map { $0.lastPathComponent })")
            
            var isEmpty = true
            
            for contentUrl in contents {
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: contentUrl.path, isDirectory: &isDirectory)
                
                if isDirectory.boolValue {
                    print("Processing subfolder: \(contentUrl.lastPathComponent)")
                    // If subfolder is empty after processing, remove it
                    if try removeEmptySubfolders(at: contentUrl) {
                        print("Removing empty folder: \(contentUrl.lastPathComponent)")
                        try fileManager.removeItem(at: contentUrl)
                    } else {
                        print("Folder not empty: \(contentUrl.lastPathComponent)")
                        isEmpty = false
                    }
                } else {
                    print("Found file: \(contentUrl.lastPathComponent)")
                    isEmpty = false
                }
            }
            
            // Remove .DS_Store file if present
            let dsStoreUrl = url.appendingPathComponent(".DS_Store")
            if fileManager.fileExists(atPath: dsStoreUrl.path) {
                print("Removing .DS_Store from \(url.lastPathComponent)")
                try fileManager.removeItem(at: dsStoreUrl)
            }
            
            print("Folder \(url.lastPathComponent) is \(isEmpty ? "empty" : "not empty")")
            return isEmpty
        }
        
        // Process subfolders and check if base folder should be removed
        if try removeEmptySubfolders(at: baseFolderUrl) {
            print("Removing base folder: \(baseFolderUrl.lastPathComponent)")
            try fileManager.removeItem(at: baseFolderUrl)
        } else {
            print("Base folder not empty: \(baseFolderUrl.lastPathComponent)")
        }
    }
} 
