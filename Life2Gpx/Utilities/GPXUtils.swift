import Foundation
import CoreGPX
import CoreLocation

class GPXUtils {
    private enum Constants {
        static let coordinateEqualityTolerance: Double = 0.00001
        static let elevationEqualityTolerance: Double = 0.1
        static let timeEqualityTolerance: TimeInterval = 1.0
        static let magneticVariationTolerance: Double = 0.01
        static let geoidHeightTolerance: Double = 0.1
        static let dilutionOfPrecisionTolerance: Double = 0.01
        static let ageofDGPSDataTolerance: Double = 0.1
        
        static let confidenceLevel1RequiredPercentage: Double = 0.2
        static let confidenceLevel2RequiredPercentage: Double = 0.4
        static let confidenceLevel3RequiredPercentage: Double = 0.6
        static let confidenceLevel4RequiredPercentage: Double = 0.8
        static let confidenceLevel5RequiredPercentage: Double = 1.0
    }
    
    static func copyExtensions(_ extensions: GPXExtensions?) -> GPXExtensions? {
        guard let sourceExtensions = extensions else { return nil }
        LogManager.shared.logData(context: "GPXUtils", content: "copyExtensions called.", verbosity: 5)
        
        var extensionsDict = [String: String]()
        
        for child in sourceExtensions.children {
            let key = child.name
            if let value = child.text, !key.isEmpty {
                extensionsDict[key] = value
            }
        }
        
        if !extensionsDict.isEmpty {
            let newExtensions = GPXExtensions()
            newExtensions.append(at: nil, contents: extensionsDict)
            LogManager.shared.logData(context: "GPXUtils", content: "copyExtensions created new extensions object with \(extensionsDict.count) items.", verbosity: 5)
            return newExtensions
        }
        
        LogManager.shared.logData(context: "GPXUtils", content: "copyExtensions found no extensions to copy.", verbosity: 5)
        return nil
    }
    
    static func updateExtension(for waypoint: GPXWaypoint, with newValues: [String: String]) {
        var combinedData = [String: String]()
        if let existing = waypoint.extensions {
            for child in existing.children {
                let k = child.name
                if let v = child.text, !k.isEmpty {
                    combinedData[k] = v
                }
            }
        }
        for (k, v) in newValues {
            combinedData[k] = v
        }
        
        if !combinedData.isEmpty {
            let newExtensions = GPXExtensions()
            newExtensions.append(at: nil, contents: combinedData)
            waypoint.extensions = newExtensions
        }
    }
    
    static func deepCopyPoint(_ point: GPXWaypoint) -> GPXWaypoint {
        LogManager.shared.logData(context: "GPXUtils", content: "deepCopyPoint called for point at time \(point.time?.description ?? "N/A").", verbosity: 5)
        let copy: GPXWaypoint
        
        if point is GPXTrackPoint {
            copy = GPXTrackPoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
        } else {
            copy = GPXWaypoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
        }
        
        populateCopy(copy, from: point)
        return copy
    }
    
    static func deepCopyAsWaypoint(_ point: GPXWaypoint) -> GPXWaypoint {
        LogManager.shared.logData(context: "GPXUtils", content: "deepCopyAsWaypoint called for point at time \(point.time?.description ?? "N/A").", verbosity: 5)
        let copy = GPXWaypoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
        populateCopy(copy, from: point)
        return copy
    }
    
    private static func populateCopy(_ copy: GPXWaypoint, from point: GPXWaypoint) {
        copy.elevation = point.elevation
        copy.time = point.time
        copy.magneticVariation = point.magneticVariation
        copy.geoidHeight = point.geoidHeight
        copy.name = point.name
        copy.comment = point.comment
        copy.desc = point.desc
        copy.source = point.source
        copy.symbol = point.symbol
        copy.type = point.type
        copy.fix = point.fix
        copy.satellites = point.satellites
        copy.horizontalDilution = point.horizontalDilution
        copy.verticalDilution = point.verticalDilution
        copy.positionDilution = point.positionDilution
        copy.ageofDGPSData = point.ageofDGPSData
        copy.DGPSid = point.DGPSid
        
        point.links.forEach { link in
            if let href = link.href {
                let newLink = GPXLink(withHref: href)
                newLink.text = link.text
                newLink.mimetype = link.mimetype
                copy.links.append(newLink)
            }
        }
        
        copy.extensions = copyExtensions(point.extensions)
        
        LogManager.shared.logData(context: "GPXUtils", content: "deepCopyPoint finished copying point.", verbosity: 5)
    }
    
