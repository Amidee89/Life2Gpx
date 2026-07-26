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
                Section {
                    NavigationLink(destination: SettingsView()) {
                        Text("Settings")
                    }
                }
                
                Section(header: Text("Places")) {
                    NavigationLink(destination: ManagePlacesView()) {
                        Text("Manage places")
                    }
                    NavigationLink(destination: FindDuplicatesView()) {
                        Text("Find duplicate places")
                    }
                    NavigationLink(destination: APIKeysView()) {
                        Text("Place data providers API keys")
                    }
                }
                
                Section(header: Text("Customization")) {
                    NavigationLink(destination: CategoryIconsView()) {
                        Text("Category items")
                    }
                    NavigationLink(destination: TrackTypesSettingsView()) {
                        Text("Track types")
                    }
                    NavigationLink(destination: ActivityRulesListView()) {
                        Text("Track activity rules")
                    }
                    NavigationLink(destination: SettingsGPXFilesView()) {
                        Text("GPX Files")
                    }
                }
                
                Section {
                    NavigationLink(destination: ImportSubmenuView()) {
                        Text("Import")
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct ImportSubmenuView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data import instructions")
                        .font(.headline)
                    Text("To start importing places, place Life2Gpx places.json files in the Import folder or the Place folder of an Arc backup in Import/Arc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("To import GPX files, place them in the app's main folder. The GPX import will sort them into year folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                NavigationLink(destination: ImportPlacesView()) {
                    Text("Import places")
                }
                NavigationLink(destination: FileManagementView()) {
                    Text("Import GPX")
                }
                NavigationLink(destination: EmptyView()) {
                    Text("Import Arc Backups")
                }
            }
        }
        .navigationTitle("Import")
    }
}

struct FileManagementView: View {
    @State private var showOrganizeResult = false
    @State private var organizeResultMessage = ""
    @State private var askToOrganize = SettingsManager.shared.askToOrganizeGpxFiles
    @State private var overwriteExisting = SettingsManager.shared.gpxOverwriteExisting
    @State private var conflictChoice = SettingsManager.shared.gpxConflictResolution

