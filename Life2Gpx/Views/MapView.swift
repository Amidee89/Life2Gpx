//
//  MapView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 25.4.2024.
//

import Foundation
import SwiftUI
import MapKit
import os

struct MapView: View {
    @Binding var timelineObjects: [TimelineObject]
    @Binding var selectedTimelineObjectID: UUID?
    @Binding var selectedGroupIDs: Set<UUID>
    @Binding var cameraPosition: MapCameraPosition 
    @Binding var selectedDate: Date
    var safeAreaTop: CGFloat
    
    @EnvironmentObject var locationManager: LocationManager
    @State private var mapHeading: Double = 0.0
    @State private var lastRawMapHeading: Double?

    private func isSelected(_ id: UUID) -> Bool {
        id == selectedTimelineObjectID || selectedGroupIDs.contains(id)
    }

    private func selectTimelineObject(_ object: TimelineObject) {
        for index in timelineObjects.indices {
            timelineObjects[index].selected = (timelineObjects[index].id == object.id)
        }
        selectedTimelineObjectID = object.id
        selectedGroupIDs = []
    }

    private func distanceToSegment(p: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double {
        let latRad = (a.latitude + b.latitude) / 2.0 * .pi / 180.0
        let cosLat = cos(latRad)
        
        let ax = a.longitude * cosLat
        let ay = a.latitude
        let bx = b.longitude * cosLat
        let by = b.latitude
        let px = p.longitude * cosLat
        let py = p.latitude
        
        let dx = bx - ax
        let dy = by - ay
        
        let segmentLengthSquared = dx * dx + dy * dy
        if segmentLengthSquared == 0 {
            return p.distance(to: a)
        }
        
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / segmentLengthSquared))
        
        let closestX = ax + t * dx
        let closestY = ay + t * dy
        
