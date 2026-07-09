import CoreLocation

/// Converts between WGS-84 (GPS / storage) and GCJ-02 (China map tiles & Gaode API).
///
/// Display rule: shift overlays only when MapKit is serving GCJ-02 tiles — inferred from
/// device location in mainland China, with an optional settings override.
///
/// Storage rule: always WGS-84. Gaode (and other GCJ-02 providers) are converted on ingest.
struct CoordinateConverter {

  private static let lastDeviceLatitudeKey = "coordinateConverter.lastDeviceLatitude"
  private static let lastDeviceLongitudeKey = "coordinateConverter.lastDeviceLongitude"

  /// Whether the device's last known position is inside mainland China.
  private(set) static var deviceInMainlandChina = false

  /// True when overlays should be shifted for the current map tiles.
  static var mapUsesGcj02: Bool {
    switch SettingsManager.shared.mapCoordinateSystemMode {
    case .auto:
      return deviceInMainlandChina
    case .forceGCJ02:
      return true
    case .forceWGS84:
      return false
    }
  }

  static func updateDeviceLocation(_ coordinate: CLLocationCoordinate2D) {
    deviceInMainlandChina = isInMainlandChina(
      lat: coordinate.latitude, lng: coordinate.longitude)
    let defaults = UserDefaults.standard
    defaults.set(coordinate.latitude, forKey: lastDeviceLatitudeKey)
    defaults.set(coordinate.longitude, forKey: lastDeviceLongitudeKey)
  }

  /// Call on launch before the first live GPS fix (uses CLLocationManager's cached location or persisted coords).
  static func restoreLastKnownDeviceLocation(from coordinate: CLLocationCoordinate2D?) {
    if let coordinate {
      updateDeviceLocation(coordinate)
      return
    }
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: lastDeviceLatitudeKey) != nil else { return }
    let lat = defaults.double(forKey: lastDeviceLatitudeKey)
    let lng = defaults.double(forKey: lastDeviceLongitudeKey)
    deviceInMainlandChina = isInMainlandChina(lat: lat, lng: lng)
  }

  // MARK: - Map display (WGS-84 storage → map tile space)

  static func forMapDisplay(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    guard mapUsesGcj02 else { return coord }
    return wgs84ToGcj02(coord)
  }

  static func forMapDisplay(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
    guard mapUsesGcj02 else { return coords }
    return coords.map { wgs84ToGcj02($0) }
  }

  static func fromMapDisplay(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    guard mapUsesGcj02 else { return coord }
    return gcj02ToWgs84(coord)
  }

  // MARK: - GCJ-02 ↔ WGS-84 math (eviltransform)

  static func wgs84ToGcj02(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    let lat = coord.latitude
    let lng = coord.longitude
    if isOutsideChinaTransformRegion(lat: lat, lng: lng) { return coord }
    let (dLat, dLng) = delta(lat: lat, lng: lng)
    return CLLocationCoordinate2D(latitude: lat + dLat, longitude: lng + dLng)
  }

  static func gcj02ToWgs84(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    let lat = coord.latitude
    let lng = coord.longitude
    if isOutsideChinaTransformRegion(lat: lat, lng: lng) { return coord }
    var wgsLat = lat
    var wgsLng = lng
    var prevLat = wgsLat
    var prevLng = wgsLng
    for _ in 0..<5 {
      let gcj = wgs84ToGcj02(CLLocationCoordinate2D(latitude: wgsLat, longitude: wgsLng))
      wgsLat -= gcj.latitude - lat
      wgsLng -= gcj.longitude - lng
      if abs(wgsLat - prevLat) < 1e-9 && abs(wgsLng - prevLng) < 1e-9 { break }
      prevLat = wgsLat
      prevLng = wgsLng
    }
    return CLLocationCoordinate2D(latitude: wgsLat, longitude: wgsLng)
  }

  // MARK: - Device-in-China detection (polygon)

  static func isInMainlandChina(lat: Double, lng: Double) -> Bool {
    guard lat >= 17.9 && lat <= 53.6 && lng >= 73.4 && lng <= 135.1 else { return false }
    return pointInPolygon(lat: lat, lng: lng, polygon: mainlandChinaPolygon)
  }

  /// Standard GCJ-02 transform bounding box — used only by the math, not for map-tile decisions.
  private static func isOutsideChinaTransformRegion(lat: Double, lng: Double) -> Bool {
    lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271
  }

  private static let a: Double = 6378245.0
  private static let ee: Double = 0.00669342162296594323

  private static func delta(lat: Double, lng: Double) -> (Double, Double) {
    var dLat = transformLat(x: lng - 105.0, y: lat - 35.0)
    var dLng = transformLng(x: lng - 105.0, y: lat - 35.0)
    let radLat = lat / 180.0 * .pi
    var magic = sin(radLat)
    magic = 1 - ee * magic * magic
    let sqrtMagic = sqrt(magic)
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
    dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
    return (dLat, dLng)
  }

  private static func transformLat(x: Double, y: Double) -> Double {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
    ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
    ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
    ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
    return ret
  }

  private static func transformLng(x: Double, y: Double) -> Double {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
    ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
    ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
    ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
    return ret
  }

  private static func pointInPolygon(lat: Double, lng: Double, polygon: [(Double, Double)]) -> Bool {
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
      let (yi, xi) = polygon[i]
      let (yj, xj) = polygon[j]
      if (yi > lat) != (yj > lat), lng < (xj - xi) * (lat - yi) / (yj - yi) + xi {
        inside.toggle()
      }
      j = i
    }
    return inside
  }

  private static let mainlandChinaPolygon: [(Double, Double)] = [
        (21.0, 108.0),   // Southern Guangxi coast (west of HK/Macau)
        (18.2, 109.0),   // Hainan south
        (18.2, 111.0),   // Hainan east
        (21.5, 111.5),   // Guangdong coast west
        (22.0, 113.0),   // Pearl River Delta (excludes HK/Macau below ~22.1)
        (23.5, 117.0),   // Fujian coast
        (25.0, 119.5),   // Fujian/Zhejiang
        (30.0, 123.0),   // Shanghai/East China Sea
        (35.0, 124.0),   // Shandong/Yellow Sea
        (39.0, 122.5),   // Liaodong
        (41.0, 124.5),   // China-DPRK border
        (43.0, 131.5),   // Northeast (Jilin-Russia)
        (48.5, 135.0),   // Heilongjiang northeast corner
        (53.5, 121.0),   // Mohe (northernmost)
        (49.5, 87.5),    // Xinjiang north (Altai)
        (45.0, 73.5),    // Xinjiang west (Kashgar area)
        (35.5, 74.0),    // Xinjiang-Pakistan border (Karakoram)
        (27.0, 88.5),    // Tibet-Nepal-Bhutan border
        (28.5, 97.0),    // Yunnan-Myanmar-Tibet junction
        (21.5, 101.0),   // Yunnan-Laos-Myanmar border
        (22.0, 106.5),   // Guangxi-Vietnam border
    ]
}
