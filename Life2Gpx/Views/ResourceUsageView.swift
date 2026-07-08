import SwiftUI
import Charts

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
                    ScrollView {
                        VStack(spacing: 30) {
                            
                            // MEMORY CHART
                            VStack(alignment: .leading) {
                                Text("Memory Used (MB)")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                Chart {
                                    ForEach(events, id: \.timestamp) { event in
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
                                .chartXSelection(value: $selectedTimeMemory)
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
                                        ForEach(events.filter { $0.cpuUsagePercentage != nil }, id: \.timestamp) { event in
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
                                    .chartXSelection(value: $selectedTimeCPU)
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
                                        let filteredEvents = events.filter { $0.executionTimeSeconds != nil && enabledContexts.contains($0.context) }
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
                                    .chartXSelection(value: $selectedTimeExecution)
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
                                    ForEach(events, id: \.timestamp) { event in
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
                                .chartXSelection(value: $selectedTimeThermal)
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
            loadAvailableFiles()
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
