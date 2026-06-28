import Foundation
import UIKit
import os

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
