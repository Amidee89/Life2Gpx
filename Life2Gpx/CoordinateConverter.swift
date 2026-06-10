import CoreLocation

struct CoordinateConverter {
    
    // MARK: - Public API
    
    static func wgs84ToGcj02(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if !isInMainlandChina(lat: coord.latitude, lng: coord.longitude) {
            return coord
        }
        let (dLat, dLng) = delta(lat: coord.latitude, lng: coord.longitude)
        return CLLocationCoordinate2D(
            latitude: coord.latitude + dLat,
            longitude: coord.longitude + dLng
        )
    }
    
    static func gcj02ToWgs84(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if !isInMainlandChina(lat: coord.latitude, lng: coord.longitude) {
            return coord
        }
        // Iterative approach for ~1m accuracy
        var wgsLat = coord.latitude
        var wgsLng = coord.longitude
        var prevLat = wgsLat
        var prevLng = wgsLng
        
        for _ in 0..<5 {
            let gcj = wgs84ToGcj02(CLLocationCoordinate2D(latitude: wgsLat, longitude: wgsLng))
            wgsLat -= (gcj.latitude - coord.latitude)
            wgsLng -= (gcj.longitude - coord.longitude)
            if abs(wgsLat - prevLat) < 1e-9 && abs(wgsLng - prevLng) < 1e-9 {
                break
            }
            prevLat = wgsLat
            prevLng = wgsLng
        }
        return CLLocationCoordinate2D(latitude: wgsLat, longitude: wgsLng)
    }
    
    /// Converts a coordinate for display on Apple Maps (WGS-84 -> GCJ-02 if in mainland China)
    static func forMapDisplay(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        return wgs84ToGcj02(coord)
    }
    
    /// Converts an array of coordinates for display on Apple Maps
    static func forMapDisplay(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        return coords.map { wgs84ToGcj02($0) }
    }
    
    /// Converts a coordinate from map display space back to WGS-84 for storage (GCJ-02 -> WGS-84 if in mainland China)
    static func fromMapDisplay(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        return gcj02ToWgs84(coord)
    }
    
    // MARK: - China Detection (bounding box + simplified polygon)
    
    static func isInMainlandChina(lat: Double, lng: Double) -> Bool {
        // Fast bounding box rejection
        guard lat >= 17.9 && lat <= 53.6 && lng >= 73.4 && lng <= 135.1 else {
            return false
        }
        // Simplified polygon of mainland China (excludes HK, Macau, Taiwan)
        return pointInPolygon(lat: lat, lng: lng, polygon: mainlandChinaPolygon)
    }
    
    // MARK: - GCJ-02 Transform (eviltransform algorithm)
    
    private static let a: Double = 6378245.0 // Semi-major axis
    private static let ee: Double = 0.00669342162296594323 // Eccentricity squared
    
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
    
    // MARK: - Point-in-Polygon (ray casting)
    
    private static func pointInPolygon(lat: Double, lng: Double, polygon: [(Double, Double)]) -> Bool {
        var inside = false
        let count = polygon.count
        var j = count - 1
        for i in 0..<count {
            let (yi, xi) = polygon[i]
            let (yj, xj) = polygon[j]
            if ((yi > lat) != (yj > lat)) &&
                (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
    
    // Simplified polygon of mainland China's border (~20 vertices)
    // Excludes Hong Kong, Macau, Taiwan, and neighboring countries
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
