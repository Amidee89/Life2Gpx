import SwiftUI
import Charts

struct RangeSlider: View {
    @Binding var range: ClosedRange<Date>
    let bounds: ClosedRange<Date>
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let totalTime = bounds.upperBound.timeIntervalSince(bounds.lowerBound)
            
            // Avoid division by zero if bounds are identical
            let safeTotalTime = totalTime > 0 ? totalTime : 1.0
            
            // X positions
            let startFraction = CGFloat(range.lowerBound.timeIntervalSince(bounds.lowerBound) / safeTotalTime)
            let endFraction = CGFloat(range.upperBound.timeIntervalSince(bounds.lowerBound) / safeTotalTime)
            
            let startX = startFraction * width
            let endX = endFraction * width
            let midY = geometry.size.height / 2.0
            
            ZStack(alignment: .topLeading) {
                // Background track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: width, height: 6)
                    .cornerRadius(3)
                    .position(x: width / 2.0, y: midY)
                
                // Active track
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: max(0, endX - startX), height: 6)
                    .cornerRadius(3)
                    .position(x: startX + (endX - startX) / 2.0, y: midY)
                
                // Left handle
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 24, height: 24)
                    .position(x: startX, y: midY)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("SliderSpace"))
                            .onChanged { value in
                                let newFraction = min(max(0, value.location.x / width), 1)
                                let newTime = bounds.lowerBound.addingTimeInterval(safeTotalTime * Double(newFraction))
                                if newTime < range.upperBound {
                                    range = newTime...range.upperBound
                                } else {
                                    range = range.upperBound...range.upperBound
                                }
                            }
                    )
                
                // Right handle
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 24, height: 24)
                    .position(x: endX, y: midY)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("SliderSpace"))
                            .onChanged { value in
                                let newFraction = min(max(0, value.location.x / width), 1)
                                let newTime = bounds.lowerBound.addingTimeInterval(safeTotalTime * Double(newFraction))
                                if newTime > range.lowerBound {
                                    range = range.lowerBound...newTime
                                } else {
                                    range = range.lowerBound...range.lowerBound
                                }
                            }
                    )
            }
            .coordinateSpace(name: "SliderSpace")
        }
        .frame(height: 24)
    }
}

struct ResourceUsageView: View {
    @State private var availableFiles: [URL] = []
    @State private var selectedFileURL: URL?
    @State private var events: [ResourceEvent] = []
    @State private var isLoading: Bool = false
    
    @State private var availableContexts: [String] = []
    @State private var enabledContexts: Set<String> = []
    
    @State private var selectedTimeMemory: Date? = nil
    @State private var selectedTimeExecution: Date? = nil
    @State private var selectedTimeThermal: Date? = nil
    @State private var selectedTimeCPU: Date? = nil
    
    @State private var selectedStatsRange: ClosedRange<Date>? = nil
    
    private let isPreview: Bool
    
    init(previewEvents: [ResourceEvent]? = nil) {
        if let previewEvents = previewEvents {
            self._events = State(initialValue: previewEvents)
            self._availableFiles = State(initialValue: [URL(fileURLWithPath: "/preview.jsonl")])
            self._selectedFileURL = State(initialValue: URL(fileURLWithPath: "/preview.jsonl"))
            
            let contexts = Set(previewEvents.compactMap { $0.executionTimeSeconds != nil ? $0.context : nil })
            self._availableContexts = State(initialValue: Array(contexts).sorted())
            self._enabledContexts = State(initialValue: contexts)
            self.isPreview = true
        } else {
            self.isPreview = false
        }
    }
    
    private var fullDayDomain: ClosedRange<Date>? {
        guard let first = events.first?.timestamp, let last = events.last?.timestamp, first < last else {
            return nil
        }
        return first...last
    }
    
    private var chartXScaleDomain: ClosedRange<Date>? {
        if let range = selectedStatsRange {
            return range
        }
        return fullDayDomain
    }
    
