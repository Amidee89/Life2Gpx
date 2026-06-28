import SwiftUI
import SymbolPicker

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var activeTab: IconTab = .symbols
    @State private var typedEmoji = ""
    @State private var sfSymbolBinding = ""

    enum IconTab {
        case symbols, emoji
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activeTab) {
                Text("Symbols").tag(IconTab.symbols)
                Text("Emoji").tag(IconTab.emoji)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch activeTab {
            case .symbols:
                SymbolPicker(symbol: $sfSymbolBinding)
                    .onChange(of: sfSymbolBinding) { _, newValue in
                        if !newValue.isEmpty {
                            selectedIcon = newValue
                        }
                    }
            case .emoji:
                NavigationView {
                    EmojiPickerContent(
                        selectedIcon: $selectedIcon,
                        typedEmoji: $typedEmoji,
                        onSelect: { dismiss() }
                    )
                    .navigationTitle("Choose Emoji")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if !selectedIcon.isEmpty {
                                Button("Clear") {
                                    selectedIcon = ""
                                    dismiss()
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }
        }
        .onAppear {
            if !selectedIcon.isEmpty && !selectedIcon.isEmojiIcon {
                sfSymbolBinding = selectedIcon
            }
        }
    }
}

private struct EmojiPickerContent: View {
    @Binding var selectedIcon: String
    @Binding var typedEmoji: String
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Type or paste one emoji", text: $typedEmoji)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: typedEmoji) { _, newValue in
                        let filtered = newValue.filter { $0.isEmoji }
                        if let first = filtered.first {
                            typedEmoji = String(first)
                        } else if !newValue.isEmpty {
                            typedEmoji = ""
                        }
                    }

                if !typedEmoji.isEmpty {
                    Button("Use") {
                        selectedIcon = typedEmoji
                        onSelect()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            categoryGrid
        }
    }

    private var categoryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                ForEach(EmojiCategory.allCases) { category in
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 8) {
                            ForEach(category.emojis, id: \.self) { emoji in
                                emojiButton(emoji)
                            }
                        }
                    } header: {
                        Text(category.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func emojiButton(_ emoji: String) -> some View {
        Button {
            selectedIcon = emoji
            onSelect()
        } label: {
            Text(emoji)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedIcon == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

enum EmojiCategory: String, CaseIterable, Identifiable {
    case travelPlaces
    case foodDrink
    case buildings
    case activities
    case nature
    case objects
    case flags
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .travelPlaces: return "Travel & Transport"
        case .foodDrink: return "Food & Drink"
        case .buildings: return "Buildings & Landmarks"
        case .activities: return "Activities & Sports"
        case .nature: return "Nature & Weather"
        case .objects: return "Objects"
        case .flags: return "Flags"
        case .people: return "People & Smileys"
        }
    }

    var emojis: [String] {
        switch self {
        case .buildings:
            return [
                "🏠", "🏡", "🏢", "🏣", "🏤", "🏥", "🏦", "🏨",
                "🏩", "🏪", "🏫", "🏬", "🏭", "🏯", "🏰", "💒",
                "🗼", "🗽", "🗾", "⛪", "🕌", "🛕", "🕍", "⛩",
                "🕋", "⛲", "⛺", "🏗", "🧱", "🪨", "🛖", "🏚",
                "🌆", "🌇", "🌃", "🌉", "🎪", "🏟", "🎡", "🎢",
                "🎠", "⛱", "🏖", "🏝", "🏜", "🌋", "⛰", "🏔",
                "🗻", "🏕"
            ]
        case .travelPlaces:
            return [
                "🚗", "🚕", "🚙", "🚌", "🚎", "🏎", "🚓", "🚑",
                "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🛵", "🏍",
                "🛺", "🚲", "🛴", "🚂", "🚆", "🚇", "🚈", "🚉",
                "✈️", "🛫", "🛬", "🛩", "🚀", "🛸", "⛵", "🚤",
                "🛥", "🛳", "⛴", "🚢", "⚓", "🛟", "🗺", "🧭",
                "🗿", "🛤", "⛽", "🚏", "🚦", "🚧", "🛞", "🛶"
            ]
        case .foodDrink:
            return [
                "🍕", "🍔", "🍟", "🌭", "🥪", "🌮", "🌯", "🫔",
                "🥙", "🧆", "🥚", "🍳", "🥘", "🍲", "🫕", "🥣",
                "🥗", "🍿", "🧈", "🧂", "🥫", "🍱", "🍘", "🍙",
                "🍚", "🍛", "🍜", "🍝", "🍠", "🍢", "🍣", "🍤",
                "🍥", "🥮", "🍡", "🥟", "🥠", "🥡", "🦀", "🦞",
                "🦐", "🦑", "🍦", "🍧", "🍨", "🍩", "🍪", "🎂",
                "🍰", "🧁", "🥧", "🍫", "🍬", "🍭", "🍮", "🍯",
                "☕", "🫖", "🍵", "🍶", "🍾", "🍷", "🍸", "🍹",
                "🍺", "🍻", "🥂", "🥃", "🫗", "🥤", "🧋", "🧃",
                "🥛", "🧉"
            ]
        case .activities:
            return [
                "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉",
                "🥏", "🎱", "🏓", "🏸", "🏒", "🥅", "⛳", "🏹",
                "🎣", "🤿", "🥊", "🥋", "🎽", "🛹", "🛼", "🛷",
                "⛸", "🥌", "🎿", "⛷", "🏂", "🏋️", "🤸", "🤼",
                "🤾", "🏌️", "🏇", "🧘", "🏄", "🏊", "🚣", "🧗",
                "🚴", "🚵", "🎭", "🎨", "🎬", "🎤", "🎧", "🎼",
                "🎹", "🥁", "🎷", "🎺", "🎸", "🪕", "🎻", "🎲",
                "♟", "🎯", "🎳", "🎮", "🕹", "🧩"
            ]
        case .nature:
            return [
                "🌸", "💐", "🌷", "🌹", "🥀", "🌺", "🌻", "🌼",
                "🌿", "🍀", "🍁", "🍂", "🍃", "🌱", "🪴", "🌵",
                "🌴", "🌳", "🌲", "🪵", "🍄", "🐚", "🪸", "🪹",
                "🌍", "🌎", "🌏", "🌐", "🌑", "🌒", "🌓", "🌔",
                "🌕", "🌖", "🌗", "🌘", "🌙", "⭐", "🌟", "✨",
                "☀️", "🌤", "⛅", "🌥", "☁️", "🌦", "🌧", "⛈",
                "🌩", "🌨", "❄️", "☃️", "⛄", "🌬", "💨", "🌪",
                "🌫", "🌈", "🔥", "💧", "🌊", "🐶", "🐱", "🐻",
                "🐼", "🦊", "🐰", "🐸", "🐵", "🦁", "🐯", "🐮",
                "🐷", "🐔", "🐧", "🐦", "🦅", "🦆", "🦉", "🐝",
                "🦋", "🐛", "🐌", "🐞", "🐜", "🕷", "🦂", "🐢",
                "🐍", "🦎", "🐊", "🐬", "🐳", "🐋", "🦈", "🐙",
                "🐠", "🐟", "🐡", "🐘", "🦏", "🦛", "🐪", "🐫",
                "🦒", "🐃", "🐂", "🐄", "🐎", "🐖", "🐑", "🦙",
                "🐐", "🦌", "🐕", "🐈", "🐓", "🦃", "🕊", "🐇"
            ]
        case .objects:
            return [
                "📱", "💻", "⌨️", "🖥", "🖨", "🖱", "🖲", "💾",
                "📀", "📷", "📸", "📹", "🎥", "📽", "📺", "📻",
                "📡", "🔭", "🔬", "🩺", "💊", "🩹", "🏧", "💰",
                "💳", "💎", "🔧", "🔨", "⚒", "🛠", "⛏", "🔩",
                "⚙️", "🔑", "🗝", "🔒", "🔓", "🏷", "📦", "📫",
                "📬", "📭", "📮", "🗳", "✏️", "✒️", "🖊", "🖋",
                "📝", "📁", "📂", "📅", "📆", "📌", "📎", "🖇",
                "📏", "📐", "✂️", "🗑", "🛒", "🛍", "🎁", "🎀",
                "🎊", "🎉", "🎈", "🏮", "🎏", "🎐", "🧧", "🪔",
                "🛋", "🪑", "🚪", "🛏", "🛁", "🪥", "🧹", "🧺",
                "🧻", "🪣", "🧴", "🧼", "🪤", "🔫", "🕯", "💡",
                "🔦", "🏮", "📖", "📚", "🔖", "🪪", "🎓", "✈️"
            ]
        case .flags:
            return [
                "🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈", "🏴‍☠️",
                "🇦🇫", "🇦🇱", "🇩🇿", "🇦🇩", "🇦🇴", "🇦🇬", "🇦🇷", "🇦🇲",
                "🇦🇺", "🇦🇹", "🇦🇿", "🇧🇸", "🇧🇭", "🇧🇩", "🇧🇧", "🇧🇾",
                "🇧🇪", "🇧🇿", "🇧🇯", "🇧🇹", "🇧🇴", "🇧🇦", "🇧🇼", "🇧🇷",
                "🇧🇳", "🇧🇬", "🇧🇫", "🇧🇮", "🇨🇻", "🇰🇭", "🇨🇲", "🇨🇦",
                "🇨🇫", "🇹🇩", "🇨🇱", "🇨🇳", "🇨🇴", "🇰🇲", "🇨🇩", "🇨🇬",
                "🇨🇷", "🇭🇷", "🇨🇺", "🇨🇾", "🇨🇿", "🇩🇰", "🇩🇲", "🇩🇴",
                "🇪🇨", "🇪🇬", "🇸🇻", "🇬🇶", "🇪🇷", "🇪🇪", "🇸🇿", "🇪🇹",
                "🇫🇮", "🇫🇷", "🇬🇦", "🇬🇲", "🇬🇪", "🇩🇪", "🇬🇭", "🇬🇷",
                "🇬🇹", "🇬🇳", "🇬🇾", "🇭🇹", "🇭🇳", "🇭🇺", "🇮🇸", "🇮🇳",
                "🇮🇩", "🇮🇷", "🇮🇶", "🇮🇪", "🇮🇱", "🇮🇹", "🇯🇲", "🇯🇵",
                "🇯🇴", "🇰🇿", "🇰🇪", "🇰🇼", "🇱🇧", "🇱🇾", "🇱🇹", "🇱🇺",
                "🇲🇬", "🇲🇾", "🇲🇱", "🇲🇹", "🇲🇽", "🇲🇦", "🇲🇿", "🇲🇲",
                "🇳🇦", "🇳🇵", "🇳🇱", "🇳🇿", "🇳🇬", "🇰🇵", "🇳🇴", "🇴🇲",
                "🇵🇰", "🇵🇦", "🇵🇪", "🇵🇭", "🇵🇱", "🇵🇹", "🇶🇦", "🇷🇴",
                "🇷🇺", "🇸🇦", "🇸🇳", "🇷🇸", "🇸🇬", "🇸🇰", "🇸🇮", "🇿🇦",
                "🇰🇷", "🇪🇸", "🇱🇰", "🇸🇩", "🇸🇪", "🇨🇭", "🇸🇾", "🇹🇼",
                "🇹🇿", "🇹🇭", "🇹🇳", "🇹🇷", "🇺🇦", "🇦🇪", "🇬🇧", "🇺🇸",
                "🇺🇾", "🇻🇪", "🇻🇳", "🇾🇪", "🇿🇲", "🇿🇼"
            ]
        case .people:
            return [
                "😀", "😃", "😄", "😁", "😆", "🥹", "😅", "🤣",
                "😂", "🙂", "🙃", "😉", "😊", "😇", "🥰", "😍",
                "🤩", "😘", "😗", "😚", "😙", "🥲", "😋", "😛",
                "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔",
                "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "🤥",
                "😌", "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕",
                "🤢", "🤮", "🥵", "🥶", "🥴", "😵", "🤯", "🤠",
                "🥳", "🥸", "😎", "🤓", "🧐", "😕", "🫤", "😟",
                "🙁", "😮", "😯", "😲", "😳", "🥺", "🥹", "😦",
                "😧", "😨", "😰", "😥", "😢", "😭", "😱", "😖",
                "😣", "😞", "😓", "😩", "😫", "🥱", "😤", "😡",
                "🤬", "😈", "👿", "💀", "☠️", "💩", "🤡", "👹",
                "👻", "👽", "👾", "🤖", "😺", "😸", "😹", "😻",
                "😼", "😽", "🙀", "😿", "😾", "🙈", "🙉", "🙊",
                "👋", "🤚", "🖐", "✋", "🖖", "🫱", "🫲", "👌",
                "🤌", "🤏", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙",
                "👈", "👉", "👆", "🖕", "👇", "☝️", "🫵", "👍",
                "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶",
                "👐", "🤲", "🤝", "🙏", "💪", "🦾", "🦵", "🦶"
            ]
        }
    }

}
