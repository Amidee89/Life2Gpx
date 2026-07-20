import SwiftUI
import CoreGPX

struct FieldToggleRow: View {
    let title: String
    @Binding var state: GPXFieldState
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 20) {
                Toggle("GPX", isOn: $state.export)
                    .labelsHidden()
                    .tint(.green)
                
                Toggle("UI", isOn: $state.visible)
                    .labelsHidden()
                    .tint(.blue)
            }
        }
    }
}

struct SettingsGPXFilesView: View {
    @AppStorage("gpxExportSettings") private var exportSettings: GPXExportSettings = SettingsManager.shared.gpxExportSettings
    
    @State private var selectedElement: Int = 0
    @State private var showingInfo = false
    
    var body: some View {
        Form {
            Section {
                Picker("Element", selection: $selectedElement) {
                    Text("Waypoints").tag(0)
                    Text("Tracks").tag(1)
                    Text("Trackpoints").tag(2)
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: 
                HStack {
                    Text("Basic Attributes")
                    Spacer()
                    HStack(spacing: 20) {
                        Text("GPX").frame(width: 51, alignment: .center)
                        Text("UI").frame(width: 51, alignment: .center)
                    }
                    .padding(.trailing, 20)
                }
            ) {
                let binding = getBinding(for: selectedElement)
                FieldToggleRow(title: "Name", state: binding.name)
                FieldToggleRow(title: "Comment", state: binding.comment)
                FieldToggleRow(title: "Description", state: binding.desc)
                FieldToggleRow(title: "Source", state: binding.source)
                FieldToggleRow(title: "Type", state: binding.type)
                FieldToggleRow(title: "Links", state: binding.links)
                
                if selectedElement == 0 || selectedElement == 2 {
                    FieldToggleRow(title: "Magnetic Variation", state: binding.magneticVariation)
                    FieldToggleRow(title: "Geoid Height", state: binding.geoidHeight)
                    FieldToggleRow(title: "Symbol", state: binding.symbol)
                    FieldToggleRow(title: "Fix", state: binding.fix)
                    FieldToggleRow(title: "Satellites", state: binding.satellites)
                    FieldToggleRow(title: "Horizontal Dilution", state: binding.horizontalDilution)
                    FieldToggleRow(title: "Vertical Dilution", state: binding.verticalDilution)
                    FieldToggleRow(title: "Position Dilution", state: binding.positionDilution)
                    FieldToggleRow(title: "Age of DGPS Data", state: binding.ageofDGPSData)
                    FieldToggleRow(title: "DGPS ID", state: binding.DGPSid)
                }
                
                if selectedElement == 1 {
                    FieldToggleRow(title: "Number", state: binding.number)
                }
            }
            
            Section(header: Text("Extensions")) {
                let binding = getBinding(for: selectedElement)
                if selectedElement == 0 {
                    ForEach(GPXExtensionKey.waypointCases) { ext in
                        let extBinding = Binding<GPXFieldState>(
                            get: { binding.wrappedValue.extensions[ext.rawValue] ?? GPXFieldState(export: true, visible: false) },
                            set: { binding.wrappedValue.extensions[ext.rawValue] = $0 }
                        )
                        FieldToggleRow(title: ext.rawValue, state: extBinding)
                    }
                } else if selectedElement == 2 {
                    ForEach(GPXExtensionKey.trackpointCases) { ext in
                        let extBinding = Binding<GPXFieldState>(
                            get: { binding.wrappedValue.extensions[ext.rawValue] ?? GPXFieldState(export: true, visible: false) },
                            set: { binding.wrappedValue.extensions[ext.rawValue] = $0 }
                        )
                        FieldToggleRow(title: ext.rawValue, state: extBinding)
                    }
                } else {
                    Text("No standard extensions for tracks")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("GPX Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text("GPX Files")
                        .font(.headline)
                    Button(action: {
                        showingInfo = true
                    }) {
                        Image(systemName: "info.circle")
                    }
                    .popover(isPresented: $showingInfo) {
                        Text("Define which data, when available, is saved in the GPX files (green) and which fields are available by default in the edit view (blue).")
                            .font(.body)
                            .padding()
                            .frame(width: 280)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }
    
    private func getBinding(for index: Int) -> Binding<GPXExportFields> {
        switch index {
        case 0:
            return $exportSettings.waypoints
        case 1:
            return $exportSettings.tracks
        case 2:
            return $exportSettings.trackpoints
        default:
            return $exportSettings.waypoints
        }
    }
}