    private var chartEvents: [ResourceEvent] {
        if let range = selectedStatsRange {
            return events.filter { range.contains($0.timestamp) }
        }
        return events
    }
    
    private var contextStats: [(context: String, count: Int, totalTime: Double, cpuTime: Double, batteryEstimate: Double)] {
        var stats: [String: (count: Int, time: Double, cpuTime: Double, batteryEstimate: Double)] = [:]
        
        let filteredEvents = chartEvents
        
        for event in filteredEvents {
            let time = event.executionTimeSeconds ?? 0
            let cpuUsage = event.cpuUsagePercentage ?? 0
            
            // cpuUsage is out of 100%. CPU Time is seconds spent at 100% equivalent.
            let cpuTime = time * (cpuUsage / 100.0)
            
            // Rough estimate: 1 hour of 100% CPU drains ~15% battery.
            // So 1 second of 100% CPU drains 15 / 3600 = 0.00416% battery.
            let batteryEstimate = cpuTime * (15.0 / 3600.0)
            
            if let existing = stats[event.context] {
                stats[event.context] = (count: existing.count + 1, time: existing.time + time, cpuTime: existing.cpuTime + cpuTime, batteryEstimate: existing.batteryEstimate + batteryEstimate)
            } else {
                stats[event.context] = (count: 1, time: time, cpuTime: cpuTime, batteryEstimate: batteryEstimate)
            }
        }
        return stats.map { (context: $0.key, count: $0.value.count, totalTime: $0.value.time, cpuTime: $0.value.cpuTime, batteryEstimate: $0.value.batteryEstimate) }
            .sorted { $0.totalTime > $1.totalTime }
    }
    
