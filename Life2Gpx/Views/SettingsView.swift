import SwiftUI

struct SettingsView: View {
    // Directly use AppStorage to bind to the UserDefaults value managed by SettingsManager
    // Ensure the key matches the one used in SettingsManager
    @AppStorage("debugLogVerbosity") private var debugLogVerbosity: Int = SettingsManager.shared.debugLogVerbosity

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
                    
                    // Explanation of levels
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
                .padding(.vertical) // Add some vertical padding for the VStack content
            }
        }
        .navigationTitle("Settings")
        // Optional: Add a navigation bar title display mode if desired
        // .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView { // Wrap in NavigationView for preview context
        SettingsView()
    }
} 