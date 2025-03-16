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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.id)
                        Spacer()
                        Text("\(entry.duration.formatted(.number.precision(.fractionLength(1))))s")
                            .monospacedDigit()
                    }
                    
                    ForEach(timingReport.filter { $0.parent == entry.id }) { childEntry in
                        HStack {
                            Text(childEntry.id)
                                .foregroundStyle(.secondary)
                                .padding(.leading)
                            Spacer()
                            Text("\(childEntry.duration.formatted(.number.precision(.fractionLength(1))))s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
} 