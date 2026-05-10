//
//  SettingsView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 17.10.2024.
//

import SwiftUI

struct ManagementView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: ManagePlacesView()) {
                    Text("Manage places")
                }
                NavigationLink(destination: FindDuplicatesView()) {
                    Text("Find duplicate places")
                }
                NavigationLink(destination: ImportPlacesView()) {
                        Text("Import places")
                }
                .overlay(alignment: .trailing) {
                    
                }
                NavigationLink(destination: APIKeysView()) {
                    Text("API Keys")
                }
                Text("Edit activity rules")
                Text("GPX Tidy up")
                NavigationLink(destination: SettingsView()) {
                    Text("Settings")
                }
                Text("Data import instructions")
            }
            .navigationTitle("Options")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct APIKeysView: View {
    @State private var providerOrder: [PlaceProvider] = SettingsManager.shared.placeProviderOrder
    @State private var apiKeys: [PlaceProvider: String] = {
        var keys = [PlaceProvider: String]()
        for provider in PlaceProvider.allCases {
            keys[provider] = SettingsManager.shared.apiKey(for: provider)
        }
        return keys
    }()
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        Form {
            Section {
                Text("Drag to reorder search priority. First provider with a key is used by default.")
                    .font(.caption)
                    .foregroundColor(.gray)

                ForEach(providerOrder) { provider in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(provider.color)
                            Text(provider.initial)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.subheadline.weight(.medium))

                            if provider.requiresApiKey {
                                HStack {
                                    let binding = Binding<String>(
                                        get: { apiKeys[provider] ?? "" },
                                        set: { newValue in
                                            apiKeys[provider] = newValue
                                            SettingsManager.shared.setApiKey(newValue, for: provider)
                                        }
                                    )
                                    SecureField("API Key", text: binding)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.caption)
                                        .focused($fieldIsFocused)

                                    if let url = provider.apiKeyURL {
                                        Link(destination: url) {
                                            Image(systemName: "key.fill")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            } else {
                                Text("No API key required")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    providerOrder.move(fromOffsets: source, toOffset: destination)
                    SettingsManager.shared.placeProviderOrder = providerOrder
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("API Keys")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldIsFocused = false }
            }
        }
    }
}

#Preview {
    ManagementView()
}
