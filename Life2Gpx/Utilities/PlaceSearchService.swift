import Foundation
import SwiftUI
import CoreLocation
import MapKit

enum PlaceProvider: String, CaseIterable, Identifiable, Codable {
    case google
    case foursquare
    case yelp
    case mapbox
    case apple
    case openStreetMap
    case here
    case gaode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google Places"
        case .foursquare: return "Foursquare"
        case .yelp: return "Yelp"
        case .mapbox: return "Mapbox"
        case .apple: return "Apple Maps"
        case .openStreetMap: return "OpenStreetMap"
        case .here: return "HERE"
        case .gaode: return "Gaode (China)"
        }
    }

    var iconAssetName: String {
        switch self {
        case .google: return "ProviderGoogle"
        case .foursquare: return "ProviderFoursquare"
        case .yelp: return "ProviderYelp"
        case .mapbox: return "ProviderMapbox"
        case .apple: return "ProviderApple"
        case .openStreetMap: return "ProviderOpenstreetmap"
        case .here: return "ProviderHERE"
        case .gaode: return "ProviderGaode"
        }
    }

    var initial: String {
        switch self {
        case .google: return "G"
        case .foursquare: return "4"
        case .yelp: return "Y"
        case .mapbox: return "M"
        case .apple: return "A"
        case .openStreetMap: return "O"
        case .here: return "H"
        case .gaode: return "高"
        }
    }

    /// Whether place-search input/output uses GCJ-02 for this provider.
    /// Gaode is always GCJ-02. Apple and Google follow the current map tile system (device in China).
    var usesGcj02ForPlaceSearch: Bool {
        switch self {
        case .gaode: return true
        case .apple, .google: return CoordinateConverter.mapUsesGcj02
        case .foursquare, .yelp, .mapbox, .openStreetMap, .here: return false
        }
    }

    var color: Color {
        switch self {
        case .google: return Color(red: 0.86, green: 0.27, blue: 0.22)
        case .foursquare: return Color(red: 0.2, green: 0.2, blue: 1.0)
        case .yelp: return Color(red: 0.83, green: 0.14, blue: 0.14)
        case .mapbox: return Color(red: 0.26, green: 0.39, blue: 0.98)
        case .apple: return Color(red: 0.0, green: 0.0, blue: 0.0)
        case .openStreetMap: return Color(red: 0.49, green: 0.73, blue: 0.25)
        case .here: return Color(red: 0.28, green: 0.82, blue: 0.6)
        case .gaode: return Color(red: 0.13, green: 0.47, blue: 0.96)
        }
    }

    var apiKeyURL: URL? {
        switch self {
        case .google: return URL(string: "https://console.cloud.google.com/google/maps-apis/start?ref=https%3A%2F%2Fdevelopers.google.com%2Fmaps%2F")!
        case .foursquare: return URL(string: "https://foursquare.com/developers/apps")!
        case .yelp: return URL(string: "https://www.yelp.com/developers/v3/manage_app")!
        case .mapbox: return URL(string: "https://account.mapbox.com/access-tokens/")!
        case .apple: return nil
        case .openStreetMap: return nil
        case .here: return URL(string: "https://platform.here.com/admin/apps")!
        case .gaode: return URL(string: "https://console.amap.com/dev/key/app")!
        }
    }

    var apiKeyLabel: String {
        switch self {
        case .gaode: return "Web服务"
        case .foursquare: return "Service Key"
        default: return "API Key"
        }
    }

    var maxResultsLimit: Int {
        switch self {
        case .mapbox: return 10
        case .google: return 20
        case .gaode: return 25
        case .foursquare, .yelp: return 50
        case .here: return 100
        case .apple, .openStreetMap: return 50
        }
    }

    var requiresApiKey: Bool {
        switch self {
        case .apple, .openStreetMap: return false
        default: return true
        }
    }

    var settingsKey: String {
        return "placesApiKey_\(rawValue)"
    }

    func externalIdKeyPath(for place: Place) -> String? {
        switch self {
        case .google: return place.googlePlacesId
        case .foursquare: return place.foursquareVenueId
        case .yelp: return place.yelpId
        case .mapbox: return place.mapboxPlaceId
        case .apple: return place.applePlaceId
        case .openStreetMap: return place.osmNodeId
        case .here: return place.herePlaceId
        case .gaode: return place.gaodePlaceId
        }
    }
}

