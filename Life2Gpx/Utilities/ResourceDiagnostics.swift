import Foundation
import UIKit
import os
import Network

let diagnosticsLog = OSLog(subsystem: "com.life2gpx.diagnostics", category: "performance")
let diagnosticsSignposter = OSSignposter(logHandle: diagnosticsLog)

private enum Constants {
    static let maxDiagnosticEvents = 180
    static let logTailMaxBytes: UInt64 = 750_000
    static let recentLogsLimit = 4
    
    static let memoryWatchdogSampleInterval: TimeInterval = 10
    static let memoryWatchdogTrendWindow = 5
    static let memoryWatchdogWarningThresholdMB: Double = 100
    static let memoryWatchdogCriticalThresholdMB: Double = 50
}

enum ResourceDiagnostics {

    static func residentMB() -> Double {
        var taskInfo = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(taskInfo.resident_size) / 1_048_576
    }

    static func availableMB() -> Double {
        Double(os_proc_available_memory()) / 1_048_576
    }

    static func memorySnapshot() -> String {
        let resident = residentMB()
        let available = availableMB()
        let residentStr = resident >= 0 ? String(format: "%.1f", resident) : "unknown"
        let availableStr = String(format: "%.1f", available)
        return "resident=\(residentStr)MB available=\(availableStr)MB"
    }

    static func cpuUsagePercentage() -> Double {
        var kernReturn: kern_return_t
        var taskInfoCount: mach_msg_type_number_t

        var taskInfo = task_basic_info()
        taskInfoCount = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size / MemoryLayout<integer_t>.size)

        let taskInfoResult = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(taskInfoCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &taskInfoCount)
            }
        }
        guard taskInfoResult == KERN_SUCCESS else { return -1 }

        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        kernReturn = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kernReturn == KERN_SUCCESS, let threads = threadList else { return -1 }

        var totalUsageOfCPU: Double = 0.0

        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let threadInfoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if threadInfoResult == KERN_SUCCESS {
                let isIdle = (threadInfo.flags & TH_FLAGS_IDLE) != 0
                if !isIdle {
                    totalUsageOfCPU += (Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))

        return totalUsageOfCPU
    }

    static func logMemory(context: String, detail: String, verbosity: Int = 2) {
        DiagnosticsStateStore.shared.update(
            section: "Memory",
            detail: "\(context): \(detail) \(memorySnapshot())"
        )
        LogManager.shared.logData(
            context: context,
            content: "\(detail) \(memorySnapshot())",
            verbosity: verbosity
        )
    }

    static func runtimeSnapshot() -> String {
        let app = UIApplication.shared
        let processInfo = ProcessInfo.processInfo
        let backgroundTime = app.backgroundTimeRemaining
        let backgroundTimeDescription = backgroundTime == .greatestFiniteMagnitude
            ? "unlimited"
            : "\(String(format: "%.1f", backgroundTime))s"

        return [
            memorySnapshot(),
            "appState=\(applicationStateDescription(app.applicationState))",
            "thermal=\(thermalStateDescription(processInfo.thermalState))",
            "lowPower=\(processInfo.isLowPowerModeEnabled)",
            "protectedData=\(app.isProtectedDataAvailable)",
            "backgroundTimeRemaining=\(backgroundTimeDescription)",
            "network={\(NetworkDiagnostics.shared.snapshot())}"
        ].joined(separator: " ")
    }

    static func logRuntime(context: String, detail: String, verbosity: Int = 4) {
        DiagnosticsStateStore.shared.update(
            section: "Runtime",
            detail: "\(context): \(detail) \(runtimeSnapshot())"
        )
        LogManager.shared.logData(
            context: context,
            content: "\(detail) \(runtimeSnapshot())",
            verbosity: verbosity
        )
    }

    private static func applicationStateDescription(_ state: UIApplication.State) -> String {
        switch state {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown(\(state.rawValue))"
        }
    }

    private static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}

final class DiagnosticsStateStore {
    static let shared = DiagnosticsStateStore()

    private let lock = NSLock()
    private var sections: [String: String] = [:]
    private var events: [String] = []
    private let maxEvents = Constants.maxDiagnosticEvents
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {}

    func update(section: String, detail: String) {
        let entry: String
        lock.lock()
        let timestamp = timestampFormatter.string(from: Date())
        entry = "\(timestamp) \(section): \(detail)"
        sections[section] = detail
        events.append(entry)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        lock.unlock()
    }