    var body: some View {
        Form {
            Section {
                Button(action: {
                    let result = FileManagerUtil.shared.organizeGpxFiles(
                        conflictResolution: SettingsManager.shared.effectiveGpxConflictResolution
                    )
                    if result.moved == 0 && result.duplicates == 0 && result.failed == 0 {
                        organizeResultMessage = "No GPX files found in the main folder to organize."
                    } else {
                        var parts: [String] = []
                        if result.moved > 0 {
                            parts.append("Moved \(result.moved) file\(result.moved == 1 ? "" : "s") into year folders.")
                        }
                        if result.duplicates > 0 {
                            parts.append("\(result.duplicates) duplicate\(result.duplicates == 1 ? "" : "s") moved to Duplicates folder.")
                        }
                        if result.failed > 0 {
                            parts.append("\(result.failed) file\(result.failed == 1 ? "" : "s") failed.")
                        }
                        organizeResultMessage = parts.joined(separator: " ")
                    }
                    showOrganizeResult = true
                }) {
                    Text("Sort GPX files in main folder")
                }
            }

            Section("Conflict Resolution") {
                Toggle("Overwrite existing files", isOn: $overwriteExisting)
                    .onChange(of: overwriteExisting) { _, newValue in
                        SettingsManager.shared.gpxOverwriteExisting = newValue
                    }
                
                if !overwriteExisting {
                    Picker("When a file already exists", selection: $conflictChoice) {
                        Text("Keep existing").tag(FileManagerUtil.ConflictResolution.keepExisting)
                        Text("Replace existing").tag(FileManagerUtil.ConflictResolution.replaceExisting)
                    }
                    .pickerStyle(.inline)
                    .onChange(of: conflictChoice) { _, newValue in
                        SettingsManager.shared.gpxConflictResolution = newValue
                    }
                    
                    Text(conflictChoice == .keepExisting
                         ? "The incoming file will be moved to the Duplicates folder."
                         : "The file already in the year folder will be moved to the Duplicates folder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Toggle("Ask to organize GPX files on startup", isOn: $askToOrganize)
                    .onChange(of: askToOrganize) { _, newValue in
                        SettingsManager.shared.askToOrganizeGpxFiles = newValue
                    }
            }
        }
        .navigationTitle("File Management")
        .alert("Organize GPX Files", isPresented: $showOrganizeResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(organizeResultMessage)
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
import SwiftUI
import SymbolPicker

struct TrackTypesSettingsView: View {
    @ObservedObject var preferencesManager = PreferencesManager.shared
    @State private var showingAddType = false
    @State private var newTypeId = ""
    @State private var newTypeName = ""
    @State private var newTypeColor = Color.blue
    @State private var newTypeIcon = "figure.walk"
    
    var body: some View {
        List {
            Section(header: Text("Track Types")) {
                ForEach($preferencesManager.trackTypes) { $trackType in
                    NavigationLink(destination: EditTrackTypeView(trackType: $trackType)) {
                        HStack {
                            PlaceIconView(icon: trackType.icon, fallbackColor: trackType.color)
                                .frame(width: 30)
                            Text(trackType.name)
                            Spacer()
                            if trackType.isDefault {
                                Text("Default")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteTrackType)
            }
        }
        .navigationTitle("Track Types")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddType = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddType) {
            NavigationView {
                Form {
                    Section("New Track Type") {
                        TextField("ID (e.g. custom_walk)", text: $newTypeId)
                            .autocapitalization(.none)
                        TextField("Name", text: $newTypeName)
                        ColorPicker("Color", selection: $newTypeColor)
                        HStack {
                            Text("Icon")
                            Spacer()
                            PlaceIconView(icon: newTypeIcon, fallbackColor: newTypeColor)
                            NavigationLink("Change") {
                                IconPickerView(selectedIcon: $newTypeIcon)
                            }
                        }
                    }
                }
                .navigationTitle("Add Track Type")
                .navigationBarItems(
                    leading: Button("Cancel") { showingAddType = false },
                    trailing: Button("Save") {
                        let newType = TrackType(
                            id: newTypeId.isEmpty ? UUID().uuidString : newTypeId,
                            name: newTypeName.isEmpty ? "New Type" : newTypeName,
                            colorHex: newTypeColor.toHex() ?? "#000000",
                            icon: newTypeIcon.isEmpty ? "questionmark" : newTypeIcon,
                            isDefault: false
                        )
                        preferencesManager.trackTypes.append(newType)
                        showingAddType = false
                        
                        // Reset fields
                        newTypeId = ""
                        newTypeName = ""
                        newTypeColor = .blue
                        newTypeIcon = "figure.walk"
                    }
                    .disabled(newTypeName.isEmpty)
                )
            }
        }
    }
    
    private func deleteTrackType(at offsets: IndexSet) {
        // Prevent deleting default types
        let itemsToDelete = offsets.map { preferencesManager.trackTypes[$0] }
        if itemsToDelete.contains(where: { $0.isDefault }) {
            // Optional: show an alert here
            return
        }
        preferencesManager.trackTypes.remove(atOffsets: offsets)
    }
}

struct EditTrackTypeView: View {
    @Binding var trackType: TrackType
    @State private var color: Color
    
    init(trackType: Binding<TrackType>) {
        self._trackType = trackType
        self._color = State(initialValue: trackType.wrappedValue.color)
    }
    
    var body: some View {
        Form {
            Section("Edit Track Type") {
                TextField("Name", text: $trackType.name)
                ColorPicker("Color", selection: $color)
                    .onChange(of: color) { _, newColor in
                        if let hex = newColor.toHex() {
                            trackType.colorHex = hex
                        }
                    }
                HStack {
                    Text("Icon")
                    Spacer()
                    PlaceIconView(icon: trackType.icon, fallbackColor: color)
                    NavigationLink("Change") {
                        IconPickerView(selectedIcon: $trackType.icon)
                    }
                }
            }
            if trackType.isDefault {
                Section {
                    Text("This is a default track type. You can edit its appearance, but you cannot delete it or change its ID.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(trackType.name)
    }
}
