import Foundation

class LocalBackupManager {
    static let shared = LocalBackupManager()
    private let fileManager = FileManager.default
    
    private init() {}
    
    /// Call this before applying edits to a file (GPX or Places)
    func backupFileBeforeEdit(originalFileURL: URL, date: Date, backupType: String = "Gpx") {
        guard SettingsManager.shared.localBackupSaveCopyOnEdits else { return }
        guard fileManager.fileExists(atPath: originalFileURL.path) else { return }
        
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        let backupsDir = documentsURL.appendingPathComponent("Backups/\(backupType)/\(dateString)")
        let fileExt = originalFileURL.pathExtension.lowercased()
        
        do {
            if !fileManager.fileExists(atPath: backupsDir.path) {
                try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            }
            
            // Check if this is the first backup for this date
            let allBackupsForDate = getBackups(in: backupsDir, fileExtension: fileExt)
            let isFirstBackup = allBackupsForDate.isEmpty
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH-mm-ss"
            let timeString = timeFormatter.string(from: Date())
            
            var backupFileName = "\(timeString).\(fileExt)"
            if isFirstBackup && SettingsManager.shared.localBackupAlwaysRetainOriginal {
                backupFileName = "original.\(fileExt)"
            }
            
            let backupURL = backupsDir.appendingPathComponent(backupFileName)
            try fileManager.copyItem(at: originalFileURL, to: backupURL)
            FileManagerUtil.logData(context: "LocalBackupManager", content: "Created backup at \(backupType)/\(dateString)/\(backupFileName)", verbosity: 3)
            
            enforceRetentionPolicies(forDate: date, backupType: backupType, fileExtension: fileExt)
            
        } catch {
            FileManagerUtil.logData(context: "LocalBackupManager", content: "Failed to create backup: \(error)", verbosity: 1)
        }
    }
    
    /// Enforce retention policies for a specific date and type
    func enforceRetentionPolicies(forDate date: Date, backupType: String = "Gpx", fileExtension: String = "gpx") {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let backupsDir = documentsURL.appendingPathComponent("Backups/\(backupType)/\(dateString)")
        
        let retentionDays = SettingsManager.shared.localBackupRetentionDays
        let retentionVersions = SettingsManager.shared.localBackupRetentionVersions
        
        if retentionDays == -1 && retentionVersions == -1 {
            return
        }
        
        var allBackups = getBackups(in: backupsDir, fileExtension: fileExtension)
        if allBackups.isEmpty { return }
        
        let originalFileName = "original.\(fileExtension)"
        
        if SettingsManager.shared.localBackupAlwaysRetainOriginal {
            if let index = allBackups.firstIndex(where: { $0.lastPathComponent == originalFileName }) {
                allBackups.remove(at: index)
            }
        }
        
        allBackups.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        if retentionDays != -1 {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
            
            var filesToDelete: [URL] = []
            for file in allBackups {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date {
                    if creationDate < cutoffDate {
                        filesToDelete.append(file)
                    }
                }
            }
            
            for file in filesToDelete {
                allBackups.removeAll { $0 == file }
                deleteFile(at: file)
            }
        }
        
        if retentionVersions != -1 {
            if allBackups.count > retentionVersions {
                let numberToDelete = allBackups.count - retentionVersions
                let filesToDelete = allBackups.prefix(numberToDelete)
                
                for file in filesToDelete {
                    deleteFile(at: file)
                }
            }
        }
        
        // Clean up directory if empty
        let remainingBackups = getBackups(in: backupsDir, fileExtension: fileExtension)
        if remainingBackups.isEmpty {
            do {
                try fileManager.removeItem(at: backupsDir)
            } catch {
                FileManagerUtil.logData(context: "LocalBackupManager", content: "Failed to delete empty backup directory: \(error)", verbosity: 1)
            }
        }
    }
    
    /// Enforces retention policies globally across all backups.
    /// Useful to run periodically, e.g. at midnight.
    func enforceAllRetentionPolicies() {
        enforceAllRetentionPolicies(forType: "Gpx", fileExtension: "gpx")
        enforceAllRetentionPolicies(forType: "Places", fileExtension: "json")
    }
    
    private func enforceAllRetentionPolicies(forType backupType: String, fileExtension: String) {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupsDir = documentsURL.appendingPathComponent("Backups/\(backupType)")
        
        guard let dateFolders = try? fileManager.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for dateFolder in dateFolders {
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: dateFolder.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }
            
            if let date = dateFormatter.date(from: dateFolder.lastPathComponent) {
                enforceRetentionPolicies(forDate: date, backupType: backupType, fileExtension: fileExtension)
            }
        }
    }
    
    private func getBackups(in directory: URL, fileExtension: String) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return []
        }
        
        return files.filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
    }
    
    private func deleteFile(at url: URL) {
        do {
            try fileManager.removeItem(at: url)
            FileManagerUtil.logData(context: "LocalBackupManager", content: "Deleted backup file due to retention policy: \(url.lastPathComponent)", verbosity: 4)
        } catch {
            FileManagerUtil.logData(context: "LocalBackupManager", content: "Failed to delete old backup file: \(error)", verbosity: 1)
        }
    }
}
