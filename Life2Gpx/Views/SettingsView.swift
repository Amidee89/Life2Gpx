import SwiftUI

struct SettingsView: View {
    @AppStorage("debugLogVerbosity") private var debugLogVerbosity: Int = SettingsManager.shared.debugLogVerbosity
    @AppStorage("loadCurrentDayOnRestoreAfterValue") private var loadCurrentDayOnRestoreAfterValue: Int = SettingsManager.shared.loadCurrentDayOnRestoreAfterValue
    @AppStorage("loadCurrentDayOnRestoreAfterUnit") private var loadCurrentDayOnRestoreAfterUnit: String = SettingsManager.shared.loadCurrentDayOnRestoreAfterUnit
    @AppStorage("defaultNewPlaceRadius") private var defaultNewPlaceRadius: Int = SettingsManager.shared.defaultNewPlaceRadius

    @FocusState private var valueFieldIsFocused: Bool // Focus state for the TextField

    private let timeUnits = ["seconds", "minutes", "hours", "days"]

    var body: some View {
        Form {
            Section(header: Text("Logging")) {
                Text("Adjust the level of detail for application logs.")
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verbosity Level:")
                        Spacer()
                        Text("\(debugLogVerbosity)")
                    }
                    Slider(value: Binding(
                        get: { Double(debugLogVerbosity) },
                        set: { debugLogVerbosity = Int($0) }
                    ), in: 0...5, step: 1)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("0: None - No logs").font(.caption)
                        Text("1: Errors - Only critical errors").font(.caption)
                        Text("2: Warnings - Errors and warnings").font(.caption)
                        Text("3: Info - Basic operational information").font(.caption)
                        Text("4: Debug - Detailed debugging information").font(.caption)
                        Text("5: Trace - Highly detailed tracing").font(.caption)
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 5)
                }
                .padding(.vertical)
            }
            
            Section(header: Text("App Behaviour")) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Auto-load current day after")
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            TextField("Value", value: $loadCurrentDayOnRestoreAfterValue, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .frame(maxWidth: 80)
                                .focused($valueFieldIsFocused) // Apply focus state
                            
                            Picker("", selection: $loadCurrentDayOnRestoreAfterUnit) {
                                ForEach(timeUnits, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .fixedSize(horizontal: true, vertical: false)
                            .labelsHidden()
                            
                            Spacer()
                        }
                        
                        Text("The app will load today's data if it has been in the background for longer than this interval.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Default new place radius (meters)")
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("\(defaultNewPlaceRadius)")
                            Spacer()
                        }
                        Slider(value: Binding(
                            get: { Double(defaultNewPlaceRadius) },
                            set: { defaultNewPlaceRadius = Int($0) }
                        ), in: 10...1000, step: 10)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Settings")
        .toolbar { 
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    valueFieldIsFocused = false
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
} 
