//
//  MapView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 25.4.2024.
//

import Foundation
import SwiftUI
import MapKit

struct MapView: View {
    @Binding var timelineObjects: [TimelineObject]
    @Binding var selectedTimelineObjectID: UUID?
    @Binding var selectedGroupIDs: Set<UUID>
    @Binding var cameraPosition: MapCameraPosition 
    @Binding var selectedDate: Date

    private func isSelected(_ id: UUID) -> Bool {
        id == selectedTimelineObjectID || selectedGroupIDs.contains(id)
    }

    var body: some View {
        Map(
            position: $cameraPosition,
            interactionModes: .all
        ) {
            if calendar.isDate(selectedDate, inSameDayAs: Date())
            {
                UserAnnotation()
            }
            ForEach(timelineObjects.filter { $0.type == .track && !isSelected($0.id) }, id: \.id) { trackObject in
                ForEach(trackObject.identifiableCoordinates, id: \.id) { identifiableCoordinates in
                    MapPolyline(coordinates: CoordinateConverter.forMapDisplay(identifiableCoordinates.coordinates))
                        .stroke(trackTypeColorMapping[trackObject.trackType?.lowercased() ?? "unknown"] ?? .purple,
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
                        .stroke(trackTypeColorMapping[selectedObject.trackType?.lowercased() ?? "unknown"] ?? .purple,
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
                        }
                    }

                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .background {
            Color.clear
                .task(id: mapDiagnosticsToken) {
                    logMapOverlayDiagnostics()
                }
        }

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

    private func logMapOverlayDiagnostics() {
        let tracks = timelineObjects.filter { $0.type == .track }
        let waypointCount = timelineObjects.filter { $0.type == .waypoint }.count
        let polylineCount = tracks.reduce(0) { $0 + $1.identifiableCoordinates.count }
        let maxPolylinePoints = tracks.flatMap(\.identifiableCoordinates).map(\.coordinates.count).max() ?? 0
        let totalPolylinePoints = tracks.flatMap(\.identifiableCoordinates).reduce(0) { $0 + $1.coordinates.count }
        let selectedTrackPoints = tracks
            .filter { isSelected($0.id) }
            .flatMap(\.identifiableCoordinates)
            .reduce(0) { $0 + $1.coordinates.count }

        if maxPolylinePoints >= 5_000 || totalPolylinePoints >= 20_000 {
            ResourceDiagnostics.logMemory(
                context: "MapView",
                detail: "Heavy map overlay: tracks=\(tracks.count) polylines=\(polylineCount) maxPolylinePoints=\(maxPolylinePoints) totalPolylinePoints=\(totalPolylinePoints) selectedTrackPoints=\(selectedTrackPoints) waypoints=\(waypointCount). Large polylines can exhaust GPU memory and stop MapKit tile loading."
            )
        }
    }
}
