import SwiftUI
import CoreGPX

struct SettingsGPXFilesView: View {
    @AppStorage("gpxExportSettings") private var exportSettings: GPXExportSettings = SettingsManager.shared.gpxExportSettings
    
    @State private var selectedElement: Int = 0
    
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
            
            Section(header: Text("Basic Attributes")) {
                let binding = getBinding(for: selectedElement)
                Toggle("Name", isOn: binding.name)
                Toggle("Comment", isOn: binding.comment)
                Toggle("Description", isOn: binding.desc)
                Toggle("Source", isOn: binding.source)
                Toggle("Type", isOn: binding.type)
                Toggle("Links", isOn: binding.links)
                
                if selectedElement == 0 || selectedElement == 2 {
                    Toggle("Magnetic Variation", isOn: binding.magneticVariation)
                    Toggle("Geoid Height", isOn: binding.geoidHeight)
                    Toggle("Symbol", isOn: binding.symbol)
                    Toggle("Fix", isOn: binding.fix)
                    Toggle("Satellites", isOn: binding.satellites)
                    Toggle("Horizontal Dilution", isOn: binding.horizontalDilution)
                    Toggle("Vertical Dilution", isOn: binding.verticalDilution)
                    Toggle("Position Dilution", isOn: binding.positionDilution)
                    Toggle("Age of DGPS Data", isOn: binding.ageofDGPSData)
                    Toggle("DGPS ID", isOn: binding.DGPSid)
                }
                
                if selectedElement == 1 {
                    Toggle("Number", isOn: binding.number)
                }
            }
            
            Section(header: Text("Extensions")) {
                let binding = getBinding(for: selectedElement)
                if selectedElement == 0 {
                    ForEach(GPXExtensionKey.waypointCases) { ext in
                        let extBinding = Binding<Bool>(
                            get: { binding.wrappedValue.extensions[ext.rawValue] ?? true },
                            set: { binding.wrappedValue.extensions[ext.rawValue] = $0 }
                        )
                        Toggle(ext.rawValue, isOn: extBinding)
                    }
                } else if selectedElement == 2 {
                    ForEach(GPXExtensionKey.trackpointCases) { ext in
                        let extBinding = Binding<Bool>(
                            get: { binding.wrappedValue.extensions[ext.rawValue] ?? true },
                            set: { binding.wrappedValue.extensions[ext.rawValue] = $0 }
                        )
                        Toggle(ext.rawValue, isOn: extBinding)
                    }
                } else {
                    Text("No standard extensions for tracks")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("GPX Files")
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