    func reportText() -> String {
        lock.lock()
        let sectionSnapshot = sections
        let eventSnapshot = events
        lock.unlock()

        var lines: [String] = []
        lines.append("Latest Diagnostic Sections")
        if sectionSnapshot.isEmpty {
            lines.append("(none recorded yet)")
        } else {
            for key in sectionSnapshot.keys.sorted() {
                lines.append("[\(key)]")
                lines.append(sectionSnapshot[key] ?? "")
                lines.append("")
            }
        }

        lines.append("Recent Diagnostic Events")
        if eventSnapshot.isEmpty {
            lines.append("(none recorded yet)")
        } else {
            lines.append(contentsOf: eventSnapshot)
        }
        return lines.joined(separator: "\n")
    }
}

enum ResourceLogDumpBuilder {
    static func writeReport(trigger: String = "manual settings button") throws -> URL {
        LogManager.shared.logData(
            context: "Diagnostics",
            content: "Resource log report requested. trigger=\(trigger)",
            verbosity: 1
        )

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reportsDirectory = documentsURL.appendingPathComponent("Logs/Dumps")
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let reportURL = reportsDirectory.appendingPathComponent("Life2Gpx-resource-dump-\(formatter.string(from: Date())).txt")
        try buildReport(trigger: trigger).write(to: reportURL, atomically: true, encoding: .utf8)

        LogManager.shared.logData(
            context: "Diagnostics",
            content: "Resource log report written to \(reportURL.path)",
            verbosity: 1
        )
        return reportURL
    }

    private static func buildReport(trigger: String) -> String {
        var lines: [String] = []
        let bundle = Bundle.main
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo
        let screen = UIScreen.main

        lines.append("Life2Gpx Resource Log Report")
        lines.append("Generated: \(Date())")
        lines.append("Trigger: \(trigger)")
        lines.append("")

        lines.append("App")
        lines.append("bundleID=\(bundle.bundleIdentifier ?? "unknown")")
        lines.append("version=\(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown")")
        lines.append("build=\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown")")
        lines.append("debugLogVerbosity=\(SettingsManager.shared.debugLogVerbosity)")
        lines.append("")

        lines.append("Device")
        lines.append("model=\(device.model) system=\(device.systemName) \(device.systemVersion)")
        lines.append("physicalMemoryMB=\(processInfo.physicalMemory / 1_048_576)")
        lines.append("processorCount=\(processInfo.processorCount) activeProcessorCount=\(processInfo.activeProcessorCount)")
        lines.append("lowPowerMode=\(processInfo.isLowPowerModeEnabled) thermal=\(thermalStateDescription(processInfo.thermalState))")
        lines.append("screenBounds=\(Int(screen.bounds.width))x\(Int(screen.bounds.height)) scale=\(screen.scale)")
        lines.append("")

        lines.append("Runtime")
        lines.append(ResourceDiagnostics.runtimeSnapshot())
        lines.append("")

        lines.append(DiagnosticsStateStore.shared.reportText())
        lines.append("")

        lines.append("Recent Log Files")
        let logURLs = recentLogURLs()
        if logURLs.isEmpty {
            lines.append("(no log files found)")
        } else {
            for url in logURLs {
                lines.append(logFileSummary(url))
            }
        }
        lines.append("")

        lines.append("")

        lines.append("Recent Resource Tracking Logs")
        let resourceURLs = recentResourceURLs()
        if resourceURLs.isEmpty {
            lines.append("(no resource logs found)")
        } else {
            for url in resourceURLs {
                lines.append(logFileSummary(url))
            }
        }
        lines.append("")

        for url in resourceURLs {
            lines.append("==== \(url.lastPathComponent) ====")
            lines.append(logTail(url))
            lines.append("")
        }

        for url in logURLs {
            lines.append("==== \(url.lastPathComponent) ====")
            lines.append(logTail(url))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func recentLogURLs(limit: Int = Constants.recentLogsLimit) -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsDirectory = documentsURL.appendingPathComponent("Logs/App")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "log" }
            .sorted {
                let lhsDate = ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                let rhsDate = ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func recentResourceURLs(limit: Int = Constants.recentLogsLimit) -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let resourcesDirectory = documentsURL.appendingPathComponent("Logs/Resources")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: resourcesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "jsonl" }
            .sorted {
                let lhsDate = ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                let rhsDate = ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func logFileSummary(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.description ?? "unknown"
        let size = values?.fileSize ?? 0
        return "\(url.lastPathComponent) size=\(size) modified=\(modified)"
    }

    private static func logTail(_ url: URL, maxBytes: UInt64 = Constants.logTailMaxBytes) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "(could not open log)"
        }
        defer { handle.closeFile() }

        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if size > maxBytes {
            handle.seek(toFileOffset: size - maxBytes)
        }
        let data = handle.readDataToEndOfFile()
        let prefix = size > maxBytes ? "(log truncated to final \(maxBytes) bytes)\n" : ""
        return prefix + (String(data: data, encoding: .utf8) ?? "(log is not valid UTF-8)")
    }