    var body: some View {
        VStack {
            if availableFiles.isEmpty {
                Text("No resource logs available.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                Picker("Select Day", selection: $selectedFileURL) {
                    ForEach(availableFiles, id: \.self) { url in
                        Text(formatDateFromFilename(url.lastPathComponent)).tag(url as URL?)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .onChange(of: selectedFileURL) { _, newURL in
                    if let url = newURL {
                        loadEvents(from: url)
                    }
                }
                
                if isLoading {
                    ProgressView()
                } else if events.isEmpty {
                    Text("No data for this day.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    
                    if let fullDomain = fullDayDomain {
                        VStack(spacing: 4) {
                            Text("Filter Time Range")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            RangeSlider(
                                range: Binding(
                                    get: { selectedStatsRange ?? fullDomain },
                                    set: { newValue in
                                        if abs(newValue.lowerBound.timeIntervalSince(fullDomain.lowerBound)) < 1 &&
                                           abs(newValue.upperBound.timeIntervalSince(fullDomain.upperBound)) < 1 {
                                            selectedStatsRange = nil
                                        } else {
                                            selectedStatsRange = newValue
                                        }
                                    }
                                ),
                                bounds: fullDomain
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            
                            HStack {
                                Text((selectedStatsRange ?? fullDomain).lowerBound.formatted(date: .omitted, time: .shortened))
                                Spacer()
                                Text((selectedStatsRange ?? fullDomain).upperBound.formatted(date: .omitted, time: .shortened))
                            }
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 10)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    
                    ScrollView {
                        VStack(spacing: 30) {
                            
                            // STATS TABLE
                            VStack(alignment: .leading) {
                                Text("Summary")
                                    .font(.headline)
                                    .padding(.horizontal)
                                

                                
                                Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 10) {
                                    GridRow {
                                        Text("Context").bold()
                                        Text("Events").bold()
                                        Text("Tot Time").bold()
                                        Text("CPU Time").bold()
                                        Text("Battery %").bold()
                                    }
                                    Divider()
                                    ForEach(contextStats, id: \.context) { stat in
                                        GridRow {
                                            Text(stat.context).lineLimit(1).minimumScaleFactor(0.8)
                                            Text("\(stat.count)")
                                            Text(String(format: "%.1fs", stat.totalTime))
                                            Text(String(format: "%.2fs", stat.cpuTime))
                                            Text(String(format: "%.4f%%", stat.batteryEstimate))
                                        }
                                    }
                                }
                                .font(.caption)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            }
                            
                            // MEMORY CHART
                            VStack(alignment: .leading) {
                                Text("Memory Used (MB)")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                Chart {
                                    ForEach(chartEvents, id: \.timestamp) { event in
                                        LineMark(
                                            x: .value("Time", event.timestamp),
                                            y: .value("Memory", event.memoryResidentMB)
                                        )
                                        .foregroundStyle(event.isBackground ? .purple : .blue)
                                        
                                        if let selected = selectedTimeMemory, Calendar.current.isDate(selected, equalTo: event.timestamp, toGranularity: .minute) {
                                            RuleMark(x: .value("Time", selected))
                                                .foregroundStyle(Color.gray.opacity(0.3))
                                            PointMark(
                                                x: .value("Time", event.timestamp),
                                                y: .value("Memory", event.memoryResidentMB)
                                            )
                                            .annotation(position: .top) {
                                                VStack {
                                                    Text("\(String(format: "%.0f", event.memoryResidentMB)) MB")
                                                        .font(.caption).bold()
                                                    Text(event.isBackground ? "Background" : "Foreground")
                                                        .font(.caption2)
                                                }
                                                .padding(4)
                                                .background(Color(.systemBackground).opacity(0.8))
                                                .cornerRadius(4)
                                            }
                                        }
                                    }
                                }
                                .chartXScale(domain: chartXScaleDomain ?? Date()...Date().addingTimeInterval(1))
                                .chartXSelection(value: $selectedTimeMemory)
                                .clipped()
                                .frame(height: 200)
                                .padding(.horizontal)
                                
                                HStack {
                                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                                    Text("Foreground").font(.caption2)
                                    Circle().fill(Color.purple).frame(width: 8, height: 8)
                                    Text("Background").font(.caption2)
                                }.padding(.horizontal)
                            }
                            
                            // CPU CHART
                            if events.contains(where: { $0.cpuUsagePercentage != nil }) {
                                VStack(alignment: .leading) {
                                    Text("CPU Usage (%)")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    Chart {
                                        ForEach(chartEvents.filter { $0.cpuUsagePercentage != nil }, id: \.timestamp) { event in
                                            LineMark(
                                                x: .value("Time", event.timestamp),
                                                y: .value("CPU", event.cpuUsagePercentage!)
                                            )
                                            .foregroundStyle(.pink)
                                            
                                            if let selected = selectedTimeCPU, Calendar.current.isDate(selected, equalTo: event.timestamp, toGranularity: .minute) {
                                                RuleMark(x: .value("Time", selected))
                                                    .foregroundStyle(Color.gray.opacity(0.3))
                                                    .annotation(position: .top) {
                                                        Text("\(String(format: "%.1f", event.cpuUsagePercentage!))%")
                                                            .font(.caption).bold()
                                                            .padding(4)
                                                            .background(Color(.systemBackground).opacity(0.8))
                                                            .cornerRadius(4)
                                                    }
                                            }
                                        }
                                    }
                                    .chartXScale(domain: chartXScaleDomain ?? Date()...Date().addingTimeInterval(1))
                                    .chartXSelection(value: $selectedTimeCPU)
                                    .clipped()
                                    .frame(height: 200)
                                    .padding(.horizontal)
                                }
                            }
                            
                            // EXECUTION TIME CHART
                            if !availableContexts.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("Execution Time (Seconds)")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack {
                                            ForEach(availableContexts, id: \.self) { context in
                                                Toggle(context, isOn: Binding(
                                                    get: { enabledContexts.contains(context) },
                                                    set: { isEnabled in
                                                        if isEnabled { enabledContexts.insert(context) }
                                                        else { enabledContexts.remove(context) }
                                                    }
                                                ))
                                                .toggleStyle(.button)
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .padding(.bottom, 8)
                                    
                                    Chart {
                                        let filteredEvents = chartEvents.filter { $0.executionTimeSeconds != nil && enabledContexts.contains($0.context) }
                                        ForEach(filteredEvents, id: \.timestamp) { event in
                                            LineMark(
                                                x: .value("Time", event.timestamp),
                                                y: .value("Execution Time", event.executionTimeSeconds!),
                                                series: .value("Context", event.context)
                                            )
                                            .foregroundStyle(by: .value("Context", event.context))
                                            
                                            PointMark(
                                                x: .value("Time", event.timestamp),
                                                y: .value("Execution Time", event.executionTimeSeconds!)
                                            )
                                            .foregroundStyle(by: .value("Context", event.context))
                                            
                                            if let selected = selectedTimeExecution, Calendar.current.isDate(selected, equalTo: event.timestamp, toGranularity: .minute) {
                                                RuleMark(x: .value("Time", selected))
                                                    .foregroundStyle(Color.gray.opacity(0.3))
                                                    .annotation(position: .top) {
                                                        VStack(alignment: .leading) {
                                                            Text("\(String(format: "%.3f", event.executionTimeSeconds!))s")
                                                                .font(.caption).bold()
                                                            Text(event.context)
                                                                .font(.caption2)
                                                            if let extraInfo = event.extraInfo {
                                                                ForEach(extraInfo.keys.sorted(), id: \.self) { key in
                                                                    Text("\(key): \(extraInfo[key]!)")
                                                                        .font(.system(size: 8))
                                                                        .foregroundColor(.gray)
                                                                }
                                                            }
                                                        }
                                                        .padding(4)
                                                        .background(Color(.systemBackground).opacity(0.8))
                                                        .cornerRadius(4)
                                                    }
                                            }
                                        }
                                    }
                                    .chartXScale(domain: chartXScaleDomain ?? Date()...Date().addingTimeInterval(1))
                                    .chartXSelection(value: $selectedTimeExecution)
                                    .clipped()
                                    .frame(height: 200)
                                    .padding(.horizontal)
                                }
                            }
                            
                            // THERMAL STATE CHART
                            VStack(alignment: .leading) {
                                Text("Thermal State")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                Chart {
                                    ForEach(chartEvents, id: \.timestamp) { event in
                                        LineMark(
                                            x: .value("Time", event.timestamp),
                                            y: .value("Thermal", thermalStateValue(event.thermalState))
                                        )
                                        .foregroundStyle(Color.gray.opacity(0.5))
                                        
                                        PointMark(
                                            x: .value("Time", event.timestamp),
                                            y: .value("Thermal", thermalStateValue(event.thermalState))
                                        )
                                        .foregroundStyle(thermalStateColor(event.thermalState))
                                        
                                        if let selected = selectedTimeThermal, Calendar.current.isDate(selected, equalTo: event.timestamp, toGranularity: .minute) {
                                            RuleMark(x: .value("Time", selected))
                                                .foregroundStyle(Color.gray.opacity(0.3))
                                                .annotation(position: .top) {
                                                    Text(event.thermalState.capitalized)
                                                        .font(.caption).bold()
                                                        .padding(4)
                                                        .background(Color(.systemBackground).opacity(0.8))
                                                        .cornerRadius(4)
                                                }
                                        }
                                    }
                                }
                                .chartXScale(domain: chartXScaleDomain ?? Date()...Date().addingTimeInterval(1))
                                .chartXSelection(value: $selectedTimeThermal)
                                .clipped()
                                .chartYAxis {
                                    AxisMarks(values: [0, 1, 2, 3]) { value in
                                        AxisValueLabel {
                                            if let intVal = value.as(Int.self) {
                                                Text(thermalStateName(intVal))
                                            }
                                        }
                                    }
                                }
                                .frame(height: 150)
                                .padding(.horizontal)
                            }
                            
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationTitle("Resource Usage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !isPreview {
                loadAvailableFiles()
            }
        }
    }
    
    private func loadAvailableFiles() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let resourcesDirectory = documentsURL.appendingPathComponent("Logs/Resources")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: resourcesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }
        availableFiles = jsonlFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }
        
        if let first = availableFiles.first {
            selectedFileURL = first
            loadEvents(from: first)
        }
    }
    
    private func loadEvents(from url: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedEvents: [ResourceEvent] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            if let data = try? Data(contentsOf: url),
               let string = String(data: data, encoding: .utf8) {
                let lines = string.components(separatedBy: .newlines)
                for line in lines {
                    guard !line.isEmpty else { continue }
                    if let lineData = line.data(using: .utf8),
                       let event = try? decoder.decode(ResourceEvent.self, from: lineData) {
                        loadedEvents.append(event)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.events = loadedEvents.sorted { $0.timestamp < $1.timestamp }
                
                let contexts = Set(self.events.compactMap { $0.executionTimeSeconds != nil ? $0.context : nil })
                self.availableContexts = Array(contexts).sorted()
                self.enabledContexts = contexts
                
                self.isLoading = false
            }
        }
    }
    
    private func formatDateFromFilename(_ filename: String) -> String {
        let prefix = filename.replacingOccurrences(of: "-resources.jsonl", with: "")
        return prefix
    }
    
    private func thermalStateValue(_ state: String) -> Int {
        switch state {
        case "nominal": return 0
        case "fair": return 1
        case "serious": return 2
        case "critical": return 3
        default: return 0
        }
    }
    
    private func thermalStateColor(_ state: String) -> Color {
        switch state {
        case "nominal": return .green
        case "fair": return .yellow
        case "serious": return .orange
        case "critical": return .red
        default: return .gray
        }
    }
    
    private func thermalStateName(_ value: Int) -> String {
        switch value {
        case 0: return "Nominal"
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Unknown"
        }
    }
}

#Preview {
    let now = Date()
    let mockEvents = [
        ResourceEvent(timestamp: now.addingTimeInterval(-3600), context: "LocationUpdate", batteryLevel: 0.8, batteryState: "unplugged", thermalState: "nominal", memoryResidentMB: 120.0, memoryAvailableMB: 500.0, executionTimeSeconds: 0.5, isBackground: true, cpuUsagePercentage: 20.0, extraInfo: ["Locations Received": "5"]),
        ResourceEvent(timestamp: now.addingTimeInterval(-1800), context: "LocationUpdate", batteryLevel: 0.78, batteryState: "unplugged", thermalState: "nominal", memoryResidentMB: 125.0, memoryAvailableMB: 495.0, executionTimeSeconds: 0.8, isBackground: true, cpuUsagePercentage: 35.0, extraInfo: ["Locations Received": "8"]),
        ResourceEvent(timestamp: now.addingTimeInterval(-900), context: "TimelineLoad", batteryLevel: 0.77, batteryState: "unplugged", thermalState: "fair", memoryResidentMB: 200.0, memoryAvailableMB: 400.0, executionTimeSeconds: 2.5, isBackground: false, cpuUsagePercentage: 85.0, extraInfo: nil),
        ResourceEvent(timestamp: now, context: "LocationUpdate", batteryLevel: 0.75, batteryState: "unplugged", thermalState: "nominal", memoryResidentMB: 130.0, memoryAvailableMB: 490.0, executionTimeSeconds: 0.4, isBackground: false, cpuUsagePercentage: 15.0, extraInfo: ["Locations Received": "3"])
    ]
    
    return NavigationView {
        ResourceUsageView(previewEvents: mockEvents)
    }
}
