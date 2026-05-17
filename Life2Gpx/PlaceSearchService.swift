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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

class PlaceSearchService {
    static let shared = PlaceSearchService()
    private init() {}

    func search(near coordinate: CLLocationCoordinate2D, provider: PlaceProvider, limit: Int = 10) async throws -> [PlaceSearchResult] {
        if provider == .apple {
            return try await searchApple(coordinate: coordinate, limit: limit)
        }
        if provider == .openStreetMap {
            return try await searchOpenStreetMap(coordinate: coordinate, limit: limit)
        }

        guard let apiKey = getApiKey(for: provider), !apiKey.isEmpty else {
            throw PlaceSearchError.noApiKey
        }

        switch provider {
        case .google: return try await searchGoogle(coordinate: coordinate, apiKey: apiKey, limit: limit)
        case .foursquare: return try await searchFoursquare(coordinate: coordinate, apiKey: apiKey, limit: limit)
        case .yelp: return try await searchYelp(coordinate: coordinate, apiKey: apiKey, limit: limit)
        case .mapbox: return try await searchMapbox(coordinate: coordinate, apiKey: apiKey, limit: limit)
        case .here: return try await searchHERE(coordinate: coordinate, apiKey: apiKey, limit: limit)
        case .gaode: return try await searchGaode(coordinate: coordinate, apiKey: apiKey, limit: limit)
        case .apple, .openStreetMap: return []
        }
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

    private func searchGoogle(coordinate: CLLocationCoordinate2D, apiKey: String, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json")!
        components.queryItems = [
            URLQueryItem(name: "location", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "200"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        let url = components.url!
        print("[PlaceSearch][Google] Request URL: \(url.absoluteString.replacingOccurrences(of: apiKey, with: "***"))")

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][Google] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let status = json?["status"] as? String {
            print("[PlaceSearch][Google] API status: \(status)")
            if let errorMessage = json?["error_message"] as? String {
                print("[PlaceSearch][Google] Error message: \(errorMessage)")
            }
            if status != "OK" && status != "ZERO_RESULTS" {
                throw PlaceSearchError.apiError("Google Places: \(status) - \(json?["error_message"] as? String ?? "unknown error")")
            }
        }

        guard let results = json?["results"] as? [[String: Any]] else {
            print("[PlaceSearch][Google] No 'results' array in response. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")")
            return []
        }
        print("[PlaceSearch][Google] Got \(results.count) results")

        return results.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let placeId = item["place_id"] as? String,
                  let name = item["name"] as? String,
                  let geometry = item["geometry"] as? [String: Any],
                  let location = geometry["location"] as? [String: Any],
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double else { return nil }

            let vicinity = item["vicinity"] as? String
            return PlaceSearchResult(id: placeId, name: name, address: vicinity,
                                     latitude: lat, longitude: lng,
                                     provider: .google, foursquareCategoryId: nil)
        }
    }

    // MARK: - Foursquare

    private func searchFoursquare(coordinate: CLLocationCoordinate2D, apiKey: String, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://places-api.foursquare.com/places/search")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "200"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-17", forHTTPHeaderField: "X-Places-Api-Version")

        print("[PlaceSearch][Foursquare] Request URL: \(components.url!.absoluteString)")
        print("[PlaceSearch][Foursquare] Auth: Bearer token (key length: \(apiKey.count))")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][Foursquare] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        if let bodyStr = String(data: data.prefix(500), encoding: .utf8) {
            print("[PlaceSearch][Foursquare] Response body (first 500 chars): \(bodyStr)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            print("[PlaceSearch][Foursquare] No 'results' array in response. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")")
            if let message = json?["message"] as? String {
                throw PlaceSearchError.apiError("Foursquare: \(message)")
            }
            return []
        }
        print("[PlaceSearch][Foursquare] Got \(results.count) results")

        return results.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let fsqId = item["fsq_place_id"] as? String,
                  let name = item["name"] as? String,
                  let lat = item["latitude"] as? Double,
                  let lng = item["longitude"] as? Double else { return nil }

            let location = item["location"] as? [String: Any]
            let address = location?["formatted_address"] as? String

            var categoryId: String? = nil
            if let categories = item["categories"] as? [[String: Any]],
               let firstCat = categories.first,
               let catId = firstCat["fsq_category_id"] as? String {
                categoryId = catId
            }

            return PlaceSearchResult(id: fsqId, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .foursquare, foursquareCategoryId: categoryId)
        }
    }

    // MARK: - Yelp

    private func searchYelp(coordinate: CLLocationCoordinate2D, apiKey: String, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://api.yelp.com/v3/businesses/search")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "200"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        print("[PlaceSearch][Yelp] Request URL: \(components.url!.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][Yelp] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let businesses = json?["businesses"] as? [[String: Any]] else {
            print("[PlaceSearch][Yelp] No 'businesses' array. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")")
            return []
        }
        print("[PlaceSearch][Yelp] Got \(businesses.count) results")

        return businesses.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let yelpId = item["id"] as? String,
                  let name = item["name"] as? String,
                  let coords = item["coordinates"] as? [String: Any],
                  let lat = coords["latitude"] as? Double,
                  let lng = coords["longitude"] as? Double else { return nil }

            let location = item["location"] as? [String: Any]
            let displayAddress = location?["display_address"] as? [String]
            let address = displayAddress?.joined(separator: ", ")

            return PlaceSearchResult(id: yelpId, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .yelp, foursquareCategoryId: nil)
        }
    }

    // MARK: - Mapbox

    private func searchMapbox(coordinate: CLLocationCoordinate2D, apiKey: String, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://api.mapbox.com/search/searchbox/v1/reverse")!
        components.queryItems = [
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "access_token", value: apiKey),
            URLQueryItem(name: "types", value: "poi"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        print("[PlaceSearch][Mapbox] Request URL: \(components.url!.absoluteString.replacingOccurrences(of: apiKey, with: "***"))")

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][Mapbox] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let features = json?["features"] as? [[String: Any]] else {
            print("[PlaceSearch][Mapbox] No 'features' array. Keys: \(json?.keys.joined(separator: ", ") ?? "nil")")
            return []
        }
        print("[PlaceSearch][Mapbox] Got \(features.count) results")

        return features.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let properties = item["properties"] as? [String: Any],
                  let mapboxId = properties["mapbox_id"] as? String,
                  let name = properties["name"] as? String else { return nil }

            let geometry = item["geometry"] as? [String: Any]
            let coordinates = geometry?["coordinates"] as? [Double]
            let lng = coordinates?.first ?? coordinate.longitude
            let lat = coordinates?.last ?? coordinate.latitude

            let address = properties["full_address"] as? String ?? properties["address"] as? String
            return PlaceSearchResult(id: mapboxId, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .mapbox, foursquareCategoryId: nil)
        }
    }

    // MARK: - OpenStreetMap (Overpass API)

    private func searchOpenStreetMap(coordinate: CLLocationCoordinate2D, limit: Int) async throws -> [PlaceSearchResult] {
        let query = """
        [out:json][timeout:10];
        (
          node(around:200,\(coordinate.latitude),\(coordinate.longitude))[~"^(amenity|shop|tourism|leisure|office|craft)$"~"."]["name"];
          way(around:200,\(coordinate.latitude),\(coordinate.longitude))[~"^(amenity|shop|tourism|leisure|office|craft)$"~"."]["name"];
        );
        out center body \(limit);
        """

        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [
            URLQueryItem(name: "data", value: query)
        ]

        print("[PlaceSearch][OSM] Request URL: \(components.url!.absoluteString.prefix(120))...")

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][OSM] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            print("[PlaceSearch][OSM] No 'elements' array in response")
            return []
        }
        print("[PlaceSearch][OSM] Got \(elements.count) results")

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

            return PlaceSearchResult(
                id: "\(osmType)/\(osmId)",
                name: name,
                address: address.isEmpty ? nil : address,
                latitude: lat,
                longitude: lon,
                provider: .openStreetMap,
                foursquareCategoryId: nil
            )
        }
    }

    // MARK: - HERE Places

    private func searchHERE(coordinate: CLLocationCoordinate2D, apiKey: String, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://browse.search.hereapi.com/v1/browse")!
        components.queryItems = [
            URLQueryItem(name: "at", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]

        print("[PlaceSearch][HERE] Request URL: \(components.url!.absoluteString.replacingOccurrences(of: apiKey, with: "***"))")

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][HERE] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            print("[PlaceSearch][HERE] No 'items' array in response")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["title"] as? String ?? json["error_description"] as? String {
                throw PlaceSearchError.apiError("HERE: \(message)")
            }
            return []
        }
        print("[PlaceSearch][HERE] Got \(items.count) results")

        return items.prefix(limit).compactMap { item -> PlaceSearchResult? in
            guard let title = item["title"] as? String,
                  let position = item["position"] as? [String: Any],
                  let lat = position["lat"] as? Double,
                  let lng = position["lng"] as? Double else { return nil }

            let hereId = item["id"] as? String ?? "here_\(String(format: "%.6f", lat))_\(String(format: "%.6f", lng))"
            let address = (item["address"] as? [String: Any])?["label"] as? String

            return PlaceSearchResult(
                id: hereId,
                name: title,
                address: address,
                latitude: lat,
                longitude: lng,
                provider: .here,
                foursquareCategoryId: nil
            )
        }
    }

    // MARK: - Apple Maps

    private func searchApple(coordinate: CLLocationCoordinate2D, limit: Int) async throws -> [PlaceSearchResult] {
        print("[PlaceSearch][Apple] Searching near \(coordinate.latitude), \(coordinate.longitude)")

        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 200)
        request.pointOfInterestFilter = .includingAll

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        print("[PlaceSearch][Apple] Got \(response.mapItems.count) results")

        return response.mapItems.prefix(limit).compactMap { item -> PlaceSearchResult? in
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
            print("[PlaceSearch][Apple] Item: \(name) -> id: \(identifier)")

            return PlaceSearchResult(id: identifier, name: name, address: address,
                                     latitude: lat, longitude: lng,
                                     provider: .apple, foursquareCategoryId: nil)
        }
    }
}

    // MARK: - Gaode (Amap)

    private func searchGaode(coordinate: CLLocationCoordinate2D, apiKey: String, limit: Int) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://restapi.amap.com/v3/place/around")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(coordinate.longitude),\(coordinate.latitude)"),
            URLQueryItem(name: "radius", value: "200"),
            URLQueryItem(name: "offset", value: "\(limit)"),
            URLQueryItem(name: "extensions", value: "all")
        ]

        print("[PlaceSearch][Gaode] Request URL: \(components.url!.absoluteString.replacingOccurrences(of: apiKey, with: "***"))")

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let httpResponse = response as? HTTPURLResponse
        print("[PlaceSearch][Gaode] HTTP status: \(httpResponse?.statusCode ?? -1), body size: \(data.count) bytes")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[PlaceSearch][Gaode] Failed to parse response")
            return []
        }

        if let status = json["status"] as? String, status != "1" {
            let info = json["info"] as? String ?? "unknown error"
            print("[PlaceSearch][Gaode] API error: \(info)")
            throw PlaceSearchError.apiError("Gaode: \(info)")
        }

        guard let pois = json["pois"] as? [[String: Any]] else {
            print("[PlaceSearch][Gaode] No 'pois' array in response. Keys: \(json.keys.joined(separator: ", "))")
            return []
        }
        print("[PlaceSearch][Gaode] Got \(pois.count) results")

        return pois.prefix(limit).compactMap { poi -> PlaceSearchResult? in
            guard let poiId = poi["id"] as? String,
                  let name = poi["name"] as? String,
                  let locationStr = poi["location"] as? String else { return nil }

            let coords = locationStr.split(separator: ",")
            guard coords.count == 2,
                  let lng = Double(coords[0]),
                  let lat = Double(coords[1]) else { return nil }

            let address = poi["address"] as? String

            return PlaceSearchResult(
                id: poiId,
                name: name,
                address: address,
                latitude: lat,
                longitude: lng,
                provider: .gaode,
                foursquareCategoryId: nil
            )
        }
    }

enum PlaceSearchError: LocalizedError {
    case noApiKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No API key configured for this provider"
        case .apiError(let msg): return msg
        }
    }
}