    static func deepCopyTrack(_ track: GPXTrack) -> GPXTrack {
        LogManager.shared.logData(context: "GPXUtils", content: "deepCopyTrack called for track named '\(track.name ?? "Unnamed")'.", verbosity: 5)
        let copy = GPXTrack()
        
        copy.name = track.name
        copy.comment = track.comment
        copy.desc = track.desc
        copy.source = track.source
        copy.number = track.number
        copy.type = track.type
        
        track.links.forEach { link in
            if let href = link.href {
                let newLink = GPXLink(withHref: href)
                newLink.text = link.text
                newLink.mimetype = link.mimetype
                copy.links.append(newLink)
            }
        }
        
        copy.extensions = copyExtensions(track.extensions)
        
        track.segments.forEach { segment in
            let newSegment = GPXTrackSegment()
            
            segment.points.forEach { point in
                if let trackPoint = deepCopyPoint(point) as? GPXTrackPoint {
                    newSegment.add(trackpoint: trackPoint)
                }
            }
            
            newSegment.extensions = copyExtensions(segment.extensions)
            
            copy.add(trackSegment: newSegment)
        }
        
        LogManager.shared.logData(context: "GPXUtils", content: "deepCopyTrack finished copying track with \(copy.segments.count) segments.", verbosity: 5)
        return copy
    }
    
    static func areExtensionsTheSame(_ ext1: GPXExtensions?, _ ext2: GPXExtensions?) -> Bool {
        if ext1 == nil && ext2 == nil { return true }
        guard let ext1 = ext1, let ext2 = ext2 else { return false }
        
        var dict1 = [String: String]()
        for child in ext1.children {
            if let text = child.text, !child.name.isEmpty {
                dict1[child.name] = text
            }
        }
        
        var dict2 = [String: String]()
        for child in ext2.children {
            if let text = child.text, !child.name.isEmpty {
                dict2[child.name] = text
            }
        }
        
        return dict1 == dict2
    }

