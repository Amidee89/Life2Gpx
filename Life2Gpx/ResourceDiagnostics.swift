import Foundation
import UIKit
import os

enum ResourceDiagnostics {
    static func memorySnapshot() -> String {
        var taskInfo = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let taskInfoResult = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let residentMB: String
        if taskInfoResult == KERN_SUCCESS {
            residentMB = String(format: "%.1f", Double(taskInfo.resident_size) / 1_048_576)
        } else {
            residentMB = "unknown"
        }

        let availableMB = String(format: "%.1f", Double(os_proc_available_memory()) / 1_048_576)
        return "resident=\(residentMB)MB available=\(availableMB)MB"
    }

    static func logMemory(context: String, detail: String, verbosity: Int = 2) {
        FileManagerUtil.logData(
            context: context,
            content: "\(detail) \(memorySnapshot())",
            verbosity: verbosity
        )
    }
}
