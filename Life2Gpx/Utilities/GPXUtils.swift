import Foundation
import CoreGPX

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
        FileManagerUtil.logData(context: "GPXUtils", content: "copyExtensions called.", verbosity: 5)
        
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
            FileManagerUtil.logData(context: "GPXUtils", content: "copyExtensions created new extensions object with \(extensionsDict.count) items.", verbosity: 5)
            return newExtensions
        }
        
        FileManagerUtil.logData(context: "GPXUtils", content: "copyExtensions found no extensions to copy.", verbosity: 5)
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
        FileManagerUtil.logData(context: "GPXUtils", content: "deepCopyPoint called for point at time \(point.time?.description ?? "N/A").", verbosity: 5)
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
        FileManagerUtil.logData(context: "GPXUtils", content: "deepCopyAsWaypoint called for point at time \(point.time?.description ?? "N/A").", verbosity: 5)
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
        
        FileManagerUtil.logData(context: "GPXUtils", content: "deepCopyPoint finished copying point.", verbosity: 5)
    }
    
    static func deepCopyTrack(_ track: GPXTrack) -> GPXTrack {
        FileManagerUtil.logData(context: "GPXUtils", content: "deepCopyTrack called for track named '\(track.name ?? "Unnamed")'.", verbosity: 5)
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
        
        FileManagerUtil.logData(context: "GPXUtils", content: "deepCopyTrack finished copying track with \(copy.segments.count) segments.", verbosity: 5)
        return copy
    }
    
    static func arePointsTheSame(_ point1: GPXWaypoint, _ point2: GPXWaypoint, confidenceLevel: Int) -> Bool {
        FileManagerUtil.logData(context: "GPXUtils", content: "arePointsTheSame called with confidence level \(confidenceLevel).", verbosity: 5)
        guard confidenceLevel >= 1 && confidenceLevel <= 5 else {
            FileManagerUtil.logData(context: "GPXUtils", content: "arePointsTheSame: Invalid confidence level \(confidenceLevel). Defaulting to 3.", verbosity: 2)
            return arePointsTheSame(point1, point2, confidenceLevel: 3)
        }
        
        var totalFields = 0
        var matchingFields = 0
        
        if let lat1 = point1.latitude, let lat2 = point2.latitude, 
           let lon1 = point1.longitude, let lon2 = point2.longitude {
            totalFields += 2
            if abs(lat1 - lat2) < Constants.coordinateEqualityTolerance { matchingFields += 1 }
            if abs(lon1 - lon2) < Constants.coordinateEqualityTolerance { matchingFields += 1 }
        }
        
        if point1.elevation != nil || point2.elevation != nil {
            totalFields += 1
            if let elevation1 = point1.elevation, let elevation2 = point2.elevation, 
               abs(elevation1 - elevation2) < Constants.elevationEqualityTolerance {
                matchingFields += 1
            }
        }
        
        if point1.time != nil || point2.time != nil {
            totalFields += 1
            if let time1 = point1.time, let time2 = point2.time,
               abs(time1.timeIntervalSince(time2)) < Constants.timeEqualityTolerance {
                matchingFields += 1
            }
        }
        
        if point1.magneticVariation != nil || point2.magneticVariation != nil {
            totalFields += 1
            if let mv1 = point1.magneticVariation, let mv2 = point2.magneticVariation,
               abs(mv1 - mv2) < Constants.magneticVariationTolerance {
                matchingFields += 1
            }
        }
        
        if point1.geoidHeight != nil || point2.geoidHeight != nil {
            totalFields += 1
            if let gh1 = point1.geoidHeight, let gh2 = point2.geoidHeight,
               abs(gh1 - gh2) < Constants.geoidHeightTolerance {
                matchingFields += 1
            }
        }
        
        if point1.name != nil || point2.name != nil {
            totalFields += 1
            if point1.name == point2.name { matchingFields += 1 }
        }
        
        if point1.comment != nil || point2.comment != nil {
            totalFields += 1
            if point1.comment == point2.comment { matchingFields += 1 }
        }
        
        if point1.desc != nil || point2.desc != nil {
            totalFields += 1
            if point1.desc == point2.desc { matchingFields += 1 }
        }
        
        if point1.source != nil || point2.source != nil {
            totalFields += 1
            if point1.source == point2.source { matchingFields += 1 }
        }
        
        if point1.symbol != nil || point2.symbol != nil {
            totalFields += 1
            if point1.symbol == point2.symbol { matchingFields += 1 }
        }
        
        if point1.type != nil || point2.type != nil {
            totalFields += 1
            if point1.type == point2.type { matchingFields += 1 }
        }
        
        if point1.fix != nil || point2.fix != nil {
            totalFields += 1
            if point1.fix == point2.fix { matchingFields += 1 }
        }
        
        if point1.satellites != nil || point2.satellites != nil {
            totalFields += 1
            if point1.satellites == point2.satellites { matchingFields += 1 }
        }
        
        if point1.horizontalDilution != nil || point2.horizontalDilution != nil {
            totalFields += 1
            if let hd1 = point1.horizontalDilution, let hd2 = point2.horizontalDilution, 
               abs(hd1 - hd2) < Constants.dilutionOfPrecisionTolerance {
                matchingFields += 1
            }
        }
        
        if point1.verticalDilution != nil || point2.verticalDilution != nil {
            totalFields += 1
            if let vd1 = point1.verticalDilution, let vd2 = point2.verticalDilution, 
               abs(vd1 - vd2) < Constants.dilutionOfPrecisionTolerance {
                matchingFields += 1
            }
        }
        
        if point1.positionDilution != nil || point2.positionDilution != nil {
            totalFields += 1
            if let pd1 = point1.positionDilution, let pd2 = point2.positionDilution, 
               abs(pd1 - pd2) < Constants.dilutionOfPrecisionTolerance {
                matchingFields += 1
            }
        }
        
        if point1.ageofDGPSData != nil || point2.ageofDGPSData != nil {
            totalFields += 1
            if let age1 = point1.ageofDGPSData, let age2 = point2.ageofDGPSData, 
               abs(age1 - age2) < Constants.ageofDGPSDataTolerance {
                matchingFields += 1
            }
        }
        
        if point1.DGPSid != nil || point2.DGPSid != nil {
            totalFields += 1
            if point1.DGPSid == point2.DGPSid { matchingFields += 1 }
        }
        
        if !point1.links.isEmpty || !point2.links.isEmpty {
            totalFields += 1
            
            if point1.links.count == point2.links.count {
                let hrefs1 = Set(point1.links.compactMap { $0.href })
                let hrefs2 = Set(point2.links.compactMap { $0.href })
                
                if hrefs1 == hrefs2 {
                    matchingFields += 1
                }
            }
        }
        
        if point1.extensions != nil || point2.extensions != nil {
            totalFields += 1
            
            if let ext1 = point1.extensions, let ext2 = point2.extensions {
                if let contents1 = ext1.get(from: nil), let contents2 = ext2.get(from: nil),
                   contents1 == contents2 {
                    matchingFields += 1
                } else {
                    let children1 = Set(ext1.children.map { $0.name })
                    let children2 = Set(ext2.children.map { $0.name })
                    
                    if children1 == children2 {
                        var childrenMatch = true
                        for childName in children1 {
                            if let childContent1 = ext1.get(from: childName),
                               let childContent2 = ext2.get(from: childName),
                               childContent1 != childContent2 {
                                childrenMatch = false
                                break
                            }
                        }
                        
                        if childrenMatch {
                            matchingFields += 1
                        }
                    }
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
        FileManagerUtil.logData(context: "GPXUtils", content: "arePointsTheSame: Fields matched: \(matchingFields)/\(totalFields) (\(String(format: "%.2f", matchPercentage * 100))%). Required: \(String(format: "%.2f", requiredPercentage * 100))%. Result: \(result).", verbosity: 5)
        return result
    }
    
    static func areTracksTheSame(_ track1: GPXTrack, _ track2: GPXTrack, confidenceLevel: Int) -> Bool {
        FileManagerUtil.logData(context: "GPXUtils", content: "areTracksTheSame called with confidence level \(confidenceLevel). Track1 segments: \(track1.segments.count), Track2 segments: \(track2.segments.count).", verbosity: 5)
        guard confidenceLevel >= 1 && confidenceLevel <= 5 else {
            FileManagerUtil.logData(context: "GPXUtils", content: "areTracksTheSame: Invalid confidence level \(confidenceLevel). Defaulting to 3.", verbosity: 2)
            return areTracksTheSame(track1, track2, confidenceLevel: 3)
        }
        
        if track1.segments.count != track2.segments.count {
            return false
        }
        
        var totalFields = 0
        var matchingFields = 0
        
        if track1.name != nil || track2.name != nil {
            totalFields += 1
            if track1.name == track2.name { matchingFields += 1 }
        }
        
        if track1.comment != nil || track2.comment != nil {
            totalFields += 1
            if track1.comment == track2.comment { matchingFields += 1 }
        }
        
        if track1.desc != nil || track2.desc != nil {
            totalFields += 1
            if track1.desc == track2.desc { matchingFields += 1 }
        }
        
        if track1.source != nil || track2.source != nil {
            totalFields += 1
            if track1.source == track2.source { matchingFields += 1 }
        }
        
        if track1.number != nil || track2.number != nil {
            totalFields += 1
            if track1.number == track2.number { matchingFields += 1 }
        }
        
        if track1.type != nil || track2.type != nil {
            totalFields += 1
            if track1.type == track2.type { matchingFields += 1 }
        }
        
        if !track1.links.isEmpty || !track2.links.isEmpty {
            totalFields += 1
            
            if track1.links.count == track2.links.count {
                let hrefs1 = Set(track1.links.compactMap { $0.href })
                let hrefs2 = Set(track2.links.compactMap { $0.href })
                
                if hrefs1 == hrefs2 {
                    matchingFields += 1
                }
            }
        }
        
        if track1.extensions != nil || track2.extensions != nil {
            totalFields += 1
            
            if let ext1 = track1.extensions, let ext2 = track2.extensions {
                if let contents1 = ext1.get(from: nil), let contents2 = ext2.get(from: nil),
                   contents1 == contents2 {
                    matchingFields += 1
                } else {
                    let children1 = Set(ext1.children.map { $0.name })
                    let children2 = Set(ext2.children.map { $0.name })
                    
                    if children1 == children2 {
                        var childrenMatch = true
                        
                        for childName in children1 {
                            if let childContent1 = ext1.get(from: childName),
                               let childContent2 = ext2.get(from: childName),
                               childContent1 != childContent2 {
                                childrenMatch = false
                                break
                            }
                        }
                        
                        if childrenMatch {
                            matchingFields += 1
                        }
                    }
                }
            }
        }
        
        for i in 0..<track1.segments.count {
            let segment1 = track1.segments[i]
            let segment2 = track2.segments[i]
            
            if segment1.points.count != segment2.points.count {
                return false
            }
            
            if segment1.extensions != nil || segment2.extensions != nil {
                totalFields += 1
                
                if let ext1 = segment1.extensions, let ext2 = segment2.extensions {
                    if let contents1 = ext1.get(from: nil), let contents2 = ext2.get(from: nil),
                       contents1 == contents2 {
                        matchingFields += 1
                    } else {
                        let children1 = Set(ext1.children.map { $0.name })
                        let children2 = Set(ext2.children.map { $0.name })
                        
                        if children1 == children2 {
                            var childrenMatch = true
                            
                            for childName in children1 {
                                if let childContent1 = ext1.get(from: childName),
                                   let childContent2 = ext2.get(from: childName),
                                   childContent1 != childContent2 {
                                    childrenMatch = false
                                    break
                                }
                            }
                            
                            if childrenMatch {
                                matchingFields += 1
                            }
                        }
                    }
                }
            }
            
            for j in 0..<segment1.points.count {
                let point1 = segment1.points[j]
                let point2 = segment2.points[j]
                
                totalFields += 1
                if arePointsTheSame(point1, point2, confidenceLevel: confidenceLevel) {
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
        FileManagerUtil.logData(context: "GPXUtils", content: "areTracksTheSame: Fields matched: \(matchingFields)/\(totalFields) (\(String(format: "%.2f", matchPercentage * 100))%). Required: \(String(format: "%.2f", requiredPercentage * 100))%. Result: \(result).", verbosity: 5)
        return result
    }

    static func updateWaypointMetadataFromPlace(updatedWaypoint: GPXWaypoint, place: Place) -> GPXWaypoint {
        FileManagerUtil.logData(context: "GPXUtils", content: "updateWaypointMetadataFromPlace called for waypoint at time \(updatedWaypoint.time?.description ?? "N/A") with place: \(place.name).", verbosity: 4)
        updatedWaypoint.name = place.name
        
        var extensionData: [String: String] = [
            "PlaceId": place.placeId
        ]
        
        if let address = place.streetAddress {
            extensionData["Address"] = address
        }
        if let fbId = place.facebookPlaceId {
            extensionData["FacebookPlaceId"] = fbId
        }
        if let mapboxId = place.mapboxPlaceId {
            extensionData["MapboxPlaceId"] = mapboxId
        }
        if let foursquareId = place.foursquareVenueId {
            extensionData["FoursquareVenueId"] = foursquareId
        }
        if let categoryId = place.foursquareCategoryId {
            extensionData["FoursquareCategoryId"] = categoryId
        }
        if let googleId = place.googlePlacesId {
            extensionData["GooglePlacesId"] = googleId
        }
        if let yelpId = place.yelpId {
            extensionData["YelpId"] = yelpId
        }
        if let appleId = place.applePlaceId {
            extensionData["ApplePlaceId"] = appleId
        }
        if let osmId = place.osmNodeId {
            extensionData["OsmNodeId"] = osmId
        }
        if let hereId = place.herePlaceId {
            extensionData["HerePlaceId"] = hereId
        }
        if let gaodeId = place.gaodePlaceId {
            extensionData["GaodePlaceId"] = gaodeId
        }
        
        GPXUtils.updateExtension(for: updatedWaypoint, with: extensionData)
        FileManagerUtil.logData(context: "GPXUtils", content: "updateWaypointMetadataFromPlace finished updating waypoint.", verbosity: 4)
        
        return updatedWaypoint
    }
} 
