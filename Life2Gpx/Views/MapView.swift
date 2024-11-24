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
    @Binding var cameraPosition: MapCameraPosition 
    @Binding var selectedDate: Date
    var body: some View {
        Map(
            position: $cameraPosition,
            interactionModes: .all
        ) {
            if calendar.isDate(selectedDate, inSameDayAs: Date())
            {
                UserAnnotation()
            }
            // First loop for non-selected tracks
            ForEach(timelineObjects.filter { $0.type == .track && $0.id != selectedTimelineObjectID }, id: \.id) { trackObject in
                ForEach(trackObject.identifiableCoordinates, id: \.id) { identifiableCoordinates in
                    MapPolyline(coordinates: identifiableCoordinates.coordinates)
                        .stroke(trackTypeColorMapping[trackObject.trackType?.lowercased() ?? "unknown"] ?? .purple,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                }
            }
            if let selectedObject = timelineObjects.first(where: { $0.type == .track && $0.id == selectedTimelineObjectID }) {
                // Generate new identifiable coordinates for the selected track, in order to make it appear on top.
                let selectedIdentifiableCoordinates = selectedObject.identifiableCoordinates.map { coordinates in
                    IdentifiableCoordinates(coordinates: coordinates.coordinates)
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
                    if (waypointObject.id == selectedTimelineObjectID){
                        Annotation(waypointObject.name ?? "", coordinate: coordinate)
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
                        Annotation(waypointObject.name ?? "", coordinate: coordinate)
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

    }
}
