import Foundation
import CoreLocation

class LogManager {
    static let shared = LogManager()
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.life2gpx.logmanager", qos: .background)
    
    private var writeCount = 0
    
    private init() {
        queue.async {
            self.enforceRetentionPolicies()
        }
    }

    func logLocation(_ location: CLLocation) {
        guard SettingsManager.shared.logAllReceivedPositions else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let logTimestamp = dateFormatter.string(from: Date())
        
        let locFormatter = DateFormatter()
        locFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS O"
        let locTimestamp = locFormatter.string(from: location.timestamp)
        
        var details = [String]()
        details.append(String(format: "<%+.6f,%+.6f>", location.coordinate.latitude, location.coordinate.longitude))
        details.append(String(format: "hAcc: %.2fm", location.horizontalAccuracy))
        details.append(String(format: "alt: %.2fm", location.altitude))
        details.append(String(format: "vAcc: %.2fm", location.verticalAccuracy))
        details.append(String(format: "spd: %.2f mps", location.speed))
        details.append(String(format: "spdAcc: %.2fm", location.speedAccuracy))
        details.append(String(format: "crs: %.2f°", location.course))
        
        if #available(iOS 13.4, *) {
            details.append(String(format: "crsAcc: %.2f°", location.courseAccuracy))
        }
        
        if let floor = location.floor {
            details.append("floor: \(floor.level)")
        }
        
        if #available(iOS 15.0, *) {
            details.append(String(format: "elAlt: %.2fm", location.ellipsoidalAltitude))
            if let src = location.sourceInformation {
                details.append("sim: \(src.isSimulatedBySoftware)")
                details.append("acc: \(src.isProducedByAccessory)")
            }
        }
        
        let detailsStr = details.joined(separator: ", ")
        let logMessage = "[\(logTimestamp)] \(detailsStr) @ \(locTimestamp)\n"
        
        queue.async {
            self.writeLocationLog(logMessage)
        }
    }

    private func writeLocationLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = formatter.string(from: Date()) + ".log"
        
        let logsDirectory = FileManagerUtil.shared.getLocationLogsDirectory()
        let logFileURL = logsDirectory.appendingPathComponent(fileName)
        
        if let data = message.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    print("[V1] Could not open file handle for \(logFileURL.path)")
                }
            } else {
                do {
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("[V1] Failed to write to \(logFileURL.path): \(error)")
                }
            }
        }
        
        // Use the same size limit logic for location logs
        writeCount += 1
        if writeCount % 50 == 0 {
            enforceSizeLimit(for: logFileURL)
        }
    }

    func logMotionData(message: String) {
        guard SettingsManager.shared.logMotionData else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let logTimestamp = dateFormatter.string(from: Date())
        
        let logMessage = "[\(logTimestamp)] \(message)\n"
        
        queue.async {
            self.writeMotionLog(logMessage)
        }
    }

    private func writeMotionLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = formatter.string(from: Date()) + ".log"
        
        let logsDirectory = FileManagerUtil.shared.getMotionLogsDirectory()
        let logFileURL = logsDirectory.appendingPathComponent(fileName)
        
        if let data = message.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    print("[V1] Could not open file handle for \(logFileURL.path)")
                }
            } else {
                do {
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("[V1] Failed to write to \(logFileURL.path): \(error)")
                }
            }
        }
        
        writeCount += 1
        if writeCount % 50 == 0 {
            enforceSizeLimit(for: logFileURL)
        }
    }

    func logFitnessData(message: String) {
        guard SettingsManager.shared.logFitnessData else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let logTimestamp = dateFormatter.string(from: Date())
        
        let logMessage = "[\(logTimestamp)] \(message)\n"
        
        queue.async {
            self.writeFitnessLog(logMessage)
        }
    }

    private func writeFitnessLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = formatter.string(from: Date()) + ".log"
        
        let logsDirectory = FileManagerUtil.shared.getFitnessLogsDirectory()
        let logFileURL = logsDirectory.appendingPathComponent(fileName)
        
        if let data = message.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    print("[V1] Could not open file handle for \(logFileURL.path)")
                }
            } else {
                do {
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("[V1] Failed to write to \(logFileURL.path): \(error)")
                }
            }
        }
        
        writeCount += 1
        if writeCount % 50 == 0 {
            enforceSizeLimit(for: logFileURL)
        }
    }

    func logData(context: String, content: String, verbosity: Int) {
        guard SettingsManager.shared.debugLogVerbosity > 0, 
              verbosity <= SettingsManager.shared.debugLogVerbosity else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedContent = content.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let logMessage = "\(context) [V\(verbosity)] - \(timestamp) - \(sanitizedContent)\n"
        
        queue.async {
            self.writeLog(logMessage)
        }
    }
    
    private func getLogFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = formatter.string(from: Date()) + ".log"
        
        let logsDirectory = FileManagerUtil.shared.getAppLogsDirectory()
        return logsDirectory.appendingPathComponent(fileName)
    }

    private func writeLog(_ message: String) {
        let logFileURL = getLogFileURL()
        
        if let data = message.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    print("[V1] Could not open file handle for \(logFileURL.path)")
                }
            } else {
                do {
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("[V1] Failed to write to \(logFileURL.path): \(error)")
                }
            }
        }
        
        writeCount += 1
        // Periodically check size to enforce limit without impacting performance on every single log line
        if writeCount % 50 == 0 {
            enforceSizeLimit(for: logFileURL)
        }
    }
    
    private func enforceSizeLimit(for fileURL: URL) {
        let limitMB = SettingsManager.shared.logSizeLimitMB
        if limitMB == -1 { return } // Infinite
        
        let maxBytes = UInt64(limitMB) * 1024 * 1024
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > maxBytes else {
            return
        }
        
        // To be performant, if we hit the limit, we discard the oldest 20% of the log file so we don't have to trim continuously.
        let targetBytes = UInt64(Double(maxBytes) * 0.8)
        let bytesToDrop = fileSize > targetBytes ? fileSize - targetBytes : 0
        guard bytesToDrop > 0 else { return }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return }
        
        fileHandle.seek(toFileOffset: bytesToDrop)
        let data = fileHandle.readDataToEndOfFile()
        fileHandle.closeFile()
        
        if let newlineIndex = data.firstIndex(of: UInt8(ascii: "\n")) {
            let validData = data.subdata(in: (newlineIndex + 1)..<data.count)
            try? validData.write(to: fileURL, options: .atomic)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func enforceRetentionPolicies() {
        let retentionDays = SettingsManager.shared.logRetentionDays
        if retentionDays == -1 { return }
        
        let directories = [
            FileManagerUtil.shared.getAppLogsDirectory(),
            FileManagerUtil.shared.getLocationLogsDirectory(),
            FileManagerUtil.shared.getMotionLogsDirectory(),
            FileManagerUtil.shared.getFitnessLogsDirectory()
        ]
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        
        for logsDirectory in directories {
            guard let files = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { continue }
            
            let logFiles = files.filter { $0.pathExtension == "log" }
            
            for file in logFiles {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date {
                    if creationDate < cutoffDate {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }
        }
    }
}
