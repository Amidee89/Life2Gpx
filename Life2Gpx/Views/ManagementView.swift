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
                NavigationLink(destination: CategoryIconsView()) {
                    Text("Category Icons")
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
    @Environment(\.colorScheme) private var colorScheme
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
                        Image(provider.iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .offset(x: provider == .openStreetMap ? 2 : 0, y: provider == .openStreetMap ? 2 : 0)
                            .frame(width: 24, height: 24, alignment: .center)
                            .clipped()
                            .padding(3)
                            .background(Circle().fill(colorScheme == .dark ? Color(white: 0.88) : Color.white))
                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            .clipShape(Circle())

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
                                    SecureField(provider.apiKeyLabel, text: binding)
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