        let closestCoord = CLLocationCoordinate2D(latitude: closestY, longitude: closestX / (cosLat != 0 ? cosLat : 1.0))
        return p.distance(to: closestCoord)
    }

    private func handleMapTap(at screenPoint: CGPoint, proxy: MapProxy) {
        guard let tappedCoordinate = proxy.convert(screenPoint, from: .local) else {
            return
        }
        
        var closestObject: TimelineObject? = nil
        var minDistance: Double = Double.infinity
        
        for obj in timelineObjects {
            if obj.type == .waypoint {
                if let coord = obj.identifiableCoordinates.first?.coordinates.first {
                    let displayCoord = CoordinateConverter.forMapDisplay(coord)
                    let distance = tappedCoordinate.distance(to: displayCoord)
                    if distance < minDistance {
                        minDistance = distance
                        closestObject = obj
                    }
                }
            } else if obj.type == .track {
                for segment in obj.identifiableCoordinates {
                    let coords = segment.coordinates
                    guard !coords.isEmpty else { continue }
                    
                    if coords.count == 1 {
                        let displayCoord = CoordinateConverter.forMapDisplay(coords[0])
                        let distance = tappedCoordinate.distance(to: displayCoord)
                        if distance < minDistance {
                            minDistance = distance
                            closestObject = obj
                        }
                    } else {
                        for i in 0..<(coords.count - 1) {
                            let displayA = CoordinateConverter.forMapDisplay(coords[i])
                            let displayB = CoordinateConverter.forMapDisplay(coords[i+1])
                            let distance = distanceToSegment(p: tappedCoordinate, a: displayA, b: displayB)
                            if distance < minDistance {
                                minDistance = distance
                                closestObject = obj
                            }
                        }
                    }
                }
            }
        }
        
        let p1 = CGPoint.zero
        let p2 = CGPoint(x: 22, y: 0)
        let toleranceInMeters: Double
        if let c1 = proxy.convert(p1, from: .local),
           let c2 = proxy.convert(p2, from: .local) {
            toleranceInMeters = c1.distance(to: c2)
        } else {
            toleranceInMeters = 100.0 // fallback
        }
        
        if minDistance <= toleranceInMeters, let object = closestObject {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectTimelineObject(object)
            }
        }
    }

    var body: some View {
        let _ = Self._logBodyEvaluation()
        MapReader { mapProxy in
            Map(
                position: $cameraPosition,
                interactionModes: [.pan, .zoom, .rotate]
            ) {
                if calendar.isDate(selectedDate, inSameDayAs: Date()),
                   let location = locationManager.currentRawLocation?.coordinate
                {
                    Annotation(coordinate: location) {
                        ZStack {
                            Image(systemName: "location.north.fill")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.blue.opacity(0.8))
                                .offset(y: -14)
                                .rotationEffect(Angle(degrees: locationManager.heading - mapHeading))
                                .animation(.linear, value: locationManager.heading)
                                .animation(.linear, value: mapHeading)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                                .shadow(radius: 2)
                            
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 16, height: 16)
                        }
                    } label: {
                        EmptyView()
                    }
                    //trying to make sure it's not covering eventual current visit's label by putting it at a lower priority. 
                    .mapOverlayLevel(level: .aboveRoads)
                }
                ForEach(timelineObjects.filter { $0.type == .track && !isSelected($0.id) }, id: \.id) { trackObject in
                    ForEach(trackObject.identifiableCoordinates, id: \.id) { identifiableCoordinates in
                        MapPolyline(coordinates: CoordinateConverter.forMapDisplay(identifiableCoordinates.coordinates))
                            .stroke(PreferencesManager.shared.color(for: trackObject.trackType),
                                   style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                    }
                }
                ForEach(timelineObjects.filter { $0.type == .track && isSelected($0.id) }, id: \.id) { selectedObject in
                    let selectedIdentifiableCoordinates = selectedObject.identifiableCoordinates.map { coordinates in
                        IdentifiableCoordinates(coordinates: CoordinateConverter.forMapDisplay(coordinates.coordinates))
                    }

                    ForEach(selectedIdentifiableCoordinates, id: \.id) { identifiableCoordinates in
                        MapPolyline(coordinates: identifiableCoordinates.coordinates)
                            .stroke(.white,
                                    style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        MapPolyline(coordinates: identifiableCoordinates.coordinates)
                            .stroke(.black,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                        MapPolyline(coordinates: identifiableCoordinates.coordinates)
                            .stroke(PreferencesManager.shared.color(for: selectedObject.trackType),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                    }
                }
        
                ForEach(timelineObjects.filter { $0.type == .waypoint }, id: \.id) { waypointObject in
                    if let coordinate = waypointObject.identifiableCoordinates.first?.coordinates.first
                    {
                        let displayCoord = CoordinateConverter.forMapDisplay(coordinate)
                        if isSelected(waypointObject.id) {
                            Annotation(waypointObject.name ?? "", coordinate: displayCoord)
                            {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(Color.orange)
                                        .padding(4)
                                }
                                .contentShape(Circle())
                                .onTapGesture {
                                    selectTimelineObject(waypointObject)
                                }
                            }
                        }
                        else
                        {
                            Annotation(waypointObject.name ?? "", coordinate: displayCoord)
                            {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                    Circle()
                                        .fill(Color.black)
                                        .padding(4)
                                }
                                .contentShape(Circle())
                                .onTapGesture {
                                    selectTimelineObject(waypointObject)
                                }
                            }
                        }

                    }
                }
            }
            .mapControls {
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                let rawHeading = context.camera.heading
                if let lastRaw = lastRawMapHeading {
                    var diff = rawHeading - lastRaw
                    if diff > 180 { diff -= 360 }
                    else if diff < -180 { diff += 360 }
                    mapHeading += diff
                } else {
                    mapHeading = rawHeading
                }
                lastRawMapHeading = rawHeading
            }
            .onTapGesture { screenPoint in
                handleMapTap(at: screenPoint, proxy: mapProxy)
            }
        }
        .safeAreaPadding(.top, safeAreaTop)
        .edgesIgnoringSafeArea(.all)
        .background {
            Color.clear
                .task(id: mapDiagnosticsToken) {
                    logMapOverlayDiagnostics(reason: "Map diagnostics token changed")
                }
        }
        .onAppear {
            logMapOverlayDiagnostics(reason: "MapView appeared")
        }
        .onDisappear {
            ResourceDiagnostics.logRuntime(
                context: "MapView",
                detail: "MapView disappeared."
            )
        }

    }

    private static func _logBodyEvaluation() {
        os_signpost(.event, log: diagnosticsLog, name: "MapView.body")
    }

    private var mapDiagnosticsToken: String {
        let trackSummaries = timelineObjects
            .filter { $0.type == .track }
            .map { track in
                let pointCount = track.identifiableCoordinates.reduce(0) { $0 + $1.coordinates.count }
                return "\(track.id.uuidString.prefix(8)):\(pointCount)"
            }
        return trackSummaries.joined(separator: "|")
    }

    private func logMapOverlayDiagnostics(reason: String) {
        let tracks = timelineObjects.filter { $0.type == .track }
        let waypointCount = timelineObjects.filter { $0.type == .waypoint }.count
        let polylineCount = tracks.reduce(0) { $0 + $1.identifiableCoordinates.count }
        let maxPolylinePoints = tracks.flatMap(\.identifiableCoordinates).map(\.coordinates.count).max() ?? 0
        let totalPolylinePoints = tracks.flatMap(\.identifiableCoordinates).reduce(0) { $0 + $1.coordinates.count }
        let selectedTrackPoints = tracks
            .filter { isSelected($0.id) }
            .flatMap(\.identifiableCoordinates)
            .reduce(0) { $0 + $1.coordinates.count }

        let snapshot = "\(reason). selectedDate=\(selectedDate), tracks=\(tracks.count), polylines=\(polylineCount), maxPolylinePoints=\(maxPolylinePoints), totalPolylinePoints=\(totalPolylinePoints), selectedTrackPoints=\(selectedTrackPoints), waypoints=\(waypointCount), selectedObject=\(selectedTimelineObjectID?.uuidString ?? "nil"), selectedGroups=\(selectedGroupIDs.count), \(ResourceDiagnostics.memorySnapshot()), network={\(NetworkDiagnostics.shared.snapshot())}"
        DiagnosticsStateStore.shared.update(section: "MapView", detail: snapshot)
        FileManagerUtil.logData(
            context: "MapView",
            content: snapshot,
            verbosity: 5
        )

        if maxPolylinePoints >= 5_000 || totalPolylinePoints >= 20_000 {
            ResourceDiagnostics.logMemory(
                context: "MapView",
                detail: "Heavy map overlay: tracks=\(tracks.count) polylines=\(polylineCount) maxPolylinePoints=\(maxPolylinePoints) totalPolylinePoints=\(totalPolylinePoints) selectedTrackPoints=\(selectedTrackPoints) waypoints=\(waypointCount). Large polylines can exhaust GPU memory and stop MapKit tile loading. network={\(NetworkDiagnostics.shared.snapshot())}"
            )
        }
    }
}
