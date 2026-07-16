import Foundation
import UIKit

class iCloudBackupManager: ObservableObject {
    static let shared = iCloudBackupManager()
    
    @Published var isBackupRunning: Bool = false
    @Published var backupStatusMessage: String = ""
    
    private let fileManager = FileManager.default
    private let containerIdentifier: String? = "iCloud.com.DeltaCygniLabs.Life2Gpx" // Uses specific container
    
    private var currentTotalFiles: Int = 0
    private var currentProcessedFiles: Int = 0
    private var currentFolderName: String = ""
    private var totalSyncedFiles: Int = 0
    private var totalFailedFiles: Int = 0
    
    private init() {}
    
    func checkAndRunBackupIfNeeded() {
        if isBackupDue() && !isBackupRunning {
            Task {
                await runBackup()
            }
        }
    }
    
    /// The local documents directory.
    private var localDocumentsURL: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    /// The root iCloud Documents directory for the app.
    private var iCloudDocumentsURL: URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            FileManagerUtil.logData(context: "iCloudBackup", content: "Failed to get iCloud container URL. Ensure iCloud Documents capability is enabled and signed in.", verbosity: 1)
            return nil
        }
        return containerURL.appendingPathComponent("Documents")
    }
    
    /// The specific iCloud backup folder for this device.
    private var iCloudBackupFolderURL: URL? {
        guard let iCloudDocs = iCloudDocumentsURL else { return nil }
        
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "UnknownDevice"
        let backupFolder = iCloudDocs.appendingPathComponent(deviceID)
        
        return backupFolder
    }
    
    /// Checks if a backup is due based on user settings.
    func isBackupDue() -> Bool {
        guard SettingsManager.shared.iCloudBackupEnabled else { return false }
        
        let lastBackupDate = SettingsManager.shared.lastICloudBackupDate ?? Date.distantPast
        let now = Date()
        
        if SettingsManager.shared.iCloudBackupMode == "daily" {
            // Check if we already backed up today after the daily time
            let calendar = Calendar.current
            let targetTime = SettingsManager.shared.iCloudBackupDailyTime
            
            // Get today's target date
            var targetComponents = calendar.dateComponents([.year, .month, .day], from: now)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: targetTime)
            targetComponents.hour = timeComponents.hour
            targetComponents.minute = timeComponents.minute
            
            guard let todaysTarget = calendar.date(from: targetComponents) else { return false }
            
            if now >= todaysTarget && lastBackupDate < todaysTarget {
                return true
            }
            
            // If now is before today's target time, check if we missed yesterday's
            if now < todaysTarget {
                guard let yesterdaysTarget = calendar.date(byAdding: .day, value: -1, to: todaysTarget) else { return false }
                if lastBackupDate < yesterdaysTarget {
                    return true
                }
            }
            
            return false
        } else {
            // Interval based
            let intervalValue = SettingsManager.shared.iCloudBackupIntervalValue
            let intervalUnit = SettingsManager.shared.iCloudBackupIntervalUnit
            
            var seconds: TimeInterval = 0
            switch intervalUnit {
            case "seconds": seconds = TimeInterval(intervalValue)
            case "minutes": seconds = TimeInterval(intervalValue * 60)
            case "hours": seconds = TimeInterval(intervalValue * 3600)
            case "days": seconds = TimeInterval(intervalValue * 86400)
            default: seconds = TimeInterval(intervalValue * 86400)
            }
            
            return now.timeIntervalSince(lastBackupDate) >= seconds
        }
    }
    
    private func countFiles(at url: URL) -> Int {
        var count = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for case let fileURL as URL in enumerator {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                    count += 1
                }
            }
        }
        return count
    }
    
    /// Runs the backup process.
    func runBackup() async {
        DispatchQueue.main.async {
            self.isBackupRunning = true
            self.backupStatusMessage = "Starting iCloud backup..."
        }
        
        FileManagerUtil.logData(context: "iCloudBackup", content: "Starting iCloud backup...", verbosity: 3)
        
        guard let localDocs = localDocumentsURL else {
            FileManagerUtil.logData(context: "iCloudBackup", content: "Could not find local documents directory.", verbosity: 1)
            DispatchQueue.main.async {
                self.backupStatusMessage = "Failed: Could not find local directory."
                self.isBackupRunning = false
            }
            return
        }
        
        guard let iCloudBackupFolder = iCloudBackupFolderURL else {
            FileManagerUtil.logData(context: "iCloudBackup", content: "Could not find iCloud backup directory. Is iCloud configured?", verbosity: 1)
            DispatchQueue.main.async {
                self.backupStatusMessage = "Failed: iCloud not configured."
                self.isBackupRunning = false
            }
            return
        }
        
        // Ensure iCloud folder exists
        do {
            try fileManager.createDirectory(at: iCloudBackupFolder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            FileManagerUtil.logData(context: "iCloudBackup", content: "Failed to create iCloud backup directory: \(error)", verbosity: 1)
            DispatchQueue.main.async {
                self.backupStatusMessage = "Failed: \(error.localizedDescription)"
                self.isBackupRunning = false
            }
            return
        }
        
        let foldersToSync = ["Gpx", "Preferences", "Places", "Backups"]
        self.totalSyncedFiles = 0
        self.totalFailedFiles = 0
        
        for folderName in foldersToSync {
            let localFolder = localDocs.appendingPathComponent(folderName)
            let remoteFolder = iCloudBackupFolder.appendingPathComponent(folderName)
            
            if fileManager.fileExists(atPath: localFolder.path) {
                self.currentFolderName = folderName
                self.currentTotalFiles = countFiles(at: localFolder)
                self.currentProcessedFiles = 0
                
                DispatchQueue.main.async {
                    self.backupStatusMessage = "Syncing \(folderName) (0/\(self.currentTotalFiles))..."
                }
                
                do {
                    try await syncFolder(localURL: localFolder, remoteURL: remoteFolder)
                } catch {
                    FileManagerUtil.logData(context: "iCloudBackup", content: "Failed to sync folder \(folderName): \(error)", verbosity: 1)
                }
            } else {
                FileManagerUtil.logData(context: "iCloudBackup", content: "Local folder \(folderName) does not exist, skipping.", verbosity: 4)
            }
        }
        
        FileManagerUtil.logData(context: "iCloudBackup", content: "iCloud backup finished. \(totalSyncedFiles) files synced, \(totalFailedFiles) failed.", verbosity: 3)
        
        DispatchQueue.main.async {
            self.backupStatusMessage = "Finished: \(self.totalSyncedFiles) files synced, \(self.totalFailedFiles) failed."
            self.isBackupRunning = false
            if self.totalFailedFiles == 0 {
                SettingsManager.shared.lastICloudBackupDate = Date()
            }
        }
    }
    
    /// Synchronizes a local folder to a remote iCloud folder (rsync style).
    private func syncFolder(localURL: URL, remoteURL: URL) async throws {
        if !fileManager.fileExists(atPath: remoteURL.path) {
            try fileManager.createDirectory(at: remoteURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let localFiles = try fileManager.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
        
        for localFile in localFiles {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: localFile.path, isDirectory: &isDir) else { continue }
            
            let remoteFile = remoteURL.appendingPathComponent(localFile.lastPathComponent)
            
            if isDir.boolValue {
                try await syncFolder(localURL: localFile, remoteURL: remoteFile)
            } else {
                do {
                    try await syncFile(localURL: localFile, remoteURL: remoteFile)
                    self.totalSyncedFiles += 1
                } catch {
                    self.totalFailedFiles += 1
                    FileManagerUtil.logData(context: "iCloudBackup", content: "Failed to sync file \(localFile.lastPathComponent): \(error)", verbosity: 1)
                }
            }
        }
    }
    
    /// Copies a single file if it's new or modified.
    private func syncFile(localURL: URL, remoteURL: URL) async throws {
        defer {
            currentProcessedFiles += 1
            let fileName = localURL.lastPathComponent
            let folderName = self.currentFolderName
            let processed = self.currentProcessedFiles
            let total = self.currentTotalFiles
            
            DispatchQueue.main.async {
                self.backupStatusMessage = "Syncing \(folderName) (\(processed)/\(total))...\n\(fileName)"
            }
        }
        
        if fileManager.fileExists(atPath: remoteURL.path) {
            let localAttrs = try fileManager.attributesOfItem(atPath: localURL.path)
            let remoteAttrs = try fileManager.attributesOfItem(atPath: remoteURL.path)
            
            let localModDate = localAttrs[.modificationDate] as? Date ?? Date.distantPast
            let remoteModDate = remoteAttrs[.modificationDate] as? Date ?? Date.distantPast
            
            let localSize = localAttrs[.size] as? NSNumber ?? NSNumber(value: 0)
            let remoteSize = remoteAttrs[.size] as? NSNumber ?? NSNumber(value: 0)
            
            // If the local file is newer or size is different, overwrite
            if localModDate > remoteModDate || localSize != remoteSize {
                var fileCoordinatorError: NSError?
                NSFileCoordinator().coordinate(writingItemAt: remoteURL, options: .forReplacing, error: &fileCoordinatorError) { newURL in
                    do {
                        try fileManager.removeItem(at: newURL)
                        try fileManager.copyItem(at: localURL, to: newURL)
                    } catch {
                        FileManagerUtil.logData(context: "iCloudBackup", content: "Failed to overwrite file: \(localURL.lastPathComponent)", verbosity: 1)
                    }
                }
                if let error = fileCoordinatorError {
                    throw error
                }
                FileManagerUtil.logData(context: "iCloudBackup", content: "Updated file: \(localURL.lastPathComponent)", verbosity: 5)
            }
        } else {
            // File does not exist remotely, just copy
            var fileCoordinatorError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: remoteURL, options: .forReplacing, error: &fileCoordinatorError) { newURL in
                do {
                    try fileManager.copyItem(at: localURL, to: newURL)
                } catch {
                    FileManagerUtil.logData(context: "iCloudBackup", content: "Failed to copy file: \(localURL.lastPathComponent)", verbosity: 1)
                }
            }
            if let error = fileCoordinatorError {
                throw error
            }
            FileManagerUtil.logData(context: "iCloudBackup", content: "Copied new file: \(localURL.lastPathComponent)", verbosity: 5)
        }
    }
}
