import SwiftUI

struct SettingsView: View {
    @AppStorage("debugLogVerbosity") private var debugLogVerbosity: Int = SettingsManager.shared.debugLogVerbosity
    @AppStorage("loadCurrentDayOnRestoreAfterValue") private var loadCurrentDayOnRestoreAfterValue: Int = SettingsManager.shared.loadCurrentDayOnRestoreAfterValue
    @AppStorage("loadCurrentDayOnRestoreAfterUnit") private var loadCurrentDayOnRestoreAfterUnit: String = SettingsManager.shared.loadCurrentDayOnRestoreAfterUnit
    @AppStorage("defaultNewPlaceRadius") private var defaultNewPlaceRadius: Int = SettingsManager.shared.defaultNewPlaceRadius
    @AppStorage("filterSmallRoundTrips") private var filterSmallRoundTrips: Bool = SettingsManager.shared.filterSmallRoundTrips
    @AppStorage("roundTripMaxPoints") private var roundTripMaxPoints: Int = SettingsManager.shared.roundTripMaxPoints
    @AppStorage("roundTripUnknownRadius") private var roundTripUnknownRadius: Int = SettingsManager.shared.roundTripUnknownRadius

    @FocusState private var valueFieldIsFocused: Bool

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
            
            Section(header: Text("Filter Small Round Trip Tracks")) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Filter small round trip tracks", isOn: $filterSmallRoundTrips)
                    
                    Text("Do not save small tracks that end up in the same place as the starting point (often caused by GPS location errors).")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if filterSmallRoundTrips {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Max points in filtered track")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(roundTripMaxPoints)")
                            }
                            Slider(value: Binding(
                                get: { Double(roundTripMaxPoints) },
                                set: { roundTripMaxPoints = Int($0) }
                            ), in: 1...10, step: 1)
                            
                            Text("Round trip tracks above this number of points will be saved.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Unknown location round trip radius (meters)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(roundTripUnknownRadius)")
                            }
                            Slider(value: Binding(
                                get: { Double(roundTripUnknownRadius) },
                                set: { roundTripUnknownRadius = Int($0) }
                            ), in: 10...1000, step: 10)
                            
                            Text("Radius from a starting unknown location to consider track as a round trip.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
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