struct PlaceSearchResult: Identifiable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let provider: PlaceProvider
    let foursquareCategoryId: String?
    let categoryIds: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var resolvedIcon: String? {
        CategorySymbolMapper.shared.resolveIcon(provider: provider, categoryIds: categoryIds)
    }
}

private enum Constants {
    static let logTruncationMaxLength = 200
}

class PlaceSearchService {
    static let shared = PlaceSearchService()
    private init() {}

    private func log(_ provider: PlaceProvider, _ message: String, verbosity: Int) {
        FileManagerUtil.logData(context: "PlaceSearch-\(provider.rawValue)", content: message, verbosity: verbosity)
    }

    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    private func formatQuery(_ query: String?) -> String {
        guard let query, !query.isEmpty else { return "<nearby>" }
        return "\"\(query)\""
    }

    private func truncateForLog(_ value: String, maxLength: Int = Constants.logTruncationMaxLength) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength)) + "..."
    }

    private func formatRadius(_ radiusMeters: Double) -> String {
        if radiusMeters >= 1000 {
            return String(format: "%.0f km", radiusMeters / 1000)
        }
        return String(format: "%.0f m", radiusMeters)
    }

    private func summarizeUserInfo(_ userInfo: [String: Any]) -> String {
        guard !userInfo.isEmpty else { return "none" }

        return userInfo.keys.sorted().compactMap { key in
            guard let value = userInfo[key] else { return nil }
            let summary = truncateForLog(String(describing: value), maxLength: 160)
            return "\(key)=\(summary)"
        }
        .joined(separator: ", ")
    }

    private func mapKitErrorHint(for error: NSError) -> String? {
        guard error.domain == MKErrorDomain else { return nil }

        switch error.code {
        case 1:
            return "MapKit unknown error"
        case 2:
            return "MapKit server failure"
        case 3:
            return "MapKit loading throttled"
        case 4:
            return "MapKit placemarkNotFound; Apple Maps could not resolve a place or placemark for the request area/query"
        case 5:
            return "MapKit directionsNotFound"
        case 6:
            return "MapKit decodingFailed"
        default:
            return "MapKit error code \(error.code)"
        }
    }

    private func summarize(error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            parts.append("reason=\(failureReason)")
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            parts.append("recovery=\(recoverySuggestion)")
        }
        if let hint = mapKitErrorHint(for: nsError) {
            parts.append("hint=\(hint)")
        }
        if !nsError.userInfo.isEmpty {
            parts.append("userInfo=\(summarizeUserInfo(nsError.userInfo))")
        }

        return parts.joined(separator: ", ")
    }

    private func appleNoResultsMessage(query: String?, radiusMeters: Double) -> String {
        let radiusText = formatRadius(radiusMeters)

        if let query, !query.isEmpty {
            return "No Apple Maps matches found for \"\(query)\" within \(radiusText) of this point."
        }

        return "No Apple Maps places found within \(radiusText) of this point."
    }

    func search(near coordinate: CLLocationCoordinate2D, provider: PlaceProvider, query: String? = nil, limit: Int = 10) async throws -> [PlaceSearchResult] {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuery = (trimmedQuery?.isEmpty ?? true) ? nil : trimmedQuery
        let effectiveLimit = min(limit, provider.maxResultsLimit)

        log(
            provider,
            "Starting search. coordinate=\(formatCoordinate(coordinate)), query=\(formatQuery(effectiveQuery)), requestedLimit=\(limit), effectiveLimit=\(effectiveLimit)",
            verbosity: 4
        )

        let searchCoordinate = provider.usesGcj02ForPlaceSearch
            ? CoordinateConverter.wgs84ToGcj02(coordinate)
            : coordinate
        if searchCoordinate.latitude != coordinate.latitude || searchCoordinate.longitude != coordinate.longitude {
            log(
                provider,
                "Search coordinate shifted for GCJ-02. wgs84=\(formatCoordinate(coordinate)), gcj02=\(formatCoordinate(searchCoordinate))",
                verbosity: 4
            )
        }

        let results: [PlaceSearchResult]

        do {
            if provider == .apple {
                results = try await searchApple(coordinate: searchCoordinate, query: effectiveQuery, limit: effectiveLimit)
            } else if provider == .openStreetMap {
                results = try await searchOpenStreetMap(coordinate: searchCoordinate, query: effectiveQuery, limit: effectiveLimit)
            } else {
                guard let apiKey = getApiKey(for: provider), !apiKey.isEmpty else {
                    throw PlaceSearchError.noApiKey
                }

                switch provider {
                case .google: results = try await searchGoogle(coordinate: searchCoordinate, apiKey: apiKey, query: effectiveQuery, limit: effectiveLimit)
                case .foursquare: results = try await searchFoursquare(coordinate: searchCoordinate, apiKey: apiKey, query: effectiveQuery, limit: effectiveLimit)
                case .yelp: results = try await searchYelp(coordinate: searchCoordinate, apiKey: apiKey, query: effectiveQuery, limit: effectiveLimit)
                case .mapbox: results = try await searchMapbox(coordinate: searchCoordinate, apiKey: apiKey, query: effectiveQuery, limit: effectiveLimit)
                case .here: results = try await searchHERE(coordinate: searchCoordinate, apiKey: apiKey, query: effectiveQuery, limit: effectiveLimit)
                case .gaode: results = try await searchGaode(coordinate: searchCoordinate, apiKey: apiKey, query: effectiveQuery, limit: effectiveLimit)
                case .apple, .openStreetMap: results = []
                }
            }
        } catch {
            log(
                provider,
                "Search failed. coordinate=\(formatCoordinate(coordinate)), query=\(formatQuery(effectiveQuery)), effectiveLimit=\(effectiveLimit), \(summarize(error: error))",
                verbosity: 1
            )
            throw error
        }

        // GCJ-02 search results → WGS-84 for storage
        if provider.usesGcj02ForPlaceSearch {
            let convertedResults = results.map { result in
                let converted = CoordinateConverter.gcj02ToWgs84(result.coordinate)
                return PlaceSearchResult(
                    id: result.id,
                    name: result.name,
                    address: result.address,
                    latitude: converted.latitude,
                    longitude: converted.longitude,
                    provider: result.provider,
                    foursquareCategoryId: result.foursquareCategoryId,
                    categoryIds: result.categoryIds
                )
            }
            log(
                provider,
                "Search completed with coordinate conversion. rawResults=\(results.count), returnedResults=\(convertedResults.count)",
                verbosity: 4
            )
            return convertedResults
        }

        log(provider, "Search completed. returnedResults=\(results.count)", verbosity: 4)
        return results
    }

    func findExistingPlace(for result: PlaceSearchResult) -> Place? {
        let allPlaces = PlaceManager.shared.getAllPlaces()
        return allPlaces.first { place in
            switch result.provider {
            case .google: return place.googlePlacesId == result.id
            case .foursquare: return place.foursquareVenueId == result.id
            case .yelp: return place.yelpId == result.id
            case .mapbox: return place.mapboxPlaceId == result.id
            case .apple: return place.applePlaceId == result.id
            case .openStreetMap: return place.osmNodeId == result.id
            case .here: return place.herePlaceId == result.id
            case .gaode: return place.gaodePlaceId == result.id
            }
        }
    }

    private func getApiKey(for provider: PlaceProvider) -> String? {
        UserDefaults.standard.string(forKey: provider.settingsKey)
    }

    static func configuredProviders() -> [PlaceProvider] {
        let order = SettingsManager.shared.placeProviderOrder
        return order.filter { provider in
            if !provider.requiresApiKey { return true }
            guard let key = UserDefaults.standard.string(forKey: provider.settingsKey) else { return false }
            return !key.isEmpty
        }
    }

    // MARK: - Google Places

    private func searchGoogle(coordinate: CLLocationCoordinate2D, apiKey: String, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json")!
        components.queryItems = [
            URLQueryItem(name: "location", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: query != nil ? "\(SettingsManager.shared.placeSearchKeywordRadius)" : "\(SettingsManager.shared.placeSearchDefaultRadius)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let query = query {
            components.queryItems?.append(URLQueryItem(name: "keyword", value: query))
        }

        let url = components.url!
        log(.google, "Request URL: \(url.absoluteString.replacingOccurrences(of: apiKey, with: "***"))", verbosity: 4)

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as? HTTPURLResponse
        log(.google, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let status = json?["status"] as? String {
            log(.google, "API status: \(status)", verbosity: 4)
            if let errorMessage = json?["error_message"] as? String {
                log(.google, "Error message: \(errorMessage)", verbosity: 2)
            }
            if status != "OK" && status != "ZERO_RESULTS" {
                throw PlaceSearchError.apiError("Google Places: \(status) - \(json?["error_message"] as? String ?? "unknown error")")
            }
        }

        guard let results = json?["results"] as? [[String: Any]] else {
            log(.google, "No 'results' array in response. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")", verbosity: 2)
            return []
        }
        log(.google, "Got \(results.count) results", verbosity: 4)

        return results.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let placeId = item["place_id"] as? String,
                  let name = item["name"] as? String,
                  let geometry = item["geometry"] as? [String: Any],
                  let location = geometry["location"] as? [String: Any],
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double else { return nil }

            let vicinity = item["vicinity"] as? String
            let types = item["types"] as? [String] ?? []
            return PlaceSearchResult(id: placeId, name: name, address: vicinity,
                                     latitude: lat, longitude: lng,
                                     provider: .google, foursquareCategoryId: nil,
                                     categoryIds: types)
        }
    }

    // MARK: - Foursquare

    private func searchFoursquare(coordinate: CLLocationCoordinate2D, apiKey: String, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://places-api.foursquare.com/places/search")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: query != nil ? "\(SettingsManager.shared.placeSearchKeywordRadius)" : "\(SettingsManager.shared.placeSearchDefaultRadius)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let query = query {
            components.queryItems?.append(URLQueryItem(name: "query", value: query))
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-17", forHTTPHeaderField: "X-Places-Api-Version")

        log(.foursquare, "Request URL: \(components.url!.absoluteString)", verbosity: 4)
        log(.foursquare, "Auth: Bearer token (key length: \(apiKey.count))", verbosity: 5)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        log(.foursquare, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        if let bodyStr = String(data: data.prefix(500), encoding: .utf8) {
            log(.foursquare, "Response body (first 500 chars): \(bodyStr)", verbosity: 5)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            log(.foursquare, "No 'results' array in response. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")", verbosity: 2)
            if let message = json?["message"] as? String {
                throw PlaceSearchError.apiError("Foursquare: \(message)")
            }
            return []
        }
        log(.foursquare, "Got \(results.count) results", verbosity: 4)

        return results.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let fsqId = item["fsq_place_id"] as? String,
                  let name = item["name"] as? String,
                  let lat = item["latitude"] as? Double,
                  let lng = item["longitude"] as? Double else { return nil }

            let location = item["location"] as? [String: Any]
            let address = location?["formatted_address"] as? String

            var categoryId: String? = nil
            var allCategoryIds: [String] = []
            if let categories = item["categories"] as? [[String: Any]] {
                for cat in categories {
                    if let catId = cat["fsq_category_id"] as? String {
                        if categoryId == nil { categoryId = catId }
                        allCategoryIds.append(catId)
                    }
                }
            }

            return PlaceSearchResult(id: fsqId, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .foursquare, foursquareCategoryId: categoryId,
                                     categoryIds: allCategoryIds)
        }
    }

    // MARK: - Yelp

    private func searchYelp(coordinate: CLLocationCoordinate2D, apiKey: String, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://api.yelp.com/v3/businesses/search")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: query != nil ? "\(SettingsManager.shared.placeSearchKeywordRadius)" : "\(SettingsManager.shared.placeSearchDefaultRadius)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let query = query {
            components.queryItems?.append(URLQueryItem(name: "term", value: query))
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        log(.yelp, "Request URL: \(components.url!.absoluteString)", verbosity: 4)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        log(.yelp, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let businesses = json?["businesses"] as? [[String: Any]] else {
            log(.yelp, "No 'businesses' array. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")", verbosity: 2)
            return []
        }
        log(.yelp, "Got \(businesses.count) results", verbosity: 4)

        return businesses.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let yelpId = item["id"] as? String,
                  let name = item["name"] as? String,
                  let coords = item["coordinates"] as? [String: Any],
                  let lat = coords["latitude"] as? Double,
                  let lng = coords["longitude"] as? Double else { return nil }

            let location = item["location"] as? [String: Any]
            let displayAddress = location?["display_address"] as? [String]
            let address = displayAddress?.joined(separator: ", ")

            var categoryAliases: [String] = []
            if let categories = item["categories"] as? [[String: Any]] {
                for cat in categories {
                    if let alias = cat["alias"] as? String {
                        categoryAliases.append(alias)
                    }
                }
            }

            return PlaceSearchResult(id: yelpId, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .yelp, foursquareCategoryId: nil,
                                     categoryIds: categoryAliases)
        }
    }

    // MARK: - Mapbox

    private func searchMapbox(coordinate: CLLocationCoordinate2D, apiKey: String, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        var components: URLComponents
        if let query = query {
            components = URLComponents(string: "https://api.mapbox.com/search/searchbox/v1/forward")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "proximity", value: "\(coordinate.longitude),\(coordinate.latitude)"),
                URLQueryItem(name: "access_token", value: apiKey),
                URLQueryItem(name: "types", value: "poi"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        } else {
            components = URLComponents(string: "https://api.mapbox.com/search/searchbox/v1/reverse")!
            components.queryItems = [
                URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
                URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
                URLQueryItem(name: "access_token", value: apiKey),
                URLQueryItem(name: "types", value: "poi"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        }

        log(.mapbox, "Request URL: \(components.url!.absoluteString.replacingOccurrences(of: apiKey, with: "***"))", verbosity: 4)

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        log(.mapbox, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let features = json?["features"] as? [[String: Any]] else {
            log(.mapbox, "No 'features' array. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")", verbosity: 2)
            return []
        }
        log(.mapbox, "Got \(features.count) results", verbosity: 4)

        return features.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let properties = item["properties"] as? [String: Any],
                  let mapboxId = properties["mapbox_id"] as? String,
                  let name = properties["name"] as? String else { return nil }

            let geometry = item["geometry"] as? [String: Any]
            let coordinates = geometry?["coordinates"] as? [Double]
            let lng = coordinates?.first ?? coordinate.longitude
            let lat = coordinates?.last ?? coordinate.latitude

            let address = properties["full_address"] as? String ?? properties["address"] as? String
            let poiCategoryIds = properties["poi_category_ids"] as? [String] ?? []
            return PlaceSearchResult(id: mapboxId, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .mapbox, foursquareCategoryId: nil,
                                     categoryIds: poiCategoryIds)
        }
    }

    // MARK: - OpenStreetMap (Overpass API)

    private func searchOpenStreetMap(coordinate: CLLocationCoordinate2D, query searchQuery: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        let radius = searchQuery != nil ? SettingsManager.shared.placeSearchKeywordRadius : SettingsManager.shared.placeSearchDefaultRadius
        let nameFilter = searchQuery.map { "\"name\"~\"\($0)\",i" } ?? "\"name\""
        let query = """
        [out:json][timeout:10];
        (
          node(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))[~"^(amenity|shop|tourism|leisure|office|craft)$"~"."][\(nameFilter)];
          way(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))[~"^(amenity|shop|tourism|leisure|office|craft)$"~"."][\(nameFilter)];
        );
        out center body \(limit);
        """

        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [
            URLQueryItem(name: "data", value: query)
        ]

        log(.openStreetMap, "Request URL: \(components.url!.absoluteString.prefix(120))...", verbosity: 4)

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        log(.openStreetMap, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            log(.openStreetMap, "No 'elements' array in response", verbosity: 2)
            return []
        }
        log(.openStreetMap, "Got \(elements.count) results", verbosity: 4)

        return elements.prefix(limit).compactMap { element -> PlaceSearchResult? in
            guard let tags = element["tags"] as? [String: String],
                  let name = tags["name"] else { return nil }

            let osmId = element["id"] as? Int ?? 0
            let osmType = element["type"] as? String ?? "node"

            var lat: Double
            var lon: Double
            if osmType == "way", let center = element["center"] as? [String: Any] {
                lat = center["lat"] as? Double ?? coordinate.latitude
                lon = center["lon"] as? Double ?? coordinate.longitude
            } else {
                lat = element["lat"] as? Double ?? coordinate.latitude
                lon = element["lon"] as? Double ?? coordinate.longitude
            }

            let address = [tags["addr:street"], tags["addr:housenumber"], tags["addr:city"]]
                .compactMap { $0 }
                .joined(separator: " ")

            var osmCategoryTags: [String] = []
            let categoryKeys = ["amenity", "shop", "tourism", "leisure", "office", "craft"]
            for key in categoryKeys {
                if let value = tags[key] {
                    osmCategoryTags.append("\(key)=\(value)")
                }
            }

            return PlaceSearchResult(
                id: "\(osmType)/\(osmId)",
                name: name,
                address: address.isEmpty ? nil : address,
                latitude: lat,
                longitude: lon,
                provider: .openStreetMap,
                foursquareCategoryId: nil,
                categoryIds: osmCategoryTags
            )
        }
    }

    // MARK: - HERE Places

    private func searchHERE(coordinate: CLLocationCoordinate2D, apiKey: String, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        let baseURL = query != nil
            ? "https://discover.search.hereapi.com/v1/discover"
            : "https://browse.search.hereapi.com/v1/browse"
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "at", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]
        if let query = query {
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        }

        log(.here, "Request URL: \(components.url!.absoluteString.replacingOccurrences(of: apiKey, with: "***"))", verbosity: 4)

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        log(.here, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            log(.here, "No 'items' array in response", verbosity: 2)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["title"] as? String ?? json["error_description"] as? String {
                throw PlaceSearchError.apiError("HERE: \(message)")
            }
            return []
        }
        log(.here, "Got \(items.count) results", verbosity: 4)

        return items.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let title = item["title"] as? String,
                  let position = item["position"] as? [String: Any],
                  let lat = position["lat"] as? Double,
                  let lng = position["lng"] as? Double else { return nil }

            let hereId = item["id"] as? String ?? "here_\(String(format: "%.6f", lat))_\(String(format: "%.6f", lng))"
            let address = (item["address"] as? [String: Any])?["label"] as? String

            var hereCategoryIds: [String] = []
            if let categories = item["categories"] as? [[String: Any]] {
                for cat in categories {
                    if let catId = cat["id"] as? String {
                        hereCategoryIds.append(catId)
                    }
                }
            }

            return PlaceSearchResult(
                id: hereId,
                name: title,
                address: address,
                latitude: lat,
                longitude: lng,
                provider: .here,
                foursquareCategoryId: nil,
                categoryIds: hereCategoryIds
            )
        }
    }

    // MARK: - Apple Maps

    private func searchApple(coordinate: CLLocationCoordinate2D, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        let requestKind = query == nil ? "nearbyPOI" : "naturalLanguage"
        let requestRadiusMeters = query == nil ? Double(SettingsManager.shared.placeSearchDefaultRadius) : Double(SettingsManager.shared.placeSearchKeywordRadius)
        log(
            .apple,
            "Searching. kind=\(requestKind), center=\(formatCoordinate(coordinate)), query=\(formatQuery(query)), radius=\(Int(requestRadiusMeters))m, limit=\(limit)",
            verbosity: 4
        )

        let search: MKLocalSearch
        if let query = query {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 10000, longitudinalMeters: 10000)
            request.pointOfInterestFilter = .includingAll
            search = MKLocalSearch(request: request)
        } else {
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: requestRadiusMeters)
            request.pointOfInterestFilter = .includingAll
            search = MKLocalSearch(request: request)
        }
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            let nsError = error as NSError
            log(
                .apple,
                "MKLocalSearch failed. kind=\(requestKind), center=\(formatCoordinate(coordinate)), query=\(formatQuery(query)), radius=\(Int(requestRadiusMeters))m, limit=\(limit), \(summarize(error: error))",
                verbosity: 1
            )
            if nsError.domain == MKErrorDomain && nsError.code == 4 {
                log(
                    .apple,
                    "placemarkNotFound usually means Apple Maps could not resolve any indexed POI or placemark for this request area/query. Sparse coverage or a too-small nearby radius can trigger it.",
                    verbosity: 2
                )
                throw PlaceSearchError.noResults(appleNoResultsMessage(query: query, radiusMeters: requestRadiusMeters))
            }
            throw error
        }

        log(.apple, "Got \(response.mapItems.count) results", verbosity: 4)

        if response.mapItems.isEmpty {
            let message = appleNoResultsMessage(query: query, radiusMeters: requestRadiusMeters)
            log(.apple, message, verbosity: 2)
            throw PlaceSearchError.noResults(message)
        }

        return response.mapItems.prefix(limit).enumerated().compactMap { index, item -> PlaceSearchResult? in
            guard let name = item.name else { return nil }
            let lat = item.placemark.coordinate.latitude
            let lng = item.placemark.coordinate.longitude

            let addressParts = [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.locality]
                .compactMap { $0 }
            let address = addressParts.isEmpty ? nil : addressParts.joined(separator: " ")

            var identifier: String
            if #available(iOS 18.0, *), let mkId = item.identifier {
                identifier = mkId.rawValue
            } else {
                identifier = "apple_\(String(format: "%.6f", lat))_\(String(format: "%.6f", lng))"
            }

            var appleCategoryIds: [String] = []
            if let category = item.pointOfInterestCategory {
                appleCategoryIds.append(category.rawValue)
            }

            log(
                .apple,
                "Item[\(index)] name=\(name), id=\(identifier), coordinate=\(formatCoordinate(item.placemark.coordinate)), address=\(address ?? "nil"), categories=\(appleCategoryIds.joined(separator: ","))",
                verbosity: 5
            )

            return PlaceSearchResult(id: identifier, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .apple, foursquareCategoryId: nil,
                                     categoryIds: appleCategoryIds)
        }
    }

    // MARK: - Gaode (Amap)

    private func searchGaode(coordinate: CLLocationCoordinate2D, apiKey: String, query: String? = nil, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://restapi.amap.com/v3/place/around")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(coordinate.longitude),\(coordinate.latitude)"),
            URLQueryItem(name: "radius", value: query != nil ? "\(SettingsManager.shared.placeSearchKeywordRadius)" : "\(SettingsManager.shared.placeSearchDefaultRadius)"),
            URLQueryItem(name: "offset", value: "\(limit)"),
            URLQueryItem(name: "extensions", value: "all")
        ]
        if let query = query {
            components.queryItems?.append(URLQueryItem(name: "keywords", value: query))
        }

        log(.gaode, "Request URL: \(components.url!.absoluteString.replacingOccurrences(of: apiKey, with: "***"))", verbosity: 4)

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        log(.gaode, "HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes", verbosity: 4)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log(.gaode, "Failed to parse response", verbosity: 2)
            return []
        }

        if let status = json["status"] as? String, status != "1" {
            let info = json["info"] as? String ?? "unknown error"
            log(.gaode, "API error: \(info)", verbosity: 2)
            throw PlaceSearchError.apiError("Gaode: \(info)")
        }

        guard let pois = json["pois"] as? [[String: Any]] else {
            log(.gaode, "No 'pois' array in response. Keys: \(json.keys.joined(separator: ", "))", verbosity: 2)
            return []
        }
        log(.gaode, "Got \(pois.count) results", verbosity: 4)

        return pois.prefix(limit).compactMap { poi -> PlaceSearchResult? in
            guard let poiId = poi["id"] as? String,
                  let name = poi["name"] as? String,
                  let locationStr = poi["location"] as? String else { return nil }

            let coords = locationStr.split(separator: ",")
            guard coords.count == 2,
                  let lng = Double(coords[0]),
                  let lat = Double(coords[1]) else { return nil }

            let address = poi["address"] as? String

            var gaodeCategoryIds: [String] = []
            if let typecode = poi["typecode"] as? String {
                gaodeCategoryIds.append(typecode)
            }

            return PlaceSearchResult(
                id: poiId,
                name: name,
                address: address,
                latitude: lat,
                longitude: lng,
                provider: .gaode,
                foursquareCategoryId: nil,
                categoryIds: gaodeCategoryIds
            )
        }
    }
}

enum PlaceSearchError: LocalizedError {
    case noApiKey
    case apiError(String)
    case noResults(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No API key configured for this provider"
        case .apiError(let msg): return msg
        case .noResults(let msg): return msg
        }
    }
}
