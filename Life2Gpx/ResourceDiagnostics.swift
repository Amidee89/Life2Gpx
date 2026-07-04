import Foundation
import UIKit
import os
import Network

let diagnosticsLog = OSLog(subsystem: "com.life2gpx.diagnostics", category: "performance")
let diagnosticsSignposter = OSSignposter(logHandle: diagnosticsLog)

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

    static func logMemory(context: String, detail: String, verbosity: Int = 2) {
        FileManagerUtil.logData(
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
        FileManagerUtil.logData(
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

        FileManagerUtil.logData(
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
        FileManagerUtil.logData(
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
    private let sampleInterval: TimeInterval = 10
    private let trendWindow = 5
    private let warningThresholdMB: Double = 100
    private let criticalThresholdMB: Double = 50

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
        FileManagerUtil.logData(
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
            FileManagerUtil.logData(
                context: "MemoryWatchdog",
                content: "🚨 CRITICAL: available=\(String(format: "%.0f", available))MB resident=\(String(format: "%.0f", resident))MB — app likely to be terminated soon. Declining trend: \(declining)",
                verbosity: 4
            )
        } else if available < warningThresholdMB {
            FileManagerUtil.logData(
                context: "MemoryWatchdog",
                content: "⚠️ WARNING: available=\(String(format: "%.0f", available))MB resident=\(String(format: "%.0f", resident))MB — memory pressure building. Declining trend: \(declining)",
                verbosity: 4
            )
        } else if declining {
            FileManagerUtil.logData(
                context: "MemoryWatchdog",
                content: "Memory declining for \(trendWindow) consecutive samples: available=\(String(format: "%.0f", available))MB resident=\(String(format: "%.0f", resident))MB",
                verbosity: 4
            )
        }
    }
}
