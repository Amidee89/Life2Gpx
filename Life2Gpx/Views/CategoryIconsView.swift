import SwiftUI
import SymbolPicker

struct CategoryIconsView: View {
    @ObservedObject private var mapper = CategorySymbolMapper.shared
    @State private var editingMapping: CategoryMapping?
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section {
                Text("These icons are automatically assigned to new places based on their category from place providers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                ForEach(mapper.mappings) { mapping in
                    Button {
                        editingMapping = mapping
                    } label: {
                        HStack(spacing: 12) {
                            iconDisplay(for: mapping)
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapping.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                HStack(spacing: 4) {
                                    Text(mapping.sfSymbol)
                                        .font(.caption2)
                                        .foregroundColor(mapping.isSFSymbolValid ? .secondary : .red)
                                    if !mapping.emoji.isEmpty {
                                        Text("· \(mapping.emoji)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                }
                .confirmationDialog("Reset all category icons to their defaults?", isPresented: $showingResetConfirmation) {
                    Button("Reset", role: .destructive) {
                        mapper.resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .navigationTitle("Category Icons")
        .sheet(item: $editingMapping) { mapping in
            EditCategoryIconSheet(mapping: mapping) { updatedSymbol, updatedEmoji in
                mapper.updateMapping(id: mapping.id, sfSymbol: updatedSymbol, emoji: updatedEmoji)
                editingMapping = nil
            }
        }
    }

    @ViewBuilder
    private func iconDisplay(for mapping: CategoryMapping) -> some View {
        if mapping.isSFSymbolValid {
            Image(systemName: mapping.sfSymbol)
                .font(.title3)
                .foregroundColor(.accentColor)
        } else if !mapping.emoji.isEmpty {
            Text(mapping.emoji)
                .font(.title3)
        } else {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundColor(.red)
        }
    }
}

struct EditCategoryIconSheet: View {
    let mapping: CategoryMapping
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sfSymbol: String
    @State private var emoji: String
    @State private var activeTab: IconTab = .symbols

    enum IconTab {
        case symbols, emoji
    }

    init(mapping: CategoryMapping, onSave: @escaping (String, String) -> Void) {
        self.mapping = mapping
        self.onSave = onSave
        _sfSymbol = State(initialValue: mapping.sfSymbol)
        _emoji = State(initialValue: mapping.emoji)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                currentPreview
                    .padding()

                Picker("", selection: $activeTab) {
                    Text("SF Symbol").tag(IconTab.symbols)
                    Text("Emoji").tag(IconTab.emoji)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch activeTab {
                case .symbols:
                    SymbolPicker(symbol: $sfSymbol)
                case .emoji:
                    emojiInput
                }
            }
            .navigationTitle(mapping.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(sfSymbol, emoji)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var currentPreview: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                if UIImage(systemName: sfSymbol) != nil {
                    Image(systemName: sfSymbol)
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                }
                Text("Symbol")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80)

            VStack(spacing: 4) {
                if !emoji.isEmpty {
                    Text(emoji)
                        .font(.largeTitle)
                } else {
                    Text("—")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
                Text("Emoji Fallback")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var emojiInput: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Paste or type one emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .onChange(of: emoji) { newValue in
                        let filtered = newValue.filter { $0.isEmoji }
                        if let first = filtered.first {
                            emoji = String(first)
                        } else if !newValue.isEmpty {
                            emoji = ""
                        }
                    }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            Text("The emoji is used as a fallback when the SF Symbol is unavailable on older iOS versions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }
}

#Preview {
    NavigationView {
        CategoryIconsView()
    }
}
