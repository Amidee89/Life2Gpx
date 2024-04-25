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
    var body: some View {
        Map(
            position: $cameraPosition,
            interactionModes: .all
        ) {
            
            // Use MapPolyline to display the path
            ForEach(timelineObjects.filter { $0.type == .track }, id: \.id) { trackObject in
                ForEach(trackObject.identifiableCoordinates, id: \.id) { identifiableCoordinates in
                    if selectedTimelineObjectID == trackObject.id
                    {
                        MapPolyline(coordinates: identifiableCoordinates.coordinates)
                            .stroke(.black,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                    }
                    else
                    {
                        MapPolyline(coordinates: identifiableCoordinates.coordinates)
                            .stroke(trackTypeColorMapping[trackObject.trackType?.lowercased() ?? "unknown"] ?? .purple,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .miter, miterLimit: 1))
                    }
                    
                }
            }
            
            ForEach(timelineObjects.filter { $0.type == .waypoint }, id: \.id) { waypointObject in
                if let coordinate = waypointObject.identifiableCoordinates.first?.coordinates.first
                {
                    Annotation(waypointObject.name ?? "Stop", coordinate: coordinate)
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
        .edgesIgnoringSafeArea(.all)
        
    }
}
