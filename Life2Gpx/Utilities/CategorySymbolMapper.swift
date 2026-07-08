import Foundation
import UIKit

struct CategoryMapping: Codable, Identifiable {
    let id: String
    var sfSymbol: String
    var emoji: String
    var label: String
    var foursquare: [String]
    var google: [String]
    var yelp: [String]
    var mapbox: [String]
    var here: [String]
    var osm: [String]
    var gaode: [String]
    var apple: [String]

    var displayIcon: String {
        if UIImage(systemName: sfSymbol) != nil {
            return sfSymbol
        }
        return emoji
    }

    var isSFSymbolValid: Bool {
        UIImage(systemName: sfSymbol) != nil
    }
}

class CategorySymbolMapper: ObservableObject {
    static let shared = CategorySymbolMapper()

    @Published var mappings: [CategoryMapping] = []

    private var foursquareIndex: [String: Int] = [:]
    private var googleIndex: [String: Int] = [:]
    private var yelpIndex: [String: Int] = [:]
    private var mapboxIndex: [String: Int] = [:]
    private var hereIndex: [String: Int] = [:]
    private var osmIndex: [String: Int] = [:]
    private var gaodeIndex: [String: Int] = [:]
    private var appleIndex: [String: Int] = [:]

    private var foursquareHexToNumeric: [String: String] = [:]

    private init() {
        loadFoursquareHexMapping()
        loadMappings()
        buildIndexes()
    }

    // MARK: - File Paths

    private var userOverridesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Places/category-icons.json")
    }

    // MARK: - Loading

    private func loadFoursquareHexMapping() {
        guard let url = Bundle.main.url(forResource: "foursquare-personalization-apis-movement-sdk-categories", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        guard let numericUrl = Bundle.main.url(forResource: "foursquare-places-and-apiv3-categories", withExtension: "csv"),
              let numericContent = try? String(contentsOf: numericUrl, encoding: .utf8) else { return }

        var labelToNumericId: [String: String] = [:]
        for line in numericContent.components(separatedBy: .newlines).dropFirst() {
            let cols = parseCSVLine(line)
            guard cols.count >= 2 else { continue }
            let numericId = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let label = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !numericId.isEmpty, !label.isEmpty else { continue }
            labelToNumericId[label] = numericId
        }

        for line in content.components(separatedBy: .newlines).dropFirst() {
            let cols = parseCSVLine(line)
            guard cols.count >= 3 else { continue }
            let hexId = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let label = cols[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hexId.isEmpty, !label.isEmpty else { continue }
            if let numericId = labelToNumericId[label] {
                foursquareHexToNumeric[hexId] = numericId
            }
        }
    }

    private func loadMappings() {
        if let userMappings = loadUserOverrides() {
            mappings = userMappings
            print("[CategorySymbolMapper] Loaded \(mappings.count) user-customized mappings")
            return
        }

        guard let url = Bundle.main.url(forResource: "symbol-map", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[CategorySymbolMapper] symbol-map.json not found in bundle")
            return
        }

        do {
            mappings = try JSONDecoder().decode([CategoryMapping].self, from: data)
            print("[CategorySymbolMapper] Loaded \(mappings.count) default mappings from bundle")
        } catch {
            print("[CategorySymbolMapper] Failed to decode symbol-map.json: \(error)")
        }
    }

    private func loadUserOverrides() -> [CategoryMapping]? {
        guard FileManager.default.fileExists(atPath: userOverridesURL.path),
              let data = try? Data(contentsOf: userOverridesURL) else { return nil }
        return try? JSONDecoder().decode([CategoryMapping].self, from: data)
    }

    // MARK: - Saving

    func saveUserOverrides() {
        let dirURL = userOverridesURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(mappings)
            try data.write(to: userOverridesURL)
            print("[CategorySymbolMapper] Saved user overrides to \(userOverridesURL.path)")
        } catch {
            print("[CategorySymbolMapper] Failed to save overrides: \(error)")
        }
    }

    func resetToDefaults() {
        try? FileManager.default.removeItem(at: userOverridesURL)
        mappings = []
        foursquareIndex = [:]
        googleIndex = [:]
        yelpIndex = [:]
        mapboxIndex = [:]
        hereIndex = [:]
        osmIndex = [:]
        gaodeIndex = [:]
        appleIndex = [:]

        guard let url = Bundle.main.url(forResource: "symbol-map", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        mappings = (try? JSONDecoder().decode([CategoryMapping].self, from: data)) ?? []
        buildIndexes()
    }

    func updateMapping(id: String, sfSymbol: String? = nil, emoji: String? = nil) {
        guard let idx = mappings.firstIndex(where: { $0.id == id }) else { return }
        if let sf = sfSymbol {
            mappings[idx].sfSymbol = sf
        }
        if let em = emoji {
            mappings[idx].emoji = em
        }
        buildIndexes()
        saveUserOverrides()
    }

    // MARK: - Index Building

    private func buildIndexes() {
        foursquareIndex = [:]
        googleIndex = [:]
        yelpIndex = [:]
        mapboxIndex = [:]
        hereIndex = [:]
        osmIndex = [:]
        gaodeIndex = [:]
        appleIndex = [:]

        for (idx, entry) in mappings.enumerated() {
            for id in entry.foursquare { foursquareIndex[id] = idx }
            for id in entry.google { googleIndex[id] = idx }
            for id in entry.yelp { yelpIndex[id] = idx }
            for id in entry.mapbox { mapboxIndex[id] = idx }
            for id in entry.here { hereIndex[id] = idx }
            for id in entry.osm { osmIndex[id] = idx }
            for id in entry.gaode { gaodeIndex[id] = idx }
            for id in entry.apple { appleIndex[id] = idx }
        }
    }

    // MARK: - Resolution

    func resolveIcon(provider: PlaceProvider, categoryIds: [String]) -> String? {
        guard !categoryIds.isEmpty else { return nil }

        let index: [String: Int]
        switch provider {
        case .foursquare: index = foursquareIndex
        case .google: index = googleIndex
        case .yelp: index = yelpIndex
        case .mapbox: index = mapboxIndex
        case .here: index = hereIndex
        case .openStreetMap: index = osmIndex
        case .gaode: index = gaodeIndex
        case .apple: index = appleIndex
        }

        let effectiveIds: [String]
        if provider == .foursquare {
            effectiveIds = categoryIds.flatMap { id -> [String] in
                var ids = [id]
                if let numericId = foursquareHexToNumeric[id] {
                    ids.append(numericId)
                }
                return ids
            }
        } else {
            effectiveIds = categoryIds
        }

        for catId in effectiveIds {
            if let entryIdx = index[catId], entryIdx < mappings.count {
                let entry = mappings[entryIdx]
                if UIImage(systemName: entry.sfSymbol) != nil {
                    return entry.sfSymbol
                }
                if !entry.emoji.isEmpty {
                    return entry.emoji
                }
            }
        }

        return nil
    }


    // MARK: - CSV Parsing (for Foursquare hex mapping)

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
