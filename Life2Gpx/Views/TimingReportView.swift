import SwiftUI

struct TimingReportView: View {
    let timingReport: [TimerEntry]
    let startTime: Date?
    let endTime: Date?
    
    var body: some View {
        Section("Performance Report") {
            if let startTime = startTime, let endTime = endTime {
                Text("Total time: \(endTime.timeIntervalSince(startTime).formatted(.number.precision(.fractionLength(1)))) seconds")
                    .font(.headline)
            }
            
            ForEach(timingReport.filter { $0.parent == nil }) { entry in
                TimerEntryView(entry: entry, allEntries: timingReport, depth: 0)
            }
        }
    }
}

private struct TimerEntryView: View {
    let entry: TimerEntry
    let allEntries: [TimerEntry]
    let depth: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.id)
                    .padding(.leading, CGFloat(depth) * 16)
                Spacer()
                Text("\(entry.duration.formatted(.number.precision(.fractionLength(1))))s")
                    .monospacedDigit()
            }
            .foregroundStyle(depth == 0 ? .primary : .secondary)
            
            ForEach(allEntries.filter { $0.parent == entry.id }) { childEntry in
                TimerEntryView(entry: childEntry, allEntries: allEntries, depth: depth + 1)
            }
        }
    }
} 