import Foundation
import CoreGPX

class GPXUtils {
    static func copyExtensions(_ extensions: GPXExtensions?) -> GPXExtensions? {
        guard let extensions = extensions else { return nil }
        
        let newExtensions = GPXExtensions()
        
        if let contents = extensions.get(from: nil) {
            newExtensions.append(at: nil, contents: contents)
        }
        
        for child in extensions.children {
            let parentTagName = child.name
            if let contents = extensions.get(from: parentTagName) {
                newExtensions.append(at: parentTagName, contents: contents)
            }
        }
        
        return newExtensions
    }
    
    static func deepCopyPoint(_ point: GPXWaypoint) -> GPXWaypoint {
        let copy: GPXWaypoint
        
        if point is GPXTrackPoint {
            copy = GPXTrackPoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
        } else {
            copy = GPXWaypoint(latitude: point.latitude ?? 0, longitude: point.longitude ?? 0)
        }
        
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
        
        return copy
    }
    
    static func deepCopyTrack(_ track: GPXTrack) -> GPXTrack {
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
        
        return copy
    }
    
    static func arePointsTheSame(_ point1: GPXWaypoint, _ point2: GPXWaypoint, confidenceLevel: Int) -> Bool {
        guard confidenceLevel >= 1 && confidenceLevel <= 5 else {
            // Default to medium confidence if invalid level provided
            return arePointsTheSame(point1, point2, confidenceLevel: 3)
        }
        
        var totalFields = 0
        var matchingFields = 0
        
        if let lat1 = point1.latitude, let lat2 = point2.latitude, 
           let lon1 = point1.longitude, let lon2 = point2.longitude {
            totalFields += 2
            if abs(lat1 - lat2) < 0.00001 { matchingFields += 1 }
            if abs(lon1 - lon2) < 0.00001 { matchingFields += 1 }
        }
        
        if point1.elevation != nil || point2.elevation != nil {
            totalFields += 1
            if let elevation1 = point1.elevation, let elevation2 = point2.elevation, 
               abs(elevation1 - elevation2) < 0.1 {
                matchingFields += 1
            }
        }
        
        if point1.time != nil || point2.time != nil {
            totalFields += 1
            if let time1 = point1.time, let time2 = point2.time,
               abs(time1.timeIntervalSince(time2)) < 1.0 {
                matchingFields += 1
            }
        }
        
        if point1.magneticVariation != nil || point2.magneticVariation != nil {
            totalFields += 1
            if let mv1 = point1.magneticVariation, let mv2 = point2.magneticVariation,
               abs(mv1 - mv2) < 0.01 {
                matchingFields += 1
            }
        }
        
        if point1.geoidHeight != nil || point2.geoidHeight != nil {
            totalFields += 1
            if let gh1 = point1.geoidHeight, let gh2 = point2.geoidHeight,
               abs(gh1 - gh2) < 0.1 {
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
               abs(hd1 - hd2) < 0.01 {
                matchingFields += 1
            }
        }
        
        if point1.verticalDilution != nil || point2.verticalDilution != nil {
            totalFields += 1
            if let vd1 = point1.verticalDilution, let vd2 = point2.verticalDilution, 
               abs(vd1 - vd2) < 0.01 {
                matchingFields += 1
            }
        }
        
        if point1.positionDilution != nil || point2.positionDilution != nil {
            totalFields += 1
            if let pd1 = point1.positionDilution, let pd2 = point2.positionDilution, 
               abs(pd1 - pd2) < 0.01 {
                matchingFields += 1
            }
        }
        
        if point1.ageofDGPSData != nil || point2.ageofDGPSData != nil {
            totalFields += 1
            if let age1 = point1.ageofDGPSData, let age2 = point2.ageofDGPSData, 
               abs(age1 - age2) < 0.1 {
                matchingFields += 1
            }
        }
        
        if point1.DGPSid != nil || point2.DGPSid != nil {
            totalFields += 1
            if point1.DGPSid == point2.DGPSid { matchingFields += 1 }
        }
        
        // Compare links
        if !point1.links.isEmpty || !point2.links.isEmpty {
            totalFields += 1
            
            // Simple check - if same number of links, check if all hrefs match
            if point1.links.count == point2.links.count {
                let hrefs1 = Set(point1.links.compactMap { $0.href })
                let hrefs2 = Set(point2.links.compactMap { $0.href })
                
                if hrefs1 == hrefs2 {
                    matchingFields += 1
                }
            }
        }
        
        // Compare extensions
        if point1.extensions != nil || point2.extensions != nil {
            totalFields += 1
            
            if let ext1 = point1.extensions, let ext2 = point2.extensions {
                // Compare root contents
                if let contents1 = ext1.get(from: nil), let contents2 = ext2.get(from: nil),
                   contents1 == contents2 {
                    matchingFields += 1
                } else {
                    // Compare by checking child elements
                    let children1 = Set(ext1.children.map { $0.name })
                    let children2 = Set(ext2.children.map { $0.name })
                    
                    if children1 == children2 {
                        // If the same child elements exist, check if their contents match
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
        
        // Calculate minimum required match percentage based on confidence level
        let requiredPercentage: Double
        switch confidenceLevel {
        case 1: requiredPercentage = 0.2
        case 2: requiredPercentage = 0.4
        case 3: requiredPercentage = 0.6
        case 4: requiredPercentage = 0.8
        case 5: requiredPercentage = 1.0
        default: requiredPercentage = 0.6 // Should never reach here due to guard
        }
        
        // Check if there are fields to compare, if not return false
        guard totalFields > 0 else { return false }
        
        let matchPercentage = Double(matchingFields) / Double(totalFields)
        return matchPercentage >= requiredPercentage
    }
    
    static func areTracksTheSame(_ track1: GPXTrack, _ track2: GPXTrack, confidenceLevel: Int) -> Bool {
        guard confidenceLevel >= 1 && confidenceLevel <= 5 else {
            // Default to medium confidence if invalid level provided
            return areTracksTheSame(track1, track2, confidenceLevel: 3)
        }
        
        // If the number of segments differ, tracks are differentx
        if track1.segments.count != track2.segments.count {
            return false
        }
        
        var totalFields = 0
        var matchingFields = 0
        
        // Compare track attributes
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
        
        // Compare links
        if !track1.links.isEmpty || !track2.links.isEmpty {
            totalFields += 1
            
            // Simple check - if same number of links, check if all hrefs match
            if track1.links.count == track2.links.count {
                let hrefs1 = Set(track1.links.compactMap { $0.href })
                let hrefs2 = Set(track2.links.compactMap { $0.href })
                
                if hrefs1 == hrefs2 {
                    matchingFields += 1
                }
            }
        }
        
        // Compare extensions
        if track1.extensions != nil || track2.extensions != nil {
            totalFields += 1
            
            if let ext1 = track1.extensions, let ext2 = track2.extensions {
                // Compare root contents
                if let contents1 = ext1.get(from: nil), let contents2 = ext2.get(from: nil),
                   contents1 == contents2 {
                    matchingFields += 1
                } else {
                    // Compare by checking child elements
                    let children1 = Set(ext1.children.map { $0.name })
                    let children2 = Set(ext2.children.map { $0.name })
                    
                    if children1 == children2 {
                        // If the same child elements exist, check if their contents match
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
        
        // Compare segments
        for i in 0..<track1.segments.count {
            let segment1 = track1.segments[i]
            let segment2 = track2.segments[i]
            
            // If segments have different number of points, tracks are different
            if segment1.points.count != segment2.points.count {
                return false
            }
            
            // Compare segment extensions
            if segment1.extensions != nil || segment2.extensions != nil {
                totalFields += 1
                
                if let ext1 = segment1.extensions, let ext2 = segment2.extensions {
                    // Compare root contents
                    if let contents1 = ext1.get(from: nil), let contents2 = ext2.get(from: nil),
                       contents1 == contents2 {
                        matchingFields += 1
                    } else {
                        // Compare by checking child elements
                        let children1 = Set(ext1.children.map { $0.name })
                        let children2 = Set(ext2.children.map { $0.name })
                        
                        if children1 == children2 {
                            // If the same child elements exist, check if their contents match
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
            
            // Compare each point in the segment
            for j in 0..<segment1.points.count {
                let point1 = segment1.points[j]
                let point2 = segment2.points[j]
                
                totalFields += 1
                // Use the existing point comparison method with the same confidence level
                // But we only count it as a single field in the track comparison
                if arePointsTheSame(point1, point2, confidenceLevel: confidenceLevel) {
                    matchingFields += 1
                }
            }
        }
        
        // Calculate minimum required match percentage based on confidence level
        let requiredPercentage: Double
        switch confidenceLevel {
        case 1: requiredPercentage = 0.2
        case 2: requiredPercentage = 0.4
        case 3: requiredPercentage = 0.6
        case 4: requiredPercentage = 0.8
        case 5: requiredPercentage = 1.0
        default: requiredPercentage = 0.6 // Should never reach here due to guard
        }
        
        // Check if there are fields to compare, if not return false
        guard totalFields > 0 else { return false }
        
        let matchPercentage = Double(matchingFields) / Double(totalFields)
        return matchPercentage >= requiredPercentage
    }
} 