    private static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}

final class NetworkDiagnostics {
    static let shared = NetworkDiagnostics()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.life2gpx.network-diagnostics")
    private let lock = NSLock()
    private var hasStarted = false
    private var latestSnapshot = "not-started"

    private init() {}

    func start() {
        lock.lock()
        guard !hasStarted else {
            lock.unlock()
            return
        }
        hasStarted = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.record(path)
        }
        monitor.start(queue: queue)

        LogManager.shared.logData(
            context: "NetworkDiagnostics",
            content: "NWPathMonitor started. Initial path: \(snapshot())",
            verbosity: 4
        )
    }

    func snapshot() -> String {
        lock.lock()
        let cachedSnapshot = latestSnapshot
        let started = hasStarted
        lock.unlock()

        guard started, cachedSnapshot != "not-started" else {
            return Self.describe(monitor.currentPath)
        }
        return cachedSnapshot
    }

    private func record(_ path: NWPath) {
        let newSnapshot = Self.describe(path)

        lock.lock()
        let previousSnapshot = latestSnapshot
        latestSnapshot = newSnapshot
        lock.unlock()

        let verbosity = previousSnapshot == "not-started" || previousSnapshot != newSnapshot ? 4 : 5
        LogManager.shared.logData(
            context: "NetworkDiagnostics",
            content: "Path update: \(newSnapshot)",
            verbosity: verbosity
        )
    }

    private static func describe(_ path: NWPath) -> String {
        let activeInterfaces = [
            (NWInterface.InterfaceType.wifi, "wifi"),
            (.cellular, "cellular"),
            (.wiredEthernet, "wired"),
            (.loopback, "loopback"),
            (.other, "other")
        ]
            .filter { path.usesInterfaceType($0.0) }
            .map { $0.1 }

        let availableInterfaces = path.availableInterfaces.map { interface in
            "\(interface.name):\(interfaceTypeDescription(interface.type))"
        }

        return [
            "status=\(statusDescription(path.status))",
            "reason=\(unsatisfiedReasonDescription(path.unsatisfiedReason))",
            "expensive=\(path.isExpensive)",
            "constrained=\(path.isConstrained)",
            "dns=\(path.supportsDNS)",
            "ipv4=\(path.supportsIPv4)",
            "ipv6=\(path.supportsIPv6)",
            "active=\(activeInterfaces.isEmpty ? "none" : activeInterfaces.joined(separator: ","))",
            "available=\(availableInterfaces.isEmpty ? "none" : availableInterfaces.joined(separator: ","))"
        ].joined(separator: " ")
    }

    private static func statusDescription(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        case .requiresConnection:
            return "requiresConnection"
        @unknown default:
            return "unknown"
        }
    }

    private static func unsatisfiedReasonDescription(_ reason: NWPath.UnsatisfiedReason) -> String {
        switch reason {
        case .notAvailable:
            return "notAvailable"
        case .cellularDenied:
            return "cellularDenied"
        case .wifiDenied:
            return "wifiDenied"
        case .localNetworkDenied:
            return "localNetworkDenied"
        case .vpnInactive:
            return "vpnInactive"
        @unknown default:
            return "unknown"
        }
    }

    private static func interfaceTypeDescription(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .wiredEthernet:
            return "wired"
        case .loopback:
            return "loopback"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}

final class MemoryWatchdog {
    static let shared = MemoryWatchdog()

    private var timer: DispatchSourceTimer?
    private var samples: [Double] = []
    private let sampleInterval: TimeInterval = Constants.memoryWatchdogSampleInterval
    private let trendWindow = Constants.memoryWatchdogTrendWindow
    private let warningThresholdMB: Double = Constants.memoryWatchdogWarningThresholdMB
    private let criticalThresholdMB: Double = Constants.memoryWatchdogCriticalThresholdMB