    static func arePointsTheSame(_ point1: GPXWaypoint, _ point2: GPXWaypoint, confidenceLevel: Int, fields: GPXExportFields = SettingsManager.shared.gpxExportSettings.waypoints) -> Bool {
        LogManager.shared.logData(context: "GPXUtils", content: "arePointsTheSame called with confidence level \(confidenceLevel).", verbosity: 5)
        guard confidenceLevel >= 1 && confidenceLevel <= 5 else {
            LogManager.shared.logData(context: "GPXUtils", content: "arePointsTheSame: Invalid confidence level \(confidenceLevel). Defaulting to 3.", verbosity: 2)
            return arePointsTheSame(point1, point2, confidenceLevel: 3, fields: fields)
        }
        
        let filteredPoint1 = deepCopyPoint(point1)
        filterPoint(filteredPoint1, fields: fields)
        let filteredPoint2 = deepCopyPoint(point2)
        filterPoint(filteredPoint2, fields: fields)
        
        var totalFields = 0
        var matchingFields = 0
        
        if let lat1 = filteredPoint1.latitude, let lat2 = filteredPoint2.latitude, 
           let lon1 = filteredPoint1.longitude, let lon2 = filteredPoint2.longitude {
            totalFields += 2
            if abs(lat1 - lat2) < Constants.coordinateEqualityTolerance { matchingFields += 1 }
            if abs(lon1 - lon2) < Constants.coordinateEqualityTolerance { matchingFields += 1 }
        }
        
        if filteredPoint1.elevation != nil || filteredPoint2.elevation != nil {
            totalFields += 1
            if let elevation1 = filteredPoint1.elevation, let elevation2 = filteredPoint2.elevation, 
               abs(elevation1 - elevation2) < Constants.elevationEqualityTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.time != nil || filteredPoint2.time != nil {
            totalFields += 1
            if let time1 = filteredPoint1.time, let time2 = filteredPoint2.time,
               abs(time1.timeIntervalSince(time2)) < Constants.timeEqualityTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.magneticVariation != nil || filteredPoint2.magneticVariation != nil {
            totalFields += 1
            if let mv1 = filteredPoint1.magneticVariation, let mv2 = filteredPoint2.magneticVariation,
               abs(mv1 - mv2) < Constants.magneticVariationTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.geoidHeight != nil || filteredPoint2.geoidHeight != nil {
            totalFields += 1
            if let gh1 = filteredPoint1.geoidHeight, let gh2 = filteredPoint2.geoidHeight,
               abs(gh1 - gh2) < Constants.geoidHeightTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.name != nil || filteredPoint2.name != nil {
            totalFields += 1
            if filteredPoint1.name == filteredPoint2.name { matchingFields += 1 }
        }
        
        if filteredPoint1.comment != nil || filteredPoint2.comment != nil {
            totalFields += 1
            if filteredPoint1.comment == filteredPoint2.comment { matchingFields += 1 }
        }
        
        if filteredPoint1.desc != nil || filteredPoint2.desc != nil {
            totalFields += 1
            if filteredPoint1.desc == filteredPoint2.desc { matchingFields += 1 }
        }
        
        if filteredPoint1.source != nil || filteredPoint2.source != nil {
            totalFields += 1
            if filteredPoint1.source == filteredPoint2.source { matchingFields += 1 }
        }
        
        if filteredPoint1.symbol != nil || filteredPoint2.symbol != nil {
            totalFields += 1
            if filteredPoint1.symbol == filteredPoint2.symbol { matchingFields += 1 }
        }
        
        if filteredPoint1.type != nil || filteredPoint2.type != nil {
            totalFields += 1
            if filteredPoint1.type == filteredPoint2.type { matchingFields += 1 }
        }
        
        if filteredPoint1.fix != nil || filteredPoint2.fix != nil {
            totalFields += 1
            if filteredPoint1.fix == filteredPoint2.fix { matchingFields += 1 }
        }
        
        if filteredPoint1.satellites != nil || filteredPoint2.satellites != nil {
            totalFields += 1
            if filteredPoint1.satellites == filteredPoint2.satellites { matchingFields += 1 }
        }
        
        if filteredPoint1.horizontalDilution != nil || filteredPoint2.horizontalDilution != nil {
            totalFields += 1
            if let hd1 = filteredPoint1.horizontalDilution, let hd2 = filteredPoint2.horizontalDilution, 
               abs(hd1 - hd2) < Constants.dilutionOfPrecisionTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.verticalDilution != nil || filteredPoint2.verticalDilution != nil {
            totalFields += 1
            if let vd1 = filteredPoint1.verticalDilution, let vd2 = filteredPoint2.verticalDilution, 
               abs(vd1 - vd2) < Constants.dilutionOfPrecisionTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.positionDilution != nil || filteredPoint2.positionDilution != nil {
            totalFields += 1
            if let pd1 = filteredPoint1.positionDilution, let pd2 = filteredPoint2.positionDilution, 
               abs(pd1 - pd2) < Constants.dilutionOfPrecisionTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.ageofDGPSData != nil || filteredPoint2.ageofDGPSData != nil {
            totalFields += 1
            if let age1 = filteredPoint1.ageofDGPSData, let age2 = filteredPoint2.ageofDGPSData, 
               abs(age1 - age2) < Constants.ageofDGPSDataTolerance {
                matchingFields += 1
            }
        }
        
        if filteredPoint1.DGPSid != nil || filteredPoint2.DGPSid != nil {
            totalFields += 1
            if filteredPoint1.DGPSid == filteredPoint2.DGPSid { matchingFields += 1 }
        }
        
        if !filteredPoint1.links.isEmpty || !filteredPoint2.links.isEmpty {
            totalFields += 1
            
            if filteredPoint1.links.count == filteredPoint2.links.count {
                let hrefs1 = Set(filteredPoint1.links.compactMap { $0.href })
                let hrefs2 = Set(filteredPoint2.links.compactMap { $0.href })
                
                if hrefs1 == hrefs2 {
                    matchingFields += 1
                }
            }
        }
        
        if filteredPoint1.extensions != nil || filteredPoint2.extensions != nil {
            totalFields += 1
            if areExtensionsTheSame(filteredPoint1.extensions, filteredPoint2.extensions) {
                matchingFields += 1
            }
        }
        
        let requiredPercentage: Double
        switch confidenceLevel {
        case 1: requiredPercentage = Constants.confidenceLevel1RequiredPercentage
        case 2: requiredPercentage = Constants.confidenceLevel2RequiredPercentage
        case 3: requiredPercentage = Constants.confidenceLevel3RequiredPercentage
        case 4: requiredPercentage = Constants.confidenceLevel4RequiredPercentage
        case 5: requiredPercentage = Constants.confidenceLevel5RequiredPercentage
        default: requiredPercentage = Constants.confidenceLevel3RequiredPercentage
        }
        
        guard totalFields > 0 else { return false }
        
        let matchPercentage = Double(matchingFields) / Double(totalFields)
        let result = matchPercentage >= requiredPercentage
        LogManager.shared.logData(context: "GPXUtils", content: "arePointsTheSame: Fields matched: \(matchingFields)/\(totalFields) (\(String(format: "%.2f", matchPercentage * 100))%). Required: \(String(format: "%.2f", requiredPercentage * 100))%. Result: \(result).", verbosity: 5)
        return result
    }
    
    static func areTracksTheSame(_ track1: GPXTrack, _ track2: GPXTrack, confidenceLevel: Int) -> Bool {
        LogManager.shared.logData(context: "GPXUtils", content: "areTracksTheSame called with confidence level \(confidenceLevel). Track1 segments: \(track1.segments.count), Track2 segments: \(track2.segments.count).", verbosity: 5)
        guard confidenceLevel >= 1 && confidenceLevel <= 5 else {
            LogManager.shared.logData(context: "GPXUtils", content: "areTracksTheSame: Invalid confidence level \(confidenceLevel). Defaulting to 3.", verbosity: 2)
            return areTracksTheSame(track1, track2, confidenceLevel: 3)
        }
        
        if track1.segments.count != track2.segments.count {
            return false
        }
        
        let trackSettings = SettingsManager.shared.gpxExportSettings.tracks
        let tpSettings = SettingsManager.shared.gpxExportSettings.trackpoints
        
        let filteredTrack1 = deepCopyTrack(track1)
        if !trackSettings.name.export { filteredTrack1.name = nil }
        if !trackSettings.comment.export { filteredTrack1.comment = nil }
        if !trackSettings.desc.export { filteredTrack1.desc = nil }
        if !trackSettings.source.export { filteredTrack1.source = nil }
        if !trackSettings.number.export { filteredTrack1.number = nil }
        if !trackSettings.type.export { filteredTrack1.type = nil }
        if !trackSettings.links.export { filteredTrack1.links.removeAll() }
        filteredTrack1.extensions = filterExtensions(filteredTrack1.extensions, fields: trackSettings)
        
        let filteredTrack2 = deepCopyTrack(track2)
        if !trackSettings.name.export { filteredTrack2.name = nil }
        if !trackSettings.comment.export { filteredTrack2.comment = nil }
        if !trackSettings.desc.export { filteredTrack2.desc = nil }
        if !trackSettings.source.export { filteredTrack2.source = nil }
        if !trackSettings.number.export { filteredTrack2.number = nil }
        if !trackSettings.type.export { filteredTrack2.type = nil }
        if !trackSettings.links.export { filteredTrack2.links.removeAll() }
        filteredTrack2.extensions = filterExtensions(filteredTrack2.extensions, fields: trackSettings)
        
        var totalFields = 0
        var matchingFields = 0
        
        if filteredTrack1.name != nil || filteredTrack2.name != nil {
            totalFields += 1
            if filteredTrack1.name == filteredTrack2.name { matchingFields += 1 }
        }
        
        if filteredTrack1.comment != nil || filteredTrack2.comment != nil {
            totalFields += 1
            if filteredTrack1.comment == filteredTrack2.comment { matchingFields += 1 }
        }
        
        if filteredTrack1.desc != nil || filteredTrack2.desc != nil {
            totalFields += 1
            if filteredTrack1.desc == filteredTrack2.desc { matchingFields += 1 }
        }
        
        if filteredTrack1.source != nil || filteredTrack2.source != nil {
            totalFields += 1
            if filteredTrack1.source == filteredTrack2.source { matchingFields += 1 }
        }
        
        if filteredTrack1.number != nil || filteredTrack2.number != nil {
            totalFields += 1
            if filteredTrack1.number == filteredTrack2.number { matchingFields += 1 }
        }
        
        if filteredTrack1.type != nil || filteredTrack2.type != nil {
            totalFields += 1
            if filteredTrack1.type == filteredTrack2.type { matchingFields += 1 }
        }
        
        if !filteredTrack1.links.isEmpty || !filteredTrack2.links.isEmpty {
            totalFields += 1
            
            if filteredTrack1.links.count == filteredTrack2.links.count {
                let hrefs1 = Set(filteredTrack1.links.compactMap { $0.href })
                let hrefs2 = Set(filteredTrack2.links.compactMap { $0.href })
                
                if hrefs1 == hrefs2 {
                    matchingFields += 1
                }
            }
        }
        
        if filteredTrack1.extensions != nil || filteredTrack2.extensions != nil {
            totalFields += 1
            if areExtensionsTheSame(filteredTrack1.extensions, filteredTrack2.extensions) {
                matchingFields += 1
            }
        }
        
        for i in 0..<filteredTrack1.segments.count {
            let segment1 = filteredTrack1.segments[i]
            let segment2 = filteredTrack2.segments[i]
            
            if segment1.points.count != segment2.points.count {
                return false
            }
            
            if segment1.extensions != nil || segment2.extensions != nil {
                totalFields += 1
                if areExtensionsTheSame(segment1.extensions, segment2.extensions) {
                    matchingFields += 1
                }
            }
            
            for j in 0..<segment1.points.count {
                let point1 = segment1.points[j]
                let point2 = segment2.points[j]
                
                totalFields += 1
                if arePointsTheSame(point1, point2, confidenceLevel: confidenceLevel, fields: tpSettings) {
                    matchingFields += 1
                }
            }
        }
        
        let requiredPercentage: Double
        switch confidenceLevel {
        case 1: requiredPercentage = Constants.confidenceLevel1RequiredPercentage
        case 2: requiredPercentage = Constants.confidenceLevel2RequiredPercentage
        case 3: requiredPercentage = Constants.confidenceLevel3RequiredPercentage
        case 4: requiredPercentage = Constants.confidenceLevel4RequiredPercentage
        case 5: requiredPercentage = Constants.confidenceLevel5RequiredPercentage
        default: requiredPercentage = Constants.confidenceLevel3RequiredPercentage
        }
        
        guard totalFields > 0 else { return false }
        
        let matchPercentage = Double(matchingFields) / Double(totalFields)
        let result = matchPercentage >= requiredPercentage
        LogManager.shared.logData(context: "GPXUtils", content: "areTracksTheSame: Fields matched: \(matchingFields)/\(totalFields) (\(String(format: "%.2f", matchPercentage * 100))%). Required: \(String(format: "%.2f", requiredPercentage * 100))%. Result: \(result).", verbosity: 5)
        return result
    }

    static func getMatchingPlace(for waypoint: GPXWaypoint) -> Place? {
        let allPlaces = PlaceManager.shared.getAllPlaces()
        let waypointPlaceId = waypoint.extensions?["PlaceId"].text
        if let waypointPlaceId = waypointPlaceId, !waypointPlaceId.isEmpty {
            if waypointPlaceId == "-1" { return nil } // One-time visit
            if let place = allPlaces.first(where: { $0.placeId == waypointPlaceId || ($0.previousIds?.contains(waypointPlaceId) ?? false) }) {
                return place
            }
        }
        // Fallback: match by coordinates if waypoint has a place-like name matching a place
        if let lat = waypoint.latitude, let lon = waypoint.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if let place = PlaceManager.shared.findPlaceAtCoordinates(for: coord) {
                if let wpName = waypoint.name, wpName == place.name {
                    return place
                }
            }
        }
        return nil
    }



    static func isWaypointPlaceInfoOutdated(_ waypoint: GPXWaypoint, matchingPlace place: Place) -> Bool {
        if (waypoint.name ?? "") != place.name { return true }
        if (waypoint.symbol ?? "") != (place.customIcon ?? "") { return true }

        func ext(_ key: String) -> String {
            return waypoint.extensions?[key].text ?? ""
        }
        func str(_ val: String?) -> String {
            return val ?? ""
        }

        if ext("PlaceId") != place.placeId { return true }
        if ext("Address") != str(place.streetAddress) { return true }
        if ext("FacebookPlaceId") != str(place.facebookPlaceId) { return true }
        if ext("MapboxPlaceId") != str(place.mapboxPlaceId) { return true }
        if ext("FoursquareVenueId") != str(place.foursquareVenueId) { return true }
        if ext("FoursquareCategoryId") != str(place.foursquareCategoryId) { return true }
        if ext("GooglePlacesId") != str(place.googlePlacesId) { return true }
        if ext("YelpId") != str(place.yelpId) { return true }
        if ext("ApplePlaceId") != str(place.applePlaceId) { return true }
        if ext("OsmNodeId") != str(place.osmNodeId) { return true }
        if ext("HerePlaceId") != str(place.herePlaceId) { return true }
        if ext("GaodePlaceId") != str(place.gaodePlaceId) { return true }

        return false
    }

    static func updateWaypointMetadataFromPlace(updatedWaypoint: GPXWaypoint, place: Place) -> GPXWaypoint {
        LogManager.shared.logData(context: "GPXUtils", content: "updateWaypointMetadataFromPlace called for waypoint at time \(updatedWaypoint.time?.description ?? "N/A") with place: \(place.name).", verbosity: 4)
        updatedWaypoint.name = place.name
        updatedWaypoint.symbol = place.customIcon
        
        let placeRelatedKeys = [
            "PlaceId", "Address", "FacebookPlaceId", "MapboxPlaceId",
            "FoursquareVenueId", "FoursquareCategoryId", "GooglePlacesId",
            "YelpId", "ApplePlaceId", "OsmNodeId", "HerePlaceId", "GaodePlaceId"
        ]

        var combinedData = [String: String]()
        if let existing = updatedWaypoint.extensions {
            for child in existing.children {
                let k = child.name
                if let v = child.text, !k.isEmpty, !placeRelatedKeys.contains(k) {
                    combinedData[k] = v
                }
            }
        }
        
        combinedData["PlaceId"] = place.placeId
        if let address = place.streetAddress, !address.isEmpty { combinedData["Address"] = address }
        if let fbId = place.facebookPlaceId, !fbId.isEmpty { combinedData["FacebookPlaceId"] = fbId }
        if let mapboxId = place.mapboxPlaceId, !mapboxId.isEmpty { combinedData["MapboxPlaceId"] = mapboxId }
        if let foursquareId = place.foursquareVenueId, !foursquareId.isEmpty { combinedData["FoursquareVenueId"] = foursquareId }
        if let categoryId = place.foursquareCategoryId, !categoryId.isEmpty { combinedData["FoursquareCategoryId"] = categoryId }
        if let googleId = place.googlePlacesId, !googleId.isEmpty { combinedData["GooglePlacesId"] = googleId }
        if let yelpId = place.yelpId, !yelpId.isEmpty { combinedData["YelpId"] = yelpId }
        if let appleId = place.applePlaceId, !appleId.isEmpty { combinedData["ApplePlaceId"] = appleId }
        if let osmId = place.osmNodeId, !osmId.isEmpty { combinedData["OsmNodeId"] = osmId }
        if let hereId = place.herePlaceId, !hereId.isEmpty { combinedData["HerePlaceId"] = hereId }
        if let gaodeId = place.gaodePlaceId, !gaodeId.isEmpty { combinedData["GaodePlaceId"] = gaodeId }
        
        if !combinedData.isEmpty {
            let newExtensions = GPXExtensions()
            newExtensions.append(at: nil, contents: combinedData)
            updatedWaypoint.extensions = newExtensions
        } else {
            updatedWaypoint.extensions = nil
        }

        LogManager.shared.logData(context: "GPXUtils", content: "updateWaypointMetadataFromPlace finished updating waypoint.", verbosity: 4)
        return updatedWaypoint
    }
    
    static func exportFilteredCopy(waypoints: [GPXWaypoint], tracks: [GPXTrack], settings: GPXExportSettings) -> ([GPXWaypoint], [GPXTrack]) {
        let filteredWaypoints = waypoints.map { wp -> GPXWaypoint in
            let copy = deepCopyAsWaypoint(wp)
            filterPoint(copy, fields: settings.waypoints)
            return copy
        }
        
        let filteredTracks = tracks.map { trk -> GPXTrack in
            let copy = deepCopyTrack(trk)
            if !settings.tracks.name.export { copy.name = nil }
            if !settings.tracks.comment.export { copy.comment = nil }
            if !settings.tracks.desc.export { copy.desc = nil }
            if !settings.tracks.source.export { copy.source = nil }
            if !settings.tracks.number.export { copy.number = nil }
            if !settings.tracks.type.export { copy.type = nil }
            if !settings.tracks.links.export { copy.links.removeAll() }
            copy.extensions = filterExtensions(copy.extensions, fields: settings.tracks)
            
            for segment in copy.segments {
                for pt in segment.points {
                    filterPoint(pt, fields: settings.trackpoints)
                }
            }
            return copy
        }
        
        return (filteredWaypoints, filteredTracks)
    }

    private static func filterPoint(_ point: GPXWaypoint, fields: GPXExportFields) {
        if !fields.magneticVariation.export { point.magneticVariation = nil }
        if !fields.geoidHeight.export { point.geoidHeight = nil }
        if !fields.name.export { point.name = nil }
        if !fields.comment.export { point.comment = nil }
        if !fields.desc.export { point.desc = nil }
        if !fields.source.export { point.source = nil }
        if !fields.symbol.export { point.symbol = nil }
        if !fields.type.export { point.type = nil }
        if !fields.fix.export { point.fix = nil }
        if !fields.satellites.export { point.satellites = nil }
        if !fields.horizontalDilution.export { point.horizontalDilution = nil }
        if !fields.verticalDilution.export { point.verticalDilution = nil }
        if !fields.positionDilution.export { point.positionDilution = nil }
        if !fields.ageofDGPSData.export { point.ageofDGPSData = nil }
        if !fields.DGPSid.export { point.DGPSid = nil }
        if !fields.links.export { point.links.removeAll() }
        
        point.extensions = filterExtensions(point.extensions, fields: fields)
    }
    
    private static func filterExtensions(_ extensions: GPXExtensions?, fields: GPXExportFields) -> GPXExtensions? {
        guard let sourceExtensions = extensions else { return nil }
        var extensionsDict = [String: String]()
        
        for child in sourceExtensions.children {
            let key = child.name
            if let value = child.text, !key.isEmpty {
                if fields.extensions[key]?.export != false {
                    extensionsDict[key] = value
                }
            }
        }
        
        if !extensionsDict.isEmpty {
            let newExtensions = GPXExtensions()
            newExtensions.append(at: nil, contents: extensionsDict)
            return newExtensions
        }
        return nil
    }

    // MARK: - Split Logic

    static func splitWaypoint(_ waypoint: GPXWaypoint, at splitTime: Date, retainMetadataInFirst: Bool) -> (GPXWaypoint, GPXWaypoint) {
        let first: GPXWaypoint
        let second: GPXWaypoint
        
        let blankPoint = GPXWaypoint(latitude: waypoint.latitude ?? 0.0, longitude: waypoint.longitude ?? 0.0)
        
        // Preserve only the timezone offset for the blank point so it renders at the correct local time
        if let extensions = waypoint.extensions {
            for child in extensions.children {
                if child.name == GPXExtensionKey.timezoneOffset.rawValue {
                    let newExt = GPXExtensions()
                    newExt.append(at: nil, contents: [GPXExtensionKey.timezoneOffset.rawValue: child.text ?? ""])
                    blankPoint.extensions = newExt
                    break
                }
            }
        }
        
        if retainMetadataInFirst {
            first = deepCopyPoint(waypoint)
            first.time = waypoint.time
            second = blankPoint
            second.time = splitTime
        } else {
            first = blankPoint
            first.time = waypoint.time
            second = deepCopyPoint(waypoint)
            second.time = splitTime
        }
        
        return (first, second)
    }
    
    static func splitTrack(_ track: GPXTrack, at splitTime: Date) -> (GPXTrack, GPXTrack) {
        let track1 = GPXTrack()
        let track2 = GPXTrack()
        
        track1.name = track.name
        track1.desc = track.desc
        track1.type = track.type
        track1.source = track.source
        
        track2.name = track.name
        track2.desc = track.desc
        track2.type = track.type
        track2.source = track.source
        
        for segment in track.segments {
            let seg1 = GPXTrackSegment()
            let seg2 = GPXTrackSegment()
            
            for point in segment.points {
                if let ptTime = point.time {
                    if ptTime <= splitTime {
                        seg1.add(trackpoint: deepCopyPoint(point) as! GPXTrackPoint)
                    } else {
                        seg2.add(trackpoint: deepCopyPoint(point) as! GPXTrackPoint)
                    }
                } else {
                    // Without time, default to appending to seg1
                    seg1.add(trackpoint: deepCopyPoint(point) as! GPXTrackPoint)
                }
            }
            
            if !seg1.points.isEmpty {
                track1.add(trackSegment: seg1)
            }
            if !seg2.points.isEmpty {
                track2.add(trackSegment: seg2)
            }
        }
        
        return (track1, track2)
    }
} 
