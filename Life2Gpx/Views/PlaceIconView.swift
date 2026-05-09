import SwiftUI
import UIKit

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

extension String {
    var isEmojiIcon: Bool {
        guard let first = first else { return false }
        return first.isEmoji
    }

    var firstEmojiCharacter: String {
        guard let first = first(where: { $0.isEmoji }) else { return "" }
        return String(first)
    }

    /// Resolves a potentially messy icon string to a single valid icon.
    /// Handles: valid SF symbol names, emoji characters, multiple emojis
    /// (takes the first one), or garbage (returns nil).
    var resolvedPlaceIcon: ResolvedIcon? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.isEmojiIcon {
            let emoji = trimmed.firstEmojiCharacter
            return emoji.isEmpty ? nil : .emoji(emoji)
        }

        if UIImage(systemName: trimmed) != nil {
            return .sfSymbol(trimmed)
        }

        // Maybe someone crammed multiple SF symbol names separated by spaces
        let parts = trimmed.components(separatedBy: .whitespaces)
        for part in parts {
            if UIImage(systemName: part) != nil {
                return .sfSymbol(part)
            }
        }

        // Last resort: look for any emoji character buried in the string
        let emoji = trimmed.firstEmojiCharacter
        if !emoji.isEmpty {
            return .emoji(emoji)
        }

        return nil
    }
}

enum ResolvedIcon {
    case sfSymbol(String)
    case emoji(String)
}

struct PlaceIconView: View {
    let icon: String?
    var font: Font = .title2
    var fallbackColor: Color = .gray

    var body: some View {
        switch icon?.resolvedPlaceIcon {
        case .emoji(let ch):
            Text(ch)
                .font(font)
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(font)
                .foregroundColor(fallbackColor)
        case nil:
            Image(systemName: "smallcircle.filled.circle")
                .font(font)
                .foregroundColor(fallbackColor)
        }
    }
}