    private init() {}

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + sampleInterval, repeating: sampleInterval)
        source.setEventHandler { [weak self] in
            self?.sample()
        }
        source.resume()
        timer = source
        LogManager.shared.logData(
            context: "MemoryWatchdog",
            content: "Started. Sampling every \(Int(sampleInterval))s. Warning at <\(Int(warningThresholdMB))MB, critical at <\(Int(criticalThresholdMB))MB available.",
            verbosity: 4
        )
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func sample() {
        let available = ResourceDiagnostics.availableMB()
        let resident = ResourceDiagnostics.residentMB()
        samples.append(available)
        if samples.count > trendWindow {
            samples.removeFirst(samples.count - trendWindow)
        }

        let declining = samples.count == trendWindow && samples == samples.sorted(by: >)

        if available < criticalThresholdMB {
            LogManager.shared.logData(
                context: "MemoryWatchdog",
                content: "🚨 CRITICAL: available=\(String(format: "%.0f", available))MB resident=\(String(format: "%.0f", resident))MB — app likely to be terminated soon. Declining trend: \(declining)",
                verbosity: 4
            )
        } else if available < warningThresholdMB {
            LogManager.shared.logData(
                context: "MemoryWatchdog",
                content: "⚠️ WARNING: available=\(String(format: "%.0f", available))MB resident=\(String(format: "%.0f", resident))MB — memory pressure building. Declining trend: \(declining)",
                verbosity: 4
            )
        } else if declining {
            LogManager.shared.logData(
                context: "MemoryWatchdog",
                content: "Memory declining for \(trendWindow) consecutive samples: available=\(String(format: "%.0f", available))MB resident=\(String(format: "%.0f", resident))MB",
                verbosity: 4
            )
        }
    }
}

struct ResourceEvent: Codable {
    let timestamp: Date
    let context: String
    let batteryLevel: Float
    let batteryState: String
    let thermalState: String
    let memoryResidentMB: Double
    let memoryAvailableMB: Double
    let executionTimeSeconds: Double?
    let isBackground: Bool
    var cpuUsagePercentage: Double?
    var extraInfo: [String: String]?
}

final class ResourceTracker {
    static let shared = ResourceTracker()

    private let queue = DispatchQueue(label: "com.life2gpx.resourcetracker")
    private var isBatteryMonitoringStarted = false

    private init() {}

    private func startBatteryMonitoringIfNeeded() {
        guard !isBatteryMonitoringStarted else { return }
        if Thread.isMainThread {
            UIDevice.current.isBatteryMonitoringEnabled = true
        } else {
            DispatchQueue.main.sync {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
        }
        isBatteryMonitoringStarted = true
    }

    func logResourceEvent(context: String, executionTime: TimeInterval? = nil, extraInfo: [String: String]? = nil) {
        guard SettingsManager.shared.trackResourceUsage else { return }

        startBatteryMonitoringIfNeeded()

        let device = UIDevice.current
        var batteryLevel: Float = 0
        var batteryStateRaw = 0
        
        if Thread.isMainThread {
            batteryLevel = device.batteryLevel
            batteryStateRaw = device.batteryState.rawValue
        } else {
            DispatchQueue.main.sync {
                batteryLevel = device.batteryLevel
                batteryStateRaw = device.batteryState.rawValue
            }
        }
        
        let batteryState: String
        switch UIDevice.BatteryState(rawValue: batteryStateRaw) ?? .unknown {
        case .unknown: batteryState = "unknown"
        case .unplugged: batteryState = "unplugged"
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        @unknown default: batteryState = "unknown"
        }

        let processInfo = ProcessInfo.processInfo
        let thermalState: String
        switch processInfo.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }

        let resident = ResourceDiagnostics.residentMB()
        let available = ResourceDiagnostics.availableMB()
        
        var isBackground = false
        if Thread.isMainThread {
            isBackground = UIApplication.shared.applicationState == .background
        } else {
            DispatchQueue.main.sync {
                isBackground = UIApplication.shared.applicationState == .background
            }
        }

        let cpuUsage = ResourceDiagnostics.cpuUsagePercentage()

        let event = ResourceEvent(
            timestamp: Date(),
            context: context,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            thermalState: thermalState,
            memoryResidentMB: resident,
            memoryAvailableMB: available,
            executionTimeSeconds: executionTime,
            isBackground: isBackground,
            cpuUsagePercentage: cpuUsage,
            extraInfo: extraInfo
        )

        queue.async {
            self.writeEvent(event)
        }
    }

    private func writeEvent(_ event: ResourceEvent) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let resourcesDirectory = documentsURL.appendingPathComponent("Logs/Resources")
        
        do {
            if !FileManager.default.fileExists(atPath: resourcesDirectory.path) {
                try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let fileName = formatter.string(from: Date()) + "-resources.jsonl"
            let fileURL = resourcesDirectory.appendingPathComponent(fileName)
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(event)
            
            if let jsonString = String(data: data, encoding: .utf8) {
                let line = jsonString + "\n"
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let fileHandle = try FileHandle(forWritingTo: fileURL)
                    fileHandle.seekToEndOfFile()
                    if let lineData = line.data(using: .utf8) {
                        fileHandle.write(lineData)
                    }
                    fileHandle.closeFile()
                } else {
                    try line.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            LogManager.shared.logData(context: "ResourceTracker", content: "Failed to write resource event: \(error)", verbosity: 2)
        }
    }
}
