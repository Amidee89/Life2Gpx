import SwiftUI
import SymbolPicker

struct SettingsTrackTypesView: View {
    @ObservedObject var preferencesManager = PreferencesManager.shared
    @State private var showingAddType = false
    @State private var newTypeId = ""
    @State private var newTypeName = ""
    @State private var newTypeColor = Color.blue
    @State private var newTypeIcon = "figure.walk"
    
    var body: some View {
        List {
            ForEach(TrackTypeCategory.allCases) { category in
                if category == .otherWorkouts {
                    Section(header: Text("Other Activities")) {
                        NavigationLink(destination: OtherActivitiesView()) {
                            HStack {
                                Image(systemName: "figure.strengthtraining.functional")
                                    .frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text("Other Activities")
                                        .font(.body)
                                    Text("Activities confined in a place")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(preferencesManager.trackTypes.filter { $0.category == .otherWorkouts }.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    let matchingTypes = preferencesManager.trackTypes.filter { $0.category == category }
                    if !matchingTypes.isEmpty {
                        Section(header: Text(category.rawValue)) {
                            ForEach($preferencesManager.trackTypes) { $trackType in
                                if trackType.category == category {
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
                            }
                            .onDelete { offsets in
                                deleteTrackTypes(at: offsets, in: category)
                            }
                        }
                    }
                }
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
    
    private func deleteTrackTypes(at offsets: IndexSet, in category: TrackTypeCategory) {
        let matchingIndices = preferencesManager.trackTypes.enumerated().compactMap { index, type in
            type.category == category ? index : nil
        }
        let realIndices = offsets.map { matchingIndices[$0] }
        let itemsToDelete = realIndices.map { preferencesManager.trackTypes[$0] }
        if itemsToDelete.contains(where: { $0.isDefault }) {
            return
        }
        for index in realIndices.sorted(by: >) {
            preferencesManager.trackTypes.remove(at: index)
        }
    }
}

/// Alias for backward compatibility
typealias TrackTypesSettingsView = SettingsTrackTypesView

struct EditTrackTypeView: View {
    @Binding var trackType: TrackType
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var preferencesManager = PreferencesManager.shared
    @State private var color: Color
    @State private var showingDeleteConfirmation = false
    
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
            } else {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Activity")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(trackType.name)
        .confirmationDialog("Are you sure you want to delete this custom activity?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Activity", role: .destructive) {
                if let index = preferencesManager.trackTypes.firstIndex(where: { $0.id == trackType.id }) {
                    preferencesManager.trackTypes.remove(at: index)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

#Preview {
    NavigationView {
        SettingsTrackTypesView()
    }
}

struct TrackTypePickerView: View {
    @Binding var selectedId: String
    @ObservedObject var prefs = PreferencesManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(TrackTypeCategory.allCases) { category in
                let matchingTypes = prefs.trackTypes.filter { $0.category == category }
                if !matchingTypes.isEmpty {
                    Section(header: Text(category.displayName)) {
                        ForEach(matchingTypes) { type in
                            Button {
                                selectedId = type.id
                                dismiss()
                            } label: {
                                HStack {
                                    PlaceIconView(icon: type.icon, fallbackColor: type.color)
                                        .frame(width: 24)
                                    Text(type.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if type.id.lowercased() == selectedId.lowercased() {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Track Type")
        .navigationBarTitleDisplayMode(.inline)
    }
}

